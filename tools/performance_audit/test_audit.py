import copy
import datetime as dt
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile
import audit

class AuditTests(unittest.TestCase):
    def valid_groups(self):
        metrics = {k: 1.0 for k in audit.METRICS}
        metrics.update(fps_avg=60, focused=True, gameplay_sync_misses={},
                       pvp={'recipe_fingerprint':'a'*64,'actors':6,'teams':[3,3],'bursts':6,'presentation_events':100})
        groups = {k: [copy.deepcopy({'valid': True, 'metrics': metrics}) for _ in range(3)] for k in audit.SCENARIOS}
        for key, roster, zone in [('pvp3v3:2',['demon','plague','archer']*2,'arena'),
                                 ('pvp_dragons:2',['wyrm','serpent','wyvern']*2,'sandbox'),
                                 ('pvp_forest:2',['warlock','wraith','plague']*2,'bg')]:
            for row in groups[key]:
                row['metrics']['pvp'].update(classes=roster, profile=key.split(':')[0])
                row['metrics']['environment'] = zone
        return groups
    def test_complete_coverage(self):
        groups = self.valid_groups()
        self.assertEqual(audit.evaluate(groups)[0], [])
        del groups['pvp3v3:2']
        self.assertTrue(audit.evaluate(groups)[0])
    def test_bad_repeat_never_hidden(self):
        groups = self.valid_groups(); groups['fight:2'][2]['metrics']['frame_ms_p99'] = 500
        _, summary = audit.evaluate(groups)
        self.assertEqual(summary['fight:2']['frame_ms_p99']['worst'], 500)
        self.assertTrue(audit.budget_issues(summary))
    def test_rejects_missing_focus_cache_and_nonfinite(self):
        for key, value in [('focused',False),('gameplay_sync_misses',{'x':1}),('frame_ms_max',float('nan'))]:
            groups = self.valid_groups(); groups['camp:2'][0]['metrics'][key] = value
            self.assertTrue(audit.evaluate(groups)[0])
    def test_flood_must_actually_run(self):
        groups = self.valid_groups(); groups['pvp3v3:2'][0]['metrics']['pvp']['actors'] = 2
        self.assertTrue(audit.evaluate(groups)[0])
    def test_wrong_pvp_roster_or_environment_rejected(self):
        for key in ['pvp_dragons:2', 'pvp_forest:2']:
            groups = self.valid_groups(); groups[key][0]['metrics']['pvp']['classes'] = ['knight']*6
            self.assertTrue(audit.evaluate(groups)[0])
            groups = self.valid_groups(); groups[key][1]['metrics']['environment'] = 'town'
            self.assertTrue(audit.evaluate(groups)[0])
    def test_recipe_changes_cannot_mix_repeats(self):
        groups = self.valid_groups()
        groups['pvp3v3:2'][1]['metrics']['pvp']['recipe_fingerprint'] = 'b'*64
        self.assertTrue(audit.evaluate(groups)[0])
        groups = self.valid_groups()
        del groups['pvp3v3:2'][0]['metrics']['pvp']['recipe_fingerprint']
        self.assertTrue(audit.evaluate(groups)[0])
    def test_balance_requires_actual_finite_positive_damage(self):
        data = {f'{cls}:20:{gear}': dict(cls=cls,lvl=20,gear=gear,dps=10,ehp=100,life=100)
                for cls in ['demon','plague','archer'] for gear in ['fresh','geared']}
        self.assertEqual(audit.balance_issues(data), [])
        data['plague:20:geared']['dps'] = 0
        self.assertTrue(audit.balance_issues(data))
        del data['archer:20:fresh']
        self.assertEqual(len(audit.balance_issues(data)), 2)
    def test_errors_with_exit_zero(self):
        self.assertTrue(audit.errors('\x1b[31mSCRIPT ERROR: bad\x1b[0m\n0 failures'))
        self.assertTrue(audit.errors('WARNING: render warning'))
        self.assertEqual(audit.errors('[SURFACE] 73 checks / 0 failures'), [])
    def test_schedule_retry_and_completion(self):
        at = dt.datetime(2026,11,6,22,30)
        self.assertTrue(audit.eligible(at, {}))
        self.assertTrue(audit.eligible(at, {'date':'2026-11-06','state':'deferred'}))
        self.assertFalse(audit.eligible(at, {'date':'2026-11-06','state':'findings'}))
        self.assertFalse(audit.eligible(at.replace(hour=12), {}))
        self.assertFalse(audit.eligible(at.replace(hour=23,minute=30), {}))
    def test_regression_uses_worst_and_median(self):
        _, before = audit.evaluate(self.valid_groups()); after = copy.deepcopy(before)
        after['pvp3v3:2']['frame_ms_max']['worst'] = 500
        self.assertTrue(audit.compare(after, before))
        self.assertEqual(audit.compare(before, before), [])
    def test_archive_escape_rejected(self):
        with tempfile.TemporaryDirectory() as d:
            archive = Path(d)/'bad.zip'
            with zipfile.ZipFile(archive,'w') as z: z.writestr('../a.app/Contents/escape','bad')
            with self.assertRaises(RuntimeError): audit.extract_mac(archive,Path(d)/'out')
    def test_busy_claim_does_not_start_or_release(self):
        with tempfile.TemporaryDirectory() as d:
            instance = audit.Audit(Path(d),Path(d))
            with patch.object(audit,'command',return_value=json.dumps({'heavy-tests':{'owner':'claude-1'}})), patch.object(audit.subprocess,'run') as run:
                with self.assertRaises(audit.Deferred): instance.execute()
                run.assert_not_called()
                self.assertFalse(instance.claimed)
    def test_legacy_lock_stops_only_own_workload(self):
        with tempfile.TemporaryDirectory() as d:
            instance = audit.Audit(Path(d),Path(d)); instance.last_memory_check = audit.time.monotonic()
            with patch.object(audit,'LEGACY',Path(d)):
                with self.assertRaises(audit.Deferred): instance.safe(42)
    def test_report_does_not_claim_green_on_deferral(self):
        with tempfile.TemporaryDirectory() as d:
            instance = audit.Audit(Path(d),Path(d)); instance.report['state']='deferred'; instance.save()
            self.assertEqual(json.loads((Path(d)/'latest.json').read_text())['state'],'deferred')

if __name__ == '__main__': unittest.main()
