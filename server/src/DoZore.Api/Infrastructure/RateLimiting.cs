using System.Globalization;
using System.Threading.RateLimiting;
using DoZore.Api.Auth;
using Microsoft.AspNetCore.RateLimiting;

namespace DoZore.Api.Infrastructure;

public sealed class RateLimitRule
{
    public int PermitLimit { get; set; }
    public int WindowSeconds { get; set; } = 60;
}

/// <summary>Fixed-window limits per player (when authenticated) or per client IP. Bound from "RateLimiting".</summary>
public sealed class RateLimitSettings
{
    public RateLimitRule Global { get; set; } = new() { PermitLimit = 300 };
    public RateLimitRule Auth { get; set; } = new() { PermitLimit = 20 };
    public RateLimitRule Writes { get; set; } = new() { PermitLimit = 60 };
    public RateLimitRule Analytics { get; set; } = new() { PermitLimit = 30 };
}

public static class RateLimiting
{
    public const string Auth = "auth";
    public const string Writes = "writes";
    public const string Analytics = "analytics";

    public static IServiceCollection AddDoZoreRateLimiting(this IServiceCollection services, RateLimitSettings settings)
    {
        services.AddRateLimiter(o =>
        {
            o.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(ctx => Window("global", ctx, settings.Global));
            o.AddPolicy(Auth, ctx => Window(Auth, ctx, settings.Auth, byIpOnly: true));
            o.AddPolicy(Writes, ctx => Window(Writes, ctx, settings.Writes));
            o.AddPolicy(Analytics, ctx => Window(Analytics, ctx, settings.Analytics));

            o.OnRejected = async (context, ct) =>
            {
                if (context.Lease.TryGetMetadata(MetadataName.RetryAfter, out var retryAfter))
                    context.HttpContext.Response.Headers.RetryAfter =
                        ((int)Math.Ceiling(retryAfter.TotalSeconds)).ToString(CultureInfo.InvariantCulture);

                context.HttpContext.RequestServices.GetRequiredService<ILoggerFactory>()
                    .CreateLogger("DoZore.RateLimiting")
                    .LogWarning("Rate limited {Path} for {Partition}", context.HttpContext.Request.Path, PartitionKey(context.HttpContext, false));

                await Problems.WriteAsync(context.HttpContext, StatusCodes.Status429TooManyRequests, "rate_limited",
                    "Too many requests", "Slow down and retry after the Retry-After delay.");
            };
        });
        return services;
    }

    static RateLimitPartition<string> Window(string policy, HttpContext ctx, RateLimitRule rule, bool byIpOnly = false) =>
        RateLimitPartition.GetFixedWindowLimiter($"{policy}:{PartitionKey(ctx, byIpOnly)}", _ => new FixedWindowRateLimiterOptions
        {
            PermitLimit = rule.PermitLimit,
            Window = TimeSpan.FromSeconds(rule.WindowSeconds),
            QueueLimit = 0,
        });

    static string PartitionKey(HttpContext ctx, bool byIpOnly) =>
        !byIpOnly && ctx.User.PlayerIdOrNull() is { } player
            ? $"player:{player}"
            : $"ip:{ctx.Connection.RemoteIpAddress?.ToString() ?? "unknown"}";
}
