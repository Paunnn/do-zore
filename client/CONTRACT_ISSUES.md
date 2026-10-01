# Client contract issues

The client targets the checked-in `contracts/openapi.yaml` and reads the
schemas and balance data without modifying them. These issues need agreement with
the backend/data owner before production integration.

## 1. Offline upload activity: resolved in contract v1.0.1

- **Endpoints:** `PUT /v1/save`, `POST /v1/offline-earnings/claim`.
- **Original problem:** v1.0.0 requires uploading progress before claiming. It defines
  the away-period start as the later of the last save upload/claim and client
  `last_seen`. A literal upload at startup therefore erases the away period and
  produces a zero grant. The client must display that server grant, including
  zero; it cannot replace an accepted server response with a larger local amount.
- **Resolution:** v1.0.1 records upload activity using the uploaded save's
  `last_seen`, clamped between prior activity and server time. Claims advance
  activity to server time. Mock behavior should follow that clarification.

## 2. Required play mechanics have no balance fields

- **Endpoint/schema:** `GET /v1/config`; `economy.schema.json`,
  `guest-types.schema.json`, `events.schema.json`.
- **Problem:** the requested high-mood stay extension, glass-breaking rate,
  glass cost, income bonus and duration, exact-song request selection, food-order
  selection, and nearby-table layout have no corresponding fields. Existing
  schema objects reject additional properties. The first-arrival delay and
  simulation step also need an explicit client policy.
- **Client behavior:** no glass-breaking or happy-stay balance is invented.
  Those effects remain explicit stubs until the data owner supplies fields.
  `client/config/simulation.json` contains only technical simulation step and
  floor-column settings; fight checks use the same adjacency as the floor view.
  First-arrival timing uses the venue arrival rate. Guests request known songs in
  their preferred genre; first orders use the preferred available drink and later
  rounds select available food. These are explicit selection policies pending
  data-defined distributions.
- **Suggested fix:** add the gameplay tuning to the agreed economy/guest schemas
  and `/data`, then activate the deferred effects. Keep UI dimensions
  and simulation implementation settings in client configuration.

## 3. Guest-specific live modifiers are underspecified for offline earnings

- **Endpoint/schema:** `GET /v1/events/active` (`LiveEventModifier`),
  `POST /v1/offline-earnings/claim`; `economy.schema.json`.
- **Problem:** a modifier can target `guest_type`, but the offline formula only
  exposes an aggregate venue rate and does not define how much income each type
  contributes. Multiplying the entire rate would overpay, while ignoring it would
  underpay.
- **Client behavior:** the local fallback does not guess a guest-specific income
  split. Guest-specific offline bonuses remain deferred. Global timed modifiers
  apply only to their overlap with the counted offline period. The Task 1 slice
  is local/mock only; real server reconciliation is deferred.
- **Suggested fix:** specify one shared weighted formula, including how guest
  spending and tips affect the weights, and add cross-client/server test vectors.

## 4. Canonical JSON hashing is not fully specified

- **Endpoint:** `GET /v1/config` (`version_hash`, `ETag`).
- **Problem:** the contract requires SHA-256 of canonical JSON without naming a
  canonicalization standard. Key order, Unicode escaping and representations such
  as `1` versus `1.0` can produce different hashes for equivalent JSON.
- **Client behavior:** the bundled build records a reproducible hash; successful
  mock configurations keep the supplied hash/ETag. A hash difference
  triggers content validation and replacement, never a gameplay failure.
- **Suggested fix:** use RFC 8785 or document exact shared encoding rules and add
  a canonical bundle/hash fixture.

## 5. Weekly rollover needs a shared timezone policy

- **Endpoint:** `GET /v1/leaderboards/weekly`,
  `POST /v1/leaderboards/weekly/score`.
- **Problem:** weeks use `Europe/Belgrade`, including daylight-saving transitions,
  but the save schema has no weekly score period. Client-only counters belong in
  `save.client`. Device locale must not determine the leaderboard week.
- **Client behavior:** weekly counters use explicit week metadata in the local
  save envelope's network state; the mock leaderboard supplies `week_id`,
  `starts_at` and `ends_at` using Belgrade boundaries. Cross-device weekly-counter
  reconciliation is deferred with live networking.
- **Suggested fix:** document the offline weekly-counter reconciliation policy
  and add tests around Sunday UTC/Monday Belgrade and both DST transitions.

## 6. Integer rounding and order settlement need shared rules

- **Endpoint/schema:** `GET /v1/config`; `upgrades.schema.json`,
  `drinks.schema.json`, `guest-types.schema.json`, `events.schema.json`.
- **Problem:** money is integral, but upgrade growth and scaled event prices can
  be fractional. The schemas do not specify rounding, whether bills settle at
  service or departure, or whether service-speed upgrades provide automatic
  service as well as faster preparation.
- **Client behavior:** upgrade and event costs use ceiling; order revenue rounds
  to the nearest dinar; tips and offline earnings use floor. Ingredients are paid
  at preparation start and bill/tips collected on departure. Service-speed
  upgrades enable automatic preparation of waiting orders. Later orders are
  spaced by `stay_seconds / orders_per_visit`.
- **Suggested fix:** define shared rounding and order/service semantics in the
  schemas and supply economy examples used by both client and simulator tests.

## 7. Offline claims need recovery after an ambiguous response

- **Endpoint:** `POST /v1/offline-earnings/claim`.
- **Problem:** a request has no idempotency key or receipt endpoint. If the server
  accepts a claim but its response is lost, retrying returns zero because the
  period has been consumed. Granting a local fallback and then retrying can also
  duplicate credit without a durable reconciliation rule.
- **Client behavior:** Task 1 settles only local earnings and persists its pending
  and settled ledger with money. The mock claim wrapper is tested independently
  but is not mixed with local settlement. Real claim reconciliation is deferred.
- **Suggested fix:** accept a client claim UUID, return the original grant on a
  retry, and specify how a previously local-settled period is uploaded without
  granting it again.
