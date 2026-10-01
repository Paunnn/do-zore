using System.Text.Json;
using System.Text.Json.Serialization;

namespace DoZore.Api.Features;

// Request/response bodies. Names and shapes mirror components/schemas in /contracts/openapi.yaml;
// requests are validated against those schemas before they are deserialized into these records.

public enum Platform { Android, Ios, Editor }

public sealed record HealthResponse(string Status, DateTimeOffset ServerTime);

public sealed record DeviceLoginRequest(Guid DeviceId, string DeviceSecret, Platform Platform, string AppVersion);
public sealed record RefreshRequest(string RefreshToken);

public sealed record PlayerResponse(Guid PlayerId, string DisplayName, DateTimeOffset CreatedAt, IReadOnlyList<string> LinkedProviders);
public sealed record UpdatePlayerRequest(string DisplayName);

public sealed record PlayerSave(
    int SchemaVersion, long Money, long TotalBaksis, string Venue, string BandLevel,
    IReadOnlyDictionary<string, int> Upgrades, IReadOnlyList<string> UnlockedSongs, DateTimeOffset LastSeen);

public sealed record SaveEnvelope(int Version, DateTimeOffset UpdatedAt, JsonElement Save);
public sealed record PutSaveRequest(int BaseVersion, JsonElement Save);
public sealed record SaveWriteResult(int Version, DateTimeOffset UpdatedAt);
public sealed record SaveConflict(string Code, SaveEnvelope Server);

public sealed record OfflineClaimRequest(DateTimeOffset LastSeen, long ClaimedAmount, int SaveVersion);
public sealed record OfflineClaimResult(
    long GrantedAmount, long ClaimedAmount, long ComputedAmount, long AwaySeconds, long CountedSeconds,
    double CapHours, bool Capped, IReadOnlyList<string> LiveEventIds, DateTimeOffset ServerTime, string DataVersionHash);

public sealed record LeaderboardEntry(int Rank, Guid PlayerId, string DisplayName, long Score);
public sealed record LeaderboardMe(int? Rank, long Score);
public sealed record WeeklyLeaderboard(
    string WeekId, DateTimeOffset StartsAt, DateTimeOffset EndsAt, int TotalPlayers,
    IReadOnlyList<LeaderboardEntry> Entries, LeaderboardMe Me);
public sealed record ScoreSubmission(string WeekId, long Score);
public sealed record ScoreResult(string WeekId, long AcceptedScore, int Rank);

public sealed record LiveEventDto(
    string Id,
    JsonElement Name,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] JsonElement? Description,
    DateTimeOffset StartsAt,
    DateTimeOffset EndsAt,
    JsonElement Modifiers);
public sealed record LiveEventList(DateTimeOffset ServerTime, IReadOnlyList<LiveEventDto> Events);

public sealed record AnalyticsEventDto(Guid EventId, string Name, DateTimeOffset Ts, JsonElement? Params);
public sealed record AnalyticsBatch(
    Guid DeviceId, Guid SessionId, Platform Platform, string AppVersion, string? DataVersionHash,
    DateTimeOffset SentAt, IReadOnlyList<AnalyticsEventDto> Events);
public sealed record AnalyticsAccepted(int Accepted, int Duplicates);
