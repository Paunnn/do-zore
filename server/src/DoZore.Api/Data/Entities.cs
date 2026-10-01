namespace DoZore.Api.Data;

public sealed class Player
{
    public Guid Id { get; set; }
    public required string DisplayName { get; set; }
    public DateTimeOffset CreatedAt { get; set; }

    /// <summary>Start of the current away period for offline earnings (see the claim endpoint).</summary>
    public DateTimeOffset? LastActivityAt { get; set; }
}

public sealed class Device
{
    public Guid DeviceId { get; set; }
    public Guid PlayerId { get; set; }
    public required byte[] SecretHash { get; set; }
    public required string Platform { get; set; }
    public required string AppVersion { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset LastLoginAt { get; set; }
}

public sealed class RefreshToken
{
    public Guid Id { get; set; }
    public Guid PlayerId { get; set; }

    /// <summary>All tokens rotated from one login share a family; reuse revokes the family.</summary>
    public Guid FamilyId { get; set; }

    public required byte[] TokenHash { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public DateTimeOffset ExpiresAt { get; set; }
    public DateTimeOffset? UsedAt { get; set; }
    public DateTimeOffset? RevokedAt { get; set; }
}

public sealed class CloudSave
{
    public Guid PlayerId { get; set; }
    public int Version { get; set; }
    public required string Data { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
}

public sealed class OfflineClaim
{
    public long Id { get; set; }
    public Guid PlayerId { get; set; }
    public long ClaimedAmount { get; set; }
    public long ComputedAmount { get; set; }
    public long GrantedAmount { get; set; }
    public DateTimeOffset AwayFrom { get; set; }
    public DateTimeOffset AwayTo { get; set; }
    public long CountedSeconds { get; set; }
    public required string DataVersionHash { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
}

public sealed class WeeklyScore
{
    public required string WeekId { get; set; }
    public Guid PlayerId { get; set; }
    public long Score { get; set; }

    /// <summary>When the current score was reached; earlier wins ties.</summary>
    public DateTimeOffset ReachedAt { get; set; }
}

public sealed class LiveEvent
{
    public required string Id { get; set; }
    public required string Name { get; set; }
    public string? Description { get; set; }
    public DateTimeOffset StartsAt { get; set; }
    public DateTimeOffset EndsAt { get; set; }
    public required string Modifiers { get; set; }
}

public sealed class AnalyticsEvent
{
    public Guid EventId { get; set; }
    public Guid? PlayerId { get; set; }
    public Guid DeviceId { get; set; }
    public Guid SessionId { get; set; }
    public required string Platform { get; set; }
    public required string AppVersion { get; set; }
    public string? DataVersionHash { get; set; }
    public required string Name { get; set; }
    public DateTimeOffset Ts { get; set; }
    public string? Params { get; set; }
    public DateTimeOffset SentAt { get; set; }
    public DateTimeOffset ReceivedAt { get; set; }
}

public sealed class GameDataVersion
{
    public int Id { get; set; }
    public required string VersionHash { get; set; }

    /// <summary>Canonical JSON bundle, stored as text so the hashed bytes are served unchanged.</summary>
    public required string Bundle { get; set; }

    public required string MinClientVersion { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
    public bool IsActive { get; set; }
}
