using System.Text.Json;
using DoZore.Api.Auth;
using DoZore.Api.Data;
using DoZore.Api.GameData;
using DoZore.Api.Infrastructure;
using Microsoft.EntityFrameworkCore;

namespace DoZore.Api.Features;

public static class OfflineEndpoints
{
    static readonly HashSet<string> IncomeStats = ["income", "offline_income"];

    public static void MapOffline(this IEndpointRouteBuilder app) =>
        app.MapPost("/v1/offline-earnings/claim", Claim).RequireAuthorization().RequireRateLimiting(RateLimiting.Writes);

    static async Task<IResult> Claim(HttpContext ctx, AppDbContext db, GameDataProvider gameData, TimeProvider time, ILogger<Program> log)
    {
        var body = await ctx.ReadAsync<OfflineClaimRequest>("OfflineClaimRequest");
        if (body.Failed) return body.Error!;
        var req = body.Value!;
        var ct = ctx.RequestAborted;

        var playerId = ctx.User.PlayerId();
        var player = await db.Players.AsNoTracking().SingleOrDefaultAsync(p => p.Id == playerId, ct);
        if (player is null) return Problems.Unauthorized("Player no longer exists.");

        var save = await db.Saves.AsNoTracking().SingleOrDefaultAsync(s => s.PlayerId == playerId, ct);
        if (save is null) return SaveEndpoints.SaveNotFound();
        if (save.Version != req.SaveVersion)
            return Problems.Result(StatusCodes.Status409Conflict, "save_version_mismatch", "Save out of date",
                $"Cloud save is at version {save.Version}; upload the current save before claiming.");

        var snapshot = await gameData.GetAsync(ct);
        if (snapshot is null) return Problems.GameDataUnavailable();

        var playerSave = JsonSerializer.Deserialize<PlayerSave>(save.Data, JsonDefaults.Options)!;
        var now = time.GetUtcNow();

        // Server clock only. The client's last_seen can shorten the window, never extend it.
        var recorded = player.LastActivityAt ?? save.UpdatedAt;
        var clientLastSeen = req.LastSeen.ToUniversalTime();
        var from = clientLastSeen > recorded ? clientLastSeen : recorded;

        var result = OfflineEarnings.Compute(snapshot.Model, playerSave, from, now, await IncomeWindowsAsync(db, from, now, ct));

        // Pay each away period once: only the request that moves the activity marker gets paid.
        var won = await db.Players
            .Where(p => p.Id == playerId && p.LastActivityAt == player.LastActivityAt)
            .ExecuteUpdateAsync(s => s.SetProperty(p => p.LastActivityAt, now), ct);
        if (won == 0)
            result = OfflineEarnings.Compute(snapshot.Model, playerSave, now, now, []);

        var granted = Math.Min(req.ClaimedAmount, result.Amount);
        db.OfflineClaims.Add(new OfflineClaim
        {
            PlayerId = playerId,
            ClaimedAmount = req.ClaimedAmount,
            ComputedAmount = result.Amount,
            GrantedAmount = granted,
            AwayFrom = from,
            AwayTo = now,
            CountedSeconds = result.CountedSeconds,
            DataVersionHash = snapshot.Hash,
            CreatedAt = now,
        });
        await db.SaveChangesAsync(ct);

        if (req.ClaimedAmount > result.Amount)
            log.LogInformation("Offline claim for {PlayerId} reduced from {Claimed} to {Computed}", playerId, req.ClaimedAmount, result.Amount);

        return Results.Ok(new OfflineClaimResult(
            granted, req.ClaimedAmount, result.Amount, result.AwaySeconds, result.CountedSeconds,
            result.CapHours, result.Capped, result.LiveEventIds, now, snapshot.Hash));
    }

    /// <summary>Live events overlapping the window, reduced to their combined income multiplier.</summary>
    public static async Task<List<IncomeWindow>> IncomeWindowsAsync(AppDbContext db, DateTimeOffset from, DateTimeOffset to, CancellationToken ct)
    {
        var events = await db.LiveEvents.AsNoTracking()
            .Where(e => e.StartsAt < to && e.EndsAt > from)
            .ToListAsync(ct);

        var windows = new List<IncomeWindow>();
        foreach (var e in events)
        {
            using var modifiers = JsonDocument.Parse(e.Modifiers);
            var multiplier = modifiers.RootElement.EnumerateArray()
                .Where(m => IncomeStats.Contains(m.GetProperty("stat").GetString()!) && !m.TryGetProperty("guest_type", out _))
                .Aggregate(1.0, (acc, m) => acc * m.GetProperty("value").GetDouble());
            if (multiplier != 1.0)
                windows.Add(new IncomeWindow(e.Id, e.StartsAt, e.EndsAt, multiplier));
        }

        return windows;
    }
}
