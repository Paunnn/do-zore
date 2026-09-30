using DoZore.Api.Features;

namespace DoZore.Api.GameData;

/// <summary>A live event's combined income multiplier over its time window.</summary>
public sealed record IncomeWindow(string Id, DateTimeOffset StartsAt, DateTimeOffset EndsAt, double Multiplier);

public sealed record OfflineComputation(
    long Amount, long AwaySeconds, long CountedSeconds, double CapHours, bool Capped, double RatePerMinute,
    IReadOnlyList<string> LiveEventIds);

/// <summary>
/// Offline earnings exactly as specified in economy.offline (contracts/schemas/economy.schema.json).
/// Pure function of game data, save and a time window: the caller supplies server time.
/// </summary>
public static class OfflineEarnings
{
    public static OfflineComputation Compute(
        GameDataModel data, PlayerSave save, DateTimeOffset from, DateTimeOffset to, IReadOnlyList<IncomeWindow> liveEvents)
    {
        // Whole seconds throughout: DB timestamps are microsecond-precise, .NET ticks are finer, and
        // sub-second slivers must not tip floor() below the exact amount.
        from = TruncateToSecond(from);
        to = TruncateToSecond(to);
        liveEvents = liveEvents
            .Select(e => e with { StartsAt = TruncateToSecond(e.StartsAt), EndsAt = TruncateToSecond(e.EndsAt) })
            .ToList();

        var rules = data.Economy.Offline;
        var stats = UpgradeStats.From(data, save.Upgrades);
        var venue = data.Venue(save.Venue);
        var band = data.BandLevel(save.BandLevel);

        var capHours = venue is null
            ? 0
            : Math.Min(stats.Additive("offline_cap_hours", venue.OfflineCapHours), rules.MaxCapHours);
        var rate = venue is null ? 0 : RatePerMinute(venue, band, stats);

        var away = Math.Max(0L, (long)Math.Floor((to - from).TotalSeconds));
        if (away < rules.MinAwaySeconds || rate <= 0)
            return new OfflineComputation(0, away, 0, capHours, false, rate, []);

        var capSeconds = (long)Math.Floor(capHours * 3600);
        var counted = Math.Min(away, capSeconds);
        var end = from.AddSeconds(counted);

        // Split the counted window at live-event boundaries; each piece earns at rate x active multipliers.
        var relevant = liveEvents.Where(e => e.StartsAt < end && e.EndsAt > from).ToList();
        var cuts = relevant.SelectMany(e => new[] { e.StartsAt, e.EndsAt })
            .Where(t => t > from && t < end)
            .Append(from).Append(end)
            .Distinct().Order().ToList();

        double weightedSeconds = 0;
        for (var i = 0; i < cuts.Count - 1; i++)
        {
            var (a, b) = (cuts[i], cuts[i + 1]);
            var multiplier = relevant.Where(e => e.StartsAt <= a && e.EndsAt >= b).Aggregate(1.0, (m, e) => m * e.Multiplier);
            weightedSeconds += (b - a).TotalSeconds * multiplier;
        }

        var amount = (long)Math.Floor(rate / 60.0 * weightedSeconds);
        return new OfflineComputation(amount, away, counted, capHours, away > capSeconds, rate,
            relevant.Select(e => e.Id).Distinct().ToList());
    }

    static DateTimeOffset TruncateToSecond(DateTimeOffset t) =>
        new(t.Ticks - t.Ticks % TimeSpan.TicksPerSecond, t.Offset);

    static double RatePerMinute(VenueDef venue, BandLevelDef? band, UpgradeStats stats)
    {
        var tables = Math.Min(stats.Additive("table_count", venue.BaseTables), venue.MaxTables);
        var rate = venue.OfflineIncomePerMinute
                   * stats.Multiplier("menu_price")
                   * stats.Multiplier("arrival_rate")
                   * stats.Multiplier("offline_income")
                   * (tables / venue.BaseTables)
                   * (band?.TipMultiplier ?? 1.0)
                   - (band?.UpkeepPerHour ?? 0) / 60.0;
        return Math.Max(0, rate);
    }
}

/// <summary>
/// Totals of upgrade effects per stat. 'add' effects sum (per_level x level); 'multiply' effects
/// compound (per_level ^ level). Levels above max_level and unknown upgrades are ignored.
/// </summary>
public sealed class UpgradeStats
{
    readonly Dictionary<string, double> _add = [];
    readonly Dictionary<string, double> _mult = [];

    public static UpgradeStats From(GameDataModel data, IReadOnlyDictionary<string, int> owned)
    {
        var stats = new UpgradeStats();
        foreach (var (id, rawLevel) in owned)
        {
            if (data.Upgrade(id) is not { } upgrade) continue;
            var level = Math.Clamp(rawLevel, 0, upgrade.MaxLevel);
            foreach (var effect in upgrade.Effects)
            {
                if (effect.Op == "add")
                    stats._add[effect.Stat] = stats._add.GetValueOrDefault(effect.Stat) + effect.PerLevel * level;
                else
                    stats._mult[effect.Stat] = stats._mult.GetValueOrDefault(effect.Stat, 1.0) * Math.Pow(effect.PerLevel, level);
            }
        }

        return stats;
    }

    /// <summary>For stats with a base value (tables, cap hours): (base + adds) x multipliers.</summary>
    public double Additive(string stat, double baseValue) =>
        (baseValue + _add.GetValueOrDefault(stat)) * _mult.GetValueOrDefault(stat, 1.0);

    /// <summary>For multiplier stats (prices, rates): (1 + adds) x multipliers.</summary>
    public double Multiplier(string stat) =>
        (1.0 + _add.GetValueOrDefault(stat)) * _mult.GetValueOrDefault(stat, 1.0);
}
