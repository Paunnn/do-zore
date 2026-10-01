using System.Text.Json;
using DoZore.Api.Data;
using DoZore.Api.Infrastructure;
using Microsoft.EntityFrameworkCore;

namespace DoZore.Api.GameData;

public sealed record GameDataSnapshot(
    string Hash, string Canonical, GameDataModel Model, string MinClientVersion, DateTimeOffset GeneratedAt);

/// <summary>
/// In-memory copy of the active game-data version. Re-checks the active hash at most every
/// 30 seconds, so a re-seed is picked up by running instances without a restart.
/// </summary>
public sealed class GameDataProvider(IServiceScopeFactory scopes, TimeProvider time)
{
    static readonly TimeSpan RecheckEvery = TimeSpan.FromSeconds(30);

    sealed record State(GameDataSnapshot Snapshot, DateTimeOffset CheckedAt);

    readonly SemaphoreSlim _lock = new(1, 1);
    State? _state;

    public void Invalidate() => Volatile.Write(ref _state, null);

    /// <summary>The active game data, or null if the database hasn't been seeded.</summary>
    public async Task<GameDataSnapshot?> GetAsync(CancellationToken ct)
    {
        var now = time.GetUtcNow();
        var state = Volatile.Read(ref _state);
        if (state is not null && now - state.CheckedAt < RecheckEvery)
            return state.Snapshot;

        await _lock.WaitAsync(ct);
        try
        {
            state = _state;
            if (state is not null && now - state.CheckedAt < RecheckEvery)
                return state.Snapshot;

            using var scope = scopes.CreateScope();
            var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
            var hash = await db.GameDataVersions.Where(v => v.IsActive).Select(v => v.VersionHash).SingleOrDefaultAsync(ct);
            if (hash is null)
            {
                _state = null;
                return null;
            }

            if (state?.Snapshot.Hash == hash)
            {
                _state = state with { CheckedAt = now };
                return state.Snapshot;
            }

            var row = await db.GameDataVersions.AsNoTracking().SingleAsync(v => v.VersionHash == hash, ct);
            var model = JsonSerializer.Deserialize<GameDataModel>(row.Bundle, JsonDefaults.Options)
                ?? throw new InvalidOperationException($"Game data {hash} is empty");
            var snapshot = new GameDataSnapshot(row.VersionHash, row.Bundle, model, row.MinClientVersion, row.CreatedAt);
            _state = new State(snapshot, now);
            return snapshot;
        }
        finally
        {
            _lock.Release();
        }
    }
}
