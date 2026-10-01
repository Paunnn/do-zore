using System.Text.Json;

namespace DoZore.Api.Infrastructure;

public sealed record BodyResult<T>(T? Value, JsonElement Raw, IResult? Error)
{
    public bool Failed => Error is not null;
}

/// <summary>
/// Reads a JSON request body with a size limit, validates it against the named OpenAPI component
/// schema, then deserializes it. Any failure becomes a contract-shaped problem response.
/// </summary>
public static class RequestBody
{
    public const long DefaultLimit = 64 * 1024;

    public static async Task<BodyResult<T>> ReadAsync<T>(
        this HttpContext ctx, string component, long limit = DefaultLimit,
        Func<IReadOnlyList<SchemaError>, IResult>? onSchemaErrors = null)
    {
        var (raw, error) = await ReadJsonAsync(ctx, limit);
        if (error is not null)
            return new(default, default, error);

        var schemas = ctx.RequestServices.GetRequiredService<ContractSchemas>();
        var errors = schemas.ValidateComponent(component, raw);
        if (errors.Count > 0)
            return new(default, raw, (onSchemaErrors ?? (e => Problems.BadRequest("Request body does not match the contract.", e)))(errors));

        try
        {
            return new(raw.Deserialize<T>(JsonDefaults.Options), raw, null);
        }
        catch (JsonException ex)
        {
            return new(default, raw, Problems.BadRequest(ex.Message));
        }
    }

    static async Task<(JsonElement, IResult?)> ReadJsonAsync(HttpContext ctx, long limit)
    {
        if (ctx.Request.ContentLength > limit)
            return (default, Problems.PayloadTooLarge(limit));

        using var buffer = new MemoryStream();
        var chunk = new byte[16 * 1024];
        int read;
        while ((read = await ctx.Request.Body.ReadAsync(chunk, ctx.RequestAborted)) > 0)
        {
            if (buffer.Length + read > limit)
                return (default, Problems.PayloadTooLarge(limit));
            buffer.Write(chunk, 0, read);
        }

        if (buffer.Length == 0)
            return (default, Problems.BadRequest("Request body is required."));

        try
        {
            using var doc = JsonDocument.Parse(buffer.ToArray());
            return (doc.RootElement.Clone(), null);
        }
        catch (JsonException)
        {
            return (default, Problems.BadRequest("Request body is not valid JSON."));
        }
    }
}
