using DoZore.Api.Features;
using DoZore.Api.Infrastructure;
using Microsoft.AspNetCore.Diagnostics;
using Serilog;
using Serilog.Formatting.Compact;

var builder = WebApplication.CreateBuilder(args);
var config = builder.Configuration;

if (config["PORT"] is { Length: > 0 } port)
    builder.WebHost.UseUrls($"http://0.0.0.0:{port}");

builder.Services.AddSerilog((services, log) => log
    .ReadFrom.Configuration(config)
    .ReadFrom.Services(services)
    .Enrich.FromLogContext()
    .WriteTo.Console(new RenderedCompactJsonFormatter()));

builder.Services.TryAddTimeProvider();
builder.Services.AddSingleton(AppPaths.Resolve(config));
builder.Services.AddSingleton<ContractSchemas>();
builder.Services.ConfigureHttpJsonOptions(o => JsonDefaults.Configure(o.SerializerOptions));
builder.Services.AddCors(o => o.AddDefaultPolicy(p => p
    .WithOrigins(config.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [])
    .AllowAnyHeader().AllowAnyMethod().WithExposedHeaders("ETag", "Retry-After")));

var app = builder.Build();

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

app.UseSerilogRequestLogging();

app.UseCors();

app.MapGet("/v1/health", (TimeProvider time) => Results.Ok(new HealthResponse("ok", time.GetUtcNow()))).AllowAnonymous();

await app.RunAsync();
return 0;

public partial class Program;

static class TimeProviderRegistration
{
    public static void TryAddTimeProvider(this IServiceCollection services)
    {
        if (services.All(d => d.ServiceType != typeof(TimeProvider)))
            services.AddSingleton(TimeProvider.System);
    }
}
