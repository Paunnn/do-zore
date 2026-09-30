namespace DoZore.Api.GameData;

// Typed view of the game-data bundle, limited to what the server reads. The full shapes are the
// JSON Schemas in /contracts/schemas; unknown properties are ignored when deserializing.

public sealed record GameDataModel(
    IReadOnlyList<GenreDef> Genres,
    IReadOnlyList<GuestTypeDef> GuestTypes,
    IReadOnlyList<SongDef> Songs,
    IReadOnlyList<DrinkDef> Drinks,
    IReadOnlyList<UpgradeDef> Upgrades,
    IReadOnlyList<BandLevelDef> BandLevels,
    IReadOnlyList<VenueDef> Venues,
    IReadOnlyList<EventDef> Events,
    EconomyDef Economy)
{
    public VenueDef? Venue(string id) => Venues.FirstOrDefault(v => v.Id == id);
    public BandLevelDef? BandLevel(string id) => BandLevels.FirstOrDefault(b => b.Id == id);
    public UpgradeDef? Upgrade(string id) => Upgrades.FirstOrDefault(u => u.Id == id);
}

public sealed record GenreDef(string Id, IReadOnlyList<RelatedGenre>? Related);
public sealed record RelatedGenre(string Genre, double Strength);

public sealed record GuestTypeDef(string Id, string PreferredGenre, string PreferredDrink);

public sealed record SongDef(string Id, string Genre, string MinBandLevel, bool IsHit);

public sealed record DrinkDef(string Id, string UnlockVenue);

public sealed record UpgradeDef(string Id, string UnlockVenue, int MaxLevel, IReadOnlyList<UpgradeEffect> Effects);
public sealed record UpgradeEffect(string Stat, string Op, double PerLevel);

public sealed record BandLevelDef(
    string Id, int Order, string RequiredVenue, IReadOnlyList<string> Genres,
    double TipMultiplier, long UpkeepPerHour, bool CanPlayHits);

public sealed record VenueDef(
    string Id, int Order, int BaseTables, int MaxTables,
    long OfflineIncomePerMinute, double OfflineCapHours, IReadOnlyDictionary<string, double> GuestMix);

public sealed record EventDef(string Id, string MinVenue, string TimeoutChoice, IReadOnlyList<EventChoice> Choices);
public sealed record EventChoice(string Id, IReadOnlyList<EventOutcome> Outcomes);
public sealed record EventOutcome(IReadOnlyList<EventEffect> Effects);
public sealed record EventEffect(string Type, string? GuestType, string? Event);

public sealed record EconomyDef(OfflineRules Offline);
public sealed record OfflineRules(int MinAwaySeconds, double MaxCapHours);
