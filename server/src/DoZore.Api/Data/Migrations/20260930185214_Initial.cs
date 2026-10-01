using System;
using Microsoft.EntityFrameworkCore.Migrations;
using Npgsql.EntityFrameworkCore.PostgreSQL.Metadata;

#nullable disable

namespace DoZore.Api.Data.Migrations
{
    /// <inheritdoc />
    public partial class Initial : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "analytics_events",
                columns: table => new
                {
                    event_id = table.Column<Guid>(type: "uuid", nullable: false),
                    player_id = table.Column<Guid>(type: "uuid", nullable: true),
                    device_id = table.Column<Guid>(type: "uuid", nullable: false),
                    session_id = table.Column<Guid>(type: "uuid", nullable: false),
                    platform = table.Column<string>(type: "text", nullable: false),
                    app_version = table.Column<string>(type: "text", nullable: false),
                    data_version_hash = table.Column<string>(type: "text", nullable: true),
                    name = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    ts = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    @params = table.Column<string>(name: "params", type: "jsonb", nullable: true),
                    sent_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    received_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_analytics_events", x => x.event_id);
                });

            migrationBuilder.CreateTable(
                name: "game_data_versions",
                columns: table => new
                {
                    id = table.Column<int>(type: "integer", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    version_hash = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    bundle = table.Column<string>(type: "text", nullable: false),
                    min_client_version = table.Column<string>(type: "text", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    is_active = table.Column<bool>(type: "boolean", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_game_data_versions", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "live_events",
                columns: table => new
                {
                    id = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    name = table.Column<string>(type: "jsonb", nullable: false),
                    description = table.Column<string>(type: "jsonb", nullable: true),
                    starts_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    ends_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    modifiers = table.Column<string>(type: "jsonb", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_live_events", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "players",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    display_name = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    last_activity_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_players", x => x.id);
                });

            migrationBuilder.CreateTable(
                name: "devices",
                columns: table => new
                {
                    device_id = table.Column<Guid>(type: "uuid", nullable: false),
                    player_id = table.Column<Guid>(type: "uuid", nullable: false),
                    secret_hash = table.Column<byte[]>(type: "bytea", nullable: false),
                    platform = table.Column<string>(type: "character varying(16)", maxLength: 16, nullable: false),
                    app_version = table.Column<string>(type: "character varying(32)", maxLength: 32, nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    last_login_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_devices", x => x.device_id);
                    table.ForeignKey(
                        name: "fk_devices_players_player_id",
                        column: x => x.player_id,
                        principalTable: "players",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "offline_claims",
                columns: table => new
                {
                    id = table.Column<long>(type: "bigint", nullable: false)
                        .Annotation("Npgsql:ValueGenerationStrategy", NpgsqlValueGenerationStrategy.IdentityByDefaultColumn),
                    player_id = table.Column<Guid>(type: "uuid", nullable: false),
                    claimed_amount = table.Column<long>(type: "bigint", nullable: false),
                    computed_amount = table.Column<long>(type: "bigint", nullable: false),
                    granted_amount = table.Column<long>(type: "bigint", nullable: false),
                    away_from = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    away_to = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    counted_seconds = table.Column<long>(type: "bigint", nullable: false),
                    data_version_hash = table.Column<string>(type: "text", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_offline_claims", x => x.id);
                    table.ForeignKey(
                        name: "fk_offline_claims_players_player_id",
                        column: x => x.player_id,
                        principalTable: "players",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "refresh_tokens",
                columns: table => new
                {
                    id = table.Column<Guid>(type: "uuid", nullable: false),
                    player_id = table.Column<Guid>(type: "uuid", nullable: false),
                    family_id = table.Column<Guid>(type: "uuid", nullable: false),
                    token_hash = table.Column<byte[]>(type: "bytea", nullable: false),
                    created_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    expires_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false),
                    used_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true),
                    revoked_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_refresh_tokens", x => x.id);
                    table.ForeignKey(
                        name: "fk_refresh_tokens_players_player_id",
                        column: x => x.player_id,
                        principalTable: "players",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "saves",
                columns: table => new
                {
                    player_id = table.Column<Guid>(type: "uuid", nullable: false),
                    version = table.Column<int>(type: "integer", nullable: false),
                    data = table.Column<string>(type: "jsonb", nullable: false),
                    updated_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_saves", x => x.player_id);
                    table.ForeignKey(
                        name: "fk_saves_players_player_id",
                        column: x => x.player_id,
                        principalTable: "players",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "weekly_scores",
                columns: table => new
                {
                    week_id = table.Column<string>(type: "character varying(8)", maxLength: 8, nullable: false),
                    player_id = table.Column<Guid>(type: "uuid", nullable: false),
                    score = table.Column<long>(type: "bigint", nullable: false),
                    reached_at = table.Column<DateTimeOffset>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("pk_weekly_scores", x => new { x.week_id, x.player_id });
                    table.ForeignKey(
                        name: "fk_weekly_scores_players_player_id",
                        column: x => x.player_id,
                        principalTable: "players",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "ix_analytics_events_name_ts",
                table: "analytics_events",
                columns: new[] { "name", "ts" });

            migrationBuilder.CreateIndex(
                name: "ix_devices_player_id",
                table: "devices",
                column: "player_id");

            migrationBuilder.CreateIndex(
                name: "ix_game_data_versions_is_active",
                table: "game_data_versions",
                column: "is_active",
                unique: true,
                filter: "is_active");

            migrationBuilder.CreateIndex(
                name: "ix_game_data_versions_version_hash",
                table: "game_data_versions",
                column: "version_hash",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_live_events_starts_at_ends_at",
                table: "live_events",
                columns: new[] { "starts_at", "ends_at" });

            migrationBuilder.CreateIndex(
                name: "ix_offline_claims_player_id_created_at",
                table: "offline_claims",
                columns: new[] { "player_id", "created_at" });

            migrationBuilder.CreateIndex(
                name: "ix_refresh_tokens_family_id",
                table: "refresh_tokens",
                column: "family_id");

            migrationBuilder.CreateIndex(
                name: "ix_refresh_tokens_player_id",
                table: "refresh_tokens",
                column: "player_id");

            migrationBuilder.CreateIndex(
                name: "ix_refresh_tokens_token_hash",
                table: "refresh_tokens",
                column: "token_hash",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "ix_weekly_scores_player_id",
                table: "weekly_scores",
                column: "player_id");

            migrationBuilder.CreateIndex(
                name: "ix_weekly_scores_week_id_score_reached_at",
                table: "weekly_scores",
                columns: new[] { "week_id", "score", "reached_at" },
                descending: new[] { false, true, false });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "analytics_events");

            migrationBuilder.DropTable(
                name: "devices");

            migrationBuilder.DropTable(
                name: "game_data_versions");

            migrationBuilder.DropTable(
                name: "live_events");

            migrationBuilder.DropTable(
                name: "offline_claims");

            migrationBuilder.DropTable(
                name: "refresh_tokens");

            migrationBuilder.DropTable(
                name: "saves");

            migrationBuilder.DropTable(
                name: "weekly_scores");

            migrationBuilder.DropTable(
                name: "players");
        }
    }
}
