using DoZore.Api.Data;
using DoZore.Api.GameData;
using DoZore.Api.Infrastructure;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Time.Testing;
using Testcontainers.PostgreSql;

namespace DoZore.Api.Tests.Infrastructure;

[CollectionDefinition(Name)]
public sealed class ApiCollection : ICollectionFixture<ApiFixture>
{
    public const string Name = "api";
}

/// <summary>
/// One Postgres container and one API instance for the whole test run, seeded with the real /data.
/// Tests run sequentially in one collection and share a fake clock that only moves forward.
/// </summary>
public sealed class ApiFixture : IAsyncLifetime
{
    readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder("postgres:17-alpine").Build();

    public FakeTimeProvider Time { get; } = new(DateTimeOffset.UtcNow);
    public ApiFactory Factory { get; private set; } = null!;
    public string ConnectionString => _postgres.GetConnectionString();
    public ContractSchemas Contract => Factory.Services.GetRequiredService<ContractSchemas>();

    public async ValueTask InitializeAsync()
    {
        await _postgres.StartAsync();
        Factory = CreateFactory();
        ContractAssert.Schemas = Contract;
        await SeedAsync();
    }

    public ApiFactory CreateFactory(IDictionary<string, string>? settings = null) => new(ConnectionString, Time, settings);

    public async Task<string> SeedAsync(string? dataDir = null)
    {
        using var scope = Factory.Services.CreateScope();
        return await scope.ServiceProvider.GetRequiredService<Seeder>().SeedGameDataAsync(dataDir);
    }

    public async Task WithDbAsync(Func<AppDbContext, Task> action)
    {
        using var scope = Factory.Services.CreateScope();
        await action(scope.ServiceProvider.GetRequiredService<AppDbContext>());
    }

    public async ValueTask DisposeAsync()
    {
        await Factory.DisposeAsync();
        await _postgres.DisposeAsync();
    }
}

public sealed class ApiFactory(string connectionString, TimeProvider time, IDictionary<string, string>? settings)
    : WebApplicationFactory<Program>
{
    public const string JwtSecret = "integration-test-secret-at-least-32-bytes-long";

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.UseEnvironment("Testing");
        builder.UseSetting("DB_CONNECTION_STRING", connectionString);
        builder.UseSetting("JWT_SECRET", JwtSecret);
        builder.UseSetting("Serilog:MinimumLevel:Default", "Warning");

        // Generous limits so the suite itself isn't throttled; RateLimitTests override these.
        foreach (var policy in new[] { "Global", "Auth", "Writes", "Analytics" })
            builder.UseSetting($"RateLimiting:{policy}:PermitLimit", "100000");

        foreach (var (key, value) in settings ?? new Dictionary<string, string>())
            builder.UseSetting(key, value);

        builder.ConfigureTestServices(services => services.AddSingleton(time));
    }
}
