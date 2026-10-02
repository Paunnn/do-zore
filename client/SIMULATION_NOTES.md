# Simulation implementation notes

The `kafana_simulation.gd` RefCounted owns runtime tables, orders, requests, mood, songs, event decisions, timers and temporary modifiers. It takes a bundle, technical settings, a save dictionary and an optional deterministic RNG seed. It has no dependency on nodes, UI, autoloads or network. `economy_math.gd` contains pure formulas; `GameState` and `Economy` bridge them to application signals and local persistence. Simulation state is stored in the schema's opaque `client.simulation` object.

## Formula and timing choices

- A newly configured simulation (no saved `client.simulation` timers) sends its first guest after
  `first_arrival_seconds` from `config/simulation.json` (3 s) instead of a full arrival interval,
  so a new game never opens on empty tables. Restored saves keep their own timers. The Python
  simulator does not model this one-off head start.

- Upgrade additions are summed before multiplication; multiplicative upgrade effects use `per_level ** owned_level`. Table capacity is capped by the current venue.
- Offline income, upkeep deduction, table scaling, cap and minimum absence follow the description in `economy.schema.json`. Offline amounts use floor. Upgrade costs and scaled event amounts use ceiling where the descriptions leave integer rounding unspecified.
- Genre matching includes related genres and their data-defined strength. Song effects include song power, guest sensitivity, positive band mood power and sound-system upgrades. Named wishes display an example known song; matching behavior remains genre-based as required by the economy formula.
- `guest-types.schema.json` explicitly applies `mood_sensitivity` to all mood changes. Waiting, preferred drinks, events and drift therefore apply it once, as do song effects.
- Tips follow the specified bill, mood curve, band, preferred-drink and upgrade multipliers, and settle once when a paying group departs. Song matches improve that eventual tip by improving mood. Replaying requests cannot mint extra copies of the same tip.
- Song duration prevents starting another song before completion. Arrivals use the configured rate and room mood curve; the first arrival also waits that data-derived interval. Known songs matching renewed requests can satisfy those requests while the band is still playing.
- Ingredient costs are paid when preparation starts; the bill is collected on departure. Order prices include party size, spending power, venue price and upgrade multipliers. Manual service starts preparation; service-speed upgrades also enable automatic service. Preparation duration uses item prep time divided by service speed. Later orders are scheduled using stay time divided by orders per visit.
- A group's first order uses its preferred drink when available. Later orders choose an unlocked food if the menu contains food. There are no invented food probabilities or food balance entries.
- In the portrait floor's two-column geometry, orthogonally connected unhappy tables count toward a fight. The geometry is a presentation choice; minimum unhappy count, chance and cooldown come from events/economy data. Random-event effects, chained events, costs, weighted outcomes and decision timeouts are implemented.
- Timed live modifiers are injected by `GameState`; the pure simulation never calls the API. Offline live multipliers use exact overlap intervals. Guest-specific offline modifiers are deferred because the contract provides no historical guest income attribution for the offline aggregate; the client does not invent distribution weights.

## Missing authoritative data

`/data/economy.json` and its strict schema do not define a high-mood stay extension or any glass-breaking roll, chance, cost or bonus. High mood does animate dancing, but stay extensions and glasses remain dormant hooks until authoritative fields are added. No balance values are invented in `/client`. The optional hooks expect `economy.mood.happy_stay_multiplier` and an `economy.glasses` object with `roll_interval_seconds`, `chance_per_happy_table`, `cost_per_glass`, `income_bonus_fraction` and `bonus_duration_seconds`; the data owner must approve and define these fields before they can appear in a schema-valid bundle.

`config/simulation.json` only contains the simulation's technical update interval and the floor's column count. Neither is an economy tuning value. New saves derive money, starting venue/band and free repertoire from canonical data.

Open contract questions to consolidate in `CONTRACT_ISSUES.md`: authoritative glass/stay fields; integer rounding for prices and upgrade/event costs; guest-specific offline modifier attribution; event adjacency (design specifies nearby tables while trigger schema says a count); whether order revenue should settle on service or departure; whether service-speed upgrades imply autonomous service.
