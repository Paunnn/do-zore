using System.Diagnostics;
using System.Text.Json.Serialization;

namespace DoZore.Api.Infrastructure;

/// <summary>RFC 9457 problem body as defined by the contract's Problem schema.</summary>
public sealed record Problem(
    string Title,
    int Status,
    string Code,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? Detail = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? TraceId = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] IReadOnlyList<SchemaError>? Errors = null)
{
    public string Type => "about:blank";
}

public static class Problems
{
    public const string ContentType = "application/problem+json";

    public static IResult Result(int status, string code, string title, string? detail = null, IReadOnlyList<SchemaError>? errors = null) =>
        Results.Json(Create(status, code, title, detail, errors), JsonDefaults.Options, ContentType, status);

    public static Problem Create(int status, string code, string title, string? detail = null, IReadOnlyList<SchemaError>? errors = null) =>
        new(title, status, code, detail, Activity.Current?.TraceId.ToString(), errors);

    public static Task WriteAsync(HttpContext ctx, int status, string code, string title, string? detail = null)
    {
        ctx.Response.StatusCode = status;
        return ctx.Response.WriteAsJsonAsync(Create(status, code, title, detail), JsonDefaults.Options, ContentType);
    }

    public static IResult BadRequest(string detail, IReadOnlyList<SchemaError>? errors = null) =>
        Result(StatusCodes.Status400BadRequest, "bad_request", "Bad request", detail, errors);

    public static IResult Unauthorized(string detail = "Missing, invalid or expired access token.") =>
        Result(StatusCodes.Status401Unauthorized, "unauthorized", "Unauthorized", detail);

    public static IResult NotImplemented(string detail) =>
        Result(StatusCodes.Status501NotImplemented, "not_implemented", "Not implemented", detail);

    public static IResult GameDataUnavailable() =>
        Result(StatusCodes.Status503ServiceUnavailable, "game_data_unavailable", "Game data unavailable",
            "The server has no game data loaded. Run the seed command.");

    public static IResult PayloadTooLarge(long limit) =>
        Result(StatusCodes.Status413PayloadTooLarge, "payload_too_large", "Payload too large", $"Body exceeds {limit / 1024} KiB.");
}
