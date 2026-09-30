using System.Net;
using DoZore.Api.Tests.Infrastructure;

namespace DoZore.Api.Tests;

[Collection(ApiCollection.Name)]
public sealed class SaveTests(ApiFixture api)
{
    object Save(string venue = "birtija", object? upgrades = null, object? client = null, long money = 1000) =>
        TestApi.Save(venue, lastSeen: api.Time.GetUtcNow(), upgrades: upgrades, client: client, money: money);

    [Fact]
    public async Task Get_without_a_save_is_404()
    {
        var player = await api.NewPlayerAsync();
        await (await player.Client.GetAsync("/v1/save")).ExpectProblemAsync(HttpStatusCode.NotFound, "save_not_found");
    }

    [Fact]
    public async Task Put_then_get_round_trips_and_versions_increase()
    {
        var player = await api.NewPlayerAsync();

        var v1 = await (await player.Client.PutJsonAsync("/v1/save", new { base_version = 0, save = Save(money: 1234) }))
            .ExpectAsync(HttpStatusCode.OK, "SaveWriteResult");
        Assert.Equal(1, v1.GetProperty("version").GetInt32());

        var got = await (await player.Client.GetAsync("/v1/save")).ExpectAsync(HttpStatusCode.OK, "SaveEnvelope");
        Assert.Equal(1, got.GetProperty("version").GetInt32());
        Assert.Equal(1234, got.GetProperty("save").GetProperty("money").GetInt64());
        Assert.True(got.GetProperty("save").GetProperty("client").GetProperty("tutorial_done").GetBoolean());

        var v2 = await (await player.Client.PutJsonAsync("/v1/save", new { base_version = 1, save = Save(money: 99) }))
            .ExpectAsync(HttpStatusCode.OK, "SaveWriteResult");
        Assert.Equal(2, v2.GetProperty("version").GetInt32());
    }

    [Fact]
    public async Task Stale_base_version_is_a_409_with_the_server_copy()
    {
        var player = await api.NewPlayerAsync();
        await (await player.Client.PutJsonAsync("/v1/save", new { base_version = 0, save = Save(money: 1) })).ExpectAsync(HttpStatusCode.OK);
        await (await player.Client.PutJsonAsync("/v1/save", new { base_version = 1, save = Save(money: 2) })).ExpectAsync(HttpStatusCode.OK);

        // A second device still thinks the cloud is at v1.
        var conflict = await (await player.Client.PutJsonAsync("/v1/save", new { base_version = 1, save = Save(money: 3) }))
            .ExpectAsync(HttpStatusCode.Conflict, "SaveConflict");
        Assert.Equal("save_conflict", conflict.GetProperty("code").GetString());
        Assert.Equal(2, conflict.GetProperty("server").GetProperty("version").GetInt32());
        Assert.Equal(2, conflict.GetProperty("server").GetProperty("save").GetProperty("money").GetInt64());

        // Creating with base_version 0 when a save already exists is also a conflict.
        await (await player.Client.PutJsonAsync("/v1/save", new { base_version = 0, save = Save(money: 4) }))
            .ExpectAsync(HttpStatusCode.Conflict, "SaveConflict");
    }

    [Fact]
    public async Task Any_base_version_is_accepted_when_there_is_no_server_save()
    {
        var player = await api.NewPlayerAsync();
        var result = await (await player.Client.PutJsonAsync("/v1/save", new { base_version = 7, save = Save() }))
            .ExpectAsync(HttpStatusCode.OK, "SaveWriteResult");
        Assert.Equal(1, result.GetProperty("version").GetInt32());
    }

    [Fact]
    public async Task Saves_referencing_unknown_content_are_422()
    {
        var player = await api.NewPlayerAsync();

        var body = await (await player.Client.PutJsonAsync("/v1/save", new { base_version = 0, save = Save(venue: "kazino") }))
            .ExpectProblemAsync(HttpStatusCode.UnprocessableEntity, "invalid_save");
        Assert.Contains("/save/venue", body.GetProperty("errors").ToString());

        body = await (await player.Client.PutJsonAsync("/v1/save", new { base_version = 0, save = Save(upgrades: new { sef = 99 }) }))
            .ExpectProblemAsync(HttpStatusCode.UnprocessableEntity, "invalid_save");
        Assert.Contains("max_level", body.GetProperty("errors").ToString());

        await (await player.Client.PutJsonAsync("/v1/save", new { base_version = 0, save = Save(upgrades: new { jacuzzi = 1 }) }))
            .ExpectProblemAsync(HttpStatusCode.UnprocessableEntity, "invalid_save");
    }

    [Fact]
    public async Task Saves_that_break_the_save_schema_are_422()
    {
        var player = await api.NewPlayerAsync();
        await (await player.Client.PutJsonAsync("/v1/save", new { base_version = 0, save = new { schema_version = 1, money = -5 } }))
            .ExpectProblemAsync(HttpStatusCode.UnprocessableEntity, "invalid_save");
    }

    [Fact]
    public async Task Broken_envelopes_are_400()
    {
        var player = await api.NewPlayerAsync();
        await (await player.Client.PutJsonAsync("/v1/save", new { save = Save() }))
            .ExpectProblemAsync(HttpStatusCode.BadRequest, "bad_request");
        await (await player.Client.PutJsonAsync("/v1/save", new { base_version = 0, save = Save(), extra = true }))
            .ExpectProblemAsync(HttpStatusCode.BadRequest, "bad_request");
        await (await player.Client.PutAsync("/v1/save", new StringContent("{", System.Text.Encoding.UTF8, "application/json")))
            .ExpectProblemAsync(HttpStatusCode.BadRequest, "bad_request");
    }

    [Fact]
    public async Task Saves_over_256_KiB_are_413()
    {
        var player = await api.NewPlayerAsync();
        var big = new string('x', 300 * 1024);
        await (await player.Client.PutJsonAsync("/v1/save", new { base_version = 0, save = Save(client: new { blob = big }) }))
            .ExpectProblemAsync(HttpStatusCode.RequestEntityTooLarge, "payload_too_large");
    }

    [Fact]
    public async Task Save_requires_auth()
    {
        var client = api.Factory.CreateClient();
        await (await client.GetAsync("/v1/save")).ExpectProblemAsync(HttpStatusCode.Unauthorized, "unauthorized");
        await (await client.PutJsonAsync("/v1/save", new { base_version = 0, save = Save() }))
            .ExpectProblemAsync(HttpStatusCode.Unauthorized, "unauthorized");
    }
}
