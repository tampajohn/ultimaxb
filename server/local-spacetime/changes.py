"""Bounded commit notifications for sessions owned by one local gateway."""
import asyncio
import threading


class ChangeFeed:
    def __init__(self):
        self.loop=asyncio.get_running_loop()
        self.sessions={}
        self.lock=threading.Lock()
        self.pending=set()
        self.scheduled=False

    def subscribe(self,player):
        if player in self.sessions:
            raise ValueError('Player already subscribed')
        event=asyncio.Event()
        self.sessions[player]=event
        return event

    def unsubscribe(self,player):
        self.sessions.pop(player,None)

    def publish(self,player):
        """May be called by an HTTP worker thread after a write or uncertain reply."""
        with self.lock:
            self.pending.add(player)
            if self.scheduled:return
            self.scheduled=True
        try:self.loop.call_soon_threadsafe(self._deliver)
        except RuntimeError:
            with self.lock:
                self.pending.clear()
                self.scheduled=False

    def _deliver(self):
        with self.lock:
            players=self.pending
            self.pending=set()
            self.scheduled=False
        # The writer sends its own immediate protocol response. Other sessions
        # coalesce arbitrary commit bursts into one authoritative refresh.
        for recipient,event in self.sessions.items():
            if players-{recipient}:
                event.set()
