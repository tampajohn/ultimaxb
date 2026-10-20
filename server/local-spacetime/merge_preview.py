"""Read-only comparison of trusted local checkpoints; never applies a merge."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import time
from urllib.request import urlopen

from backend import load_backend
import checkpoint as cp
from run import free_port, stop

HERE = Path(__file__).resolve().parent
SCHEMA = json.loads((HERE / 'merge_schema.json').read_text())
SCHEMA_DIGEST = hashlib.sha256(cp.canonical(SCHEMA)).hexdigest()
JOURNALS = {name for name in SCHEMA if name.endswith('_event')} | {
    'item_action', 'inventory_actor', 'hunting_actor', 'player_movement',
    'movement_height'}
PRIVATE = {'gateway', 'player_account'}
TRANSIENT = {'player_presence'}
COUNTERS = {'inventory_state', 'scene', 'starter_kit'}
ITEM_TABLES = {'inventory_item', 'equipment_slot', 'ground_location'}


def manifest_digest(manifest):
    return hashlib.sha256(cp.canonical(manifest)).hexdigest()


def lineage(base, left, right, intermediates=()):
    """Require complete hash-linked paths to the explicit ancestor."""
    manifests = [base, left, right, *intermediates]
    by_id = {}
    for manifest in manifests:
        key = manifest['id']
        if key in by_id and by_id[key] != manifest:
            raise ValueError('Conflicting checkpoint identity')
        by_id[key] = manifest
        if manifest['runtime_sha256'] != base['runtime_sha256']:
            raise ValueError('Checkpoint runtimes differ')
    branch_ids = [m['branch']['id'] for m in (base, left, right)]
    if len(set(branch_ids)) != 3:
        raise ValueError('Preview needs an ancestor and two distinct descendant branches')
    for descendant in (left, right):
        seen = set()
        current = descendant
        while current['id'] != base['id']:
            if current['id'] in seen:
                raise ValueError('Cyclic checkpoint ancestry')
            seen.add(current['id'])
            parent = current['branch']['parent']
            if parent is None or parent['checkpoint'] not in by_id:
                raise ValueError('Missing or unrelated ancestor checkpoint')
            prior = by_id[parent['checkpoint']]
            if (parent['branch'] != prior['branch']['id'] or
                    parent['manifest_sha256'] != manifest_digest(prior)):
                raise ValueError('Checkpoint ancestry digest or branch does not match')
            current = prior


def logical_snapshot(checkpoint, runtime, manifest):
    """Only temporary stores are opened by standalone; source bytes stay offline."""
    with tempfile.TemporaryDirectory(prefix='ultima-preview-') as temporary:
        root = Path(temporary)
        data = root / 'world'
        source_port = int(cp.read_json(Path(checkpoint) / 'store/gateway.json')['endpoint'].rsplit(':', 1)[1])
        port = free_port()
        while port == source_port:
            port = free_port()
        cp.fork(checkpoint, data, runtime, port)
        command = [str(runtime), 'start', '--listen-addr', f'127.0.0.1:{port}',
                   '--data-dir', str(data), '--jwt-pub-key-path', str(data / 'jwt-public.pem'),
                   '--jwt-priv-key-path', str(data / 'jwt-private-pkcs8.pem'), '--non-interactive']
        process = None
        try:
            with (root / 'database.log').open('w') as log:
                process = subprocess.Popen(command, stdout=log, stderr=log)
                for _ in range(100):
                    if process.poll() is not None:
                        raise RuntimeError('Temporary preview database failed to start')
                    try:
                        with urlopen(f'http://127.0.0.1:{port}/v1/identity/public-key', timeout=.3):
                            time.sleep(.1)
                            if process.poll() is not None:
                                raise RuntimeError('Temporary preview database exited')
                            break
                    except OSError:
                        time.sleep(.1)
                else:
                    raise RuntimeError('Temporary preview database timed out')
                backend = load_backend(data / 'gateway.json')
                def query(sql):
                    result = json.loads(backend.request(backend.path + '/sql', sql.encode(),
                                                       content_type='text/plain'))
                    if len(result) != 1:
                        raise ValueError('Unexpected SQL result shape')
                    return result[0]
                tables = {r[0] for r in query('SELECT table_name FROM st_table')['rows']
                          if not r[0].startswith('st_')}
                if tables != set(SCHEMA):
                    raise ValueError('Unsupported application table set')
                state = {}
                for table, expected_schema in SCHEMA.items():
                    result = query('SELECT * FROM ' + table)
                    if result['schema'] != expected_schema:
                        raise ValueError('Unsupported logical schema: ' + table)
                    names = [e['name']['some'] for e in expected_schema['elements']]
                    rows = {}
                    for row in result['rows']:
                        if len(row) != len(names):
                            raise ValueError('Unexpected row width')
                        key = row[0]
                        if key in rows:
                            raise ValueError('Duplicate primary key')
                        rows[key] = dict(zip(names, row))
                    state[table] = rows
                module = query('SELECT program_hash FROM st_module')['rows']
                if len(module) != 1:
                    raise ValueError('Expected one published module')
                return {'tables': state, 'module': module[0][0]}
        finally:
            stop(process)
            # Verify source integrity on failure as well as success.
            if cp.verify(checkpoint, runtime) != manifest:
                raise ValueError('Source checkpoint changed during preview')


def validate_history(base, state):
    """Immutable inherited history and bindings make base-qualified IDs meaningful."""
    for name in JOURNALS:
        if any(state[name].get(key) != row for key, row in base[name].items()):
            raise ValueError('Inherited history was rewritten: ' + name)
    for name in PRIVATE | {'starter_kit'}:
        if base[name] != state[name]:
            raise ValueError('Inherited ownership or setup metadata changed')
    old, new = base['inventory_state'][0], state['inventory_state'][0]
    if new['next_serial'] < old['next_serial'] or new['revision'] < old['revision']:
        raise ValueError('Inventory allocation or revision regressed')
    for serial in state['inventory_item'].keys() - base['inventory_item'].keys():
        if serial < old['next_serial'] or serial >= new['next_serial']:
            raise ValueError('New item reuses an ancestral serial or exceeds allocation')


def item_view(state):
    result = {}
    for serial, row in state['inventory_item'].items():
        result[serial] = dict(row, layer=state['equipment_slot'].get(serial, {}).get('layer'),
                              z=state['ground_location'].get(serial, {}).get('z'))
    if (set(state['equipment_slot']) | set(state['ground_location'])) - set(result):
        raise ValueError('Dangling equipment or ground reference')
    return result


def public_row(table, row):
    if row is None:
        return None
    # Account names currently coincide with demo passwords. Never emit them.
    if table in PRIVATE:
        raise ValueError('Private table cannot be included in a report')
    return {k: v for k, v in row.items() if k not in {'name', 'revision', 'movement_revision'}}


def compare_states(base, left, right, manifests):
    """Conservative comparison: candidates and conflicts, never merged rows."""
    if base['module'] != left['module'] or base['module'] != right['module']:
        raise ValueError('Published game modules differ')
    b, l, r = (s['tables'] for s in (base, left, right))
    validate_history(b, l)
    validate_history(b, r)
    branches = {side: manifest['branch']['id'] for side, manifest in
                zip(('ancestor', 'left', 'right'), manifests)}
    changes, conflicts, collisions = [], [], []
    def compare_table(table, before, lhs, rhs):
        for key in sorted(set(before) | set(lhs) | set(rhs), key=lambda v: cp.canonical(v)):
            old, a, c = (public_row(table, rows.get(key)) for rows in (before, lhs, rhs))
            if a == old and c == old:
                continue
            identity = {'table': table, 'key': key}
            if table == 'item':
                identity['origin_branch'] = branches['ancestor'] if key in before else None
            record = {'entity': identity, 'ancestor': old, 'left': a, 'right': c}
            if table == 'item' and old is None:
                # Both may allocate the exact same integer for unrelated outputs.
                for side, value in (('left', a), ('right', c)):
                    if value is not None:
                        changes.append({'entity': dict(identity, origin_branch=branches[side]),
                                        'kind': 'branch_created_item', 'side': side, 'value': value})
                if a is not None and c is not None:
                    collisions.append({'serial': key, 'left_branch': branches['left'],
                                       'right_branch': branches['right'],
                                       'resolution': 'Distinct entities; remapping is required before import'})
                continue
            if a == old or c == old:
                record.update(kind='one_sided_change', side='right' if a == old else 'left')
                changes.append(record)
            else:
                category = ('item_ownership_or_quantity' if table == 'item' else
                            'resource_outcome' if table == 'resource_bank' else
                            'merchant_outcome' if table in {'merchant', 'merchant_goods'} else
                            'creature_outcome' if table == 'creature' else 'concurrent_state')
                record.update(kind=category, equal_final_state=a == c, resolved=False)
                conflicts.append(record)
    compare_table('item', item_view(b), item_view(l), item_view(r))
    for table in sorted(set(SCHEMA) - JOURNALS - PRIVATE - TRANSIENT - COUNTERS - ITEM_TABLES):
        compare_table(table, b[table], l[table], r[table])
    histories = {}
    for side, state in (('left', l), ('right', r)):
        histories[side] = {}
        for table in sorted(JOURNALS):
            histories[side][table] = [
                {'branch': branches[side], 'local_key': key, 'event': public_row(table, row)}
                for key, row in sorted(state[table].items(), key=lambda pair: cp.canonical(pair[0]))
                if key not in b[table]]
    def consumption(history):
        consumed = {}
        origins = {serial: {serial} for serial in b['inventory_item']}
        fields = {'crafting_event': ('ingredient', 'consumed'),
                  'metal_event': ('source', 'consumed'), 'cooking_event': ('source', 'amount'),
                  'sale_event': ('source', 'quantity')}
        relevant = set(fields) | {'inventory_event', 'item_action'}
        events = sorted((event['local_key'], table, event)
                        for table in relevant for event in history[table])
        for _, table, event in events:
            row = event['event']
            if table == 'inventory_event':
                if row['remainder_serial']:
                    origins[row['remainder_serial']] = set(origins.get(row['serial'], ()))
                continue
            if table == 'item_action' and row['kind'] == 'merge':
                origins.setdefault(row['target'], set()).update(origins.get(row['serial'], ()))
                continue
            if table == 'item_action' and row['kind'] == 'eat':
                source, amount = row['serial'], row['amount']
            elif table in fields:
                source_field, amount_field = fields[table]
                source, amount = row[source_field], row[amount_field]
            else:
                continue
            roots = origins.get(source, set())
            for ancestral in sorted(roots):
                consumed.setdefault(ancestral, []).append({
                    'table': table, 'branch': event['branch'], 'local_key': event['local_key'],
                    'source_serial': source, 'amount_in_source_units': amount,
                    'dependency_only': source != ancestral or len(roots) != 1})
            if table in {'crafting_event', 'metal_event', 'cooking_event'}:
                origins.setdefault(row['output'], set()).update(roots)
        return consumed
    lc, rc = consumption(histories['left']), consumption(histories['right'])
    for serial in sorted(lc.keys() & rc.keys()):
        conflicts.append({'kind': 'shared_ancestral_consumption', 'serial': serial,
                          'ancestor_amount': b['inventory_item'][serial]['amount'],
                          'left': lc[serial], 'right': rc[serial], 'resolved': False})
    def kills(history):
        return {e['event']['life']: e for e in history['hunting_event']
                if e['event']['remaining'] == 0 and e['event']['loot']}
    lk, rk = kills(histories['left']), kills(histories['right'])
    for life in sorted(lk.keys() & rk.keys()):
        conflicts.append({'kind': 'repeated_creature_reward', 'creature': 3, 'life': life,
                          'left': lk[life], 'right': rk[life], 'resolved': False})
    return {
        'format': 'ultima-merge-preview', 'version': 1, 'schema_sha256': SCHEMA_DIGEST,
        'provenance': {side: {'checkpoint': m['id'], 'branch': m['branch']['id'],
                             'manifest_sha256': manifest_digest(m)}
                       for side, m in zip(('ancestor', 'left', 'right'), manifests)},
        'changes': changes, 'conflicts': conflicts, 'serial_collisions': collisions,
        'new_history': histories, 'can_apply': False, 'conservation': 'not_proven',
        'limitations': [
            'One-sided state changes are candidates, not independent transaction replay instructions.',
            'Split/merge stack histories need transaction-level lineage before conservation can be proved.',
            'Equal concurrent outcomes do not deduplicate consumption, skill gains, or rewards.',
            'No resolution policy or merged world is applied.',
        ],
    }


def preview(ancestor, left, right, runtime, intermediates=()):
    paths = [ancestor, left, right, *intermediates]
    manifests = [cp.verify(path, runtime) for path in paths]
    lineage(*manifests[:3], manifests[3:])
    states = [logical_snapshot(path, runtime, manifest)
              for path, manifest in zip(paths[:3], manifests[:3])]
    # Reading a later input must not change a previously read source either.
    if [cp.verify(path, runtime) for path in paths] != manifests:
        raise ValueError('Source checkpoints changed')
    return compare_states(*states, manifests[:3])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', required=True, type=Path)
    parser.add_argument('--ancestor', required=True, type=Path)
    parser.add_argument('--left', required=True, type=Path)
    parser.add_argument('--right', required=True, type=Path)
    parser.add_argument('--lineage', action='append', default=[], type=Path,
                        help='intermediate parent checkpoint, repeat for deeper forks')
    parser.add_argument('--output', required=True, type=Path,
                        help='new credential-free JSON report; existing files are refused')
    args = parser.parse_args()
    for path in [args.ancestor, args.left, args.right, *args.lineage]:
        cp.disjoint(path, args.output)
    if args.output.exists() or args.output.is_symlink():
        raise FileExistsError('Report destination already exists')
    result = preview(args.ancestor, args.left, args.right, args.runtime.resolve(), args.lineage)
    cp.write_json(args.output, result)
    print('Preview written; no merge applied')


if __name__ == '__main__':
    main()
