using System.Globalization;
using DoZore.Api.Auth;
using DoZore.Api.Data;
using DoZore.Api.Infrastructure;
using Microsoft.EntityFrameworkCore;

namespace DoZore.Api.Features;

public static class LeaderboardEndpoints
{
    const int MaxEntries = 100;
    static readonly TimeSpan LateSubmissionGrace = TimeSpan.FromHours(1);

    public static void MapLeaderboard(this IEndpointRouteBuilder app)
    {
        app.MapGet("/v1/leaderboards/weekly", GetWeekly).RequireAuthorization();
        app.MapPost("/v1/leaderboards/weekly/score", SubmitScore).RequireAuthorization().RequireRateLimiting(RateLimiting.Writes);
    }

    static async Task<IResult> GetWeekly(HttpContext ctx, AppDbContext db, TimeProvider time, string? limit)
    {
        var take = MaxEntries;
        if (limit is not null && (!int.TryParse(limit, NumberStyles.None, CultureInfo.InvariantCulture, out take) || take is < 1 or > MaxEntries))
            return Problems.BadRequest("limit must be an integer from 1 to 100.", [new SchemaError("/limit", "Out of range.")]);

        var ct = ctx.RequestAborted;
        var week = WeekCalendar.Containing(time.GetUtcNow());
        var playerId = ctx.User.PlayerId();

        var top = await (
                from s in db.WeeklyScores
                where s.WeekId == week.Id
                join p in db.Players on s.PlayerId equals p.Id
                orderby s.Score descending, s.ReachedAt, s.PlayerId
                select new { s.PlayerId, p.DisplayName, s.Score })
            .Take(take)
            .ToListAsync(ct);

        var total = await db.WeeklyScores.CountAsync(s => s.WeekId == week.Id, ct);
        var mine = await db.WeeklyScores.AsNoTracking().SingleOrDefaultAsync(s => s.WeekId == week.Id && s.PlayerId == playerId, ct);

        return Results.Ok(new WeeklyLeaderboard(
            week.Id, week.StartsAt, week.EndsAt, total,
            top.Select((e, i) => new LeaderboardEntry(i + 1, e.PlayerId, e.DisplayName, e.Score)).ToList(),
            mine is null ? new LeaderboardMe(null, 0) : new LeaderboardMe(await RankAsync(db, mine, ct), mine.Score)));
    }

    static async Task<IResult> SubmitScore(HttpContext ctx, AppDbContext db, TimeProvider time, IConfiguration config)
    {
        var body = await ctx.ReadAsync<ScoreSubmission>("ScoreSubmission");
        if (body.Failed) return body.Error!;
        var req = body.Value!;
        var ct = ctx.RequestAborted;

        var now = time.GetUtcNow();
        var current = WeekCalendar.Containing(now);
        var previous = WeekCalendar.Previous(current);
        Week? week = req.WeekId == current.Id ? current
            : req.WeekId == previous.Id && now < current.StartsAt + LateSubmissionGrace ? previous
            : null;
        if (week is null)
            return Problems.Result(StatusCodes.Status409Conflict, "week_closed", "Week closed",
                $"Scores are accepted for {current.Id} only.");

        var playerId = ctx.User.PlayerId();
        var player = await db.Players.AsNoTracking().SingleOrDefaultAsync(p => p.Id == playerId, ct);
        if (player is null) return Problems.Unauthorized("Player no longer exists.");

        // Anti-cheat clamp: nobody can earn faster than MaxScorePerSecond since they could first play this week.
        var perSecond = config.GetValue("Leaderboard:MaxScorePerSecond", 5000L);
        var playableFrom = player.CreatedAt > week.StartsAt ? player.CreatedAt : week.StartsAt;
        var playableUntil = now < week.EndsAt ? now : week.EndsAt;
        var plausible = (long)Math.Max(0, (playableUntil - playableFrom).TotalSeconds) * perSecond;
        var accepted = Math.Min(req.Score, plausible);

        for (var attempt = 0; ; attempt++)
        {
            var row = await db.WeeklyScores.SingleOrDefaultAsync(s => s.WeekId == week.Id && s.PlayerId == playerId, ct);
            if (row is null)
                db.WeeklyScores.Add(row = new WeeklyScore { WeekId = week.Id, PlayerId = playerId, Score = accepted, ReachedAt = now });
            else if (accepted > row.Score)
            {
                row.Score = accepted;
                row.ReachedAt = now;
            }

            try
            {
                await db.SaveChangesAsync(ct);
                return Results.Ok(new ScoreResult(week.Id, row.Score, await RankAsync(db, row, ct)));
            }
            catch (DbUpdateException) when (attempt == 0)
            {
                db.ChangeTracker.Clear(); // concurrent first submission; retry as an update
            }
        }
    }

    /// <summary>1-based rank: higher score first, then whoever reached it earlier.</summary>
    static async Task<int> RankAsync(AppDbContext db, WeeklyScore mine, CancellationToken ct) =>
        1 + await db.WeeklyScores.CountAsync(s =>
            s.WeekId == mine.WeekId && s.PlayerId != mine.PlayerId &&
            (s.Score > mine.Score || (s.Score == mine.Score && s.ReachedAt < mine.ReachedAt)), ct);
}
