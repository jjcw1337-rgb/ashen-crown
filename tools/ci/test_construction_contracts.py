import unittest
from pathlib import Path
from construction_contracts import inspect


class ConstructionContracts(unittest.TestCase):
    def test_new_zone_cannot_bypass_grass_scheduler(self):
        self.assertEqual(len(inspect(Path('zone.gd'), 'Grass.scatter(root, bounds, w, colors, 2, 42)')), 1)
        self.assertEqual(inspect(Path('zone.gd'), 'await w.scatter_grass(bounds, colors, 2, 42)'), [])

    def test_wrapped_sync_fallback_and_comments_remain_valid(self):
        self.assertEqual(inspect(Path('world.gd'), 'Grass.scatter(root, bounds, self, colors, 2, 42)'), [])
        self.assertEqual(inspect(Path('zone.gd'), '# Grass.scatter is the old API'), [])

    def test_coroutine_chain_must_be_awaited(self):
        for call in ['BgForest.build(w)', 'Battlegrounds.build(self)', 'w._scatter_ferns(500)']:
            with self.subTest(call=call):
                self.assertEqual(len(inspect(Path('zone.gd'), call)), 1)
                self.assertEqual(inspect(Path('zone.gd'), 'await ' + call), [])
