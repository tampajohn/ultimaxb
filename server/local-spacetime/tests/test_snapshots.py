import sys
import unittest
from pathlib import Path
from unittest.mock import Mock

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from backend import Backend,BackendError


class SnapshotTests(unittest.TestCase):
    def test_transfer_between_reads_reloads_snapshot(self):
        backend=Backend('http://127.0.0.1:3000','test','unused')
        backend._revision=Mock(side_effect=[8,9,9,9])
        # A ground row was read before pickup, its elevation after pickup.
        read=Mock(side_effect=[BackendError('Ground item lacks elevation'),(9,[])])
        self.assertEqual(backend.stable_snapshot('inventory_state',read),(9,[]))
        self.assertEqual(read.call_count,2)

    def test_stable_corruption_is_not_hidden(self):
        backend=Backend('http://127.0.0.1:3000','test','unused')
        backend._revision=Mock(return_value=8)
        read=Mock(side_effect=BackendError('Ground item lacks elevation'))
        with self.assertRaisesRegex(BackendError,'Ground item lacks elevation'):
            backend.stable_snapshot('inventory_state',read)
        self.assertEqual(read.call_count,1)

    def test_continuously_changing_snapshot_is_bounded(self):
        backend=Backend('http://127.0.0.1:3000','test','unused')
        backend._revision=Mock(side_effect=range(10))
        read=Mock(return_value=(0,[]))
        with self.assertRaisesRegex(BackendError,'changed repeatedly'):
            backend.stable_snapshot('inventory_state',read)
        self.assertEqual(read.call_count,5)
