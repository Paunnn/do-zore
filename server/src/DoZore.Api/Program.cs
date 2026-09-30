using DoZore.Api.Auth;
using DoZore.Api.Data;
using DoZore.Api.Features;
using DoZore.Api.GameData;
using DoZore.Api.Infrastructure;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.EntityFrameworkCore;
using Serilog;
using Serilog.Formatting.Compact;

// Commands:
//   (none)                                      run the API
//   seed [--data <dir>] [--live-events <file>]  load /data (and optionally live events) into the DB, then exit
var command = args.FirstOrDefault(a => !a.StartsWith('-')) ?? "serve";

var builder = WebApplication.CreateBuilder(args);
var config = builder.Configuration;

if (config["PORT"] is { Length: > 0 } port)
    builder.WebHost.UseUrls($"http://0.0.0.0:{port}");

builder.Services.AddSerilog((services, log) => log
    .ReadFrom.Configuration(config)
    .ReadFrom.Services(services)
    .Enrich.FromLogContext()
    .WriteTo.Console(new RenderedCompactJsonFormatter()));

var connectionString = config["DB_CONNECTION_STRING"] ?? config.GetConnectionString("Default")
    ?? throw new InvalidOperationException("Set DB_CONNECTION_STRING.");
builder.Services.AddDbContext<AppDbContext>(o => AppDbContext.Configure(o, connectionString));

var jwt = config.GetSection("Jwt").Get<JwtSettings>() ?? new JwtSettings();
jwt.Secret = config["JWT_SECRET"] ?? jwt.Secret;
if (command == "serve")
    jwt.Validate(builder.Environment.IsProduction());

builder.Services.TryAddTimeProvider();
builder.Services.AddSingleton(AppPaths.Resolve(config));
builder.Services.AddSingleton<ContractSchemas>();
builder.Services.AddSingleton<GameDataLoader>();
builder.Services.AddSingleton<GameDataProvider>();
builder.Services.AddScoped<Seeder>();
builder.Services.AddDoZoreAuth(jwt);
builder.Services.AddDoZoreRateLimiting(config.GetSection("RateLimiting").Get<RateLimitSettings>() ?? new RateLimitSettings());
builder.Services.ConfigureHttpJsonOptions(o => JsonDefaults.Configure(o.SerializerOptions));
builder.Services.AddCors(o => o.AddDefaultPolicy(p => p
    .WithOrigins(config.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [])
    .AllowAnyHeader().AllowAnyMethod().WithExposedHeaders("ETag", "Retry-After")));

var app = builder.Build();

if (command == "seed")
    return await Seed(app);

if (config.GetValue("Database:MigrateOnStartup", true))
{
    using var scope = app.Services.CreateScope();
    await scope.ServiceProvider.GetRequiredService<AppDbContext>().Database.MigrateAsync();
}

// Fail fast if the contract can't be loaded.
_ = app.Services.GetRequiredService<ContractSchemas>();

app.UseExceptionHandler(handler => handler.Run(async ctx =>
{
    var error = ctx.Features.Get<IExceptionHandlerFeature>()?.Error;
    if (error is BadHttpRequestException bad)
    {
        var (code, title) = bad.StatusCode == StatusCodes.Status413PayloadTooLarge
            ? ("payload_too_large", "Payload too large") : ("bad_request", "Bad request");
        await Problems.WriteAsync(ctx, bad.StatusCode, code, title, bad.Message);
        return;
    }

    await Problems.WriteAsync(ctx, StatusCodes.Status500InternalServerError, "internal_error", "Internal server error");
}));

// Contract-shaped bodies for framework-generated empty errors (unknown route, wrong method).
app.UseStatusCodePages(async status =>
{
    var ctx = status.HttpContext;
    if (ctx.Response.StatusCode is 404 or 405)
        await Problems.WriteAsync(ctx, ctx.Response.StatusCode,
            ctx.Response.StatusCode == 404 ? "not_found" : "method_not_allowed",
            ctx.Response.StatusCode == 404 ? "Not found" : "Method not allowed");
});

app.UseSerilogRequestLogging(o =>
{
    o.EnrichDiagnosticContext = (diag, http) =>
    {
        if (http.User.PlayerIdOrNull() is { } playerId)
            diag.Set("PlayerId", playerId);
    };
    // 501 is the planned-endpoint answer, not a server fault.
    o.GetLevel = (http, _, ex) => ex is not null || (http.Response.StatusCode >= 500 && http.Response.StatusCode != 501)
        ? Serilog.Events.LogEventLevel.Error
        : Serilog.Events.LogEventLevel.Information;
});

app.UseCors();
app.UseAuthentication();
app.UseAuthorization();
app.UseRateLimiter();

app.MapGet("/v1/health", (TimeProvider time) => Results.Ok(new HealthResponse("ok", time.GetUtcNow()))).AllowAnonymous();
app.MapAuth();
app.MapSave();
app.MapConfig();

await app.RunAsync();
return 0;

static async Task<int> Seed(WebApplication app)
{
    var config = app.Configuration;
    using var scope = app.Services.CreateScope();
    var log = scope.ServiceProvider.GetRequiredService<ILogger<Program>>();
    try
    {
        await scope.ServiceProvider.GetRequiredService<AppDbContext>().Database.MigrateAsync();
        var seeder = scope.ServiceProvider.GetRequiredService<Seeder>();
        await seeder.SeedGameDataAsync(config["data"]);
        if (config["live-events"] is { Length: > 0 } liveEvents)
            await seeder.SeedLiveEventsAsync(liveEvents);
        return 0;
    }
    catch (GameDataException ex)
    {
        log.LogError("Seed failed: {Errors}", string.Join("; ", ex.Errors));
        return 1;
    }
    finally
    {
        await Log.CloseAndFlushAsync();
    }
}

public partial class Program;

static class TimeProviderRegistration
{
    public static void TryAddTimeProvider(this IServiceCollection services)
    {
        if (services.All(d => d.ServiceType != typeof(TimeProvider)))
            services.AddSingleton(TimeProvider.System);
    }
}
