using System.Net;
using DoZore.Api.Features;
using DoZore.Api.Tests.Infrastructure;

namespace DoZore.Api.Tests;

[Collection(ApiCollection.Name)]
public sealed class LeaderboardTests(ApiFixture api)
{
    DateTimeOffset Now => api.Time.GetUtcNow();

    /// <summary>Moves the clock into a brand-new, empty week (plus an offset into it).</summary>
    Week StartFreshWeek(TimeSpan into)
    {
        var next = WeekCalendar.Containing(Now).EndsAt;
        api.Time.Advance(next - Now + into);
        return WeekCalendar.Containing(Now);
    }

    static Task<HttpResponseMessage> SubmitAsync(Session s, string week, long score) =>
        s.Client.PostJsonAsync("/v1/leaderboards/weekly/score", new { week_id = week, score });

    [Fact]
    public async Task Ranks_by_score_then_by_who_got_there_first()
    {
        var week = StartFreshWeek(TimeSpan.FromHours(2));
        var (a, b, c) = (await api.NewPlayerAsync(), await api.NewPlayerAsync(), await api.NewPlayerAsync());
        await (await b.Client.PatchJsonAsync("/v1/me", new { display_name = "Bora" })).ExpectAsync(HttpStatusCode.OK);
        api.Time.Advance(TimeSpan.FromMinutes(10)); // new players need time to earn, see the clamp

        await (await SubmitAsync(a, week.Id, 500)).ExpectAsync(HttpStatusCode.OK, "ScoreResult");
        await (await SubmitAsync(b, week.Id, 900)).ExpectAsync(HttpStatusCode.OK, "ScoreResult");
        api.Time.Advance(TimeSpan.FromSeconds(1));
        var cResult = await (await SubmitAsync(c, week.Id, 900)).ExpectAsync(HttpStatusCode.OK, "ScoreResult");
        Assert.Equal(2, cResult.GetProperty("rank").GetInt32());

        var board = await (await a.Client.GetAsync("/v1/leaderboards/weekly")).ExpectAsync(HttpStatusCode.OK, "WeeklyLeaderboard");
        Assert.Equal(week.Id, board.GetProperty("week_id").GetString());
        Assert.Equal(week.StartsAt, board.GetProperty("starts_at").GetDateTimeOffset());
        Assert.Equal(3, board.GetProperty("total_players").GetInt32());

        var entries = board.GetProperty("entries").EnumerateArray().ToList();
        Assert.Equal([b.PlayerId, c.PlayerId, a.PlayerId], entries.Select(e => e.GetProperty("player_id").GetGuid()));
        Assert.Equal([1, 2, 3], entries.Select(e => e.GetProperty("rank").GetInt32()));
        Assert.Equal("Bora", entries[0].GetProperty("display_name").GetString());

        Assert.Equal(3, board.GetProperty("me").GetProperty("rank").GetInt32());
        Assert.Equal(500, board.GetProperty("me").GetProperty("score").GetInt64());

        var limited = await (await a.Client.GetAsync("/v1/leaderboards/weekly?limit=2")).ExpectAsync(HttpStatusCode.OK, "WeeklyLeaderboard");
        Assert.Equal(2, limited.GetProperty("entries").GetArrayLength());
    }

    [Fact]
    public async Task Keeps_the_highest_score_and_clamps_implausible_ones()
    {
        var week = StartFreshWeek(TimeSpan.FromHours(1));
        var player = await api.NewPlayerAsync();
        api.Time.Advance(TimeSpan.FromMinutes(10));

        await (await SubmitAsync(player, week.Id, 800)).ExpectAsync(HttpStatusCode.OK);
        var lower = await (await SubmitAsync(player, week.Id, 100)).ExpectAsync(HttpStatusCode.OK, "ScoreResult");
        Assert.Equal(800, lower.GetProperty("accepted_score").GetInt64());

        // 10 minutes since the player existed x 5000/s is the most anyone could have earned.
        var cheat = await (await SubmitAsync(player, week.Id, 1_000_000_000_000)).ExpectAsync(HttpStatusCode.OK, "ScoreResult");
        Assert.Equal(600L * 5000, cheat.GetProperty("accepted_score").GetInt64());
    }

    [Fact]
    public async Task Previous_week_is_accepted_only_within_the_grace_hour()
    {
        var week = StartFreshWeek(TimeSpan.FromMinutes(30));
        var previous = WeekCalendar.Previous(week);
        var player = await api.NewPlayerAsync();
        api.Time.Advance(TimeSpan.FromMinutes(1));

        await (await SubmitAsync(player, previous.Id, 0)).ExpectAsync(HttpStatusCode.OK, "ScoreResult");

        api.Time.Advance(TimeSpan.FromMinutes(40)); // now 1h11m into the week
        await player.RefreshAsync();
        await (await SubmitAsync(player, previous.Id, 0)).ExpectProblemAsync(HttpStatusCode.Conflict, "week_closed");
        await (await SubmitAsync(player, "2020-W01", 0)).ExpectProblemAsync(HttpStatusCode.Conflict, "week_closed");
    }

    [Fact]
    public async Task Player_without_a_score_has_a_null_rank()
    {
        StartFreshWeek(TimeSpan.FromHours(1));
        var player = await api.NewPlayerAsync();
        var board = await (await player.Client.GetAsync("/v1/leaderboards/weekly")).ExpectAsync(HttpStatusCode.OK, "WeeklyLeaderboard");
        Assert.Equal(System.Text.Json.JsonValueKind.Null, board.GetProperty("me").GetProperty("rank").ValueKind);
        Assert.Equal(0, board.GetProperty("me").GetProperty("score").GetInt64());
        Assert.Equal(0, board.GetProperty("total_players").GetInt32());
    }

    [Fact]
    public async Task Validates_input_and_requires_auth()
    {
        var player = await api.NewPlayerAsync();
        var week = WeekCalendar.Containing(Now);
        await (await SubmitAsync(player, "2026-40", 1)).ExpectProblemAsync(HttpStatusCode.BadRequest, "bad_request");
        await (await SubmitAsync(player, week.Id, -1)).ExpectProblemAsync(HttpStatusCode.BadRequest, "bad_request");
        await (await player.Client.GetAsync("/v1/leaderboards/weekly?limit=0")).ExpectProblemAsync(HttpStatusCode.BadRequest, "bad_request");
        await (await player.Client.GetAsync("/v1/leaderboards/weekly?limit=101")).ExpectProblemAsync(HttpStatusCode.BadRequest, "bad_request");

        var anonymous = api.Factory.CreateClient();
        await (await anonymous.GetAsync("/v1/leaderboards/weekly")).ExpectProblemAsync(HttpStatusCode.Unauthorized, "unauthorized");
    }

    [Fact]
    public void Weeks_are_iso_weeks_in_belgrade_time()
    {
        // Monday 2026-09-28 00:00 in Belgrade (CEST, UTC+2) is Sunday 22:00 UTC.
        var week = WeekCalendar.Containing(new DateTimeOffset(2026, 9, 27, 22, 30, 0, TimeSpan.Zero));
        Assert.Equal("2026-W40", week.Id);
        Assert.Equal(new DateTimeOffset(2026, 9, 27, 22, 0, 0, TimeSpan.Zero), week.StartsAt);
        Assert.Equal("2026-W39", WeekCalendar.Containing(new DateTimeOffset(2026, 9, 27, 21, 59, 0, TimeSpan.Zero)).Id);

        // Winter: CET, UTC+1.
        Assert.Equal(new DateTimeOffset(2026, 12, 27, 23, 0, 0, TimeSpan.Zero), WeekCalendar.Of(2026, 53).StartsAt);
    }
}
