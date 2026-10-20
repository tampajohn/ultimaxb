"""Serialized, bounded calls to the server-owned Swift asset/collision helper."""
import json
from pathlib import Path
import select
import subprocess
import threading

ROOT = Path(__file__).resolve().parents[2]


class NavigationError(RuntimeError):
    pass


class Navigation:
    def __init__(self, assets=None, executable=None):
        self.lock = threading.Lock()
        self.process = subprocess.Popen([
            str(executable or ROOT / 'build/spacetime-tools/navigation'),
            str(assets or ROOT / 'uo1998-client')], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, bufsize=0)
        try:
            response = self._read()
            if response.get('x') != 6144 or response.get('y') != 4096:
                raise NavigationError('Unexpected navigation map dimensions')
        except BaseException:
            self.close()
            raise

    def _read(self):
        # Read a single bounded line without buffering past the select boundary.
        result = bytearray()
        while len(result) < 1024:
            if not select.select([self.process.stdout], [], [], 5)[0]:
                raise NavigationError('Navigation helper timed out')
            byte = self.process.stdout.read(1)
            if not byte:
                raise NavigationError('Navigation helper stopped')
            if byte == b'\n':
                try:
                    return json.loads(result)
                except ValueError:
                    raise NavigationError('Invalid navigation response') from None
            result.extend(byte)
        raise NavigationError('Oversized navigation response')

    def query(self, op, avatar, direction=None, objects=None, graphic=None, details=False):
        with self.lock:
            if self.process.poll() is not None:
                raise NavigationError('Navigation helper stopped')
            request = {key: avatar[key] for key in ('x', 'y', 'z')}
            request.update(op=op, direction=direction, graphic=graphic)
            if objects is not None:
                request['objects'] = [{k: item[k] for k in ('serial', 'graphic', 'x', 'y', 'z')} for item in objects]
            try:
                self.process.stdin.write(json.dumps(request).encode() + b'\n')
                response = self._read()
                if response.get('error'):
                    raise NavigationError(response['error'])
                if response.get('blocked'):
                    return None
                if not all(isinstance(response.get(key), int) for key in ('x', 'y', 'z')):
                    raise NavigationError('Invalid navigation point')
                return response if details else {key: response[key] for key in ('x', 'y', 'z')}
            except (OSError, NavigationError) as error:
                # A broken/timed-out stream cannot safely be reused for another step.
                self.close()
                raise NavigationError('Navigation unavailable; movement stopped') from error

    def close(self):
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait()
        self.process.stdin.close()
        self.process.stdout.close()
