# Three-way world comparison

Status: implemented; real-fork acceptance passed on October 20, 2026.
No merge is applied by this phase.

## Inputs and lineage

Supply one explicit common-ancestor checkpoint and two checkpoints of distinct
descendant branches. Every checkpoint must pass the private checkpoint verifier
with the same runtime. For forks of forks, also supply the intermediate parent
checkpoints so each parent checkpoint ID, manifest digest, and branch ID can be
verified all the way back to the explicit ancestor.

Two later snapshots of the same branch are not independent descendants.
The physical checkpoint format does not record linear snapshot ancestry, so a
same-branch timestamp is not evidence of descent. Unsupported lineage is rejected
rather than guessed. These remain trusted local checkpoints, not authenticated
artifacts from strangers.

Read each world by restoring it to a disposable directory and starting only its
standalone database on an unused loopback port. Do not start a gateway, provision
the module, call gameplay reducers, or write to a source checkpoint. Check the
complete application table set and the pinned logical schema before comparing.
Reject unsupported schemas and changes to inherited ownership bindings or
append-only history. Source file inventories must remain unchanged after reading.

## Entity identity and outcomes

An item present in the ancestor keeps its ancestor-qualified identity in both
descendants. An item created after the fork has a branch-qualified identity.
Equal local serial numbers in two branches do not identify the same new item.
Report those collisions explicitly, keeping both identities distinct.

Join inventory, equipment layer, and ground elevation into one item view so a
transfer, equip, and position cannot be compared as unrelated facts. Compare
characters, health, nutrition, skills, fixtures, resource banks, merchant stock
and money, creature outcomes, and action cooldowns by their established keys.
Do not merge global allocation counters or revision numbers as gameplay values.

Classify one-sided state changes, concurrent incompatible changes, and equal
concurrent outcomes separately. Equal final quantities are not proof that two
consumption histories can be combined. Cross-reference new action histories to
report consumption of the same ancestral stack, potentially repeated creature
rewards, and competing resource/merchant outcomes. Branch-local journal revision
numbers are namespaced too; equal revisions never deduplicate actions.

Track material dependency through split remainders, stack merges, and recipe
outputs. This is conservative ancestry, not exact quantity accounting: a mixed
stack can depend on several ancestral stacks, and crafting changes units. Such
consumption records are marked `dependency_only`, with amounts explicitly in
source-item units. Never sum those amounts as if they were ancestor quantities.

The report is a comparison, not a conservation proof for an invented merged
world. One-sided changes are candidates for reconciliation, not authorization to
apply rows independently of the transactions that produced them. Any suggestion
favoring a branch must retain conflicts and provenance and must not mark the
result safe to apply.

## Output and privacy

Emit deterministic JSON: stable ordering and IDs, no current-time field, random
temporary paths, runtime ports, tokens, signing keys, database identities, or
account names. Reference checkpoint IDs, branch IDs, manifest digests, and the
schema version. Player serials and game-state values are sufficient for this
prototype. The output is credential-free but still reveals gameplay history.

Include all unresolved conflicts and explicit limitations. Never emit reducers,
SQL mutations, a restored merged world, or a claim that duplicated rewards have
been resolved. The source checkpoints and running local world remain unchanged.

## Following phases

1. Read-only three-way comparison with verified provenance (this phase).
2. Logical export/import with identity rebinding and stable entity/operation
   IDs, independent of storage-engine files.
3. Transaction-aware resolution plans with quantity and ownership constraints,
   explicit policy overrides, and a conservation check over the proposed result.
4. Atomic import into a new reconciled branch with both parents recorded.
   Rebase uses the same reviewable process; original branches remain available.

## Acceptance gates

- Real ancestor/two-fork scenarios: independent actions, divergent ownership,
  competing consumption, repeated rewards, resource/merchant conflicts, and
  different new items allocated the same local serial.
- Reject unrelated branches, broken ancestry, incompatible schema/runtime,
  changed ownership bindings, and rewritten inherited journals.
- Identical inputs yield byte-identical reports despite different temporary
  ports and directories.
- Reports contain no source credentials or database identities.
- Source checkpoint file inventories remain identical, all temporary database
  processes are stopped, and the actual shared gateway stays running.

## Commands

First create a common checkpoint, fork it twice, play each fork independently,
stop both runners, and capture each descendant. See [BRANCHES.md](BRANCHES.md)
for those commands. Given checkpoints named `base`, `left`, and `right`:

```sh
python3 server/local-spacetime/merge_preview.py \
  --runtime build/spacetime-tools/spacetimedb-standalone \
  --ancestor build/checkpoints/base \
  --left build/checkpoints/left \
  --right build/checkpoints/right \
  --output build/merge-preview.json
```

For deeper ancestry, add `--lineage build/checkpoints/intermediate` for each
intermediate parent checkpoint. An existing report path is refused. Reports
cannot be written inside any source checkpoint.

The JSON report contains:

- `provenance`: checkpoint and branch IDs plus manifest digests.
- `changes`: one-sided state changes and branch-qualified newly created items.
- `conflicts`: concurrent state/ownership/quantity changes, shared consumption
  dependencies, resource/merchant outcomes, and repeated creature rewards.
- `serial_collisions`: new item IDs that require remapping before any import.
- `new_history`: branch-qualified post-ancestor events, retaining provenance.
- `can_apply: false` and `conservation: "not_proven"`, even if no conflict is found.

No automatic preference policy is implemented. Inspect the report without
assuming that choosing a branch for one row also resolves its transaction,
ingredients, rewards, skill gains, or money transfers.

```sh
python3 -m unittest discover -s server/local-spacetime/tests -p test_merge_preview.py -v
python3 server/local-spacetime/run.py --verify-merge
```

The disposable-world acceptance scenario gathers different materials into
colliding serials, consumes an inherited apple in both worlds, trades with the
same merchant, independently kills the inherited creature, and leaves a sword
worn in one world and on the ground in the other. A second player's independent
food and movement changes exercise one-sided classification. It checks repeated
output determinism, private-field exclusion, CLI output/non-overwrite behavior,
incompatible schema and unrelated ancestry rejection, and source file equality.

Release acceptance passed all of the real-fork checks above, including byte-identical
CLI output and refusing to overwrite an existing report. Nine focused comparison
tests additionally cover nested ancestry, rewritten inherited history, ownership
rebinding, module mismatch, reused ancestral serials, and split-stack dependencies.
The schema adapter covers all 41 application tables; private bindings are checked
internally and never included in the output.

The full regression run also passed 54 Python tests, five Rust rules tests,
database restart checks, and the real Swift GameConnection/SmeltWorkflow smoke.
The existing shared gateway stayed running throughout verification.
