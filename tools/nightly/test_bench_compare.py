import copy
import unittest
from unittest.mock import patch
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import run_kpi
from bench_compare import aggregate, compare, NAMES


def fixture():
    data = {}
    for key in NAMES:
        row = dict(**{'class': 'knight', 'skill': ''}, schema=2, clock='monotonic_wall', focused=True, engine='4.3', renderer='forward_plus',
                   gpu_name='fixture', environment='fixture', map_title='fixture', resolution='1600x900', preset=int(key[-1]), scenario=key.split('_q')[0],
                   fps_avg=60, frame_ms_p99=20, frame_ms_max=30, first_use_max_ms=40, hitches_per_min=0,
                   load_ms=2500, ram_mb=500, vram_mb=1000, frames=1800, secs=30, validation={'clean': True, 'quiet': True},
                   pvp={'actors': 6, 'teams': [3, 3], 'bursts': 5, 'presentation_events': 300})
        data[key] = aggregate([copy.deepcopy(row) for _ in range(3)])
    return data


class Gate(unittest.TestCase):
    def test_unchanged(self):
        self.assertEqual(compare(fixture(), fixture()), [])

    def test_bad_signals(self):
        for field, value in [('fps_avg', 40), ('frame_ms_p99', 500), ('hitches_per_min', 20),
                             ('load_ms', 20000), ('ram_mb', 1000), ('vram_mb', 2000), ('first_use_max_ms', 600),
                             ('frame_ms_max', 800), ('focused', False), ('fps_avg', float('nan'))]:
            with self.subTest(field=field, value=value):
                changed = fixture()
                runs = changed['pvp3v3_q2']['runs']
                for r in runs:
                    r[field] = value
                changed['pvp3v3_q2'] = aggregate(runs)
                self.assertTrue(compare(fixture(), changed))

    def test_missing_scenario_and_repeat(self):
        for key in NAMES:
            data = fixture()
            del data[key]
            self.assertTrue(compare(fixture(), data))
        data = fixture()
        data['pvp3v3_q2'] = aggregate(data['pvp3v3_q2']['runs'][:2])
        self.assertTrue(compare(fixture(), data))

    def test_error_and_wrong_workload(self):
        for field, value in [('validation', {'clean': False, 'quiet': True}), ('validation', {'clean': True, 'quiet': False}), ('pvp', {'actors': 2}), ('resolution', '800x600')]:
            data = fixture()
            data['pvp3v3_q2']['runs'][1][field] = value
            self.assertTrue(compare(fixture(), data))

    def test_one_bad_repeat_is_not_hidden(self):
        data = fixture()
        runs = data['pvp3v3_q2']['runs']
        runs[0]['frame_ms_max'] = 2000
        data['pvp3v3_q2'] = aggregate(runs)
        self.assertEqual(data['pvp3v3_q2']['frame_ms_max'], 30)
        self.assertTrue(compare(fixture(), data))

    def test_changed_map_is_not_comparable(self):
        changed = fixture()
        for row in changed['crypt_q2']['runs']: row['map_title'] = 'new map'
        changed['crypt_q2'] = aggregate(changed['crypt_q2']['runs'])
        self.assertTrue(compare(fixture(), changed))

    def test_missing_context(self):
        data = fixture()
        for row in data["pvp3v3_q2"]["runs"]:
            row.pop("renderer")
        data["pvp3v3_q2"] = aggregate(data["pvp3v3_q2"]["runs"])
        self.assertTrue(compare(fixture(), data))

    def test_median_not_best(self):
        rows = [{'fps_avg': 10}, {'fps_avg': 20}, {'fps_avg': 100}]
        result = aggregate(rows)
        self.assertEqual(result['fps_avg'], 20)
        self.assertEqual(len(result['runs']), 3)


class Runner(unittest.TestCase):
    def test_exit_zero_with_runtime_error_rejected(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(run_kpi, 'other_engines', return_value=[]), contextlib.redirect_stdout(io.StringIO()):
            prefix = Path(folder) / 'probe'
            code = run_kpi.run(prefix, [sys.executable, '-c', 'print("SCRIPT ERROR: fixture")'])
            self.assertEqual(code, 1)
            self.assertFalse(json.loads(prefix.with_suffix('.validation.json').read_text())['clean'])

    def test_competition_does_not_launch_or_reuse_result(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(run_kpi, 'other_engines', return_value=[123]), patch.object(run_kpi.subprocess, 'Popen') as launch, contextlib.redirect_stdout(io.StringIO()):
            prefix = Path(folder) / 'probe'
            prefix.with_suffix('.json').write_text('{}')
            self.assertEqual(run_kpi.run(prefix, [sys.executable]), 1)
            launch.assert_not_called()
            self.assertFalse(prefix.with_suffix('.json').exists())

    def test_clean_and_timeout(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(run_kpi, 'other_engines', return_value=[]), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(run_kpi.run(Path(folder) / 'ok', [sys.executable, '-c', 'print("ok")']), 0)
            self.assertEqual(run_kpi.run(Path(folder) / 'timeout', [sys.executable, '-c', 'import time; time.sleep(10)'], timeout=.1), 1)
            self.assertTrue(json.loads((Path(folder) / 'timeout.validation.json').read_text())['timed_out'])



class FunctionalLogTests(unittest.TestCase):
    def test_telemetry_requires_exact_injections_and_successful_reporting(self):
        from check_functional_log import inspect
        text = '\n'.join(f'[T] EXPECT TELEMETRY INJECTION {n}\nERROR: telemetry test error {n}\n   at: push_error (core/variant/variant_utility.cpp:1092)' for n in (1234, 5678))
        text += '\n[T] ok   an error from the log, fingerprinted: one issue, counted twice (2)\n[T] done, 0 failed'
        self.assertEqual(len(inspect(text)[1]), 2)
        self.assertEqual(inspect(text, True)[1], [])
        self.assertTrue(inspect(text.replace('[T] done, 0 failed', ''), True)[1])
        self.assertTrue(inspect(text + '\nERROR: telemetry test error 1234', True)[1])
        self.assertTrue(inspect(text + '\nERROR: unrelated failure', True)[1])

    def test_only_the_exact_dummy_renderer_defect_is_classified_known(self):
        from check_functional_log import inspect
        known = 'ERROR: Parameter "m" is null.\n   at: mesh_get_surface_count (servers/rendering/dummy/storage/mesh_storage.h:120)'
        self.assertEqual(inspect(known)[:2], (1, []))
        self.assertEqual(len(inspect(known + '\nSCRIPT ERROR: broken readiness')[1]), 1)
        self.assertEqual(len(inspect('ERROR: Parameter "m" is null.\n at: game.gd:12')[1]), 1)
        self.assertEqual(inspect('[TEST] passed')[:2], (0, []))
        self.assertEqual(len(inspect('[X] FAIL missing status effect')[1]), 1)

if __name__ == '__main__':
    unittest.main()
