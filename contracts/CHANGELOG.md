# Contract changelog

Every change to `openapi.yaml` or `schemas/` is logged here, newest first.
Format: date, version, what changed, why, and whether it is breaking for the client.

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
