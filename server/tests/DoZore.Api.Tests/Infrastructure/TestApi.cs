using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json;
using DoZore.Api.Infrastructure;

namespace DoZore.Api.Tests.Infrastructure;

/// <summary>A logged-in player with its own HttpClient.</summary>
public sealed class Session(HttpClient client, Guid deviceId, string deviceSecret)
{
    public HttpClient Client { get; } = client;
    public Guid DeviceId { get; } = deviceId;
    public string DeviceSecret { get; } = deviceSecret;
    public Guid PlayerId { get; private set; }
    public string AccessToken { get; private set; } = "";
    public string RefreshToken { get; private set; } = "";

    public void Apply(JsonElement tokenPair)
    {
        PlayerId = tokenPair.GetProperty("player_id").GetGuid();
        AccessToken = tokenPair.GetProperty("access_token").GetString()!;
        RefreshToken = tokenPair.GetProperty("refresh_token").GetString()!;
        Client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", AccessToken);
    }

    /// <summary>Gets a fresh access token (needed after advancing the fake clock past 15 minutes).</summary>
    public async Task RefreshAsync()
    {
        var response = await Client.PostJsonAsync("/v1/auth/refresh", new { refresh_token = RefreshToken });
        Apply(await response.ExpectAsync(HttpStatusCode.OK));
    }
}

public static class TestApi
{
    public static string NewSecret() => Convert.ToHexString(RandomNumberGenerator.GetBytes(24));

    public static object DeviceLogin(Guid deviceId, string secret) =>
        new { device_id = deviceId, device_secret = secret, platform = "android", app_version = "0.1.0" };

    public static async Task<Session> NewPlayerAsync(this ApiFixture fixture) => await fixture.Factory.NewPlayerAsync();

    public static async Task<Session> NewPlayerAsync(this ApiFactory factory)
    {
        var session = new Session(factory.CreateClient(), Guid.NewGuid(), NewSecret());
        var response = await session.Client.PostJsonAsync("/v1/auth/device", DeviceLogin(session.DeviceId, session.DeviceSecret));
        session.Apply(await response.ExpectAsync(HttpStatusCode.OK, "TokenPair"));
        return session;
    }

    public static Task<HttpResponseMessage> PostJsonAsync(this HttpClient client, string url, object body) =>
        client.PostAsJsonAsync(url, body, JsonDefaults.Options);

    public static Task<HttpResponseMessage> PutJsonAsync(this HttpClient client, string url, object body) =>
        client.PutAsJsonAsync(url, body, JsonDefaults.Options);

    public static Task<HttpResponseMessage> PatchJsonAsync(this HttpClient client, string url, object body) =>
        client.PatchAsJsonAsync(url, body, JsonDefaults.Options);

    public static Task<HttpResponseMessage> PostRawAsync(this HttpClient client, string url, string body) =>
        client.PostAsync(url, new StringContent(body, System.Text.Encoding.UTF8, "application/json"));

    /// <summary>Asserts the status and, when a component is given, that the body matches it in the contract.</summary>
    public static async Task<JsonElement> ExpectAsync(this HttpResponseMessage response, HttpStatusCode status, string? component = null)
    {
        var text = await response.Content.ReadAsStringAsync();
        Assert.True(response.StatusCode == status, $"Expected {(int)status}, got {(int)response.StatusCode}: {text}");
        if (text.Length == 0)
            return default;

        var body = JsonDocument.Parse(text).RootElement.Clone();
        if (component is not null)
            ContractAssert.Matches(component, body);
        return body;
    }

    /// <summary>Asserts a contract Problem response with the given status and code.</summary>
    public static async Task<JsonElement> ExpectProblemAsync(this HttpResponseMessage response, HttpStatusCode status, string code)
    {
        Assert.Equal("application/problem+json", response.Content.Headers.ContentType?.MediaType);
        var body = await response.ExpectAsync(status, "Problem");
        Assert.Equal(code, body.GetProperty("code").GetString());
        Assert.Equal((int)status, body.GetProperty("status").GetInt32());
        return body;
    }

    public static object Save(string venue = "birtija", string band = "solo_harmonikas", DateTimeOffset? lastSeen = null,
        object? upgrades = null, long money = 1000, object? client = null) => new
    {
        schema_version = 1,
        money,
        total_baksis = 0,
        venue,
        band_level = band,
        upgrades = upgrades ?? new { },
        unlocked_songs = new[] { "kafu_mi_draga", "ajde_jano" },
        last_seen = lastSeen ?? DateTimeOffset.UtcNow,
        stats = new { songs_played = 3 },
        client = client ?? new { tutorial_done = true },
    };
}

public static class ContractAssert
{
    public static ContractSchemas? Schemas { get; set; }

    public static void Matches(string component, JsonElement body)
    {
        var errors = (Schemas ?? throw new InvalidOperationException("ContractAssert.Schemas not set")).ValidateComponent(component, body);
        Assert.True(errors.Count == 0,
            $"Response does not match {component}:\n  {string.Join("\n  ", errors.Select(e => $"{e.Pointer}: {e.Message}"))}\n{body}");
    }
}
