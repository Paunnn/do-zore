using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Design;

namespace DoZore.Api.Data;

public sealed class AppDbContext(DbContextOptions<AppDbContext> options) : DbContext(options)
{
    public DbSet<Player> Players => Set<Player>();
    public DbSet<Device> Devices => Set<Device>();
    public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>();
    public DbSet<CloudSave> Saves => Set<CloudSave>();
    public DbSet<OfflineClaim> OfflineClaims => Set<OfflineClaim>();
    public DbSet<WeeklyScore> WeeklyScores => Set<WeeklyScore>();
    public DbSet<LiveEvent> LiveEvents => Set<LiveEvent>();
    public DbSet<AnalyticsEvent> AnalyticsEvents => Set<AnalyticsEvent>();
    public DbSet<GameDataVersion> GameDataVersions => Set<GameDataVersion>();

    public static void Configure(DbContextOptionsBuilder options, string connectionString) =>
        options.UseNpgsql(connectionString).UseSnakeCaseNamingConvention();

    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<Player>(e =>
        {
            e.Property(p => p.DisplayName).HasMaxLength(20);
        });

        b.Entity<Device>(e =>
        {
            e.HasKey(d => d.DeviceId);
            e.HasOne<Player>().WithMany().HasForeignKey(d => d.PlayerId);
            e.Property(d => d.Platform).HasMaxLength(16);
            e.Property(d => d.AppVersion).HasMaxLength(32);
        });

        b.Entity<RefreshToken>(e =>
        {
            e.HasOne<Player>().WithMany().HasForeignKey(t => t.PlayerId);
            e.HasIndex(t => t.TokenHash).IsUnique();
            e.HasIndex(t => t.FamilyId);
        });

        b.Entity<CloudSave>(e =>
        {
            e.HasKey(s => s.PlayerId);
            e.HasOne<Player>().WithOne().HasForeignKey<CloudSave>(s => s.PlayerId);
            e.Property(s => s.Data).HasColumnType("jsonb");
        });

        b.Entity<OfflineClaim>(e =>
        {
            e.HasOne<Player>().WithMany().HasForeignKey(c => c.PlayerId);
            e.HasIndex(c => new { c.PlayerId, c.CreatedAt });
        });

        b.Entity<WeeklyScore>(e =>
        {
            e.HasKey(s => new { s.WeekId, s.PlayerId });
            e.HasOne<Player>().WithMany().HasForeignKey(s => s.PlayerId);
            e.Property(s => s.WeekId).HasMaxLength(8);
            e.HasIndex(s => new { s.WeekId, s.Score, s.ReachedAt }).IsDescending(false, true, false);
        });

        b.Entity<LiveEvent>(e =>
        {
            e.Property(l => l.Id).HasMaxLength(64);
            e.Property(l => l.Name).HasColumnType("jsonb");
            e.Property(l => l.Description).HasColumnType("jsonb");
            e.Property(l => l.Modifiers).HasColumnType("jsonb");
            e.HasIndex(l => new { l.StartsAt, l.EndsAt });
        });

        b.Entity<AnalyticsEvent>(e =>
        {
            e.HasKey(a => a.EventId);
            e.Property(a => a.Name).HasMaxLength(64);
            e.Property(a => a.Params).HasColumnType("jsonb");
            e.HasIndex(a => new { a.Name, a.Ts });
        });

        b.Entity<GameDataVersion>(e =>
        {
            e.HasIndex(v => v.VersionHash).IsUnique();
            e.Property(v => v.VersionHash).HasMaxLength(64);
            // At most one active version.
            e.HasIndex(v => v.IsActive).IsUnique().HasFilter("is_active");
        });
    }
}

/// <summary>Lets `dotnet ef` build the context without starting the app.</summary>
public sealed class DesignTimeDbContextFactory : IDesignTimeDbContextFactory<AppDbContext>
{
    public AppDbContext CreateDbContext(string[] args)
    {
        var options = new DbContextOptionsBuilder<AppDbContext>();
        AppDbContext.Configure(options, Environment.GetEnvironmentVariable("DB_CONNECTION_STRING")
            ?? "Host=localhost;Database=dozore;Username=dozore;Password=dozore");
        return new AppDbContext(options.Options);
    }
}
