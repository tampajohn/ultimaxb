import asyncio
import sys
import unittest
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from changes import ChangeFeed


class ChangeFeedTests(unittest.IsolatedAsyncioTestCase):
    async def test_worker_notifications_coalesce_and_exclude_writer(self):
        feed=ChangeFeed()
        first=feed.subscribe(1);second=feed.subscribe(4)
        with self.assertRaises(ValueError):feed.subscribe(4)
        def burst():
            for _ in range(100):feed.publish(1)
        await asyncio.to_thread(burst)
        await asyncio.wait_for(second.wait(),1)
        self.assertFalse(first.is_set())
        self.assertTrue(second.is_set())
        second.clear()
        await asyncio.sleep(0)
        self.assertFalse(second.is_set())
        feed.publish(4)
        await asyncio.wait_for(first.wait(),1)
        feed.unsubscribe(4)
        feed.publish(1)
        await asyncio.sleep(0)
        self.assertFalse(second.is_set())
