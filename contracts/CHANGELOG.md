# Contract changelog

Every change to `openapi.yaml` or `schemas/` is logged here, newest first.
Format: date, version, what changed, why, and whether it is breaking for the client.

## 2026-10-04 — v1.1.0 (service and pay-per-round)

**Breaking:** no (an optional `economy.service` object and description changes; no API shape changed)

- `economy.schema.json`: new optional `service` object with `auto_serve_seconds`. Waiters take a waiting order by themselves after `auto_serve_seconds / service_speed`; a tap still serves at once. Each round is now paid when it is delivered, and the tip when the party leaves (computed from the rounds paid). Guests who leave without paying take back their last round.
- `events.schema.json`, `guest-types.schema.json`, `economy.tips`: descriptions updated for pay-per-round (no field changed).
- `/data` (balance, not contract): shorter visits (80–180 s), more rounds per visit, shorter prep and songs, more arrivals, offline income at about 35% of active income and a 60 s minimum absence, and re-priced venues, bands, late upgrades and songs. Tuned with the client simulation so the kafana opens after ~12 min of play, the restoran after ~35–45 min and the splav after ~2 h.

**Why:** players had to tap every order and were paid only when a table left, 3–8 minutes later; money rarely moved, offline income was 3–12% of active play and the first venue took ~3 h.

## 2026-09-30 — v1.0.1 (offline-claim clarification)

**Breaking:** no (description-only; no request/response shape changed)

- `POST /v1/offline-earnings/claim`: v1.0.0 said a save upload resets the player's recorded activity to the upload time, while also telling the client to upload before claiming — which would make every claim pay 0. Now a save upload records the save's `last_seen`, clamped between the previous recorded activity and server now; a claim records server now.
- `PUT /v1/save`: documented that when the server has no save, any `base_version` is accepted (there is no server copy to conflict with), and that uploads update recorded activity.

**Why:** found while implementing the server; the v1.0.0 flow could never pay offline earnings when online.

## 2026-09-30 — v1.0.0 (initial contract)

**Breaking:** n/a (first version)

### API (`openapi.yaml`, OpenAPI 3.1)
- `GET /v1/health`: liveness check.
- `POST /v1/auth/device`: anonymous login with a client-generated `device_id` + `device_secret`, returns a JWT access token (15 min) and a rotating refresh token (30 days).
- `POST /v1/auth/refresh`: single-use refresh tokens with reuse detection.
- `POST /v1/auth/link/google`, `POST /v1/auth/link/apple`: planned, return 501 in v1.
- `GET/PATCH /v1/me`: player profile and display name (needed for leaderboard names).
- `GET/PUT /v1/save`: cloud save with integer `version`; PUT takes `base_version`, and a stale write gets 409 with the server copy.
- `POST /v1/offline-earnings/claim`: client sends `last_seen` + `claimed_amount` + `save_version`; server grants `min(claimed, computed)` using its own clock and stored save.
- `GET /v1/config`: full game-data bundle + SHA-256 `version_hash`, ETag / `If-None-Match` → 304.
- `GET /v1/leaderboards/weekly`: top 100 by weekly bakšiš + the caller's rank. `POST /v1/leaderboards/weekly/score` reports the weekly total.
- `GET /v1/events/active`: server-scheduled live events (active + next 7 days) with stat multipliers.
- `POST /v1/analytics/batch`: up to 500 events per batch, de-duplicated by `event_id`.
- `POST /v1/iap/validate`: stub (501 in v1); request/response shape fixed.
- Errors are RFC 9457 problem+json with a stable `code`.

### Schemas (`schemas/`, JSON Schema 2020-12)
- `common`: ids, localized text (sr required, en optional), dinars, progress-scaled `Amount`.
- `genres`, `guest-types`, `songs`, `drinks` (includes food via `kind`), `upgrades`, `band-levels`, `venues`, `events` (random events, 2–3 choices, weighted outcomes, typed effects).
- `economy`: all global balance constants and formulas (mood, tips, arrivals, event rolls, offline earnings), so no balance number lives in code.
- `game-data`: the bundle served by `/v1/config`.
- `save`: player save format used by cloud save and offline-earnings verification.

**Why:** first contract, so server and client can be built in parallel.
