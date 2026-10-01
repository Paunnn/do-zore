using System.Text.Json;
using DoZore.Api.Data;
using DoZore.Api.Infrastructure;
using Microsoft.EntityFrameworkCore;

namespace DoZore.Api.GameData;

/// <summary>
/// Loads /data into the database as the active game-data version (idempotent: re-seeding the same
/// data only re-activates it), and optionally upserts scheduled live events from a JSON file.
/// </summary>
public sealed class Seeder(
    AppDbContext db,
    GameDataLoader loader,
    ContractSchemas schemas,
    GameDataProvider provider,
    AppPaths paths,
    TimeProvider time,
    IConfiguration config,
    ILogger<Seeder> log)
{
    public async Task<string> SeedGameDataAsync(string? dataDir = null, CancellationToken ct = default)
    {
        var bundle = loader.LoadDirectory(dataDir ?? paths.Data);
        var minClientVersion = config["GameData:MinClientVersion"] ?? "0.1.0";

        await using var tx = await db.Database.BeginTransactionAsync(ct);
        await db.GameDataVersions
            .Where(v => v.IsActive && v.VersionHash != bundle.Hash)
            .ExecuteUpdateAsync(s => s.SetProperty(v => v.IsActive, false), ct);

        var existing = await db.GameDataVersions.SingleOrDefaultAsync(v => v.VersionHash == bundle.Hash, ct);
        if (existing is null)
        {
            db.GameDataVersions.Add(new GameDataVersion
            {
                VersionHash = bundle.Hash,
                Bundle = bundle.Canonical,
                MinClientVersion = minClientVersion,
                CreatedAt = time.GetUtcNow(),
                IsActive = true,
            });
        }
        else
        {
            existing.IsActive = true;
            existing.MinClientVersion = minClientVersion;
        }

        await db.SaveChangesAsync(ct);
        await tx.CommitAsync(ct);
        provider.Invalidate();

        log.LogInformation("Game data {VersionHash} active ({Status})", bundle.Hash, existing is null ? "new" : "unchanged");
        return bundle.Hash;
    }

    /// <summary>File format: <c>{"live_events": [LiveEvent, ...]}</c> with LiveEvent from the contract.</summary>
    public async Task<int> SeedLiveEventsAsync(string file, CancellationToken ct = default)
    {
        using var doc = JsonDocument.Parse(await File.ReadAllTextAsync(file, ct));
        var items = doc.RootElement.GetProperty("live_events").EnumerateArray().ToList();

        var errors = items.SelectMany((item, i) =>
            schemas.ValidateComponent("LiveEvent", item).Select(e => $"live_events/{i}{e.Pointer}: {e.Message}")).ToList();
        if (errors.Count > 0)
            throw new GameDataException(errors);

        foreach (var item in items)
        {
            var id = item.GetProperty("id").GetString()!;
            var entity = await db.LiveEvents.FindAsync([id], ct);
            if (entity is null)
            {
                entity = new LiveEvent { Id = id, Name = "", Modifiers = "" };
                db.LiveEvents.Add(entity);
            }

            entity.Name = item.GetProperty("name").GetRawText();
            entity.Description = item.TryGetProperty("description", out var d) ? d.GetRawText() : null;
            entity.StartsAt = item.GetProperty("starts_at").GetDateTimeOffset().ToUniversalTime();
            entity.EndsAt = item.GetProperty("ends_at").GetDateTimeOffset().ToUniversalTime();
            entity.Modifiers = item.GetProperty("modifiers").GetRawText();
        }

        await db.SaveChangesAsync(ct);
        log.LogInformation("Upserted {Count} live events from {File}", items.Count, file);
        return items.Count;
    }
}
