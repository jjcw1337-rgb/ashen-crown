"""Exercise actual HTTP admission across different development build revisions."""
import json
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path
from types import SimpleNamespace
from service import Handler, Lobbies, Rejected

class HttpAdmissionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.model = Lobbies(str(Path(self.temp.name) / 'state.sqlite'), lambda r: '127.0.0.1:24600', lambda r: None)
        def user(header):
            if header not in ('Bearer account-a', 'Bearer account-b'):
                raise Rejected('Sign in first.')
            return header.removeprefix('Bearer ')
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.server.service = SimpleNamespace(args=SimpleNamespace(dev=False), version='server-old', user=user, model=self.model)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
    def tearDown(self):
        self.server.shutdown(); self.server.server_close(); self.thread.join()
        self.model.db.close(); self.temp.cleanup()
    def post(self, op, account='account-a', **body):
        req = urllib.request.Request('http://127.0.0.1:%d/lobbies' % self.server.server_port,
            data=json.dumps(dict(op=op, **body)).encode(), headers={'Authorization': 'Bearer ' + account})
        try:
            with urllib.request.urlopen(req) as response: return response.status, json.load(response)
        except urllib.error.HTTPError as response: return response.code, json.load(response)
    def test_different_builds_create_join_ready_start(self):
        status, data = self.post('create', version='new-client-a', mode='arena', character='a')
        self.assertEqual(status, 200); rid = data['lobby']['id']
        self.assertEqual(self.post('join', 'account-b', version='new-client-b', id=rid, character='b')[0], 200)
        for account in ('account-a', 'account-b'):
            self.assertEqual(self.post('ready', account, version='another-build', id=rid, ready=True)[0], 200)
        status, data = self.post('start', version='new-client-a', id=rid)
        self.assertEqual(status, 200); self.assertEqual(data['lobby']['state'], 'starting')
    def test_missing_revision_is_allowed(self):
        self.assertEqual(self.post('create', mode='waves', character='a')[0], 200)
    def test_anonymous_and_dev_identity_still_rejected(self):
        for account in ('', 'dev-test'):
            status, data = self.post('create', account, version='anything', mode='waves', character='a')
            self.assertEqual(status, 400); self.assertEqual(data['error'], 'Sign in first.')
    def test_ready_rule_remains(self):
        _, data = self.post('create', version='anything', mode='waves', character='a')
        status, data = self.post('start', id=data['lobby']['id'])
        self.assertEqual(status, 400); self.assertEqual(data['error'], 'Everyone must be ready.')
