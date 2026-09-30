using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using DoZore.Api.Data;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;

namespace DoZore.Api.Auth;

public sealed class JwtSettings
{
    public string Secret { get; set; } = "";
    public string Issuer { get; set; } = "do-zore";
    public string Audience { get; set; } = "do-zore-client";
    public int AccessTokenMinutes { get; set; } = 15;
    public int RefreshTokenDays { get; set; } = 30;

    public SymmetricSecurityKey SigningKey => new(Encoding.UTF8.GetBytes(Secret));

    public void Validate(bool isProduction)
    {
        if (Encoding.UTF8.GetByteCount(Secret) < 32)
            throw new InvalidOperationException("JWT_SECRET must be at least 32 bytes.");
        if (isProduction && Secret.Contains("CHANGE_ME", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("JWT_SECRET is still the placeholder value.");
    }
}

public sealed record TokenPairResponse(
    string TokenType, string AccessToken, int ExpiresIn, string RefreshToken, int RefreshExpiresIn,
    Guid PlayerId, bool IsNewPlayer);

public enum RefreshOutcome { Ok, Invalid, Reused }

public sealed class TokenService(AppDbContext db, JwtSettings settings, TimeProvider time)
{
    static readonly JsonWebTokenHandler Handler = new();

    public static byte[] Hash(string value) => SHA256.HashData(Encoding.UTF8.GetBytes(value));

    /// <summary>Creates an access token and a new refresh token in the given family (does not save).</summary>
    public TokenPairResponse Issue(Guid playerId, Guid familyId, bool isNewPlayer)
    {
        var now = time.GetUtcNow();
        var access = Handler.CreateToken(new SecurityTokenDescriptor
        {
            Subject = new ClaimsIdentity([
                new Claim(JwtRegisteredClaimNames.Sub, playerId.ToString()),
                new Claim(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()),
            ]),
            Issuer = settings.Issuer,
            Audience = settings.Audience,
            IssuedAt = now.UtcDateTime,
            NotBefore = now.UtcDateTime,
            Expires = now.AddMinutes(settings.AccessTokenMinutes).UtcDateTime,
            SigningCredentials = new SigningCredentials(settings.SigningKey, SecurityAlgorithms.HmacSha256),
        });

        var refresh = Base64UrlEncoder.Encode(RandomNumberGenerator.GetBytes(32));
        db.RefreshTokens.Add(new RefreshToken
        {
            Id = Guid.NewGuid(),
            PlayerId = playerId,
            FamilyId = familyId,
            TokenHash = Hash(refresh),
            CreatedAt = now,
            ExpiresAt = now.AddDays(settings.RefreshTokenDays),
        });

        return new TokenPairResponse(
            "Bearer", access, settings.AccessTokenMinutes * 60, refresh, settings.RefreshTokenDays * 86400, playerId, isNewPlayer);
    }

    /// <summary>Single-use rotation. Presenting a used token revokes its whole family.</summary>
    public async Task<(RefreshOutcome, TokenPairResponse?)> RotateAsync(string refreshToken, CancellationToken ct)
    {
        var now = time.GetUtcNow();
        var hash = Hash(refreshToken);
        var token = await db.RefreshTokens.AsNoTracking().SingleOrDefaultAsync(t => t.TokenHash == hash, ct);
        if (token is null || token.RevokedAt is not null || token.ExpiresAt <= now)
            return (RefreshOutcome.Invalid, null);

        // Mark used only if still unused, so two concurrent refreshes can't both succeed.
        var claimed = await db.RefreshTokens
            .Where(t => t.Id == token.Id && t.UsedAt == null)
            .ExecuteUpdateAsync(s => s.SetProperty(t => t.UsedAt, now), ct);

        if (claimed == 0)
        {
            await db.RefreshTokens
                .Where(t => t.FamilyId == token.FamilyId && t.RevokedAt == null)
                .ExecuteUpdateAsync(s => s.SetProperty(t => t.RevokedAt, now), ct);
            return (RefreshOutcome.Reused, null);
        }

        var pair = Issue(token.PlayerId, token.FamilyId, isNewPlayer: false);
        await db.SaveChangesAsync(ct);
        return (RefreshOutcome.Ok, pair);
    }
}
