using System.Net;
using DoZore.Api.Data;
using DoZore.Api.Tests.Infrastructure;

namespace DoZore.Api.Tests;

/// <summary>
/// Expected numbers come from /data: birtija pays 250/min offline with a 2 h cap, the solo
/// harmonikaš has tip multiplier 1.0 and no upkeep, min away time is 300 s.
/// </summary>
[Collection(ApiCollection.Name)]
public sealed class OfflineEarningsTests(ApiFixture api)
{
    const long Plenty = 100_000_000;

    DateTimeOffset Now => api.Time.GetUtcNow();

    async Task<Session> PlayerWithSaveAsync(object? upgrades = null, string band = "solo_harmonikas")
    {
        var player = await api.NewPlayerAsync();
        await (await player.Client.PutJsonAsync("/v1/save", new
        {
            base_version = 0,
            save = TestApi.Save(band: band, lastSeen: Now, upgrades: upgrades),
        })).ExpectAsync(HttpStatusCode.OK);
        return player;
    }

    async Task AwayAsync(Session player, TimeSpan away)
    {
        api.Time.Advance(away);
        await player.RefreshAsync(); // access token is long expired
    }

    static Task<HttpResponseMessage> ClaimAsync(Session player, long claimed, DateTimeOffset lastSeen, int saveVersion = 1) =>
        player.Client.PostJsonAsync("/v1/offline-earnings/claim",
            new { last_seen = lastSeen, claimed_amount = claimed, save_version = saveVersion });

    [Fact]
    public async Task Pays_server_computed_amount_capped_at_the_venue_cap()
    {
        var player = await PlayerWithSaveAsync();
        var leftAt = Now;
        await AwayAsync(player, TimeSpan.FromHours(3));

        var result = await (await ClaimAsync(player, Plenty, leftAt)).ExpectAsync(HttpStatusCode.OK, "OfflineClaimResult");

        Assert.Equal(250 * 120, result.GetProperty("computed_amount").GetInt64());
        Assert.Equal(250 * 120, result.GetProperty("granted_amount").GetInt64());
        Assert.Equal(Plenty, result.GetProperty("claimed_amount").GetInt64());
        Assert.Equal(3 * 3600, result.GetProperty("away_seconds").GetInt64());
        Assert.Equal(2 * 3600, result.GetProperty("counted_seconds").GetInt64());
        Assert.Equal(2.0, result.GetProperty("cap_hours").GetDouble());
        Assert.True(result.GetProperty("capped").GetBoolean());
        Assert.Equal(Now, result.GetProperty("server_time").GetDateTimeOffset());
    }

    [Fact]
    public async Task Grants_the_claim_when_it_is_lower_than_the_server_amount()
    {
        var player = await PlayerWithSaveAsync();
        var leftAt = Now;
        await AwayAsync(player, TimeSpan.FromHours(1));

        var result = await (await ClaimAsync(player, 1000, leftAt)).ExpectAsync(HttpStatusCode.OK, "OfflineClaimResult");
        Assert.Equal(250 * 60, result.GetProperty("computed_amount").GetInt64());
        Assert.Equal(1000, result.GetProperty("granted_amount").GetInt64());
        Assert.False(result.GetProperty("capped").GetBoolean());
    }

    [Fact]
    public async Task Each_away_period_pays_once()
    {
        var player = await PlayerWithSaveAsync();
        var leftAt = Now;
        await AwayAsync(player, TimeSpan.FromHours(1));

        await (await ClaimAsync(player, Plenty, leftAt)).ExpectAsync(HttpStatusCode.OK);
        var again = await (await ClaimAsync(player, Plenty, leftAt)).ExpectAsync(HttpStatusCode.OK, "OfflineClaimResult");
        Assert.Equal(0, again.GetProperty("granted_amount").GetInt64());
    }

    [Fact]
    public async Task Client_clock_cannot_extend_the_window()
    {
        var player = await PlayerWithSaveAsync();
        await AwayAsync(player, TimeSpan.FromHours(1));

        // Claims to have left a week ago: still only the hour since the server last saw it.
        var result = await (await ClaimAsync(player, Plenty, Now.AddDays(-7))).ExpectAsync(HttpStatusCode.OK, "OfflineClaimResult");
        Assert.Equal(3600, result.GetProperty("away_seconds").GetInt64());
        Assert.Equal(250 * 60, result.GetProperty("granted_amount").GetInt64());
    }

    [Fact]
    public async Task Client_last_seen_can_shorten_the_window()
    {
        var player = await PlayerWithSaveAsync();
        await AwayAsync(player, TimeSpan.FromHours(1));

        // Played offline until 20 minutes ago.
        var result = await (await ClaimAsync(player, Plenty, Now.AddMinutes(-20))).ExpectAsync(HttpStatusCode.OK, "OfflineClaimResult");
        Assert.Equal(20 * 60, result.GetProperty("away_seconds").GetInt64());
        Assert.Equal(250 * 20, result.GetProperty("granted_amount").GetInt64());

        // A last_seen in the future just means "not away".
        await AwayAsync(player, TimeSpan.FromHours(1));
        result = await (await ClaimAsync(player, Plenty, Now.AddHours(5))).ExpectAsync(HttpStatusCode.OK, "OfflineClaimResult");
        Assert.Equal(0, result.GetProperty("granted_amount").GetInt64());
    }

    [Fact]
    public async Task Short_absences_pay_nothing()
    {
        var player = await PlayerWithSaveAsync();
        var leftAt = Now;
        api.Time.Advance(TimeSpan.FromSeconds(299));

        var result = await (await ClaimAsync(player, Plenty, leftAt)).ExpectAsync(HttpStatusCode.OK, "OfflineClaimResult");
        Assert.Equal(0, result.GetProperty("computed_amount").GetInt64());
        Assert.Equal(299, result.GetProperty("away_seconds").GetInt64());
    }

    [Fact]
    public async Task Cap_upgrades_band_and_price_upgrades_follow_the_formula()
    {
        // sef +1 h cap per level; bolji_sank x1.06 menu price; trio x1.1 tips, 3000/h upkeep.
        var player = await PlayerWithSaveAsync(new { sef = 2, bolji_sank = 1 }, band: "trio");
        var leftAt = Now;
        await AwayAsync(player, TimeSpan.FromHours(5));

        var result = await (await ClaimAsync(player, Plenty, leftAt)).ExpectAsync(HttpStatusCode.OK, "OfflineClaimResult");
        var ratePerMinute = 250 * 1.06 * 1.1 - 3000 / 60.0;
        Assert.Equal(4.0, result.GetProperty("cap_hours").GetDouble());
        Assert.Equal((long)Math.Floor(ratePerMinute * 240), result.GetProperty("granted_amount").GetInt64());
    }

    [Fact]
    public async Task Uploading_the_save_before_claiming_keeps_the_away_period()
    {
        var player = await PlayerWithSaveAsync();
        var leftAt = Now;
        await AwayAsync(player, TimeSpan.FromHours(2));

        // Session start: the client syncs its (unchanged) save first, then claims.
        await (await player.Client.PutJsonAsync("/v1/save", new { base_version = 1, save = TestApi.Save(lastSeen: leftAt) }))
            .ExpectAsync(HttpStatusCode.OK);
        var result = await (await ClaimAsync(player, Plenty, leftAt, saveVersion: 2)).ExpectAsync(HttpStatusCode.OK, "OfflineClaimResult");
        Assert.Equal(250 * 120, result.GetProperty("granted_amount").GetInt64());
    }

    [Fact]
    public async Task Live_event_income_multipliers_apply_pro_rata()
    {
        var player = await PlayerWithSaveAsync();
        var leftAt = Now;
        var eventId = $"double_{Guid.NewGuid():N}"[..20];
        await api.WithDbAsync(async db =>
        {
            db.LiveEvents.Add(new LiveEvent
            {
                Id = eventId,
                Name = """{"sr":"Dupla zarada"}""",
                StartsAt = leftAt,
                EndsAt = leftAt.AddMinutes(30),
                Modifiers = """[{"stat":"income","value":2.0},{"stat":"tip_rate","value":3.0}]""",
            });
            await db.SaveChangesAsync();
        });

        await AwayAsync(player, TimeSpan.FromHours(1));
        var result = await (await ClaimAsync(player, Plenty, leftAt)).ExpectAsync(HttpStatusCode.OK, "OfflineClaimResult");

        // 30 min at 2x + 30 min at 1x; tip_rate doesn't affect offline income.
        Assert.Equal(250 * (30 * 2 + 30), result.GetProperty("granted_amount").GetInt64());
        Assert.Equal(new[] { eventId }, result.GetProperty("live_event_ids").EnumerateArray().Select(e => e.GetString()!));
    }

    [Fact]
    public async Task Stale_save_version_is_409_and_missing_save_is_404()
    {
        var player = await PlayerWithSaveAsync();
        await (await ClaimAsync(player, 10, Now, saveVersion: 5)).ExpectProblemAsync(HttpStatusCode.Conflict, "save_version_mismatch");

        var fresh = await api.NewPlayerAsync();
        await (await ClaimAsync(fresh, 10, Now)).ExpectProblemAsync(HttpStatusCode.NotFound, "save_not_found");
    }

    [Fact]
    public async Task Bad_bodies_are_400_and_auth_is_required()
    {
        var player = await PlayerWithSaveAsync();
        await (await player.Client.PostJsonAsync("/v1/offline-earnings/claim", new { last_seen = Now, claimed_amount = -1, save_version = 1 }))
            .ExpectProblemAsync(HttpStatusCode.BadRequest, "bad_request");
        await (await player.Client.PostJsonAsync("/v1/offline-earnings/claim", new { last_seen = "yesterday", claimed_amount = 1, save_version = 1 }))
            .ExpectProblemAsync(HttpStatusCode.BadRequest, "bad_request");

        await (await ClaimAsync(new Session(api.Factory.CreateClient(), Guid.Empty, ""), 1, Now))
            .ExpectProblemAsync(HttpStatusCode.Unauthorized, "unauthorized");
    }
}
