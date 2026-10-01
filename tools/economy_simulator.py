#!/usr/bin/env python3
"""Seeded, read-only Do Zore balance experiment; Python standard library only.

Discrete guests follow the Godot slice's equations. A scripted player serves every
affordable order and chooses the song with the largest aggregate requested mood
gain. Time discretisation and the buying/event policies are explicit assumptions,
not new balance constants. No source data is written.
"""
from __future__ import annotations

import argparse
import copy
from dataclasses import dataclass, field
import json
import math
from pathlib import Path
import random
import statistics
from typing import Any

ROOT = Path(__file__).resolve().parents[1]


def load_data(directory: Path = ROOT / "data") -> dict[str, Any]:
    data: dict[str, Any] = {}
    for path in sorted(directory.glob("*.json")):
        part = json.loads(path.read_text(encoding="utf-8-sig"))
        if path.stem == "economy":
            data["economy"] = {k: v for k, v in part.items() if k != "$schema"}
        else:
            data.update({k: v for k, v in part.items() if k != "$schema"})
    for name in ("venues", "band_levels", "guest_types", "songs", "drinks", "genres", "upgrades", "events", "economy"):
        if name not in data:
            raise ValueError(f"Missing data collection: {name}")
    return data


def item(data: dict, collection: str, identifier: str) -> dict:
    return next(value for value in data[collection] if value["id"] == identifier)


def fresh_save(data: dict) -> dict:
    venue = min(data["venues"], key=lambda row: row["order"])
    band = min(data["band_levels"], key=lambda row: row["order"])
    return {"money": data["economy"]["start"]["money"], "total_baksis": 0,
            "venue": venue["id"], "band_level": band["id"], "upgrades": {},
            "unlocked_songs": [s["id"] for s in data["songs"] if s["unlock_cost"] == 0
                               and item(data, "band_levels", s["min_band_level"])["order"] <= band["order"]]}


def stat(data: dict, save: dict, name: str, base: float = 1.0) -> float:
    addition, multiplier = 0.0, 1.0
    for upgrade in data["upgrades"]:
        level = save["upgrades"].get(upgrade["id"], 0)
        for effect in upgrade["effects"]:
            if effect["stat"] == name:
                if effect["op"] == "add":
                    addition += effect["per_level"] * level
                else:
                    multiplier *= effect["per_level"] ** level
    return (base + addition) * multiplier


def upgrade_cost(upgrade: dict, level: int) -> int:
    return math.ceil(upgrade["base_cost"] * upgrade["cost_growth"] ** level)


def table_count(data: dict, save: dict) -> int:
    venue = item(data, "venues", save["venue"])
    return min(venue["max_tables"], int(stat(data, save, "table_count", venue["base_tables"])))


def curve(points: list[dict], x: float) -> float:
    if not points:
        return 1.0
    if x <= points[0]["x"]:
        return points[0]["y"]
    for before, after in zip(points, points[1:]):
        if x <= after["x"]:
            return before["y"] + (after["y"] - before["y"]) * (x - before["x"]) / (after["x"] - before["x"])
    return points[-1]["y"]


def offline_rate(data: dict, save: dict) -> float:
    venue = item(data, "venues", save["venue"])
    band = item(data, "band_levels", save["band_level"])
    rate = venue["offline_income_per_minute"]
    for name in ("menu_price", "arrival_rate", "offline_income"):
        rate *= stat(data, save, name)
    rate *= table_count(data, save) / venue["base_tables"] * band["tip_multiplier"]
    return max(0.0, rate - band["upkeep_per_hour"] / 60)


def offline_earnings(data: dict, save: dict, seconds: float) -> dict:
    venue = item(data, "venues", save["venue"])
    rules = data["economy"]["offline"]
    cap = min(stat(data, save, "offline_cap_hours", venue["offline_cap_hours"]), rules["max_cap_hours"])
    away = max(0.0, seconds)
    counted = min(away, cap * 3600) if away >= rules["min_away_seconds"] else 0.0
    return {"granted_amount": math.floor(offline_rate(data, save) * counted / 60),
            "counted_seconds": int(counted), "cap_hours": cap, "capped": away > cap * 3600}


def amount(data: dict, save: dict, specification: dict) -> int:
    return math.ceil(max(specification.get("min", 0), specification.get("fixed", 0)
                         + specification.get("income_minutes", 0) * offline_rate(data, save)))


def stationary_estimate(data: dict, save: dict) -> float:
    """Heuristic for ROI decisions only; never paid into the simulated wallet.

    Assumes neutral-start mood plus a preferred drink, mean party sizes, all orders
    completed, uniform unlocked food selection, and table-capacity-limited flow.
    This is deliberately separate from observed discrete simulation income.
    """
    venue = item(data, "venues", save["venue"])
    band = item(data, "band_levels", save["band_level"])
    menu = [d for d in data["drinks"] if item(data, "venues", d["unlock_venue"])["order"] <= venue["order"]]
    food = [d for d in menu if d["kind"] == "food"]
    mix_sum = sum(venue["guest_mix"].values())
    mean_profit = mean_stay = 0.0
    mood = data["economy"]["mood"]["table_start"] + data["economy"]["mood"]["preferred_drink_delta"]
    for guest_id, weight in venue["guest_mix"].items():
        guest = item(data, "guest_types", guest_id)
        preferred = [d for d in menu if d["id"] == guest["preferred_drink"]] or menu
        orders = [preferred] + [(food or preferred)] * (guest["orders_per_visit"] - 1)
        size = (guest["party_size"]["min"] + guest["party_size"]["max"]) / 2
        gross = sum(statistics.mean(d["price"] for d in options) for options in orders)
        gross *= size * guest["spending_power"] * venue["price_multiplier"] * stat(data, save, "menu_price")
        costs = size * sum(statistics.mean(d["cost"] for d in options) for options in orders)
        tips = gross * guest["tip_rate"] * curve(data["economy"]["tips"]["mood_curve"], mood)
        tips *= band["tip_multiplier"] * stat(data, save, "tip_rate")
        tips *= 1 + data["economy"]["tips"]["preferred_drink_bonus"]
        mean_profit += (gross + tips - costs) * weight / mix_sum
        mean_stay += guest["stay_seconds"] * weight / mix_sum
    arrivals = venue["arrivals_per_minute"] * stat(data, save, "arrival_rate")
    arrivals *= curve(data["economy"]["arrivals"]["room_mood_curve"], mood)
    flow = min(arrivals, table_count(data, save) * 60 / mean_stay)
    return flow * mean_profit - band["upkeep_per_hour"] / 60


@dataclass
class Options:
    hours: float = 72.0
    step_seconds: float = 5.0
    online_minutes_per_day: float = 30.0
    upgrade_policy: str = "roi"
    roi_minutes: float = 360.0
    reserve_minutes: float = 5.0
    event_policy: str = "expected_cash"
    floor_columns: int = 2


@dataclass
class Metrics:
    online_seconds: float = 0.0
    offline_seconds: float = 0.0
    online_net: int = 0
    offline_income: int = 0
    investments: int = 0
    denied_orders: int = 0
    denied_arrivals: int = 0
    requests_matched: int = 0
    events: int = 0
    fights: int = 0
    by_venue: dict = field(default_factory=dict)
    milestones: dict = field(default_factory=dict)
    purchases: list = field(default_factory=list)


class Simulation:
    def __init__(self, data: dict, options: Options, seed: int, online_minutes: float):
        self.data, self.options, self.rng = data, options, random.Random(seed)
        self.save = fresh_save(data)
        self.lookup = {key: {row["id"]: row for row in data[key]} for key in
                       ("venues", "band_levels", "guest_types", "songs", "drinks", "genres", "upgrades", "events")}
        self.online_minutes = online_minutes
        self.metrics = Metrics(milestones={self.save["venue"]: 0.0})
        self.tables: list[dict | None] = [None] * table_count(data, self.save)
        self.elapsed = self.online_time = 0.0
        self.song: dict | None = None
        self.song_left = self.closed_left = self.upkeep_remainder = 0.0
        self.modifiers: list[dict] = []
        self.cooldowns: dict[str, float] = {}
        self.global_cooldown = 0.0
        self.mood_rules = data["economy"]["mood"]
        self.event_rules = data["economy"]["events"]
        self.room_mood = self.mood_rules["neutral"]
        self.event_left = self.event_rules["roll_interval_seconds"]
        self.condition_left = self.event_rules["condition_check_interval_seconds"]
        self.arrival_left = self.arrival_interval()
        self.purchase_left = 0.0
        self._base_stats: dict[str, float] = {}

    @property
    def venue(self) -> dict:
        return self.lookup["venues"][self.save["venue"]]

    @property
    def band(self) -> dict:
        return self.lookup["band_levels"][self.save["band_level"]]

    def s(self, name: str) -> float:
        if not hasattr(self, "_base_stats"):
            return stat(self.data, self.save, name)
        if name not in self._base_stats:
            self._base_stats[name] = stat(self.data, self.save, name)
        value = self._base_stats[name]
        for effect in self.modifiers:
            if effect["stat"] == name:
                value *= effect["value"]
        return value

    def available_menu(self) -> list[dict]:
        return [d for d in self.data["drinks"] if self.lookup["venues"][d["unlock_venue"]]["order"] <= self.venue["order"]]

    def known_songs(self) -> list[dict]:
        return [self.lookup["songs"][song_id] for song_id in self.save["unlocked_songs"]]

    def weighted(self, values: list, weights: list[float]):
        return self.rng.choices(values, weights=weights, k=1)[0]

    def arrival_interval(self) -> float:
        rate = self.venue["arrivals_per_minute"] * self.s("arrival_rate")
        rate *= curve(self.data["economy"]["arrivals"]["room_mood_curve"], self.room_mood)
        return 60 / rate if rate > 0 else math.inf

    def change_mood(self, table: dict, delta: float) -> None:
        sensitivity = self.lookup["guest_types"][table["guest"]]["mood_sensitivity"]
        table["mood"] = max(self.mood_rules["min"], min(self.mood_rules["max"], table["mood"] + delta * sensitivity))

    def song_delta(self, table: dict, song: dict) -> tuple[float, float]:
        preferred = table["request"]
        strength = 1.0 if preferred == song["genre"] else next(
            (r["strength"] for r in self.lookup["genres"][preferred]["related"] if r["genre"] == song["genre"]), 0.0)
        delta = self.mood_rules["song_mismatch_delta"]
        if strength > 0:
            delta = self.mood_rules["song_match_delta"] * strength * self.band["mood_multiplier"]
        return delta * song["mood_power"] * self.s("song_mood_power"), strength

    def apply_song(self, table: dict) -> None:
        if self.song and table["request"]:
            delta, strength = self.song_delta(table, self.song)
            self.change_mood(table, delta)
            if strength > 0:
                table["request"] = ""
                self.metrics.requests_matched += 1

    def request_song(self, table: dict) -> None:
        guest = self.lookup["guest_types"][table["guest"]]
        table["request"] = guest["preferred_genre"]
        table["request_left"] = guest["song_request_interval_seconds"]
        if self.song_left > 0:
            self.apply_song(table)

    def create_order(self, table: dict) -> None:
        guest = self.lookup["guest_types"][table["guest"]]
        if table["served"] >= guest["orders_per_visit"]:
            return
        menu = self.available_menu()
        preferred = self.lookup["drinks"][guest["preferred_drink"]]
        chosen = preferred if preferred in menu else self.rng.choice(menu)
        food = [d for d in menu if d["kind"] == "food"]
        if table["served"] > 0 and food:
            chosen = self.rng.choice(food)
        table.update(drink=chosen["id"], status="waiting", waiting=0.0)

    def spawn(self, guest_id: str | None = None) -> None:
        if self.closed_left > 0:
            return
        if None not in self.tables:
            self.metrics.denied_arrivals += 1
            return
        guest_id = guest_id or self.weighted(list(self.venue["guest_mix"]), list(self.venue["guest_mix"].values()))
        guest = self.lookup["guest_types"][guest_id]
        table = {"guest": guest_id, "size": self.rng.randint(guest["party_size"]["min"], guest["party_size"]["max"]),
                 "mood": self.mood_rules["table_start"], "stay": float(guest["stay_seconds"]),
                 "served": 0, "bill": 0, "preferred": False, "prep": 0.0, "next_order": 0.0,
                 "denied": False}
        self.tables[self.tables.index(None)] = table
        self.request_song(table)
        self.create_order(table)

    def depart(self, index: int, pay: bool = True, with_tip: bool = True) -> None:
        table = self.tables[index]
        if table is None:
            return
        if pay:
            self.save["money"] += table["bill"]
            if with_tip:
                guest = self.lookup["guest_types"][table["guest"]]
                tip = table["bill"] * guest["tip_rate"] * self.band["tip_multiplier"] * self.s("tip_rate")
                tip *= curve(self.data["economy"]["tips"]["mood_curve"], table["mood"])
                if table["preferred"]:
                    tip *= 1 + self.data["economy"]["tips"]["preferred_drink_bonus"]
                self.save["money"] += math.floor(tip)
                self.save["total_baksis"] += math.floor(tip)
        self.tables[index] = None

    def automated_player(self) -> None:
        if self.closed_left > 0:
            return
        if self.song_left <= 0:
            requested = [t for t in self.tables if t and t["request"]]
            if requested and self.known_songs():
                self.song = max(self.known_songs(), key=lambda song: sum(
                    self.song_delta(t, song)[0] * self.lookup["guest_types"][t["guest"]]["mood_sensitivity"] for t in requested))
                self.song_left = self.song["duration_seconds"]
                for table in requested:
                    self.apply_song(table)
        for table in self.tables:
            if table and table["status"] == "waiting":
                drink = self.lookup["drinks"][table["drink"]]
                cost = drink["cost"] * table["size"]
                if self.save["money"] >= cost:
                    self.save["money"] -= cost
                    table.update(status="preparing", prep=drink["prep_seconds"] / self.s("service_speed"))
                elif not table["denied"]:
                    self.metrics.denied_orders += 1
                    table["denied"] = True

    def complete_service(self, table: dict) -> None:
        guest = self.lookup["guest_types"][table["guest"]]
        drink = self.lookup["drinks"][table["drink"]]
        revenue = drink["price"] * table["size"] * guest["spending_power"]
        revenue *= self.venue["price_multiplier"] * self.s("menu_price") * self.s("income")
        table["bill"] += math.floor(revenue + 0.5)
        table["served"] += 1
        table.update(status="served", next_order=guest["stay_seconds"] / guest["orders_per_visit"])
        if drink["id"] == guest["preferred_drink"]:
            table["preferred"] = True
            self.change_mood(table, self.mood_rules["preferred_drink_delta"])

    def step(self, delta: float) -> None:
        self.automated_player()
        for effect in self.modifiers:
            effect["remaining"] -= delta
        self.modifiers = [e for e in self.modifiers if e["remaining"] > 0]
        self.cooldowns = {k: max(0, v - delta) for k, v in self.cooldowns.items()}
        self.global_cooldown = max(0, self.global_cooldown - delta)
        if self.closed_left > 0:
            self.closed_left = max(0, self.closed_left - delta)
            return
        self.upkeep_remainder += self.band["upkeep_per_hour"] * delta / 3600
        due = math.floor(self.upkeep_remainder)
        self.save["money"] = max(0, self.save["money"] - due)
        self.upkeep_remainder -= due
        self.song_left = max(0, self.song_left - delta)
        if self.song_left == 0:
            self.song = None
        for index, table in enumerate(self.tables):
            if table is None:
                continue
            guest = self.lookup["guest_types"][table["guest"]]
            decay = self.mood_rules["decay_per_minute"] * self.s("mood_decay") * guest["mood_sensitivity"] * delta / 60
            neutral = self.mood_rules["neutral"]
            table["mood"] += min(decay, neutral - table["mood"]) if table["mood"] < neutral else -min(decay, table["mood"] - neutral)
            happy = min(table["mood"], self.room_mood) >= self.mood_rules["happy_at_or_above"]
            table["stay"] -= delta / (self.mood_rules.get("happy_stay_multiplier", 1.0) if happy else 1.0)
            if table["status"] in ("waiting", "preparing"):
                table["waiting"] += delta
                if table["waiting"] > guest["patience_seconds"] * self.s("patience"):
                    self.change_mood(table, -self.mood_rules["waiting_penalty_per_minute"] * delta / 60)
            if table["status"] == "preparing":
                table["prep"] -= delta
                if table["prep"] <= 0:
                    self.complete_service(table)
            elif table["status"] == "served":
                table["next_order"] -= delta
                if table["next_order"] <= 0:
                    self.create_order(table)
            table["request_left"] -= delta
            if table["request_left"] <= 0:
                self.request_song(table)
            if table["mood"] <= self.mood_rules["leave_at_or_below"]:
                self.depart(index, True, False)
            elif table["stay"] <= 0:
                self.depart(index)
        occupied = [t["mood"] for t in self.tables if t]
        self.room_mood = statistics.mean(occupied) if occupied else self.mood_rules["neutral"]
        self.arrival_left -= delta
        if self.arrival_left <= 0:
            self.spawn()
            self.arrival_left = self.arrival_interval()
        self.condition_left -= delta
        if self.condition_left <= 0:
            self.check_fights()
            self.condition_left = self.event_rules["condition_check_interval_seconds"]
        self.event_left -= delta
        if self.event_left <= 0:
            self.roll_event()
            self.event_left = self.event_rules["roll_interval_seconds"]

    def event_eligible(self, event: dict) -> bool:
        return (self.global_cooldown <= 0 and self.cooldowns.get(event["id"], 0) <= 0
                and self.lookup["venues"][event["min_venue"]]["order"] <= self.venue["order"])

    def check_fights(self) -> None:
        unhappy = {i for i, t in enumerate(self.tables) if t and t["mood"] < self.mood_rules["unhappy_below"]}
        largest = 0
        while unhappy:
            cluster = [unhappy.pop()]
            for origin in cluster:
                for other in list(unhappy):
                    columns = self.options.floor_columns
                    if abs(origin % columns - other % columns) + abs(origin // columns - other // columns) == 1:
                        unhappy.remove(other)
                        cluster.append(other)
            largest = max(largest, len(cluster))
        for event in self.data["events"]:
            trigger = event["trigger"]
            if trigger["kind"] == "unhappy_tables" and self.event_eligible(event) and largest >= trigger["min_unhappy_tables"]:
                chance = trigger["chance"] * max(self.event_rules["fight_chance_min_multiplier"], self.s("fight_chance"))
                if self.rng.random() < chance:
                    self.metrics.fights += 1
                    self.resolve_event(event)
                    return

    def roll_event(self) -> None:
        if self.global_cooldown > 0 or self.rng.random() >= self.event_rules["chance_per_roll"]:
            return
        eligible = [e for e in self.data["events"] if e["trigger"]["kind"] == "random" and self.event_eligible(e)]
        if eligible:
            self.resolve_event(self.weighted(eligible, [e["trigger"]["weight"] for e in eligible]))

    def choice_value(self, choice: dict) -> float:
        value = -amount(self.data, self.save, choice.get("cost", {}))
        total = sum(o["weight"] for o in choice["outcomes"])
        rate = max(0, stationary_estimate(self.data, self.save))
        for outcome in choice["outcomes"]:
            cash = 0.0
            for effect in outcome["effects"]:
                kind = effect["type"]
                if kind in ("money_gain", "money_loss"):
                    cash += amount(self.data, self.save, effect["amount"]) * (1 if kind == "money_gain" else -1)
                elif kind == "close_venue":
                    cash -= rate * effect["duration_seconds"] / 60 + sum(t["bill"] for t in self.tables if t)
                elif kind == "remove_unhappy_guests" and not effect["pay"]:
                    cash -= sum(t["bill"] for t in self.tables if t and t["mood"] < self.mood_rules["unhappy_below"])
                elif kind == "stat_multiplier" and effect["stat"] in ("income", "arrival_rate"):
                    cash += rate * (effect["value"] - 1) * effect["duration_seconds"] / 60
            value += cash * outcome["weight"] / total
        return value

    def resolve_event(self, event: dict, depth: int = 0) -> None:
        if depth > len(self.data["events"]):
            raise ValueError("Cyclic trigger_event effects")
        self.metrics.events += 1
        self.cooldowns[event["id"]] = event["cooldown_seconds"]
        self.global_cooldown = self.event_rules["global_cooldown_seconds"]
        choices = [c for c in event["choices"] if amount(self.data, self.save, c.get("cost", {})) <= self.save["money"]]
        if not choices:
            return
        if self.options.event_policy == "timeout":
            choice = next((c for c in choices if c["id"] == event["timeout_choice"]), choices[0])
        else:
            choice = max(choices, key=self.choice_value)
        self.save["money"] -= amount(self.data, self.save, choice.get("cost", {}))
        outcome = self.weighted(choice["outcomes"], [o["weight"] for o in choice["outcomes"]])
        for effect in outcome["effects"]:
            kind = effect["type"]
            if kind in ("money_gain", "money_loss"):
                change = amount(self.data, self.save, effect["amount"]) * (1 if kind == "money_gain" else -1)
                self.save["money"] = max(0, self.save["money"] + change)
            elif kind == "mood_change":
                for table in self.tables:
                    if table:
                        self.change_mood(table, effect["value"])
            elif kind == "stat_multiplier":
                self.modifiers.append(dict(stat=effect["stat"], value=effect["value"], remaining=effect["duration_seconds"]))
            elif kind == "close_venue":
                self.closed_left = effect["duration_seconds"]
                self.tables = [None] * len(self.tables)
                self.song, self.song_left = None, 0.0
            elif kind == "remove_unhappy_guests":
                for index, table in enumerate(self.tables):
                    if table and table["mood"] < self.mood_rules["unhappy_below"]:
                        self.depart(index, effect["pay"], False)
            elif kind == "spawn_guests":
                for _ in range(math.ceil(len(self.tables) * effect["table_fraction"])):
                    self.spawn(effect["guest_type"])
            elif kind == "trigger_event":
                self.resolve_event(self.lookup["events"][effect["event"]], depth + 1)

    def daily_estimate(self, save: dict) -> float:
        return (stationary_estimate(self.data, save) * self.online_minutes
                + offline_earnings(self.data, save, (1440 - self.online_minutes) * 60)["granted_amount"])

    def purchase(self, kind: str, identifier: str, cost: int) -> None:
        self.save["money"] -= cost
        self.metrics.investments += cost
        if kind == "venue":
            self.save["venue"] = identifier
            self.metrics.milestones[identifier] = self.elapsed / 3600
        elif kind == "upgrade":
            self.save["upgrades"][identifier] = self.save["upgrades"].get(identifier, 0) + 1
        elif kind == "band":
            self.save["band_level"] = identifier
        else:
            self.save["unlocked_songs"].append(identifier)
        self._base_stats.clear()
        self.tables.extend([None] * (table_count(self.data, self.save) - len(self.tables)))
        for song in self.data["songs"]:
            if (song["unlock_cost"] == 0 and song["id"] not in self.save["unlocked_songs"]
                    and self.lookup["band_levels"][song["min_band_level"]]["order"] <= self.band["order"]):
                self.save["unlocked_songs"].append(song["id"])
        self.metrics.purchases.append({"hour": round(self.elapsed / 3600, 4), "kind": kind, "id": identifier, "cost": cost})

    def buy_progress(self) -> None:
        reserve = max(0, stationary_estimate(self.data, self.save)) * self.options.reserve_minutes
        next_venue = next((v for v in self.data["venues"] if v["order"] == self.venue["order"] + 1), None)
        if next_venue and self.save["money"] >= next_venue["unlock_cost"] + reserve:
            self.purchase("venue", next_venue["id"], next_venue["unlock_cost"])
            return
        if self.options.upgrade_policy == "none":
            return
        baseline = self.daily_estimate(self.save)
        candidates = []
        for upgrade in self.data["upgrades"]:
            level = self.save["upgrades"].get(upgrade["id"], 0)
            if level >= upgrade["max_level"] or self.lookup["venues"][upgrade["unlock_venue"]]["order"] > self.venue["order"]:
                continue
            if any(e["stat"] == "table_count" for e in upgrade["effects"]) and len(self.tables) >= self.venue["max_tables"]:
                continue
            cost = upgrade_cost(upgrade, level)
            if self.save["money"] < cost + reserve:
                continue
            candidate = copy.deepcopy(self.save)
            candidate["upgrades"][upgrade["id"]] = level + 1
            gain = self.daily_estimate(candidate) - baseline
            payback = cost / gain * 1440 if gain > 0 else math.inf
            if payback <= self.options.roi_minutes:
                candidates.append((payback, "upgrade", upgrade["id"], cost))
        for band in self.data["band_levels"]:
            if band["order"] != self.band["order"] + 1 or self.lookup["venues"][band["required_venue"]]["order"] > self.venue["order"]:
                continue
            if self.save["money"] < band["unlock_cost"] + reserve:
                continue
            candidate = copy.deepcopy(self.save)
            candidate["band_level"] = band["id"]
            gain = self.daily_estimate(candidate) - baseline
            payback = band["unlock_cost"] / gain * 1440 if gain > 0 else math.inf
            if payback <= self.options.roi_minutes:
                candidates.append((payback, "band", band["id"], band["unlock_cost"]))
        if candidates:
            _, kind, identifier, cost = min(candidates)
            self.purchase(kind, identifier, cost)

    def run(self) -> dict:
        horizon = self.options.hours * 3600
        while self.elapsed < horizon:
            day_position = self.elapsed % 86400
            active_window = self.online_minutes * 60
            if day_position < active_window:
                delta = min(self.options.step_seconds, horizon - self.elapsed, active_window - day_position)
                venue_id = self.save["venue"]
                before = self.save["money"]
                self.step(delta)
                net = self.save["money"] - before
                self.metrics.online_net += net
                self.metrics.online_seconds += delta
                venue_metrics = self.metrics.by_venue.setdefault(venue_id, {"online_seconds": 0.0, "online_net": 0})
                venue_metrics["online_seconds"] += delta
                venue_metrics["online_net"] += net
                self.elapsed += delta
                self.online_time += delta
                self.purchase_left -= delta
                if self.purchase_left <= 0:
                    self.buy_progress()
                    self.purchase_left = 60.0  # Scripted player checks purchases once per minute.
            else:
                away = min(86400 - day_position, horizon - self.elapsed)
                grant = offline_earnings(self.data, self.save, away)["granted_amount"]
                self.save["money"] += grant
                self.metrics.offline_income += grant
                self.metrics.offline_seconds += away
                self.elapsed += away
                # A login at the horizon claims income; no post-horizon play is simulated.
                self.buy_progress()
        for row in self.metrics.by_venue.values():
            row["net_per_online_minute"] = row["online_net"] * 60 / row["online_seconds"] if row["online_seconds"] else 0.0
        return {"final_venue": self.save["venue"], "final_money": self.save["money"], "final_band": self.save["band_level"],
                "upgrades": self.save["upgrades"], "total_baksis": self.save["total_baksis"],
                "metrics": self.metrics.__dict__, "uncollected_bills": sum(t["bill"] for t in self.tables if t)}


def build_report(data: dict, options: Options, seeds: list[int]) -> dict:
    scenarios = {}
    for name, active_minutes in (("active", 1440.0), ("daily_login", options.online_minutes_per_day)):
        runs = [Simulation(data, options, seed, active_minutes).run() for seed in seeds]
        milestones = {}
        for venue in sorted(data["venues"], key=lambda row: row["order"]):
            times = [r["metrics"]["milestones"][venue["id"]] for r in runs if venue["id"] in r["metrics"]["milestones"]]
            milestones[venue["id"]] = {"reached_runs": len(times), "total_runs": len(runs),
                                      "median_hours": statistics.median(times) if times else None,
                                      "min_hours": min(times) if times else None, "max_hours": max(times) if times else None}
        online = statistics.mean(r["metrics"]["online_net"] / (r["metrics"]["online_seconds"] / 60) if r["metrics"]["online_seconds"] else 0 for r in runs)
        offline = statistics.mean(r["metrics"]["offline_income"] / (r["metrics"]["offline_seconds"] / 60) if r["metrics"]["offline_seconds"] else 0 for r in runs)
        scenarios[name] = {"online_minutes_per_day": active_minutes, "milestones": milestones,
                           "mean_net_per_online_minute": online, "mean_net_per_offline_minute_including_cap": offline,
                           "offline_online_ratio": offline / online if online > 0 else None, "runs": runs}
    stationary = []
    recommendations = []
    for venue in sorted(data["venues"], key=lambda row: row["order"]):
        save = fresh_save(data)
        save["venue"] = venue["id"]
        online = stationary_estimate(data, save)
        offline = offline_rate(data, save)
        row = {"venue": venue["id"], "heuristic_online_net_per_minute": round(online, 2),
               "offline_uncapped_net_per_minute": offline, "offline_online_ratio": offline / online if online > 0 else None,
               "base_cap_hours": venue["offline_cap_hours"]}
        stationary.append(row)
        if online > 0 and offline > online:
            recommendations.append({"field": f"venues.{venue['id']}.offline_income_per_minute",
                                    "current": venue["offline_income_per_minute"], "suggested": max(1, round(online)),
                                    "reason": "Offline rate exceeds heuristic perfect-service online net; suggested parity benchmark, not a validated target."})
    for band in sorted(data["band_levels"], key=lambda row: row["order"])[1:]:
        save = fresh_save(data)
        save["venue"] = band["required_venue"]
        previous = next(b for b in data["band_levels"] if b["order"] == band["order"] - 1)
        save["band_level"] = previous["id"]
        before = stationary_estimate(data, save)
        save["band_level"] = band["id"]
        after = stationary_estimate(data, save)
        if after < before:
            marginal_tips_per_hour = (after - before) * 60 + band["upkeep_per_hour"] - previous["upkeep_per_hour"]
            suggested = max(0, math.floor(previous["upkeep_per_hour"] + marginal_tips_per_hour))
            recommendations.append({"field": f"band_levels.{band['id']}.upkeep_per_hour", "current": band["upkeep_per_hour"],
                                    "suggested": suggested, "reason": "Direct tip gain alone does not cover marginal upkeep at minimum required venue. Suggested break-even upkeep excludes genre/mood benefits."})
    gaps = []
    if "glasses" not in data["economy"]:
        gaps.append("No canonical glasses cost/chance/bonus data: both this model and the client leave glass-breaking economics dormant.")
    if "happy_stay_multiplier" not in data["economy"]["mood"]:
        gaps.append("No canonical happy_stay_multiplier: high mood does not extend visits until data defines it.")
    return {"model": "seeded_discrete_client_slice", "options": options.__dict__, "seeds": seeds,
            "assumptions": ["No network, ads, purchases, live events, or data writes.",
                            "Guests, ingredient cash flow, delayed bills, mood, requests, song durations, random events and nearby fights are simulated.",
                            "A scripted player serves affordable orders every timestep and picks maximum aggregate requested mood gain.",
                            "Python RNG differs from Godot RNG; identical seeds reproduce this simulator, not Godot's exact guest sequence.",
                            "One contiguous active session per day; offline income is credited on the next login, including a final login at the horizon.",
                            "ROI uses a separate perfect-service stationary heuristic, checks once per minute, and does not value genre unlocks or buy paid songs.",
                            "Expected-cash event choices use monetary effects/closures only; mood and future guest spawn value are not valued by that policy.",
                            "Observed net cash excludes investment spend; in-progress ingredient outlays are included and unpaid bills reported separately.",
                            "Milestone medians/min/max include only runs reaching that venue; unreached runs are explicitly counted (right-censored).",
                            "Compare smaller --step-seconds and more --seeds before acting on proposed tuning; suggestions are hypotheses, not calibrated prescriptions."],
            "scenarios": scenarios, "stationary_diagnostics": stationary, "data_gaps": gaps, "suggestions": recommendations}


def render_report(report: dict) -> str:
    lines = ["DO ZORE — READ-ONLY ECONOMY EXPERIMENT", f"Seeded discrete model; {report['options']['hours']:g} h horizon; {report['options']['step_seconds']:g} s timestep; seeds {report['seeds']}", ""]
    for name, scenario in report["scenarios"].items():
        lines.append(f"{name}: {scenario['online_minutes_per_day']:g} online min/day")
        lines.append(f"  observed net / online minute: {scenario['mean_net_per_online_minute']:,.1f} din")
        lines.append(f"  credited net / offline minute (cap included): {scenario['mean_net_per_offline_minute_including_cap']:,.1f} din")
        ratio = scenario["offline_online_ratio"]
        lines.append(f"  offline / online ratio: {ratio:.3f}" if ratio is not None else "  offline / online ratio: undefined (nonpositive online net)")
        for venue, reached in scenario["milestones"].items():
            timing = "not reached" if reached["median_hours"] is None else f"median {reached['median_hours']:.2f} h (range {reached['min_hours']:.2f}–{reached['max_hours']:.2f})"
            lines.append(f"  {venue}: {timing}; reached {reached['reached_runs']}/{reached['total_runs']}")
        lines.append("")
    lines.append("Stationary diagnostics (heuristic; base tables/band, no upgrades):")
    for row in report["stationary_diagnostics"]:
        ratio = row["offline_online_ratio"]
        ratio_text = f"{ratio:.2f}x" if ratio is not None else "undefined"
        lines.append(f"  {row['venue']}: online {row['heuristic_online_net_per_minute']:,.0f}, offline {row['offline_uncapped_net_per_minute']:,.0f} din/min; {ratio_text}; cap {row['base_cap_hours']} h")
    lines.extend(["", "Balance hypotheses (suggested values only; data unchanged):"])
    for suggestion in report["suggestions"]:
        lines.append(f"  {suggestion['field']}: {suggestion['current']} -> trial {suggestion['suggested']}. {suggestion['reason']}")
    lines.extend("  " + gap for gap in report["data_gaps"])
    lines.extend(["", "Assumptions / uncertainty:"])
    lines.extend("  - " + assumption for assumption in report["assumptions"])
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data", type=Path, default=ROOT / "data")
    parser.add_argument("--hours", type=float, default=72.0)
    parser.add_argument("--step-seconds", type=float, default=5.0)
    parser.add_argument("--online-minutes-per-day", type=float, default=30.0)
    parser.add_argument("--seeds", default="1,2,3", help="Comma-separated integer seeds")
    parser.add_argument("--upgrade-policy", choices=("none", "roi"), default="roi")
    parser.add_argument("--roi-minutes", type=float, default=360.0, help="Maximum calendar-minute heuristic payback for purchases")
    parser.add_argument("--reserve-minutes", type=float, default=5.0, help="Keep this many heuristic income minutes before investments")
    parser.add_argument("--event-policy", choices=("timeout", "expected_cash"), default="expected_cash")
    parser.add_argument("--floor-columns", type=int, default=2, help="Client layout assumption used for nearby fight checks")
    parser.add_argument("--json", type=Path, help="Optional machine-readable report path")
    args = parser.parse_args()
    if args.hours <= 0 or not 0 < args.step_seconds <= 60 or not 0 < args.online_minutes_per_day <= 1440:
        parser.error("hours must be positive, step-seconds in (0,60], online-minutes-per-day in (0,1440]")
    if args.roi_minutes < 0 or args.reserve_minutes < 0 or args.floor_columns < 1:
        parser.error("ROI/reserve must be nonnegative and floor-columns >= 1")
    try:
        seeds = [int(value.strip()) for value in args.seeds.split(",")]
    except ValueError:
        parser.error("seeds must be comma-separated integers")
    options = Options(args.hours, args.step_seconds, args.online_minutes_per_day, args.upgrade_policy,
                      args.roi_minutes, args.reserve_minutes, args.event_policy, args.floor_columns)
    report = build_report(load_data(args.data), options, seeds)
    print(render_report(report), end="")
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
