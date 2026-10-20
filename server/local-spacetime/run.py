"""Build and run the local protocol sandbox, or verify it in a temporary world.
Requires Python 3.10+, Cargo with wasm32-unknown-unknown, and SpacetimeDB standalone.
"""
from collections import deque
import argparse
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from urllib.request import urlopen
from backend import load_backend, FORGE
from navigation import Navigation

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def free_port():
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0))
        return sock.getsockname()[1]


def stop(process):
    if process and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def stage_smoke_near_forge(config, assets):
    """Move only the disposable verifier avatar through authoritative walk steps.
    Earlier tests finish at arbitrary nearby cells; SmeltWorkflow needs forge reach.
    """
    backend=load_backend(config)
    navigation=Navigation(assets)
    backend.navigation=navigation
    try:
        avatar=backend.avatar(); objects=backend.world()[1]
        forge=next(o for o in objects if o['serial']==FORGE)
        first=tuple(avatar[k] for k in ('x','y','z'))
        queue,parents=deque([first]),{first:None}
        goal=None
        for _ in range(256):
            if not queue: break
            point=queue.popleft()
            if abs(point[0]-forge['x'])+abs(point[1]-forge['y'])==1 and abs(point[2]-forge['z'])<=16:
                goal=point;break
            for direction in range(8):
                target=navigation.query('step',dict(zip(('x','y','z'),point)),direction,objects=objects)
                if target is None:continue
                key=tuple(target[k] for k in ('x','y','z'))
                if key not in parents and max(abs(key[0]-first[0]),abs(key[1]-first[1]))<=10:
                    parents[key]=point,direction;queue.append(key)
        if goal is None: raise RuntimeError('Cannot approach the verification forge')
        path=[]
        while parents[goal] is not None:
            goal,direction=parents[goal];path.append(direction)
        for direction in reversed(path):
            if avatar['direction']&7!=direction:avatar=backend.walk(avatar['revision'],direction)
            avatar=backend.walk(avatar['revision'],direction)
        backend.check_reach(forge,avatar,objects)
    finally:navigation.close()


def serve(args, data):
    data.mkdir(parents=True, exist_ok=True)
    private, public = data / 'jwt-private-pkcs8.pem', data / 'jwt-public.pem'
    if not private.exists() and not public.exists():
        subprocess.run(['openssl', 'genpkey', '-algorithm', 'EC', '-pkeyopt',
                        'ec_paramgen_curve:P-256', '-out', str(private)], check=True)
        private.chmod(0o600)
        subprocess.run(['openssl', 'pkey', '-in', str(private), '-pubout', '-out', str(public)], check=True)
    if not private.exists() or not public.exists():
        raise RuntimeError('Incomplete key pair; restore the missing key rather than replacing world identity')
    db_port, game_port = (free_port(), free_port()) if args.verify else (args.db_port, args.port)
    while args.verify and db_port == game_port:
        game_port = free_port()
    config = data / 'gateway.json'
    db_command = [args.standalone, 'start', '--listen-addr', f'127.0.0.1:{db_port}',
                  '--data-dir', str(data), '--jwt-pub-key-path', str(public),
                  '--jwt-priv-key-path', str(private), '--non-interactive']
    db = gateway = None
    with (data / 'server.log').open('a') as log:
        def start_db():
            process = subprocess.Popen(db_command, stdout=log, stderr=log, cwd=ROOT)
            try:
                for _ in range(100):
                    if process.poll() is not None:
                        raise RuntimeError(f'SpacetimeDB exited; see {data / "server.log"}')
                    try:
                        with urlopen(f'http://127.0.0.1:{db_port}/v1/identity/public-key', timeout=0.3):
                            # Ensure the process hasn't failed because another service owns this port.
                            time.sleep(0.1)
                            if process.poll() is not None:
                                raise RuntimeError('SpacetimeDB failed to start')
                            return process
                    except OSError:
                        time.sleep(0.1)
                raise RuntimeError('SpacetimeDB startup timed out')
            except BaseException:
                stop(process)
                raise
        try:
            db = start_db()
            if config.exists() and load_backend(config).endpoint != f'http://127.0.0.1:{db_port}':
                raise RuntimeError('Saved endpoint differs; use the original --db-port')
            subprocess.run([sys.executable, str(HERE / 'provision.py'), '--config', str(config),
                            '--port', str(db_port)], cwd=ROOT, check=True)
            if args.verify:
                env = dict(os.environ, ULTIMA_SPACETIME_CONFIG=str(config), ULTIMA_CLIENT_ASSETS=args.client)
                env['PYTHONPATH']=str(HERE/'tests')+os.pathsep+env.get('PYTHONPATH','')
                hunting_test='test_live.LiveTests.test_b_hunting_weapons_disconnect_death_and_loot'
                subprocess.run([sys.executable,'-m','unittest','-v',hunting_test],env=env,cwd=ROOT,check=True,timeout=60)
                dead=load_backend(config).hunting_state()
                dead_inventory=load_backend(config).inventory()
                if load_backend(config).creature()['health']!=0:
                    raise RuntimeError('Hunting fixture must leave a dead creature')
                stop(db);db=start_db()
                if load_backend(config).hunting_state()!=dead or load_backend(config).inventory()!=dead_inventory:
                    raise RuntimeError('Restart changed death, respawn deadline, cooldown, or loot')
                print('PASS: death, cooldown, respawn deadline, and loot survive restart before respawn',flush=True)
                # Resume the remaining suite without repeating the first kill.
                remaining_tests = """import sys,unittest
suite=unittest.defaultTestLoader.discover(sys.argv[1])
def flatten(suite):
    for test in suite:
        if isinstance(test,unittest.TestSuite):yield from flatten(test)
        else:yield test
selected=unittest.TestSuite(t for t in flatten(suite) if t.id()!=sys.argv[2])
result=unittest.TextTestRunner(verbosity=2).run(selected)
sys.exit(not result.wasSuccessful())
"""
                subprocess.run([sys.executable,'-c',remaining_tests,str(HERE/'tests'),hunting_test],
                               env=env,cwd=ROOT,check=True,timeout=180)
                stage_smoke_near_forge(config,args.client)
                before = load_backend(config).avatar()
                world_before = load_backend(config).world()
                inventory_before = load_backend(config).inventory()
                equipment_before = load_backend(config).equipment()
                nutrition_before = load_backend(config).nutrition()
                gathering_before = load_backend(config).gathering_state()
                merchant_before = load_backend(config).merchant_state()
                skills_before = load_backend(config).skill_state()
                hunting_before = load_backend(config).hunting_state()
                cooking_before = load_backend(config).cooking_state()
                stop(db)
                db = start_db()
                if load_backend(config).cooking_state()!=cooking_before:
                    raise RuntimeError('Database restart changed cooking history')
                if load_backend(config).hunting_state()!=hunting_before:
                    raise RuntimeError('Database restart changed creature or hunting history')
                if load_backend(config).skill_state() != skills_before:
                    raise RuntimeError('Database restart changed skills or gain history')
                if load_backend(config).merchant_state() != merchant_before:
                    raise RuntimeError('Database restart changed merchant or purchases')
                after = load_backend(config).avatar()
                if before != after:
                    raise RuntimeError('Database restart changed persisted avatar')
                if load_backend(config).world() != world_before:
                    raise RuntimeError('Database restart changed persisted world objects')
                if load_backend(config).inventory() != inventory_before:
                    raise RuntimeError('Database restart changed persisted inventory')
                if load_backend(config).equipment() != equipment_before:
                    raise RuntimeError('Database restart changed persisted equipment')
                if load_backend(config).nutrition() != nutrition_before:
                    raise RuntimeError('Database restart changed persisted nutrition')
                if load_backend(config).gathering_state() != gathering_before:
                    raise RuntimeError('Database restart changed resource banks, cooldowns, or action journals')
                print('PASS: avatar, world objects, inventory, and revisions survive standalone database restart', flush=True)
            gateway = subprocess.Popen([sys.executable, str(HERE / 'gateway.py'), '--config', str(config),
                                        '--port', str(game_port), '--client', args.client], cwd=ROOT)
            if args.verify:
                for _ in range(100):
                    if gateway.poll() is not None:
                        raise RuntimeError('Gateway failed to start')
                    try:
                        with socket.create_connection(('127.0.0.1', game_port), timeout=0.1):
                            break
                    except OSError:
                        time.sleep(0.05)
                import protocol as wire
                vendor=load_backend(config).merchant()
                fixture=data/'merchant-packets.bin'
                fixture.write_bytes(wire.merchant_mobile(vendor)+wire.merchant_offers(vendor)+wire.merchant_sell_offers(
                    dict(item=dict(serial=0x40000900,graphic=0x1bdd,amount=4)))+
                    wire.creature_mobile(load_backend(config).creature())+b'\xaa\0\0\0\3'+
                    wire.creature_status(load_backend(config).creature())+wire.creature_death())
                subprocess.run([str(ROOT / 'build/spacetime-tools/client-smoke'), str(game_port), args.client,str(fixture)],
                               cwd=ROOT, check=True, timeout=30)
                items = load_backend(config).inventory()[1]
                if any(i['graphic']==0x1bdd for i in items) or sum(i['amount'] for i in items if i['graphic']==0x1b7a) != 2:
                    raise RuntimeError('Real-client craft failed ingredient/output conservation')
                if any(i['graphic']==0x19b8 for i in items) or sum(i['amount'] for i in items if i['graphic']==0x1bf2)!=5:
                    raise RuntimeError('Real-client smelting failed material conservation')
                print('PASS: ten ore became five remaining ingots and five consumed for one helmet',flush=True)
                if load_backend(config).merchant_state()['merchant_goods'] != [[0x1bdd,2]]:
                    raise RuntimeError('Merchant did not retain exactly the two sold logs')
                print('PASS: twelve harvested logs became two shields and two retained merchant logs',flush=True)
                if load_backend(config).skills() != {7:1,11:2,44:6,45:7}:
                    raise RuntimeError('Final skills do not match successful actions')
                print('PASS: persisted skill gains match successful gathering, smelting, and crafting actions',flush=True)
            else:
                while gateway.poll() is None and db.poll() is None:
                    time.sleep(0.25)
                raise RuntimeError('A local server process stopped unexpectedly')
        finally:
            stop(gateway)
            stop(db)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify', action='store_true', help='test a disposable world, including DB restart')
    parser.add_argument('--port', type=int, default=2594)
    parser.add_argument('--db-port', type=int, default=3000)
    parser.add_argument('--client', default=str(ROOT / 'uo1998-client'), help='UO assets for server collision')
    parser.add_argument('--standalone', default=str(ROOT / 'build/spacetime-tools/spacetimedb-standalone'))
    args = parser.parse_args()
    args.client = str(Path(args.client).resolve())
    if not Path(args.standalone).is_file():
        args.standalone = shutil.which('spacetimedb-standalone') or args.standalone
    if not Path(args.standalone).is_file():
        parser.error('SpacetimeDB standalone is missing; see README.md beside this script')
    subprocess.run(['cargo', 'build', '--manifest-path', str(HERE / 'module/Cargo.toml'),
                    '--locked', '--target', 'wasm32-unknown-unknown', '--release',
                    '--target-dir', str(ROOT / 'build/spacetime-module')], cwd=ROOT, check=True)
    if args.verify:
        subprocess.run(['cargo', 'test', '--manifest-path', str(HERE / 'module/Cargo.toml'),
                        '--locked', '--target-dir', str(ROOT / 'build/spacetime-module')], cwd=ROOT, check=True)
    tools = ROOT / 'build/spacetime-tools'
    tools.mkdir(parents=True, exist_ok=True)
    # Another session may be editing UOCore. Compile a temporary snapshot so
    # files cannot change underneath swiftc during its compilation passes.
    with tempfile.TemporaryDirectory(prefix='spacetime-client-', dir=ROOT / 'build') as snapshot:
        sources = Path(snapshot)
        for source in (ROOT / 'Sources/UOCore').glob('*.swift'):
            shutil.copy2(source, sources / source.name)
        executables = [(HERE / 'NavigationService.swift', 'navigation')]
        if args.verify:
            executables += [(HERE / 'tests/ClientSmoke.swift', 'client-smoke'),
                            (HERE / 'tests/NavigationChecks.swift', 'navigation-checks')]
        for main_source, executable in executables:
            subprocess.run(['swiftc', '-module-cache-path', str(tools / 'module-cache'),
                            '-whole-module-optimization', '-Onone', '-parse-as-library',
                            *map(str, sorted(sources.glob('*.swift'))),
                            str(main_source), '-o', str(tools / executable)], check=True)
    if args.verify:
        subprocess.run([str(tools / 'navigation-checks'), args.client], check=True)
        with tempfile.TemporaryDirectory(prefix='spacetime-verify-', dir=ROOT / 'build') as temporary:
            serve(args, Path(temporary))
    else:
        serve(args, ROOT / 'build/spacetime-data')


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        pass
