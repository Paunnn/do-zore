using System.Text.Json;
using System.Text.Json.Nodes;
using DoZore.Api.Infrastructure;

namespace DoZore.Api.GameData;

public sealed record GameDataBundle(string Canonical, string Hash, GameDataModel Model);

public sealed class GameDataException(IReadOnlyList<string> errors)
    : Exception("Invalid game data:\n  " + string.Join("\n  ", errors))
{
    public IReadOnlyList<string> Errors { get; } = errors;
}

/// <summary>Reads /data, validates it against the contract schemas and cross-references, and bundles it.</summary>
public sealed class GameDataLoader(ContractSchemas schemas)
{
    // data file -> (bundle key, schema file)
    static readonly (string File, string Key, string Schema)[] Files =
    [
        ("genres.json", "genres", "genres"),
        ("guest_types.json", "guest_types", "guest-types"),
        ("songs.json", "songs", "songs"),
        ("drinks.json", "drinks", "drinks"),
        ("upgrades.json", "upgrades", "upgrades"),
        ("band_levels.json", "band_levels", "band-levels"),
        ("venues.json", "venues", "venues"),
        ("events.json", "events", "events"),
        ("economy.json", "economy", "economy"),
    ];

    public GameDataBundle LoadDirectory(string dataDir)
    {
        var errors = new List<string>();
        var bundle = new JsonObject();

        foreach (var (file, key, schema) in Files)
        {
            var path = Path.Combine(dataDir, file);
            if (!File.Exists(path))
            {
                errors.Add($"{file}: missing");
                continue;
            }

            JsonElement doc;
            try
            {
                doc = JsonDocument.Parse(File.ReadAllText(path)).RootElement;
            }
            catch (JsonException ex)
            {
                errors.Add($"{file}: not valid JSON ({ex.Message})");
                continue;
            }

            errors.AddRange(schemas.ValidateFile(schema, doc).Select(e => $"{file}{e.Pointer}: {e.Message}"));

            var node = JsonNode.Parse(doc.GetRawText())!.AsObject();
            node.Remove("$schema");
            bundle[key] = key == "economy" ? node : node[key]?.DeepClone();
        }

        if (errors.Count > 0)
            throw new GameDataException(errors);

        return FromBundle(bundle);
    }

    public GameDataBundle FromBundle(JsonObject bundle)
    {
        var canonical = CanonicalJson.Serialize(bundle);
        using var doc = JsonDocument.Parse(canonical);

        var errors = schemas.ValidateFile("game-data", doc.RootElement).Select(e => $"bundle{e.Pointer}: {e.Message}").ToList();
        if (errors.Count > 0)
            throw new GameDataException(errors);

        var model = doc.RootElement.Deserialize<GameDataModel>(JsonDefaults.Options)
            ?? throw new GameDataException(["bundle: empty"]);
        errors.AddRange(CrossReferences(model));
        if (errors.Count > 0)
            throw new GameDataException(errors);

        return new GameDataBundle(canonical, CanonicalJson.Sha256Hex(canonical), model);
    }

    /// <summary>Checks the schemas can't express: ids are unique and every reference resolves.</summary>
    public static IEnumerable<string> CrossReferences(GameDataModel m)
    {
        var genres = Ids("genres", m.Genres.Select(g => g.Id), out var dupGenres);
        var guests = Ids("guest_types", m.GuestTypes.Select(g => g.Id), out var dupGuests);
        var drinks = Ids("drinks", m.Drinks.Select(d => d.Id), out var dupDrinks);
        var venues = Ids("venues", m.Venues.Select(v => v.Id), out var dupVenues);
        var bands = Ids("band_levels", m.BandLevels.Select(b => b.Id), out var dupBands);
        var events = Ids("events", m.Events.Select(e => e.Id), out var dupEvents);
        Ids("songs", m.Songs.Select(s => s.Id), out var dupSongs);
        Ids("upgrades", m.Upgrades.Select(u => u.Id), out var dupUpgrades);

        foreach (var dup in dupGenres.Concat(dupGuests).Concat(dupDrinks).Concat(dupVenues).Concat(dupBands).Concat(dupEvents).Concat(dupSongs).Concat(dupUpgrades))
            yield return dup;

        foreach (var g in m.Genres)
        foreach (var r in g.Related ?? [])
            if (!genres.Contains(r.Genre) || r.Genre == g.Id)
                yield return $"genres/{g.Id}: related genre '{r.Genre}' is unknown or itself";

        foreach (var g in m.GuestTypes)
        {
            if (!genres.Contains(g.PreferredGenre)) yield return $"guest_types/{g.Id}: unknown genre '{g.PreferredGenre}'";
            if (!drinks.Contains(g.PreferredDrink)) yield return $"guest_types/{g.Id}: unknown drink '{g.PreferredDrink}'";
        }

        var bandById = m.BandLevels.ToDictionary(b => b.Id);
        foreach (var s in m.Songs)
        {
            if (!genres.Contains(s.Genre)) yield return $"songs/{s.Id}: unknown genre '{s.Genre}'";
            if (!bandById.TryGetValue(s.MinBandLevel, out var band))
                yield return $"songs/{s.Id}: unknown band level '{s.MinBandLevel}'";
            else
            {
                if (!band.Genres.Contains(s.Genre)) yield return $"songs/{s.Id}: band '{band.Id}' can't play genre '{s.Genre}'";
                if (s.IsHit && !band.CanPlayHits) yield return $"songs/{s.Id}: hit on band '{band.Id}' that can't play hits";
            }
        }

        foreach (var d in m.Drinks.Where(d => !venues.Contains(d.UnlockVenue)))
            yield return $"drinks/{d.Id}: unknown venue '{d.UnlockVenue}'";
        foreach (var u in m.Upgrades.Where(u => !venues.Contains(u.UnlockVenue)))
            yield return $"upgrades/{u.Id}: unknown venue '{u.UnlockVenue}'";

        foreach (var b in m.BandLevels)
        {
            if (!venues.Contains(b.RequiredVenue)) yield return $"band_levels/{b.Id}: unknown venue '{b.RequiredVenue}'";
            foreach (var g in b.Genres.Where(g => !genres.Contains(g)))
                yield return $"band_levels/{b.Id}: unknown genre '{g}'";
        }

        foreach (var v in m.Venues)
        {
            if (v.BaseTables > v.MaxTables) yield return $"venues/{v.Id}: base_tables > max_tables";
            foreach (var g in v.GuestMix.Keys.Where(g => !guests.Contains(g)))
                yield return $"venues/{v.Id}: unknown guest type '{g}' in guest_mix";
        }

        if (!IsSequence(m.Venues.Select(v => v.Order))) yield return "venues: order must be 1..n";
        if (!IsSequence(m.BandLevels.Select(b => b.Order))) yield return "band_levels: order must be 1..n";

        foreach (var e in m.Events)
        {
            if (!venues.Contains(e.MinVenue)) yield return $"events/{e.Id}: unknown venue '{e.MinVenue}'";
            if (e.Choices.All(c => c.Id != e.TimeoutChoice)) yield return $"events/{e.Id}: timeout_choice '{e.TimeoutChoice}' is not a choice";
            if (e.Choices.Select(c => c.Id).Distinct().Count() != e.Choices.Count) yield return $"events/{e.Id}: duplicate choice ids";

            foreach (var effect in e.Choices.SelectMany(c => c.Outcomes).SelectMany(o => o.Effects))
            {
                if (effect.GuestType is { } gt && !guests.Contains(gt)) yield return $"events/{e.Id}: unknown guest type '{gt}'";
                if (effect.Event is { } ev && (!events.Contains(ev) || ev == e.Id)) yield return $"events/{e.Id}: trigger_event '{ev}' is unknown or itself";
            }
        }
    }

    static HashSet<string> Ids(string collection, IEnumerable<string> ids, out List<string> duplicates)
    {
        var set = new HashSet<string>();
        duplicates = [];
        foreach (var id in ids)
            if (!set.Add(id))
                duplicates.Add($"{collection}: duplicate id '{id}'");
        return set;
    }

    static bool IsSequence(IEnumerable<int> orders) =>
        orders.Order().Select((o, i) => o == i + 1).All(x => x);
}
