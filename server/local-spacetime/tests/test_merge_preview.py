import copy
from pathlib import Path
import sys
import unittest
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import checkpoint as cp
import merge_preview as merge


def manifest(parent=None):
    result = {'id': str(uuid.uuid4()), 'runtime_sha256': 'a' * 64,
              'branch': {'id': str(uuid.uuid4()), 'parent': None}}
    if parent:
        result['branch']['parent'] = {'branch': parent['branch']['id'],
            'checkpoint': parent['id'], 'manifest_sha256': merge.manifest_digest(parent)}
    return result


def state():
    tables = {name: {} for name in merge.SCHEMA}
    tables['inventory_state'][0] = dict(id=0, revision=10, next_serial=500)
    tables['inventory_item'][100] = dict(serial=100, graphic=0x9d0, amount=5, container=400, x=65, y=85)
    tables['inventory_item'][101] = dict(serial=101, graphic=0xf51, amount=1, container=400, x=65, y=85)
    tables['gateway'][0] = dict(id=0, owner='PRIVATE-DATABASE-OWNER')
    tables['player_account'][1] = dict(serial=1, account='PRIVATE-ACCOUNT',
                                       identity='PRIVATE-IDENTITY', backpack=400)
    tables['avatar'][1] = dict(serial=1, name='PRIVATE-CHARACTER-NAME', x=100, y=100, z=0, direction=0, revision=1)
    tables['item_action'][10] = dict(revision=10, kind='place', serial=100, target=400, amount=5, x=65, y=85, z=0)
    return {'module': 'same-module', 'tables': tables}


class MergePreviewTests(unittest.TestCase):
    def setUp(self):
        self.base = state()
        self.left, self.right = copy.deepcopy(self.base), copy.deepcopy(self.base)
        base = manifest()
        self.manifests = [base, manifest(base), manifest(base)]

    def compare(self):
        return merge.compare_states(self.base, self.left, self.right, self.manifests)

    def test_independent_changes_are_candidates_and_never_claim_conservation(self):
        self.left['tables']['inventory_item'][101]['container'] = 1
        self.left['tables']['equipment_slot'][101] = dict(serial=101, layer=1)
        self.right['tables']['avatar'][1]['x'] = 101
        result = self.compare()
        self.assertEqual(len(result['changes']), 2)
        self.assertEqual(result['conflicts'], [])
        self.assertFalse(result['can_apply'])
        self.assertEqual(result['conservation'], 'not_proven')
        self.assertEqual(cp.canonical(result), cp.canonical(self.compare()))

    def test_equal_local_serials_remain_distinct_branch_entities(self):
        for child, graphic in ((self.left, 0x1bdd), (self.right, 0x19b8)):
            child['tables']['inventory_state'][0]['next_serial'] = 501
            child['tables']['inventory_item'][500] = dict(serial=500, graphic=graphic, amount=2, container=400, x=65, y=85)
        result = self.compare()
        new = [r for r in result['changes'] if r['kind'] == 'branch_created_item']
        self.assertEqual(len(new), 2)
        self.assertNotEqual(new[0]['entity']['origin_branch'], new[1]['entity']['origin_branch'])
        self.assertEqual(result['serial_collisions'][0]['serial'], 500)

    def test_identical_consumption_is_a_conflict_not_a_deduplicated_action(self):
        for child in (self.left, self.right):
            child['tables']['inventory_item'][100]['amount'] = 4
            child['tables']['item_action'][11] = dict(revision=11, kind='eat', serial=100, target=0, amount=1, x=0, y=0, z=0)
        result = self.compare()
        kinds = {r['kind'] for r in result['conflicts']}
        self.assertIn('shared_ancestral_consumption', kinds)
        conflict = next(r for r in result['conflicts'] if r['kind'] == 'item_ownership_or_quantity')
        self.assertTrue(conflict['equal_final_state'])
        self.assertEqual(len(result['new_history']['left']['item_action']), 1)
        self.assertEqual(len(result['new_history']['right']['item_action']), 1)

    def test_divergent_owner_resource_merchant_and_reward_conflicts(self):
        for i, child in enumerate((self.left, self.right)):
            t = child['tables']
            t['inventory_item'][101]['container'] = 1 if i == 0 else 4
            t['resource_bank'][7] = dict(id=7, remaining=8-i, refill_at=123)
            t['merchant'][2] = dict(serial=2, stock=19-i, gold=3+i)
            t['hunting_event'][1] = dict(revision=1, life=1, weapon=101, damage=5, remaining=0, loot=500+i, at=123+i)
        kinds = {r['kind'] for r in self.compare()['conflicts']}
        self.assertTrue({'item_ownership_or_quantity', 'resource_outcome', 'merchant_outcome',
                         'repeated_creature_reward'} <= kinds)

    def test_private_fields_and_names_are_absent(self):
        self.left['tables']['avatar'][1]['x'] += 1
        report = cp.canonical(self.compare())
        for secret in (b'PRIVATE-DATABASE-OWNER', b'PRIVATE-IDENTITY',
                       b'PRIVATE-ACCOUNT', b'PRIVATE-CHARACTER-NAME'):
            self.assertNotIn(secret, report)

    def test_split_remainders_retain_consumption_dependency(self):
        for offset, child in enumerate((self.left, self.right)):
            serial = 500 + offset
            child['tables']['inventory_event'][11] = dict(
                revision=11, serial=100, amount=1, from_container=400,
                to_container=400, remainder_serial=serial)
            child['tables']['item_action'][12] = dict(
                revision=12, kind='eat', serial=serial, target=0, amount=1, x=0, y=0, z=0)
        result = self.compare()
        conflict = next(c for c in result['conflicts'] if c['kind'] == 'shared_ancestral_consumption')
        self.assertEqual(conflict['serial'], 100)
        self.assertTrue(conflict['left'][0]['dependency_only'])
        self.assertTrue(conflict['right'][0]['dependency_only'])

    def test_rewritten_history_bindings_module_and_reused_serial_rejected(self):
        mutations = [
            lambda s: s['tables']['item_action'][10].update(amount=999),
            lambda s: s['tables']['player_account'][1].update(identity='changed'),
            lambda s: s.update(module='different-module'),
            lambda s: s['tables']['inventory_item'].update({102: dict(serial=102)}),
        ]
        for mutate in mutations:
            self.left = copy.deepcopy(self.base)
            mutate(self.left)
            with self.assertRaises(ValueError):
                self.compare()

    def test_complete_nested_ancestry_required(self):
        base, direct, sibling = self.manifests
        nested = manifest(direct)
        merge.lineage(base, nested, sibling, [direct])
        with self.assertRaises(ValueError):
            merge.lineage(base, nested, sibling)
        tampered = copy.deepcopy(direct)
        tampered['branch']['parent']['manifest_sha256'] = 'b' * 64
        with self.assertRaises(ValueError):
            merge.lineage(base, tampered, sibling)

    def test_unrelated_same_branch_and_runtime_mismatch_rejected(self):
        base, left, right = self.manifests
        with self.assertRaises(ValueError):
            merge.lineage(base, manifest(), right)
        same = copy.deepcopy(right)
        same['branch']['id'] = left['branch']['id']
        with self.assertRaises(ValueError):
            merge.lineage(base, left, same)
        wrong_runtime = copy.deepcopy(right)
        wrong_runtime['runtime_sha256'] = 'b' * 64
        with self.assertRaises(ValueError):
            merge.lineage(base, left, wrong_runtime)
