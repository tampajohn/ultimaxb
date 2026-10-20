"""Real standalone checkpoint acceptance, after the populated shared scenario."""
import json
from pathlib import Path
import re
import signal
import socket
import subprocess
import sys
import tempfile
import time
from urllib.request import urlopen

from accounts import ensure_local_accounts
from backend import load_backend
from checkpoint import capture, fork, verify
from run import free_port, stop


def snapshot(data):
    backend = load_backend(Path(data) / 'gateway.json')
    module = Path(__file__).resolve().parents[1] / 'module/src'
    tables = sorted({name for source in module.glob('*.rs')
                     for name in re.findall(r'#\[spacetimedb::table\(accessor\s*=\s*(\w+)', source.read_text())})
    if len(tables) < 32:
        raise AssertionError('Incomplete table discovery')
    return {table: sorted(json.loads(backend.request(backend.path + '/sql',
             ('SELECT * FROM ' + table).encode(), content_type='text/plain'))[0]['rows'], key=repr)
            for table in tables}


def check(data, runtime, expected, assets=None):
    """No live/default paths: data is the caller's disposable populated store."""
    data = Path(data)
    assets = assets or str(Path(__file__).resolve().parents[3] / 'uo1998-client')
    with tempfile.TemporaryDirectory(prefix='spacetime-forks-', dir=data.parent) as temporary:
        root = Path(temporary)
        checkpoint, child = root / 'checkpoint', root / 'child'
        manifest = capture(data, checkpoint, runtime)
        assert verify(checkpoint, runtime) == manifest
        child_port = free_port()
        parent_config = json.loads((data / 'gateway.json').read_text())
        parent_port = int(parent_config['endpoint'].rsplit(':', 1)[1])
        while child_port == parent_port:
            child_port = free_port()
        branch = fork(checkpoint, child, runtime, child_port)
        assert branch['id'] != manifest['branch']['id']
        assert branch['parent']['checkpoint'] == manifest['id']
        processes = []
        with (root / 'acceptance.log').open('w') as log:
            def start(directory, port):
                command = [runtime, 'start', '--listen-addr', f'127.0.0.1:{port}',
                           '--data-dir', str(directory),
                           '--jwt-pub-key-path', str(directory / 'jwt-public.pem'),
                           '--jwt-priv-key-path', str(directory / 'jwt-private-pkcs8.pem'),
                           '--non-interactive']
                process = subprocess.Popen(command, stdout=log, stderr=log)
                processes.append(process)
                for _ in range(100):
                    if process.poll() is not None:
                        raise RuntimeError('Checkpoint acceptance database failed to start')
                    try:
                        with urlopen(f'http://127.0.0.1:{port}/v1/identity/public-key', timeout=.3):
                            time.sleep(.1)
                            if process.poll() is not None:
                                raise RuntimeError('Checkpoint acceptance database failed')
                            return process
                    except OSError:
                        time.sleep(.1)
                raise RuntimeError('Checkpoint acceptance database timed out')
            try:
                parent_db = start(data, parent_port)
                child_db = start(child, child_port)
                assert snapshot(data) == expected, 'Parent changed at checkpoint boundary'
                assert snapshot(child) == expected, 'Child lost or changed persisted rows'
                print(f'PASS: checkpoint restores every row in {len(expected)} populated game tables', flush=True)
                # The live native lock must reject capture even without our runner.
                from world_lock import WorldBusy
                try:
                    capture(child, root / 'must-not-exist', runtime)
                except WorldBusy:
                    pass
                else:
                    raise AssertionError('Captured a running standalone')
                assert not (root / 'must-not-exist').exists()
                parent = load_backend(data / 'gateway.json')
                children = ensure_local_accounts(load_backend(child / 'gateway.json'), child / 'gateway.json')
                second = children['local2']
                def eat(backend):
                    apple = next(i for i in backend.inventory()[1]
                                 if i['container'] == backend.backpack and i['graphic'] == 0x9d0)
                    quantity = apple['amount']
                    backend.eat(backend.lift(apple['serial'], 1))
                    remaining = next((i['amount'] for i in backend.inventory()[1]
                                      if i['serial'] == apple['serial']), 0)
                    assert remaining == quantity - 1, 'Eating did not consume exactly one apple'
                child_before = snapshot(child)
                eat(second)
                child_after = snapshot(child)
                assert child_after != child_before
                assert snapshot(data) == expected, 'Child action changed parent'
                eat(parent)
                parent_after = snapshot(data)
                assert parent_after != expected
                assert snapshot(child) == child_after, 'Parent action changed child'
                stop(child_db)
                child_db = start(child, child_port)
                assert snapshot(child) == child_after, 'Fork state did not survive restart'
                stop(parent_db)
                parent_db = start(data, parent_port)
                assert snapshot(data) == parent_after, 'Parent state did not survive restart'
                assert snapshot(child) == child_after
                print('PASS: independent parent/player-1 and child/player-2 consumption; both persist after restart', flush=True)
                stop(child_db)
                # Exercise the production runner's fork path without rebuilding
                # tools already built by run.py for this acceptance run.
                game_port = free_port()
                while game_port in (parent_port, child_port):
                    game_port = free_port()
                entry = """import sys
from pathlib import Path
from types import SimpleNamespace
from run import serve
args=SimpleNamespace(standalone=sys.argv[2],db_port=int(sys.argv[3]),port=int(sys.argv[4]),
                     client=sys.argv[5],verify=False,verify_shared=False,verify_checkpoint=False)
try:serve(args,Path(sys.argv[1]))
except KeyboardInterrupt:pass
"""
                runner = subprocess.Popen(
                    [sys.executable, '-c', entry, str(child), runtime, str(child_port),
                     str(game_port), assets], cwd=Path(__file__).resolve().parents[1],
                    stdout=log, stderr=log)
                try:
                    for _ in range(200):
                        if runner.poll() is not None:
                            raise RuntimeError('Fork runner failed')
                        try:
                            with socket.create_connection(('127.0.0.1', game_port), timeout=.1):
                                break
                        except OSError:
                            time.sleep(.1)
                    else:
                        raise RuntimeError('Fork gateway timed out')
                    assert snapshot(child) == child_after, 'Fork startup changed saved gameplay'
                    assert snapshot(data) == parent_after, 'Fork runner touched parent'
                    print('PASS: production runner serves the fork without republishing or changing saved gameplay', flush=True)
                finally:
                    if runner.poll() is None:
                        runner.send_signal(signal.SIGINT)
                        try:
                            runner.wait(timeout=15)
                        except subprocess.TimeoutExpired:
                            stop(runner)
                child_checkpoint = root / 'child-checkpoint'
                second_manifest = capture(child, child_checkpoint, runtime)
                assert second_manifest['branch'] == branch
                grandchild = root / 'grandchild'
                grandbranch = fork(child_checkpoint, grandchild, runtime, free_port())
                assert grandbranch['parent']['branch'] == branch['id']
                assert grandbranch['parent']['checkpoint'] == second_manifest['id']
                print('PASS: descendant checkpoint retains ancestry and supports another independent fork', flush=True)
            finally:
                for process in reversed(processes):
                    stop(process)
