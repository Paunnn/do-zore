using System.Security.Claims;
using DoZore.Api.Infrastructure;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.JsonWebTokens;
using Microsoft.IdentityModel.Tokens;

namespace DoZore.Api.Auth;

public static class AuthSetup
{
    public static IServiceCollection AddDoZoreAuth(this IServiceCollection services, JwtSettings settings)
    {
        services.AddSingleton(settings);
        services.AddScoped<TokenService>();
        services.AddAuthorization();
        services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer();

        // Configured through DI so token lifetime is checked against the app's TimeProvider.
        services.AddOptions<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme)
            .Configure<TimeProvider>((o, time) =>
            {
                o.MapInboundClaims = false;
                o.TokenValidationParameters = new TokenValidationParameters
                {
                    ValidIssuer = settings.Issuer,
                    ValidAudience = settings.Audience,
                    IssuerSigningKey = settings.SigningKey,
                    ValidAlgorithms = [SecurityAlgorithms.HmacSha256],
                    NameClaimType = JwtRegisteredClaimNames.Sub,
                    LifetimeValidator = (notBefore, expires, _, _) =>
                    {
                        var now = time.GetUtcNow().UtcDateTime;
                        var skew = TimeSpan.FromSeconds(30);
                        return (notBefore is null || notBefore <= now + skew) && expires is not null && expires > now - skew;
                    },
                };
                o.Events = new JwtBearerEvents
                {
                    OnChallenge = async ctx =>
                    {
                        ctx.HandleResponse();
                        ctx.Response.Headers.WWWAuthenticate = "Bearer";
                        await Problems.WriteAsync(ctx.HttpContext, StatusCodes.Status401Unauthorized, "unauthorized",
                            "Unauthorized", "Missing, invalid or expired access token.");
                    },
                };
            });

        return services;
    }

    public static Guid PlayerId(this ClaimsPrincipal user) =>
        Guid.Parse(user.FindFirstValue(JwtRegisteredClaimNames.Sub)
            ?? throw new InvalidOperationException("No authenticated player"));

    public static Guid? PlayerIdOrNull(this ClaimsPrincipal user) =>
        user.Identity?.IsAuthenticated == true && Guid.TryParse(user.FindFirstValue(JwtRegisteredClaimNames.Sub), out var id) ? id : null;
}
