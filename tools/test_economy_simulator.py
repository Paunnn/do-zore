"""Run with python -m unittest discover -s tools -p 'test_*.py'."""
import copy
import hashlib
import math
from pathlib import Path
import unittest

import economy_simulator as model


class EconomySimulatorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = model.load_data()

    def setUp(self):
        self.save = model.fresh_save(self.data)

    def test_offline_formula_at_all_tiers(self):
        for venue in self.data['venues']:
            for band in self.data['band_levels']:
                self.save.update(venue=venue['id'], band_level=band['id'])
                expected = max(0, venue['offline_income_per_minute'] * band['tip_multiplier'] - band['upkeep_per_hour'] / 60)
                self.assertAlmostEqual(model.offline_rate(self.data, self.save), expected)

    def test_absence_minimum_cap_and_clock_rollback(self):
        rules = self.data['economy']['offline']
        venue = model.item(self.data, 'venues', self.save['venue'])
        self.assertEqual(model.offline_earnings(self.data, self.save, -1)['granted_amount'], 0)
        self.assertEqual(model.offline_earnings(self.data, self.save, rules['min_away_seconds'] - 1)['granted_amount'], 0)
        cap = min(venue['offline_cap_hours'], rules['max_cap_hours'])
        expected = math.floor(model.offline_rate(self.data, self.save) * cap * 60)
        result = model.offline_earnings(self.data, self.save, cap * 7200)
        self.assertEqual(result['granted_amount'], expected)
        self.assertTrue(result['capped'])

    def test_upgrade_effects_and_table_ceiling(self):
        for upgrade in self.data['upgrades']:
            self.save['upgrades'] = {upgrade['id']: upgrade['max_level']}
            for effect in upgrade['effects']:
                expected = (1 + effect['per_level'] * upgrade['max_level'] if effect['op'] == 'add'
                            else effect['per_level'] ** upgrade['max_level'])
                self.assertAlmostEqual(model.stat(self.data, self.save, effect['stat']), expected)
        self.save['upgrades'] = {u['id']: u['max_level'] for u in self.data['upgrades']}
        self.assertLessEqual(model.table_count(self.data, self.save), model.item(self.data, 'venues', self.save['venue'])['max_tables'])
        self.assertLessEqual(model.offline_earnings(self.data, self.save, 10**9)['cap_hours'], self.data['economy']['offline']['max_cap_hours'])

    def test_curve_interpolation_and_clamping(self):
        points = self.data['economy']['tips']['mood_curve']
        self.assertEqual(model.curve(points, points[0]['x'] - 1), points[0]['y'])
        self.assertEqual(model.curve(points, points[-1]['x'] + 1), points[-1]['y'])
        midpoint = (points[0]['x'] + points[1]['x']) / 2
        self.assertEqual(model.curve(points, midpoint), (points[0]['y'] + points[1]['y']) / 2)

    def test_determinism_and_no_source_writes(self):
        sources = sorted((model.ROOT / 'data').glob('*.json'))
        hashes = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
        options = model.Options(hours=0.5, step_seconds=1, upgrade_policy='none')
        first = model.Simulation(self.data, options, 7, 1440).run()
        second = model.Simulation(self.data, options, 7, 1440).run()
        self.assertEqual(first, second)
        self.assertGreater(first['metrics']['online_seconds'], 0)
        self.assertGreater(first['metrics']['requests_matched'], 0)
        self.assertEqual(hashes, {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in sources})

    def test_serving_charges_once_and_departure_pays_once(self):
        sim = model.Simulation(self.data, model.Options(upgrade_policy='none'), 1, 1440)
        guest = self.data['guest_types'][0]
        sim.spawn(guest['id'])
        table = sim.tables[0]
        drink = model.item(self.data, 'drinks', table['drink'])
        before = sim.save['money']
        sim.automated_player()
        charged = sim.save['money']
        self.assertEqual(before - charged, drink['cost'] * table['size'])
        sim.automated_player()
        self.assertEqual(sim.save['money'], charged)
        sim.complete_service(table)
        sim.depart(0)
        paid = sim.save['money']
        self.assertGreater(paid, charged)
        sim.depart(0)
        self.assertEqual(sim.save['money'], paid)

    def test_song_match_uses_guest_and_band_multipliers(self):
        sim = model.Simulation(self.data, model.Options(), 3, 1440)
        guest = self.data['guest_types'][0]
        sim.spawn(guest['id'])
        table = sim.tables[0]
        song = next(s for s in sim.known_songs() if s['genre'] == guest['preferred_genre'])
        sim.song = song
        before = table['mood']
        sim.apply_song(table)
        expected = self.data['economy']['mood']['song_match_delta'] * song['mood_power'] * guest['mood_sensitivity'] * sim.band['mood_multiplier']
        self.assertAlmostEqual(table['mood'] - before, expected)
        self.assertEqual(table['request'], '')

    def test_progression_respects_prices_and_tier_order(self):
        sim = model.Simulation(self.data, model.Options(upgrade_policy='none', reserve_minutes=0), 1, 1440)
        for venue in sorted(self.data['venues'], key=lambda v: v['order'])[1:]:
            sim.save['money'] = venue['unlock_cost'] - 1
            before = sim.save['venue']
            sim.buy_progress()
            self.assertEqual(sim.save['venue'], before)
            sim.save['money'] = venue['unlock_cost']
            sim.buy_progress()
            self.assertEqual(sim.save['venue'], venue['id'])
            self.assertEqual(sim.save['money'], 0)

    def test_report_marks_unreached_and_separates_heuristics(self):
        report = model.build_report(self.data, model.Options(hours=0.1, upgrade_policy='none'), [1])
        self.assertIsNone(report['scenarios']['active']['milestones'][self.data['venues'][-1]['id']]['median_hours'])
        self.assertIn('heuristic_online_net_per_minute', report['stationary_diagnostics'][0])
        self.assertIn('not reached', model.render_report(report))
        self.assertTrue(report['assumptions'])

    def test_daily_return_applies_cap(self):
        options = model.Options(hours=24, online_minutes_per_day=1, upgrade_policy='none')
        result = model.Simulation(self.data, options, 1, 1).run()
        expected = model.offline_earnings(self.data, self.save, 1439 * 60)['granted_amount']
        self.assertEqual(result['metrics']['offline_income'], expected)
        self.assertEqual(result['metrics']['online_seconds'], 60)


if __name__ == '__main__':
    unittest.main()
