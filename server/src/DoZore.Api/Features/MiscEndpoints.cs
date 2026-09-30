using System.Text.Json;
using DoZore.Api.Auth;
using DoZore.Api.Data;
using DoZore.Api.Infrastructure;
using Microsoft.EntityFrameworkCore;
using Npgsql;
using NpgsqlTypes;

namespace DoZore.Api.Features;

public static class MiscEndpoints
{
    public const long MaxAnalyticsBytes = 512 * 1024;
    static readonly TimeSpan UpcomingWindow = TimeSpan.FromDays(7);

    public static void MapMisc(this IEndpointRouteBuilder app)
    {
        app.MapGet("/v1/health", (TimeProvider time) => Results.Ok(new HealthResponse("ok", time.GetUtcNow()))).AllowAnonymous();
        app.MapGet("/v1/events/active", GetLiveEvents).AllowAnonymous();
        app.MapPost("/v1/analytics/batch", PostAnalytics).AllowAnonymous().RequireRateLimiting(RateLimiting.Analytics);
        app.MapPost("/v1/iap/validate", (Delegate)ValidatePurchase).RequireAuthorization().RequireRateLimiting(RateLimiting.Writes);
    }

    static async Task<IResult> GetLiveEvents(AppDbContext db, TimeProvider time, CancellationToken ct)
    {
        var now = time.GetUtcNow();
        var horizon = now + UpcomingWindow;
        var events = await db.LiveEvents.AsNoTracking()
            .Where(e => e.EndsAt > now && e.StartsAt < horizon)
            .OrderBy(e => e.StartsAt).ThenBy(e => e.Id)
            .ToListAsync(ct);

        return Results.Ok(new LiveEventList(now, events.Select(e => new LiveEventDto(
            e.Id, Parse(e.Name), e.Description is null ? null : Parse(e.Description), e.StartsAt, e.EndsAt, Parse(e.Modifiers))).ToList()));
    }

    static async Task<IResult> PostAnalytics(HttpContext ctx, AppDbContext db, TimeProvider time)
    {
        var body = await ctx.ReadAsync<AnalyticsBatch>("AnalyticsBatch", MaxAnalyticsBytes);
        if (body.Failed) return body.Error!;
        var batch = body.Value!;

        var events = batch.Events.DistinctBy(e => e.EventId).ToList();
        const string sql = """
            INSERT INTO analytics_events
                (event_id, player_id, device_id, session_id, platform, app_version, data_version_hash, name, ts, params, sent_at, received_at)
            SELECT e.event_id, @player_id, @device_id, @session_id, @platform, @app_version, @data_version_hash, e.name, e.ts, e.params, @sent_at, @received_at
            FROM unnest(@event_ids, @names, @tss, @params) AS e(event_id, name, ts, params)
            ON CONFLICT (event_id) DO NOTHING
            """;

        var inserted = await db.Database.ExecuteSqlRawAsync(sql, [
            new NpgsqlParameter("player_id", NpgsqlDbType.Uuid) { Value = (object?)ctx.User.PlayerIdOrNull() ?? DBNull.Value },
            new NpgsqlParameter("device_id", batch.DeviceId),
            new NpgsqlParameter("session_id", batch.SessionId),
            new NpgsqlParameter("platform", batch.Platform.ToString().ToLowerInvariant()),
            new NpgsqlParameter("app_version", batch.AppVersion),
            new NpgsqlParameter("data_version_hash", NpgsqlDbType.Text) { Value = (object?)batch.DataVersionHash ?? DBNull.Value },
            new NpgsqlParameter("sent_at", batch.SentAt.ToUniversalTime()),
            new NpgsqlParameter("received_at", time.GetUtcNow()),
            new NpgsqlParameter("event_ids", events.Select(e => e.EventId).ToArray()),
            new NpgsqlParameter("names", events.Select(e => e.Name).ToArray()),
            new NpgsqlParameter("tss", events.Select(e => e.Ts.ToUniversalTime()).ToArray()),
            new NpgsqlParameter("params", NpgsqlDbType.Array | NpgsqlDbType.Jsonb)
                { Value = events.Select(e => e.Params?.GetRawText()).ToArray() },
        ], ctx.RequestAborted);

        return Results.Json(new AnalyticsAccepted(inserted, batch.Events.Count - inserted), JsonDefaults.Options,
            statusCode: StatusCodes.Status202Accepted);
    }

    static async Task<IResult> ValidatePurchase(HttpContext ctx)
    {
        var body = await ctx.ReadAsync<object>("IapValidationRequest");
        return body.Failed ? body.Error! : Problems.NotImplemented("Receipt validation is a stub in v1.");
    }

    static JsonElement Parse(string json)
    {
        using var doc = JsonDocument.Parse(json);
        return doc.RootElement.Clone();
    }
}
