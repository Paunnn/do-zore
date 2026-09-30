using System.Net;
using DoZore.Api.Data;
using DoZore.Api.GameData;
using DoZore.Api.Tests.Infrastructure;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace DoZore.Api.Tests;

[Collection(ApiCollection.Name)]
public sealed class LiveEventTests(ApiFixture api)
{
    [Fact]
    public async Task Lists_active_and_next_7_days_events_anonymously()
    {
        var now = api.Time.GetUtcNow();
        var tag = Guid.NewGuid().ToString("N")[..8];
        LiveEvent Event(string id, TimeSpan startIn, TimeSpan length, string? description = null) => new()
        {
            Id = $"{id}_{tag}",
            Name = """{"sr":"Vikend","en":"Weekend"}""",
            Description = description,
            StartsAt = now + startIn,
            EndsAt = now + startIn + length,
            // arrival_rate so these events never change other tests' offline earnings
            Modifiers = """[{"stat":"arrival_rate","value":1.5}]""",
        };

        await api.WithDbAsync(async db =>
        {
            db.LiveEvents.AddRange(
                Event("active", TimeSpan.FromHours(-1), TimeSpan.FromHours(3), """{"sr":"Dupla zarada"}"""),
                Event("soon", TimeSpan.FromDays(3), TimeSpan.FromDays(2)),
                Event("later", TimeSpan.FromDays(10), TimeSpan.FromDays(2)),
                Event("past", TimeSpan.FromDays(-3), TimeSpan.FromDays(1)));
            await db.SaveChangesAsync();
        });

        var body = await (await api.Factory.CreateClient().GetAsync("/v1/events/active")).ExpectAsync(HttpStatusCode.OK, "LiveEventList");
        var ids = body.GetProperty("events").EnumerateArray().Select(e => e.GetProperty("id").GetString()).ToList();

        Assert.Contains($"active_{tag}", ids);
        Assert.Contains($"soon_{tag}", ids);
        Assert.DoesNotContain($"later_{tag}", ids);
        Assert.DoesNotContain($"past_{tag}", ids);
        Assert.Equal(now, body.GetProperty("server_time").GetDateTimeOffset());
    }

    [Fact]
    public async Task Seeding_live_events_validates_and_upserts()
    {
        var file = Path.GetTempFileName();
        try
        {
            await File.WriteAllTextAsync(file, """
                {"live_events":[{"id":"seeded_weekend","name":{"sr":"Vikend"},"starts_at":"2030-01-05T00:00:00Z",
                 "ends_at":"2030-01-07T00:00:00Z","modifiers":[{"stat":"income","value":1.5}]}]}
                """);
            using var scope = api.Factory.Services.CreateScope();
            var seeder = scope.ServiceProvider.GetRequiredService<Seeder>();
            Assert.Equal(1, await seeder.SeedLiveEventsAsync(file));
            Assert.Equal(1, await seeder.SeedLiveEventsAsync(file)); // idempotent
            await api.WithDbAsync(async db => Assert.Equal(1, await db.LiveEvents.CountAsync(e => e.Id == "seeded_weekend")));

            await File.WriteAllTextAsync(file, """{"live_events":[{"id":"bad","name":{"sr":"x"}}]}""");
            await Assert.ThrowsAsync<GameDataException>(() => seeder.SeedLiveEventsAsync(file));
        }
        finally
        {
            File.Delete(file);
        }
    }
}

[Collection(ApiCollection.Name)]
public sealed class AnalyticsTests(ApiFixture api)
{
    object Batch(IEnumerable<object> events) => new
    {
        device_id = Guid.NewGuid(),
        session_id = Guid.NewGuid(),
        platform = "ios",
        app_version = "0.1.0",
        sent_at = api.Time.GetUtcNow(),
        events,
    };

    static object Event(Guid? id = null, string name = "song_played") => new
    {
        event_id = id ?? Guid.NewGuid(),
        name,
        ts = DateTimeOffset.UtcNow,
        @params = new { song = "tamo_daleko", match = true, mood = 71.5 },
    };

    [Fact]
    public async Task Accepts_anonymous_batches_and_deduplicates_by_event_id()
    {
        var client = api.Factory.CreateClient();
        var repeated = Guid.NewGuid();

        var first = await (await client.PostJsonAsync("/v1/analytics/batch", Batch([Event(repeated), Event(), Event(repeated)])))
            .ExpectAsync(HttpStatusCode.Accepted, "AnalyticsAccepted");
        Assert.Equal(2, first.GetProperty("accepted").GetInt32());
        Assert.Equal(1, first.GetProperty("duplicates").GetInt32());

        var again = await (await client.PostJsonAsync("/v1/analytics/batch", Batch([Event(repeated)])))
            .ExpectAsync(HttpStatusCode.Accepted, "AnalyticsAccepted");
        Assert.Equal(0, again.GetProperty("accepted").GetInt32());
        Assert.Equal(1, again.GetProperty("duplicates").GetInt32());
    }

    [Fact]
    public async Task Attributes_events_to_the_player_when_logged_in()
    {
        var player = await api.NewPlayerAsync();
        var id = Guid.NewGuid();
        await (await player.Client.PostJsonAsync("/v1/analytics/batch", Batch([Event(id, "session_start")])))
            .ExpectAsync(HttpStatusCode.Accepted, "AnalyticsAccepted");

        await api.WithDbAsync(async db =>
        {
            var stored = await db.AnalyticsEvents.SingleAsync(e => e.EventId == id);
            Assert.Equal(player.PlayerId, stored.PlayerId);
            Assert.Equal("session_start", stored.Name);
            Assert.Contains("tamo_daleko", stored.Params);
        });
    }

    [Fact]
    public async Task Rejects_invalid_and_oversized_batches()
    {
        var client = api.Factory.CreateClient();
        await (await client.PostJsonAsync("/v1/analytics/batch", Batch([Event(name: "Bad Name!")])))
            .ExpectProblemAsync(HttpStatusCode.BadRequest, "bad_request");
        await (await client.PostJsonAsync("/v1/analytics/batch", Batch([])))
            .ExpectProblemAsync(HttpStatusCode.BadRequest, "bad_request");
        await (await client.PostJsonAsync("/v1/analytics/batch", Batch(Enumerable.Range(0, 501).Select(_ => Event()))))
            .ExpectProblemAsync(HttpStatusCode.BadRequest, "bad_request");

        var huge = Enumerable.Range(0, 500).Select(_ => new
        {
            event_id = Guid.NewGuid(), name = "blob", ts = DateTimeOffset.UtcNow,
            @params = new { data = new string('x', 2000) },
        });
        await (await client.PostJsonAsync("/v1/analytics/batch", Batch(huge)))
            .ExpectProblemAsync(HttpStatusCode.RequestEntityTooLarge, "payload_too_large");
    }
}

[Collection(ApiCollection.Name)]
public sealed class StubEndpointTests(ApiFixture api)
{
    public static TheoryData<string, object, object> Stubs => new()
    {
        { "/v1/auth/link/google", new { id_token = "eyJ..." }, new { token = 1 } },
        { "/v1/auth/link/apple", new { identity_token = "a", authorization_code = "b" }, new { identity_token = "a" } },
        {
            "/v1/iap/validate",
            new { platform = "google", product_id = "starter_pack", transaction_id = "GPA.1", receipt = "token" },
            new { platform = "steam", product_id = "x", transaction_id = "1", receipt = "r" }
        },
    };

    [Theory]
    [MemberData(nameof(Stubs))]
    public async Task Stubs_check_auth_and_body_then_return_501(string url, object valid, object invalid)
    {
        await (await api.Factory.CreateClient().PostJsonAsync(url, valid))
            .ExpectProblemAsync(HttpStatusCode.Unauthorized, "unauthorized");

        var player = await api.NewPlayerAsync();
        await (await player.Client.PostJsonAsync(url, invalid)).ExpectProblemAsync(HttpStatusCode.BadRequest, "bad_request");
        await (await player.Client.PostJsonAsync(url, valid)).ExpectProblemAsync(HttpStatusCode.NotImplemented, "not_implemented");
    }
}

[Collection(ApiCollection.Name)]
public sealed class RateLimitTests(ApiFixture api)
{
    [Fact]
    public async Task Exceeding_a_limit_returns_429_with_retry_after()
    {
        await using var factory = api.CreateFactory(new Dictionary<string, string>
        {
            ["RateLimiting:Auth:PermitLimit"] = "3",
            ["RateLimiting:Auth:WindowSeconds"] = "60",
        });
        var client = factory.CreateClient();

        for (var i = 0; i < 3; i++)
            await (await client.PostJsonAsync("/v1/auth/device", TestApi.DeviceLogin(Guid.NewGuid(), TestApi.NewSecret())))
                .ExpectAsync(HttpStatusCode.OK);

        var limited = await client.PostJsonAsync("/v1/auth/device", TestApi.DeviceLogin(Guid.NewGuid(), TestApi.NewSecret()));
        await limited.ExpectProblemAsync(HttpStatusCode.TooManyRequests, "rate_limited");
        Assert.True(limited.Headers.RetryAfter?.Delta > TimeSpan.Zero);

        // Other policies are unaffected.
        await (await client.GetAsync("/v1/health")).ExpectAsync(HttpStatusCode.OK);
    }
}
