"""Real fork histories for read-only preview acceptance; no live-world paths."""
from contextlib import contextmanager
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from unittest.mock import patch
from urllib.request import urlopen

from accounts import ensure_local_accounts
from backend import load_backend, BARREL
import checkpoint as cp
import merge_preview as merge
from navigation import Navigation
from run import free_port, stop


@contextmanager
def database(data, runtime, assets):
    config = data / 'gateway.json'
    port = int(cp.read_json(config)['endpoint'].rsplit(':', 1)[1])
    command = [runtime, 'start', '--listen-addr', f'127.0.0.1:{port}',
               '--data-dir', str(data), '--jwt-pub-key-path', str(data / 'jwt-public.pem'),
               '--jwt-priv-key-path', str(data / 'jwt-private-pkcs8.pem'), '--non-interactive']
    navigation = None
    with (data / 'server.log').open('a') as log:
        process = subprocess.Popen(command, stdout=log, stderr=log)
        try:
            for _ in range(100):
                if process.poll() is not None:
                    raise RuntimeError('Merge fixture database failed to start')
                try:
                    with urlopen(f'http://127.0.0.1:{port}/v1/identity/public-key', timeout=.3):
                        break
                except OSError:
                    time.sleep(.1)
            else:
                raise RuntimeError('Merge fixture database timed out')
            navigation = Navigation(assets)
            backend = load_backend(config)
            backend.navigation = navigation
            accounts = ensure_local_accounts(backend, config)
            yield backend, accounts['local2'], navigation
        finally:
            if navigation:
                navigation.close()
            stop(process)


def check(data, runtime, assets):
    with tempfile.TemporaryDirectory(prefix='spacetime-merge-', dir=data.parent) as temporary:
        root = Path(temporary)
        base_path, left_path, right_path = [root / name for name in ('base', 'left', 'right')]
        base = cp.capture(data, base_path, runtime)
        parent_port = int(cp.read_json(data / 'gateway.json')['endpoint'].rsplit(':', 1)[1])
        def port():
            result = free_port()
            while result == parent_port:
                result = free_port()
            return result
        left_world, right_world = root / 'left-world', root / 'right-world'
        cp.fork(base_path, left_world, runtime, port())
        cp.fork(base_path, right_world, runtime, port())
        def relocate(backend, point):
            current, scene = backend.avatar(), backend.world()[0]
            while any(current[k] != point[k] for k in ('x', 'y', 'z')):
                x = current['x'] + max(-8, min(8, point['x'] - current['x']))
                y = current['y'] + max(-8, min(8, point['y'] - current['y']))
                backend.request(backend.path + '/call/settle', json.dumps(
                    [current['revision'], x, y, point['z'], scene]).encode())
                current = backend.avatar()
        def item(backend, graphic):
            return next(i for i in backend.inventory()[1]
                        if i['graphic'] == graphic and i['container'] in (backend.player, backend.backpack))
        def beside(backend, navigation, target):
            objects = backend.world()[1]
            return next(p for dx, dy in ((0, 1), (1, 0), (0, -1), (-1, 0))
                        if (p := navigation.query('stand', dict(x=target['x']+dx,
                            y=target['y']+dy, z=target['z']), objects=objects)))
        for side, world, destination in (('left', left_world, left_path), ('right', right_world, right_path)):
            with database(world, runtime, assets) as (backend, second, navigation):
                origin = backend.avatar()
                tree = navigation.query('tree_site', origin, details=True)
                mine = navigation.query('ore_site', dict(x=1250, y=1249, z=0), details=True)
                assert tree and mine, 'Resource sites required for fixture'
                # The first new serial is logs on the left and ore on the right.
                site, graphic = (tree, 0xf43) if side == 'left' else (mine, 0xe86)
                relocate(backend, site)
                tool = item(backend, graphic)
                backend.equip(backend.lift(tool['serial'], 1), tool['serial'],
                              2 if graphic == 0xf43 else 1, backend.player)
                backend.perform_tool(backend.begin_tool(tool['serial']), dict(site['target'], serial=0))
                if side == 'right':
                    time.sleep(2.05)
                    relocate(backend, tree)
                    tool = item(backend, 0xf43)
                    backend.equip(backend.lift(tool['serial'], 1), tool['serial'], 2, backend.player)
                    backend.perform_tool(backend.begin_tool(tool['serial']), dict(tree['target'], serial=0))
                apple = item(backend, 0x9d0)
                backend.eat(backend.lift(apple['serial'], 1))
                if side == 'left':
                    apple = item(second, 0x9d0)
                    second.eat(second.lift(apple['serial'], 1))
                else:
                    # A turn changes only player 2's own movement history.
                    avatar = second.avatar()
                    second.walk(avatar['revision'], (avatar['direction'] + 2) & 7)
                barrel = next(o for o in backend.world()[1] if o['serial'] == BARREL)
                relocate(backend, beside(backend, navigation, barrel))
                gold = next(i for i in backend.inventory()[1] if i['container'] == BARREL and i['graphic'] == 0xeed)
                backend.transfer(backend.lift(gold['serial'], 25), gold['serial'], backend.backpack, 65, 85)
                vendor = backend.merchant()
                relocate(backend, beside(backend, navigation, vendor))
                backend.buy_apples(backend.merchant_quote(), 1)
                sword = item(backend, 0xf61)
                backend.equip(backend.lift(sword['serial'], 1), sword['serial'], 1, backend.player)
                creature = backend.creature()
                relocate(backend, beside(backend, navigation, creature))
                while backend.creature()['health']:
                    if backend.strike_creature() is None:
                        time.sleep(.1)
                if side == 'right':
                    avatar = backend.avatar()
                    backend.transfer(backend.lift(sword['serial'], 1), sword['serial'], 0xffffffff,
                                     avatar['x'], avatar['y'], avatar['z'])
            cp.capture(world, destination, runtime)
        fingerprints = {path: cp.checked_tree(path) for path in (base_path, left_path, right_path)}
        report = merge.preview(base_path, left_path, right_path, runtime)
        kinds = {c['kind'] for c in report['conflicts']}
        assert {'shared_ancestral_consumption', 'repeated_creature_reward',
                'item_ownership_or_quantity', 'resource_outcome', 'merchant_outcome'} <= kinds
        assert report['serial_collisions']
        created = [c for c in report['changes'] if c['kind'] == 'branch_created_item']
        collision = report['serial_collisions'][0]['serial']
        collided = [c for c in created if c['entity']['key'] == collision]
        assert len(collided) == 2 and collided[0]['value']['graphic'] != collided[1]['value']['graphic']
        assert any(c['kind'] == 'one_sided_change' and c['entity']['table'] == 'nutrition'
                   for c in report['changes'])
        assert not report['can_apply'] and report['conservation'] == 'not_proven'
        first_bytes = cp.canonical(report)
        assert first_bytes == cp.canonical(merge.preview(base_path, left_path, right_path, runtime))
        config = cp.read_json(base_path / 'store/gateway.json')
        secrets = [config['token'], config['players']['local2']['token'],
                   config['players']['local2']['identity']]
        for secret in secrets:
            assert secret.encode() not in first_bytes
        assert b'-----BEGIN' not in first_bytes
        ancestor_state = merge.logical_snapshot(base_path, runtime, base)
        owner = ancestor_state['tables']['gateway'][0]['owner']
        assert cp.canonical(owner) not in first_bytes
        report_path = root / 'preview.json'
        command = [sys.executable, str(Path(merge.__file__)), '--runtime', runtime,
                   '--ancestor', str(base_path), '--left', str(left_path),
                   '--right', str(right_path), '--output', str(report_path)]
        subprocess.run(command, check=True, capture_output=True, timeout=30)
        assert report_path.read_bytes() == first_bytes
        duplicate = subprocess.run(command, capture_output=True, timeout=30)
        assert duplicate.returncode != 0 and report_path.read_bytes() == first_bytes
        assert all(cp.checked_tree(path) == expected for path, expected in fingerprints.items())
        print('PASS: real three-way conflicts, independent changes, distinct colliding item IDs, deterministic private-field-free output, and immutable sources', flush=True)
        # Pinning the adapter rejects an unsupported table set before reading rows.
        wrong_schema = dict(merge.SCHEMA)
        wrong_schema.pop('avatar')
        with patch.object(merge, 'SCHEMA', wrong_schema):
            try:
                merge.preview(base_path, left_path, right_path, runtime)
            except ValueError as error:
                assert 'table set' in str(error)
            else:
                raise AssertionError('Unsupported schema accepted')
        # A structurally valid checkpoint without the needed lineage is rejected.
        unrelated = cp.read_json(right_path / 'manifest.json')
        unrelated['branch']['parent'] = None
        try:
            merge.lineage(base, cp.read_json(left_path / 'manifest.json'), unrelated)
        except ValueError:
            pass
        else:
            raise AssertionError('Unrelated branch accepted')
        assert all(cp.checked_tree(path) == expected for path, expected in fingerprints.items())
        print('PASS: incompatible schema and unrelated lineage rejected without changing checkpoints', flush=True)
