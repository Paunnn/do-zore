using System.Text.Json;
using DoZore.Api.Auth;
using DoZore.Api.Data;
using DoZore.Api.GameData;
using DoZore.Api.Infrastructure;
using Microsoft.EntityFrameworkCore;

namespace DoZore.Api.Features;

public static class SaveEndpoints
{
    public const long MaxSaveBytes = 256 * 1024;

    public static void MapSave(this IEndpointRouteBuilder app)
    {
        app.MapGet("/v1/save", GetSave).RequireAuthorization();
        app.MapPut("/v1/save", PutSave).RequireAuthorization().RequireRateLimiting(RateLimiting.Writes);
    }

    static async Task<IResult> GetSave(HttpContext ctx, AppDbContext db)
    {
        var save = await db.Saves.AsNoTracking().SingleOrDefaultAsync(s => s.PlayerId == ctx.User.PlayerId(), ctx.RequestAborted);
        return save is null ? SaveNotFound() : Results.Ok(ToEnvelope(save));
    }

    static async Task<IResult> PutSave(HttpContext ctx, AppDbContext db, GameDataProvider gameData, TimeProvider time, ILogger<Program> log)
    {
        // Problems inside the save itself are 422; problems with the envelope are 400.
        var body = await ctx.ReadAsync<PutSaveRequest>("PutSaveRequest", MaxSaveBytes, errors =>
            errors.All(e => e.Pointer == "/save" || e.Pointer.StartsWith("/save/", StringComparison.Ordinal))
                ? InvalidSave("Save does not match the save schema.", errors)
                : Problems.BadRequest("Request body does not match the contract.", errors));
        if (body.Failed) return body.Error!;
        var req = body.Value!;
        var save = req.Save.Deserialize<PlayerSave>(JsonDefaults.Options)!;

        var snapshot = await gameData.GetAsync(ctx.RequestAborted);
        if (snapshot is null) return Problems.GameDataUnavailable();
        var dataErrors = CheckAgainstGameData(save, snapshot.Model);
        if (dataErrors.Count > 0)
            return InvalidSave("Save references content that doesn't exist in the current game data.", dataErrors);

        var playerId = ctx.User.PlayerId();
        var player = await db.Players.FindAsync([playerId], ctx.RequestAborted);
        if (player is null) return Problems.Unauthorized("Player no longer exists.");

        var now = time.GetUtcNow();
        var data = req.Save.GetRawText();

        await using var tx = await db.Database.BeginTransactionAsync(ctx.RequestAborted);
        var existing = await db.Saves.AsNoTracking().SingleOrDefaultAsync(s => s.PlayerId == playerId, ctx.RequestAborted);
        int version;
        if (existing is null)
        {
            // Nothing to conflict with, so any base_version is accepted.
            db.Saves.Add(new CloudSave { PlayerId = playerId, Version = 1, Data = data, UpdatedAt = now });
            try
            {
                await db.SaveChangesAsync(ctx.RequestAborted);
            }
            catch (DbUpdateException)
            {
                await tx.RollbackAsync(ctx.RequestAborted);
                return await Conflict(db, playerId, ctx.RequestAborted); // another device created it first
            }

            version = 1;
        }
        else
        {
            if (req.BaseVersion != existing.Version)
                return Conflict(existing);

            var updated = await db.Saves
                .Where(s => s.PlayerId == playerId && s.Version == req.BaseVersion)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(x => x.Version, x => x.Version + 1)
                    .SetProperty(x => x.Data, data)
                    .SetProperty(x => x.UpdatedAt, now), ctx.RequestAborted);
            if (updated == 0)
            {
                await tx.RollbackAsync(ctx.RequestAborted);
                return await Conflict(db, playerId, ctx.RequestAborted);
            }

            version = req.BaseVersion + 1;
        }

        // Recorded activity for offline earnings: the save's last_seen, clamped so the client clock
        // can neither move it before the previous activity nor after server now.
        var floor = player.LastActivityAt ?? player.CreatedAt;
        var lastSeen = save.LastSeen.ToUniversalTime();
        player.LastActivityAt = lastSeen < floor ? floor : lastSeen > now ? now : lastSeen;
        await db.SaveChangesAsync(ctx.RequestAborted);
        await tx.CommitAsync(ctx.RequestAborted);

        log.LogInformation("Save v{Version} stored for {PlayerId}", version, playerId);
        return Results.Ok(new SaveWriteResult(version, now));
    }

    public static List<SchemaError> CheckAgainstGameData(PlayerSave save, GameDataModel data)
    {
        var errors = new List<SchemaError>();
        if (data.Venue(save.Venue) is null)
            errors.Add(new("/save/venue", $"Unknown venue '{save.Venue}'."));
        if (data.BandLevel(save.BandLevel) is null)
            errors.Add(new("/save/band_level", $"Unknown band level '{save.BandLevel}'."));

        foreach (var (id, level) in save.Upgrades)
        {
            var upgrade = data.Upgrade(id);
            if (upgrade is null)
                errors.Add(new($"/save/upgrades/{id}", $"Unknown upgrade '{id}'."));
            else if (level > upgrade.MaxLevel)
                errors.Add(new($"/save/upgrades/{id}", $"Level {level} exceeds max_level {upgrade.MaxLevel}."));
        }

        var songs = data.Songs.Select(s => s.Id).ToHashSet();
        errors.AddRange(save.UnlockedSongs.Where(s => !songs.Contains(s))
            .Select(s => new SchemaError("/save/unlocked_songs", $"Unknown song '{s}'.")));
        return errors;
    }

    public static SaveEnvelope ToEnvelope(CloudSave save)
    {
        using var doc = JsonDocument.Parse(save.Data);
        return new SaveEnvelope(save.Version, save.UpdatedAt, doc.RootElement.Clone());
    }

    static IResult Conflict(CloudSave server) =>
        Results.Json(new SaveConflict("save_conflict", ToEnvelope(server)), JsonDefaults.Options, statusCode: StatusCodes.Status409Conflict);

    static async Task<IResult> Conflict(AppDbContext db, Guid playerId, CancellationToken ct)
    {
        db.ChangeTracker.Clear();
        return Conflict(await db.Saves.AsNoTracking().SingleAsync(s => s.PlayerId == playerId, ct));
    }

    public static IResult SaveNotFound() =>
        Problems.Result(StatusCodes.Status404NotFound, "save_not_found", "No cloud save", "This player has no cloud save yet.");

    static IResult InvalidSave(string detail, IReadOnlyList<SchemaError> errors) =>
        Problems.Result(StatusCodes.Status422UnprocessableEntity, "invalid_save", "Invalid save", detail, errors);
}
