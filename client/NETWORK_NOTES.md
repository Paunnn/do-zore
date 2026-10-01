# Offline slice and API boundary

This build makes **no server calls**. `ApiClient` exposes typed wrappers for every endpoint in `/contracts/openapi.yaml` 1.0.1, backed only by a persistent local mock. The bundled config defaults to `mock_enabled: true`. Setting it to false, or setting `mock_network_available: false`, returns an immediate unavailable response while the game continues. `api_base_url` and request timeout are configuration placeholders for the later HTTP integration task.

The mock covers device login and rotating refresh tokens, config ETags, local cloud-save versions and 409 conflicts, profiles, scheduled-event cache, weekly leaderboard, idempotent analytics batches, health, and the contract's planned 501 link/IAP responses. No monetization UI is present. Wrapper results have `{ok, http_status, body, headers}`; `body` matches the relevant API response schema. A response with HTTP status 0 is a local transport failure rather than an HTTP response.

## Persistence

`SaveSystem` writes `user://do_zore.json` via a flushed temporary file and keeps `do_zore.backup.json`. A corrupt primary falls back to the last valid backup. The envelope contains the schema-valid `save`, settings, and local-only network metadata. Only the save object is passed to the mock save endpoint. It saves periodically, on settings changes, on application pause, and on exit notification. Locale defaults to Serbian Latin.

The generated device secret and mock tokens remain local in this envelope. Production Android Keystore/iOS Keychain credential storage, actual HTTPS transport, retry/backoff, and real authentication are follow-up work. Mock data and tokens must be cleared or namespaced when enabling a real backend.

On startup/resume, offline income uses the data-driven capped `Economy.offline_earnings` calculation. A pending ledger is persisted before crediting, and money plus the settled marker are saved in the same envelope. An interrupted pending ledger resumes locally. Repeating the same away-period origin cannot credit again. No server offline claim is made in this slice. Demo offline results are previews and do not alter money.

## Later integration

The unused offline-claim wrapper and mock follow contract 1.0.1: upload the preserved old `last_seen`, receive the current save version, and claim against it; upload activity is clamped between previous activity and server now. A claim records server now. The earlier 1.0.0 upload/claim contradiction was fixed upstream. Keep away-period transactions serialized with save uploads when adding HTTP, and never make a second grant after a locally settled period. The contract currently has no claim idempotency key to recover an ambiguous successful response; see `CONTRACT_ISSUES.md`.

Analytics UUIDs and the queued events are persisted before mock transmission. Successful batches remove only the acknowledged batch IDs, preserving new events queued while awaiting a response. The queue size and batch size are operational config. Scheduled events retain server time offset and are applied only within their cached start/end times. The mock currently returns an empty event list.

## Testing

Set the absolute `DO_ZORE_TEST_USER_DIR` environment variable to isolate all save files. In this mode automatic startup/periodic mock sync is disabled; explicit `await ApiClient.sync_now()` is available to tests. Local offline settlement still runs. `ApiClient.mock_conflict()` exercises the save-choice popup; `demo_offline_earnings(seconds)` previews the capped earnings popup. Never use a normal player save directory for destructive persistence tests.
