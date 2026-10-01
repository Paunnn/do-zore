using System.Text;
using System.Text.Json;
using DoZore.Api.GameData;
using DoZore.Api.Infrastructure;

namespace DoZore.Api.Features;

public static class ConfigEndpoints
{
    public static void MapConfig(this IEndpointRouteBuilder app) =>
        app.MapGet("/v1/config", GetConfig).AllowAnonymous();

    static async Task<IResult> GetConfig(HttpContext ctx, GameDataProvider gameData)
    {
        var snapshot = await gameData.GetAsync(ctx.RequestAborted);
        if (snapshot is null) return Problems.GameDataUnavailable();

        var etag = $"\"{snapshot.Hash}\"";
        ctx.Response.Headers.ETag = etag;
        ctx.Response.Headers.CacheControl = "public, max-age=300";

        var ifNoneMatch = ctx.Request.GetTypedHeaders().IfNoneMatch;
        if (ifNoneMatch.Any(tag => tag.Tag == "*" || tag.Tag == etag))
            return Results.StatusCode(StatusCodes.Status304NotModified);

        return Results.Text(Body(snapshot), "application/json; charset=utf-8");
    }

    /// <summary>ConfigResponse with the stored canonical bundle embedded verbatim, so `data` hashes to version_hash.</summary>
    public static string Body(GameDataSnapshot snapshot)
    {
        using var stream = new MemoryStream();
        using (var w = new Utf8JsonWriter(stream))
        {
            w.WriteStartObject();
            w.WriteString("version_hash", snapshot.Hash);
            w.WriteString("generated_at", snapshot.GeneratedAt);
            w.WriteString("min_client_version", snapshot.MinClientVersion);
            w.WritePropertyName("data");
            w.WriteRawValue(snapshot.Canonical, skipInputValidation: true);
            w.WriteEndObject();
        }

        return Encoding.UTF8.GetString(stream.ToArray());
    }
}
