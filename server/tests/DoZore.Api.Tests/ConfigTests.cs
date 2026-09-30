using System.Net;
using System.Net.Http.Headers;
using System.Text.Json.Nodes;
using DoZore.Api.Data;
using DoZore.Api.GameData;
using DoZore.Api.Infrastructure;
using DoZore.Api.Tests.Infrastructure;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;

namespace DoZore.Api.Tests;

[Collection(ApiCollection.Name)]
public sealed class ConfigTests(ApiFixture api)
{
    [Fact]
    public async Task Serves_the_seeded_data_with_a_matching_hash_and_etag_anonymously()
    {
        var response = await api.Factory.CreateClient().GetAsync("/v1/config");
        var body = await response.ExpectAsync(HttpStatusCode.OK, "ConfigResponse");

        var hash = body.GetProperty("version_hash").GetString()!;
        Assert.Equal($"\"{hash}\"", response.Headers.ETag?.ToString());
        Assert.Contains("max-age=300", response.Headers.CacheControl?.ToString());

        // version_hash is the SHA-256 of the canonical JSON of data.
        var data = JsonNode.Parse(body.GetProperty("data").GetRawText())!;
        Assert.Equal(hash, CanonicalJson.Sha256Hex(CanonicalJson.Serialize(data)));

        // ...and data is exactly what's in /data.
        var loader = api.Factory.Services.GetRequiredService<GameDataLoader>();
        var paths = api.Factory.Services.GetRequiredService<AppPaths>();
        Assert.Equal(loader.LoadDirectory(paths.Data).Hash, hash);
        Assert.Equal(250, body.GetProperty("data").GetProperty("venues")[0].GetProperty("offline_income_per_minute").GetInt32());
    }

    [Fact]
    public async Task If_none_match_returns_304_only_for_the_current_version()
    {
        var client = api.Factory.CreateClient();
        var etag = (await client.GetAsync("/v1/config")).Headers.ETag!;

        var same = new HttpRequestMessage(HttpMethod.Get, "/v1/config");
        same.Headers.IfNoneMatch.Add(etag);
        var notModified = await client.SendAsync(same);
        Assert.Equal(HttpStatusCode.NotModified, notModified.StatusCode);
        Assert.Equal(etag, notModified.Headers.ETag);

        var weak = new HttpRequestMessage(HttpMethod.Get, "/v1/config");
        weak.Headers.IfNoneMatch.Add(new EntityTagHeaderValue(etag.Tag, isWeak: true));
        Assert.Equal(HttpStatusCode.NotModified, (await client.SendAsync(weak)).StatusCode);

        var stale = new HttpRequestMessage(HttpMethod.Get, "/v1/config");
        stale.Headers.IfNoneMatch.Add(new EntityTagHeaderValue("\"0000\""));
        await (await client.SendAsync(stale)).ExpectAsync(HttpStatusCode.OK, "ConfigResponse");
    }

    [Fact]
    public async Task Reseeding_is_idempotent_and_changed_data_becomes_active()
    {
        var original = await api.SeedAsync();
        Assert.Equal(original, await api.SeedAsync());

        var dir = CopyData();
        try
        {
            var venues = JsonNode.Parse(File.ReadAllText(Path.Combine(dir, "venues.json")))!;
            venues["venues"]![0]!["offline_income_per_minute"] = 300;
            File.WriteAllText(Path.Combine(dir, "venues.json"), venues.ToJsonString());

            var changed = await api.SeedAsync(dir);
            Assert.NotEqual(original, changed);

            var body = await (await api.Factory.CreateClient().GetAsync("/v1/config")).ExpectAsync(HttpStatusCode.OK, "ConfigResponse");
            Assert.Equal(changed, body.GetProperty("version_hash").GetString());

            await api.WithDbAsync(async db =>
                Assert.Equal(1, await db.GameDataVersions.CountAsync(v => v.IsActive)));
        }
        finally
        {
            Assert.Equal(original, await api.SeedAsync());
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public async Task Seed_rejects_schema_violations_and_broken_references()
    {
        var dir = CopyData();
        try
        {
            var guests = JsonNode.Parse(File.ReadAllText(Path.Combine(dir, "guest_types.json")))!;
            guests["guest_types"]![0]!["preferred_drink"] = "kokakola";
            guests["guest_types"]![1]!["patience_seconds"] = -5;
            File.WriteAllText(Path.Combine(dir, "guest_types.json"), guests.ToJsonString());

            var ex = await Assert.ThrowsAsync<GameDataException>(() => api.SeedAsync(dir));
            Assert.Contains(ex.Errors, e => e.Contains("guest_types.json/guest_types/1/patience_seconds"));

            // Fix the schema error so the cross-reference check is reached.
            guests["guest_types"]![1]!["patience_seconds"] = 90;
            File.WriteAllText(Path.Combine(dir, "guest_types.json"), guests.ToJsonString());
            ex = await Assert.ThrowsAsync<GameDataException>(() => api.SeedAsync(dir));
            Assert.Contains(ex.Errors, e => e.Contains("unknown drink 'kokakola'"));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    string CopyData()
    {
        var source = api.Factory.Services.GetRequiredService<AppPaths>().Data;
        var dir = Directory.CreateTempSubdirectory("dozore-data-").FullName;
        foreach (var file in Directory.GetFiles(source, "*.json"))
            File.Copy(file, Path.Combine(dir, Path.GetFileName(file)));
        return dir;
    }
}
