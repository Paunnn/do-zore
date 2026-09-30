using System.Net;
using System.Text.RegularExpressions;
using DoZore.Api.Tests.Infrastructure;

namespace DoZore.Api.Tests;

[Collection(ApiCollection.Name)]
public sealed partial class AuthTests(ApiFixture api)
{
    [Fact]
    public async Task Device_login_creates_a_player_once_and_logs_back_in()
    {
        var client = api.Factory.CreateClient();
        var device = Guid.NewGuid();
        var secret = TestApi.NewSecret();

        var first = await (await client.PostJsonAsync("/v1/auth/device", TestApi.DeviceLogin(device, secret)))
            .ExpectAsync(HttpStatusCode.OK, "TokenPair");
        Assert.True(first.GetProperty("is_new_player").GetBoolean());
        Assert.Equal("Bearer", first.GetProperty("token_type").GetString());
        Assert.Equal(15 * 60, first.GetProperty("expires_in").GetInt32());
        Assert.Equal(30 * 86400, first.GetProperty("refresh_expires_in").GetInt32());

        var second = await (await client.PostJsonAsync("/v1/auth/device", TestApi.DeviceLogin(device, secret)))
            .ExpectAsync(HttpStatusCode.OK, "TokenPair");
        Assert.False(second.GetProperty("is_new_player").GetBoolean());
        Assert.Equal(first.GetProperty("player_id").GetGuid(), second.GetProperty("player_id").GetGuid());
    }

    [Fact]
    public async Task Device_login_with_the_wrong_secret_is_rejected()
    {
        var player = await api.NewPlayerAsync();
        var response = await api.Factory.CreateClient().PostJsonAsync("/v1/auth/device", TestApi.DeviceLogin(player.DeviceId, TestApi.NewSecret()));
        await response.ExpectProblemAsync(HttpStatusCode.Unauthorized, "invalid_device_credentials");
    }

    [Theory]
    [InlineData("""{"device_id":"not-a-uuid","device_secret":"0123456789abcdef0123456789abcdef","platform":"android","app_version":"1"}""")]
    [InlineData("""{"device_id":"6f1c2c1e-1111-4b8e-9f00-000000000001","device_secret":"short","platform":"android","app_version":"1"}""")]
    [InlineData("""{"device_id":"6f1c2c1e-1111-4b8e-9f00-000000000001","device_secret":"0123456789abcdef0123456789abcdef","platform":"windows","app_version":"1"}""")]
    [InlineData("""{"device_id":"6f1c2c1e-1111-4b8e-9f00-000000000001","device_secret":"0123456789abcdef0123456789abcdef","platform":"ios","app_version":"1","extra":1}""")]
    [InlineData("""{"device_id":"6f1c2c1e-1111-4b8e-9f00-000000000001"}""")]
    [InlineData("not json")]
    public async Task Device_login_rejects_bodies_that_break_the_contract(string body)
    {
        var response = await api.Factory.CreateClient().PostRawAsync("/v1/auth/device", body);
        await response.ExpectProblemAsync(HttpStatusCode.BadRequest, "bad_request");
    }

    [Fact]
    public async Task Refresh_rotates_tokens_and_reuse_revokes_the_family()
    {
        var player = await api.NewPlayerAsync();
        var client = api.Factory.CreateClient();
        var original = player.RefreshToken;

        var rotated = await (await client.PostJsonAsync("/v1/auth/refresh", new { refresh_token = original }))
            .ExpectAsync(HttpStatusCode.OK, "TokenPair");
        Assert.False(rotated.GetProperty("is_new_player").GetBoolean());
        player.Apply(rotated);
        await (await player.Client.GetAsync("/v1/me")).ExpectAsync(HttpStatusCode.OK, "Player");

        // Reusing the old token is treated as theft: it fails and kills the new one too.
        await (await client.PostJsonAsync("/v1/auth/refresh", new { refresh_token = original }))
            .ExpectProblemAsync(HttpStatusCode.Unauthorized, "invalid_refresh_token");
        await (await client.PostJsonAsync("/v1/auth/refresh", new { refresh_token = player.RefreshToken }))
            .ExpectProblemAsync(HttpStatusCode.Unauthorized, "invalid_refresh_token");
    }

    [Fact]
    public async Task Refresh_rejects_unknown_tokens_and_bad_bodies()
    {
        var client = api.Factory.CreateClient();
        await (await client.PostJsonAsync("/v1/auth/refresh", new { refresh_token = "garbage" }))
            .ExpectProblemAsync(HttpStatusCode.Unauthorized, "invalid_refresh_token");
        await (await client.PostJsonAsync("/v1/auth/refresh", new { token = "x" }))
            .ExpectProblemAsync(HttpStatusCode.BadRequest, "bad_request");
    }

    [Fact]
    public async Task Access_tokens_expire_after_15_minutes_and_refresh_tokens_after_30_days()
    {
        var player = await api.NewPlayerAsync();
        api.Time.Advance(TimeSpan.FromMinutes(16));
        await (await player.Client.GetAsync("/v1/me")).ExpectProblemAsync(HttpStatusCode.Unauthorized, "unauthorized");

        await player.RefreshAsync();
        await (await player.Client.GetAsync("/v1/me")).ExpectAsync(HttpStatusCode.OK, "Player");

        api.Time.Advance(TimeSpan.FromDays(31));
        await (await player.Client.PostJsonAsync("/v1/auth/refresh", new { refresh_token = player.RefreshToken }))
            .ExpectProblemAsync(HttpStatusCode.Unauthorized, "invalid_refresh_token");
    }

    [Fact]
    public async Task Me_requires_a_valid_token()
    {
        var client = api.Factory.CreateClient();
        await (await client.GetAsync("/v1/me")).ExpectProblemAsync(HttpStatusCode.Unauthorized, "unauthorized");

        client.DefaultRequestHeaders.Authorization = new("Bearer", "not.a.jwt");
        await (await client.GetAsync("/v1/me")).ExpectProblemAsync(HttpStatusCode.Unauthorized, "unauthorized");
    }

    [Fact]
    public async Task Me_returns_a_generated_guest_name()
    {
        var player = await api.NewPlayerAsync();
        var me = await (await player.Client.GetAsync("/v1/me")).ExpectAsync(HttpStatusCode.OK, "Player");

        Assert.Equal(player.PlayerId, me.GetProperty("player_id").GetGuid());
        Assert.Matches(GuestName(), me.GetProperty("display_name").GetString());
        Assert.Equal(0, me.GetProperty("linked_providers").GetArrayLength());
    }

    [Fact]
    public async Task Me_display_name_can_be_changed_with_serbian_letters()
    {
        var player = await api.NewPlayerAsync();
        var me = await (await player.Client.PatchJsonAsync("/v1/me", new { display_name = "  Čika Đorđe_1 " }))
            .ExpectAsync(HttpStatusCode.OK, "Player");
        Assert.Equal("Čika Đorđe_1", me.GetProperty("display_name").GetString());

        me = await (await player.Client.GetAsync("/v1/me")).ExpectAsync(HttpStatusCode.OK, "Player");
        Assert.Equal("Čika Đorđe_1", me.GetProperty("display_name").GetString());
    }

    [Theory]
    [InlineData("ab")]
    [InlineData("<script>")]
    [InlineData("this name is far too long")]
    public async Task Me_rejects_invalid_display_names(string name)
    {
        var player = await api.NewPlayerAsync();
        await (await player.Client.PatchJsonAsync("/v1/me", new { display_name = name }))
            .ExpectProblemAsync(HttpStatusCode.BadRequest, "bad_request");
    }

    [Theory]
    [InlineData("Admin")]
    [InlineData("Ádmin 99")]
    [InlineData("do zore")]
    public async Task Me_rejects_blocked_display_names(string name)
    {
        var player = await api.NewPlayerAsync();
        await (await player.Client.PatchJsonAsync("/v1/me", new { display_name = name }))
            .ExpectProblemAsync(HttpStatusCode.UnprocessableEntity, "display_name_rejected");
    }

    [GeneratedRegex(@"^Gost \d{4}$")]
    private static partial Regex GuestName();
}
