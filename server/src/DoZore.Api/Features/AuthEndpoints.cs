using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using DoZore.Api.Auth;
using DoZore.Api.Data;
using DoZore.Api.Infrastructure;
using Microsoft.EntityFrameworkCore;

namespace DoZore.Api.Features;

public static class AuthEndpoints
{
    public static void MapAuth(this IEndpointRouteBuilder app)
    {
        var auth = app.MapGroup("/v1/auth");

        auth.MapPost("/device", LoginWithDevice).AllowAnonymous().RequireRateLimiting(RateLimiting.Auth);
        auth.MapPost("/refresh", Refresh).AllowAnonymous().RequireRateLimiting(RateLimiting.Auth);

        // Planned: shapes are validated now, linking itself returns 501 in v1.
        auth.MapPost("/link/google", (Delegate)((HttpContext ctx) => NotYet(ctx, "LinkGoogleRequest", "Google account linking")))
            .RequireAuthorization().RequireRateLimiting(RateLimiting.Writes);
        auth.MapPost("/link/apple", (Delegate)((HttpContext ctx) => NotYet(ctx, "LinkAppleRequest", "Apple ID linking")))
            .RequireAuthorization().RequireRateLimiting(RateLimiting.Writes);

        app.MapGet("/v1/me", GetMe).RequireAuthorization();
        app.MapPatch("/v1/me", UpdateMe).RequireAuthorization().RequireRateLimiting(RateLimiting.Writes);
    }

    static async Task<IResult> LoginWithDevice(HttpContext ctx, AppDbContext db, TokenService tokens, TimeProvider time, ILogger<Program> log)
    {
        var body = await ctx.ReadAsync<DeviceLoginRequest>("DeviceLoginRequest");
        if (body.Failed) return body.Error!;
        var req = body.Value!;

        var now = time.GetUtcNow();
        var secretHash = TokenService.Hash(req.DeviceSecret);
        var platform = req.Platform.ToString().ToLowerInvariant();
        var isNew = false;

        var device = await db.Devices.SingleOrDefaultAsync(d => d.DeviceId == req.DeviceId, ctx.RequestAborted);
        if (device is null)
        {
            var player = new Player { Id = Guid.NewGuid(), DisplayName = GuestName(), CreatedAt = now };
            device = new Device
            {
                DeviceId = req.DeviceId, PlayerId = player.Id, SecretHash = secretHash,
                Platform = platform, AppVersion = req.AppVersion, CreatedAt = now, LastLoginAt = now,
            };
            db.AddRange(player, device);
            try
            {
                await db.SaveChangesAsync(ctx.RequestAborted);
                isNew = true;
                log.LogInformation("New player {PlayerId} on {Platform}", player.Id, platform);
            }
            catch (DbUpdateException)
            {
                // Concurrent first login with the same device id: use the row that won.
                db.ChangeTracker.Clear();
                device = await db.Devices.SingleAsync(d => d.DeviceId == req.DeviceId, ctx.RequestAborted);
            }
        }

        if (!isNew)
        {
            if (!CryptographicOperations.FixedTimeEquals(device.SecretHash, secretHash))
                return Problems.Result(StatusCodes.Status401Unauthorized, "invalid_device_credentials",
                    "Invalid device credentials", "This device id is registered with a different secret.");

            device.LastLoginAt = now;
            device.Platform = platform;
            device.AppVersion = req.AppVersion;
        }

        var pair = tokens.Issue(device.PlayerId, familyId: Guid.NewGuid(), isNew);
        await db.SaveChangesAsync(ctx.RequestAborted);
        return Results.Ok(pair);
    }

    static async Task<IResult> Refresh(HttpContext ctx, TokenService tokens, ILogger<Program> log)
    {
        var body = await ctx.ReadAsync<RefreshRequest>("RefreshRequest");
        if (body.Failed) return body.Error!;

        var (outcome, pair) = await tokens.RotateAsync(body.Value!.RefreshToken, ctx.RequestAborted);
        if (outcome == RefreshOutcome.Reused)
            log.LogWarning("Refresh token reuse detected; token family revoked");

        return outcome == RefreshOutcome.Ok
            ? Results.Ok(pair)
            : Problems.Result(StatusCodes.Status401Unauthorized, "invalid_refresh_token",
                "Invalid refresh token", "The refresh token is invalid, expired or already used. Log in again.");
    }

    static async Task<IResult> NotYet(HttpContext ctx, string component, string feature)
    {
        var body = await ctx.ReadAsync<object>(component);
        return body.Failed ? body.Error! : Problems.NotImplemented($"{feature} is planned but not available in v1.");
    }

    static async Task<IResult> GetMe(HttpContext ctx, AppDbContext db)
    {
        var player = await db.Players.FindAsync([ctx.User.PlayerId()], ctx.RequestAborted);
        return player is null ? Problems.Unauthorized("Player no longer exists.") : Results.Ok(ToResponse(player));
    }

    static async Task<IResult> UpdateMe(HttpContext ctx, AppDbContext db, IConfiguration config)
    {
        var body = await ctx.ReadAsync<UpdatePlayerRequest>("UpdatePlayerRequest");
        if (body.Failed) return body.Error!;

        var name = body.Value!.DisplayName.Trim();
        if (name.Length is < 3 or > 20 || !name.All(c => char.IsLetterOrDigit(c) || c is ' ' or '_' or '.' or '-'))
            return Problems.BadRequest("display_name must be 3-20 letters, digits, spaces or _ . -",
                [new SchemaError("/display_name", "Invalid characters or length.")]);

        var blocked = config.GetSection("DisplayNames:Blocked").Get<string[]>() ?? [];
        var folded = Fold(name);
        if (blocked.Any(word => folded.Contains(Fold(word), StringComparison.Ordinal)))
            return Problems.Result(StatusCodes.Status422UnprocessableEntity, "display_name_rejected",
                "Display name rejected", "Please choose a different name.");

        var player = await db.Players.FindAsync([ctx.User.PlayerId()], ctx.RequestAborted);
        if (player is null)
            return Problems.Unauthorized("Player no longer exists.");

        player.DisplayName = name;
        await db.SaveChangesAsync(ctx.RequestAborted);
        return Results.Ok(ToResponse(player));
    }

    static PlayerResponse ToResponse(Player p) => new(p.Id, p.DisplayName, p.CreatedAt, []);

    static string GuestName() => $"Gost {RandomNumberGenerator.GetInt32(1000, 10000)}";

    /// <summary>Lower-case and strip diacritics (č→c, đ→d) so the blocklist can't be dodged with accents.</summary>
    static string Fold(string s)
    {
        var decomposed = s.Replace('đ', 'd').Replace('Đ', 'D').Normalize(NormalizationForm.FormD);
        var sb = new StringBuilder(decomposed.Length);
        foreach (var c in decomposed)
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark && char.IsLetterOrDigit(c))
                sb.Append(char.ToLowerInvariant(c));
        return sb.ToString();
    }
}
