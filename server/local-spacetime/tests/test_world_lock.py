import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from world_lock import file_lock, offline_lock, runner_lock, WorldBusy


class WorldLockTests(unittest.TestCase):
    def test_runner_excludes_offline_copy_between_database_restarts(self):
        with tempfile.TemporaryDirectory() as temp:
            with runner_lock(temp):
                with self.assertRaises(WorldBusy):
                    with offline_lock(temp):
                        self.fail('Acquired running world')
            with offline_lock(temp):
                with self.assertRaises(WorldBusy):
                    with runner_lock(temp):
                        self.fail('Started while copying')

    def test_native_process_lock_excludes_copy_and_releases_on_exit(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'spacetime.pid'
            code = """import fcntl,sys
with open(sys.argv[1],'w') as f:
    fcntl.flock(f,fcntl.LOCK_EX)
    print('locked',flush=True)
    sys.stdin.read()
"""
            process = subprocess.Popen([sys.executable, '-c', code, str(path)],
                                       stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
            try:
                self.assertEqual(process.stdout.readline().strip(), 'locked')
                with self.assertRaises(WorldBusy):
                    with offline_lock(temp):
                        self.fail('Copied a native locked store')
            finally:
                process.communicate('', timeout=5)
            with offline_lock(temp):
                pass

    def test_linked_lock_is_rejected_without_modifying_target(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'target'
            path.write_text('preserve')
            link = Path(temp) / 'lock'
            link.symlink_to(path)
            with self.assertRaises(OSError):
                with file_lock(link):
                    pass
            link.unlink()
            os.link(path, link)
            with self.assertRaises(ValueError):
                with file_lock(link):
                    pass
            self.assertEqual(path.read_text(), 'preserve')
