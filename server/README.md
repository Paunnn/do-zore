# Do Zore — server

ASP.NET Core (.NET 10 LTS) backend for Do Zore. It implements `/contracts/openapi.yaml` and nothing else. Game balance comes from `/data`, which is seeded into PostgreSQL and served by `GET /v1/config`.

The game never needs this server. Every endpoint is an optional sync/online feature (see `CLAUDE.md`).

## Quick start (Docker)

```sh
cd server
docker compose up --build
```

| Service | URL | What it is |
|---|---|---|
| `api` | http://localhost:5000/v1/health | the API |
| `swagger` | http://localhost:8080 | Swagger UI rendering `/contracts/openapi.yaml` ("Try it out" hits the API) |
| `db` | (internal) | PostgreSQL 17, data in the `pgdata` volume |
| `seed` | (one-shot) | applies migrations, loads `/data` and `seed/live_events.dev.json`, then exits |

`docker compose down` stops everything. Add `-v` to also delete the database volume.

Compose runs with `ASPNETCORE_ENVIRONMENT=Development` and a built-in dev JWT secret, so it works without a `.env`. Don't deploy it like that.

## Environment variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `DB_CONNECTION_STRING` | yes | — | Npgsql connection string, e.g. `Host=localhost;Port=5432;Database=dozore;Username=dozore;Password=…` |
| `JWT_SECRET` | yes | — | HMAC-SHA256 signing key, **at least 32 bytes**. In Production the app refuses to start if it still contains `CHANGE_ME`. |
| `PORT` | no | ASP.NET default (5000/8080) | Port the API listens on (all interfaces). |
| `ASPNETCORE_ENVIRONMENT` | no | `Production` | `Development` turns on debug logging and allows the Swagger UI origin through CORS. |

These are the same names as in the root `.env.example`. Any other setting in `appsettings.json` can be overridden with an environment variable, using `__` as the separator:

| Setting | Default | Example override |
|---|---|---|
| Rate limits (per player, or per IP when anonymous; fixed 60 s window) | global 300, auth 20, writes 60, analytics 30 | `RateLimiting__Auth__PermitLimit=10` |
| Leaderboard anti-cheat ceiling (bakšiš per second of possible play) | 5000 | `Leaderboard__MaxScorePerSecond=8000` |
| `min_client_version` stamped on seeded game data | `0.1.0` | `GameData__MinClientVersion=0.2.0` |
| CORS origins | none (Development: `http://localhost:8080`) | `Cors__AllowedOrigins__0=https://admin.example` |
| Display-name blocklist | `admin`, `moderator`, `dozore`, `support` | `DisplayNames__Blocked__4=…` |
| Contract / data folders | found by walking up from the app dir | `Paths__Contracts=/srv/contracts` |
| Run migrations on API start | `true` | `Database__MigrateOnStartup=false` |

Compose-only variables: `POSTGRES_PASSWORD`, `API_PORT` (5000), `SWAGGER_PORT` (8080).

## Running without Docker

Requires the .NET 10 SDK and a PostgreSQL 15+ you can reach.

```sh
cd server
export DB_CONNECTION_STRING="Host=localhost;Database=dozore;Username=dozore;Password=dozore"
export JWT_SECRET="local-dev-only-jwt-secret-0123456789abcdef"
export ASPNETCORE_ENVIRONMENT=Development

dotnet run --project src/DoZore.Api -- seed      # migrate + load /data (exit code 1 on invalid data)
dotnet run --project src/DoZore.Api              # serve on http://localhost:5000
```

PowerShell: use `$env:DB_CONNECTION_STRING = "…"` instead of `export`.

### Seeding

```
DoZore.Api seed [--data <dir>] [--live-events <file>]
```

- Validates every `/data` file against its schema in `/contracts/schemas`, then checks cross-references (e.g. a guest's preferred drink exists, a song's band level can play its genre). Any error aborts the seed and lists every problem.
- Stores the bundle as canonical JSON (keys sorted, no whitespace) and uses its SHA-256 as `version_hash` / `ETag`. Re-seeding unchanged data is a no-op. Changed data becomes the single active version, and running API instances pick it up within 30 s.
- `--live-events` upserts scheduled live events from `{"live_events": [LiveEvent…]}` (the contract's `LiveEvent` shape). The dev file is `seed/live_events.dev.json`.

## Tests

```sh
cd server
dotnet test
```

Needs Docker running: the suite starts a throwaway `postgres:17-alpine` with Testcontainers. It runs the real app in-process with `WebApplicationFactory` and a fake clock, so offline earnings, token expiry and leaderboard weeks are tested deterministically. There are 63 tests covering every endpoint.

- Every response body is validated against its `components/schemas` entry in `openapi.yaml`, so the tests fail if the server drifts from the contract.
- `SystemTests.Every_contract_operation_is_implemented_and_nothing_else_is_exposed` compares the app's routes with the contract's paths in both directions.

## How it works

- **Contract-driven validation.** At startup `ContractSchemas` builds JSON Schema validators from `/contracts/schemas/*.json` and every `components/schemas` entry in `openapi.yaml`, resolving `$ref`s across files. Request bodies are validated against the contract component before they are deserialized. Invalid input gets `400 bad_request` with per-field `errors`. Saves that break the save schema or reference unknown content get `422 invalid_save`.
- **Errors** are RFC 9457 `application/problem+json` with a stable `code`. Unknown routes and methods return the same shape.
- **Auth.** Anonymous device login with a client-generated `device_id` + `device_secret` (stored as SHA-256). Access JWTs last 15 min. Refresh tokens last 30 days, are single-use and rotate; reusing one revokes its whole login family.
- **Cloud save.** Integer `version` with optimistic concurrency (`UPDATE … WHERE version = base_version`). A stale write gets `409` with the server copy.
- **Offline earnings** use the formula in `economy.offline` (see `contracts/schemas/economy.schema.json`) and **only server time**:
  - The away window runs from the later of the server's recorded activity and the client's `last_seen` to server now. The client clock can shorten the window but never lengthen it.
  - The window is capped by the venue's `offline_cap_hours` plus upgrades, never more than `max_cap_hours`.
  - Live-event income multipliers apply pro rata to the part of the window they overlap.
  - The server grants `min(claimed, computed)`. Each away period pays once, even under concurrent claims.
- **Leaderboard.** ISO weeks, Monday 00:00 Europe/Belgrade. Keeps each player's best submission. Ties go to whoever reached the score first. A submission is capped at `MaxScorePerSecond ×` the seconds the player could have played this week. Late submissions for last week are accepted for 1 h after rollover.
- **Analytics** are bulk-inserted with `ON CONFLICT DO NOTHING` on `event_id`, so re-sent batches are harmless.
- **Logging** is structured JSON (Serilog compact format) to stdout. There's one line per request with method, path, status, elapsed time and `PlayerId`, plus a trace id that also appears in every error body.
- **Rate limiting** uses fixed windows per player (per IP when anonymous). Exceeding a limit returns `429 rate_limited` with `Retry-After`.
- **Health.** `GET /v1/health` is the contract's health endpoint. There is no separate `/health`, because anything outside the contract would be drift.

## Layout

```
server/
  src/DoZore.Api/
    Program.cs            host setup, pipeline, `seed` command
    Infrastructure/       contract schemas, request reading, problems, rate limiting, JSON
    Auth/                 JWT + refresh-token rotation
    Data/                 EF Core entities, DbContext, migrations
    GameData/             /data loading + validation, canonical hash, seeder, offline-earnings formula
    Features/             endpoints grouped by contract tag, DTOs
  tests/DoZore.Api.Tests/ integration tests (Testcontainers + WebApplicationFactory)
  seed/                   dev live events
  Dockerfile              build context = repo root
  docker-compose.yml
```

## Database migrations

```sh
cd server
dotnet tool restore
dotnet ef migrations add <Name> --project src/DoZore.Api --output-dir Data/Migrations
```

Migrations are applied by `seed` and on API start.

On a brand-new database, EF logs one `Failed executing DbCommand … __EFMigrationsHistory` error before it creates that table. It's harmless.

## Not implemented yet (by contract)

`POST /v1/auth/link/google`, `POST /v1/auth/link/apple` and `POST /v1/iap/validate` check auth and validate the body, then return `501 not_implemented`, as the v1 contract specifies.
