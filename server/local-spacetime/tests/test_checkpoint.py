"""Format failure checks; real store/restart tests are a separate acceptance run."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import checkpoint as cp
from world_lock import runner_lock, WorldBusy


class CheckpointTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.world = self.root / 'world'
        self.world.mkdir()
        self.runtime = self.root / 'runtime'
        self.runtime.write_bytes(b'pinned runtime fixture')
        for name in cp.REQUIRED:
            path = self.world / name
            if name in {'control-db', 'replicas', 'program-bytes'}:
                path.mkdir()
                (path / 'data').write_bytes(b'durable data')
            else:
                path.write_bytes(b'fixture')
        (self.world / 'gateway.json').write_text(json.dumps({
            'endpoint': 'http://127.0.0.1:3000', 'database': 'world', 'token': 'private'}))
        self.checkpoint = self.root / 'checkpoint'
        self.child = self.root / 'child'

    def capture(self):
        return cp.capture(self.world, self.checkpoint, self.runtime)

    def test_roundtrip_ancestry_private_modes_and_isolation(self):
        manifest = self.capture()
        self.assertEqual(cp.verify(self.checkpoint, self.runtime), manifest)
        parent_files = cp.world_files(self.world)
        branch = cp.fork(self.checkpoint, self.child, self.runtime, 3901)
        self.assertNotEqual(branch['id'], manifest['branch']['id'])
        self.assertEqual(branch['parent']['checkpoint'], manifest['id'])
        self.assertEqual(cp.world_files(self.world), parent_files)
        child_config = cp.read_json(self.child / 'gateway.json')
        self.assertEqual(child_config['endpoint'], 'http://127.0.0.1:3901')
        self.assertEqual(child_config['token'], 'private')
        (self.child / 'replicas/data').write_bytes(b'independent')
        self.assertEqual((self.world / 'replicas/data').read_bytes(), b'durable data')
        for directory in (self.child, self.checkpoint):
            self.assertEqual(directory.stat().st_mode & 0o777, 0o700)
            for file in directory.rglob('*'):
                if file.is_file():
                    self.assertEqual(file.stat().st_mode & 0o777, 0o600)

    def test_active_world_and_overlapping_destination_refused(self):
        with runner_lock(self.world):
            with self.assertRaises(WorldBusy):
                self.capture()
        self.assertFalse(self.checkpoint.exists())
        with self.assertRaises(ValueError):
            cp.capture(self.world, self.world / 'nested', self.runtime)

    def test_existing_destination_never_overwritten(self):
        self.capture()
        self.child.mkdir()
        sentinel = self.child / 'keep'
        sentinel.write_text('original')
        with self.assertRaises(FileExistsError):
            cp.fork(self.checkpoint, self.child, self.runtime, 3901)
        self.assertEqual(sentinel.read_text(), 'original')

    def test_corruption_and_incompatible_runtime_leave_no_child(self):
        self.capture()
        self.runtime.write_bytes(b'different runtime')
        with self.assertRaises(ValueError):
            cp.fork(self.checkpoint, self.child, self.runtime, 3901)
        self.runtime.write_bytes(b'pinned runtime fixture')
        (self.checkpoint / 'store/replicas/data').write_bytes(b'corrupt')
        with self.assertRaises(ValueError):
            cp.fork(self.checkpoint, self.child, self.runtime, 3901)
        self.assertFalse(self.child.exists())

    def test_path_traversal_and_duplicate_json_keys_rejected(self):
        self.capture()
        path = self.checkpoint / 'manifest.json'
        manifest = cp.read_json(path)
        manifest['files']['../escape'] = {'size': 0, 'sha256': '0' * 64}
        path.write_bytes(cp.canonical(manifest))
        with self.assertRaises(ValueError):
            cp.verify(self.checkpoint, self.runtime)
        path.write_text('{"format":"x","format":"y"}')
        with self.assertRaises(ValueError):
            cp.verify(self.checkpoint, self.runtime)

    def test_missing_extra_linked_and_special_files_rejected(self):
        self.capture()
        path = self.checkpoint / 'store/replicas/data'
        content = path.read_bytes()
        path.unlink()
        with self.assertRaises(ValueError):
            cp.verify(self.checkpoint, self.runtime)
        path.symlink_to(self.world / 'replicas/data')
        with self.assertRaises(ValueError):
            cp.verify(self.checkpoint, self.runtime)
        path.unlink()
        os.link(self.world / 'replicas/data', path)
        with self.assertRaises(ValueError):
            cp.verify(self.checkpoint, self.runtime)
        path.unlink()
        os.mkfifo(path)
        with self.assertRaises(ValueError):
            cp.verify(self.checkpoint, self.runtime)
        path.unlink()
        path.write_bytes(content)
        extra = self.checkpoint / 'store/extra'
        extra.write_text('unexpected')
        with self.assertRaises(ValueError):
            cp.verify(self.checkpoint, self.runtime)

    def test_source_link_rejected_without_creating_checkpoint(self):
        path = self.world / 'replicas/data'
        path.unlink()
        path.symlink_to(self.runtime)
        with self.assertRaises(ValueError):
            self.capture()
        self.assertFalse(self.checkpoint.exists())

    def test_interrupted_fork_is_not_startable_or_capturable(self):
        self.capture()
        with patch.object(cp, 'copy_store', side_effect=OSError('simulated disk full')):
            with self.assertRaises(OSError):
                cp.fork(self.checkpoint, self.child, self.runtime, 3901)
        self.assertFalse(self.child.exists())
        (self.world / '.fork-incomplete').write_text('{}')
        with self.assertRaises(ValueError):
            cp.capture(self.world, self.root / 'incomplete-copy', self.runtime)
        from run import serve_locked
        with self.assertRaisesRegex(RuntimeError, 'Incomplete fork'):
            serve_locked(None, self.world)

    def test_parent_port_and_unsupported_version_refused(self):
        self.capture()
        with self.assertRaises(ValueError):
            cp.fork(self.checkpoint, self.child, self.runtime, 3000)
        self.assertFalse(self.child.exists())
        manifest_path = self.checkpoint / 'manifest.json'
        manifest = cp.read_json(manifest_path)
        manifest['version'] += 1
        manifest_path.write_bytes(cp.canonical(manifest))
        with self.assertRaises(ValueError):
            cp.fork(self.checkpoint, self.child, self.runtime, 3901)
        self.assertFalse(self.child.exists())
