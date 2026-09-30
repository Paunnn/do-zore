using System.Net;
using System.Text.Json;
using DoZore.Api.Tests.Infrastructure;
using Microsoft.AspNetCore.Routing;
using Microsoft.Extensions.DependencyInjection;

namespace DoZore.Api.Tests;

[Collection(ApiCollection.Name)]
public sealed class SystemTests(ApiFixture api)
{
    [Fact]
    public async Task Health_returns_ok_with_server_time()
    {
        var body = await (await api.Factory.CreateClient().GetAsync("/v1/health")).ExpectAsync(HttpStatusCode.OK, "Health");

        Assert.Equal("ok", body.GetProperty("status").GetString());
        Assert.Equal(api.Time.GetUtcNow(), body.GetProperty("server_time").GetDateTimeOffset());
    }

    [Fact]
    public async Task Unknown_route_is_a_problem_404()
    {
        await (await api.Factory.CreateClient().GetAsync("/v1/nope")).ExpectProblemAsync(HttpStatusCode.NotFound, "not_found");
    }

    [Fact]
    public void Every_contract_operation_is_implemented_and_nothing_else_is_exposed()
    {
        var contract = new HashSet<string>();
        foreach (var path in api.Contract.OpenApi.GetProperty("paths").EnumerateObject())
        foreach (var op in path.Value.EnumerateObject())
            contract.Add($"{op.Name.ToUpperInvariant()} {path.Name}");

        var implemented = api.Factory.Services.GetRequiredService<EndpointDataSource>().Endpoints
            .OfType<RouteEndpoint>()
            .SelectMany(e => (e.Metadata.GetMetadata<HttpMethodMetadata>()?.HttpMethods ?? [])
                .Select(m => $"{m} /{e.RoutePattern.RawText!.TrimStart('/')}"))
            .ToHashSet();

        Assert.Empty(contract.Except(implemented));
        Assert.Empty(implemented.Except(contract));
    }

    [Fact]
    public void Contract_components_all_build()
    {
        Assert.Contains("SaveEnvelope", api.Contract.ComponentNames);
        Assert.Contains("TokenPair", api.Contract.ComponentNames);
        Assert.Equal(JsonValueKind.Object, api.Contract.OpenApi.GetProperty("paths").ValueKind);
    }
}
