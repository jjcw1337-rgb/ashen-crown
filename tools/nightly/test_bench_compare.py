import copy
import unittest
from bench_compare import aggregate, compare, NAMES


def fixture():
    data = {}
    for key in NAMES:
        row = dict(schema=2, clock='monotonic_wall', focused=True, engine='4.3', renderer='forward_plus',
                   gpu_name='fixture', resolution='1600x900', preset=int(key[-1]), scenario=key.split('_q')[0],
                   fps_avg=60, frame_ms_p99=20, frame_ms_max=30, first_use_max_ms=40, hitches_per_min=0,
                   load_ms=2500, ram_mb=500, vram_mb=1000, frames=1800, secs=30, validation={'clean': True},
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
        for field, value in [('validation', {'clean': False}), ('pvp', {'actors': 2}), ('resolution', '800x600')]:
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

    def test_median_not_best(self):
        rows = [{'fps_avg': 10}, {'fps_avg': 20}, {'fps_avg': 100}]
        result = aggregate(rows)
        self.assertEqual(result['fps_avg'], 20)
        self.assertEqual(len(result['runs']), 3)


if __name__ == '__main__':
    unittest.main()
