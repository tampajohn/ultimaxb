# World checkpoints and branches

Status: private checkpoint/fork implementation and real-store acceptance passed
on October 20, 2026. The running shared world was not stopped or copied.

## Delivery phases

1. **Private local checkpoints and forks (current).** Stop a world, capture its
   complete durable store, verify file hashes, and restore into a new directory
   with its own branch UUID and parent checkpoint reference. Preserve both
   players, identities, journals, serial allocations, and cooldown deadlines.
   Test with populated disposable worlds and prove that parent/child actions
   cannot affect each other.
2. **Logical, shareable exports.** Define a versioned game-state schema independent
   of the storage engine. Rebind identities using new credentials on import;
   exclude credentials and runtime internals from the shareable artifact.
   Validate references, ownership, quantities, and schema migrations in one
   atomic import into a new world.
3. **Merge preview (implemented and verified).** Assign
   branch-qualified identities to new items and operations. Verify an explicit
   common ancestor and compare both descendants.
   Classify independent changes, mutually exclusive transfers/consumption,
   shared quest/resource outcomes, and conflicting character progression.
   Show the consequences before writing anything.
   See [MERGE_PREVIEW.md](MERGE_PREVIEW.md) for the read-only comparison contract
   and CLI. Stable identities in a future import still require phase 2.
4. **Reconciled child worlds.** Apply an explicit policy to the preview, create a
   new child with both parents recorded, and validate conservation/provenance.
   Keep both source branches intact. Rebase is another explicit reconciliation,
   not replacement of a player's current save.
5. **LAN and hosted sessions.** Add authenticated discovery, world selection,
   host lifecycle, durable remote storage, and measured idle costs. Concurrent
   authoritative hosts require a separate consensus/ownership design.

Raft can order actions in a single shared world. It does not decide whether two
independent histories may both consume the same sword or receive the same unique
reward. Those are merge policy conflicts. Timestamps and local serial/revision
numbers alone cannot identify or resolve them.

## Version 1 checkpoint contract

The first checkpoint is a **private local directory**, not a public interchange
format. It contains account tokens and signing keys needed to retain current
database ownership. Keep it under ignored `build/`, with directory permissions
0700 and file permissions 0600. Do not commit, upload, or share it. Original game
assets are not part of a world store and must never be added to the checkpoint.
Credential-free exports belong to phase 2.

Layout:

```
checkpoint/
  manifest.json
  store/
    gateway.json
    jwt-private-pkcs8.pem
    jwt-public.pem
    control-db/...
    replicas/...
    program-bytes/...
    metadata.toml
    config.toml
    branch.json
```

`manifest.json` declares format/version, creation UTC time, checkpoint UUID,
branch UUID and parent reference, exact runtime SHA-256, and a sorted inventory
of relative file paths, lengths, and SHA-256 digests. A canonical manifest digest
identifies the checkpoint referenced by descendants. No filenames may escape
`store/`; symbolic links, hard links, special files, duplicate paths, unexpected
files, missing files, and digest/size mismatches are rejected.
Hashes detect accidental alteration; they do not authenticate an untrusted
checkpoint. Only restore checkpoints you created locally. The embedded module
is executable database code.

Capture requires exclusive runner and native database locks for the entire copy.
The native lock is `spacetime.pid`; the application runner lock is separate and
survives database restarts. Neither lock file is copied. Logs and rebuildable
caches are excluded. A snapshot is usable only after the complete manifest is
written. Failure must leave no usable partial checkpoint or fork.

Restore verifies the complete checkpoint before constructing a child. The
destination must not exist, must not overlap the checkpoint, and receives a
fresh branch UUID plus the source branch/checkpoint reference. The saved gateway
endpoint is rebound to an explicitly selected loopback port. Runtime compatibility
is exact for this first format; it must not silently upgrade the stored module.
Starting a fork requires separate database and game ports.
The runner checks the pinned runtime and uses the stored module without
republishing the current source. An interrupted restore carries a
`.fork-incomplete` marker and cannot be started or captured.

The child retains the original SpacetimeDB database identity and account
identities inside its independent standalone store. Its **world branch identity**
is new. Credentials are therefore shared with its parent: this is isolation for
trusted local experimentation, not an authentication boundary between strangers.
Never put these clones behind a shared remote database endpoint.

Cooldown timestamps remain absolute. Time spent offline can satisfy a deadline,
but no attacks, harvesting, replenishment, or respawns are simulated by copying.
Presence is transient and is cleared when the child's gateway starts.

## Acceptance gates

- Refuse capture while a runner or native standalone holds its lock.
- Reject malformed, incompatible, altered, truncated, incomplete, linked, or
  path-traversing checkpoint input without changing the parent or any destination.
- Preserve every persisted game table across checkpoint/restore, including both
  players and all event journals; normalize only transient presence on startup.
- Give child and parent separate directories, endpoints, and branch identities.
- Mutate each world independently and prove the other is unchanged.
- Restart the child and prove those changes persist.
- Account for quantities and resource state at the fork boundary.
- Leave the actual running shared world intact throughout disposable verification.

Runtime locking was checked against the pinned [SpacetimeDB 2.12.0
implementation](https://github.com/clockworklabs/SpacetimeDB/blob/v2.12.0/crates/paths/src/server.rs).

## Commands

From the repository root, first shut down the source world's runner normally
with Ctrl-C and wait for it to exit. These commands never stop a running world
for you; capture refuses an active database. The actual shared world was left
running during development of this feature.

```sh
mkdir -p build/checkpoints
python3 server/local-spacetime/checkpoint.py \
  --runtime build/spacetime-tools/spacetimedb-standalone \
  capture build/spacetime-data build/checkpoints/my-world

python3 server/local-spacetime/checkpoint.py \
  --runtime build/spacetime-tools/spacetimedb-standalone \
  verify build/checkpoints/my-world

python3 server/local-spacetime/checkpoint.py \
  --runtime build/spacetime-tools/spacetimedb-standalone \
  fork build/checkpoints/my-world build/my-world-fork --db-port 3001

python3 server/local-spacetime/run.py \
  --data-dir build/my-world-fork --db-port 3001 --port 2595
```

Connect a client to `127.0.0.1:2595` using the same local account credentials.
The parent can run separately on its original ports, 3000 and 2594. Choose unused
ports for every additional fork. Both checkpoint and fork destination paths must
be new; commands refuse existing destinations. A source's first capture creates
its branch metadata without altering gameplay state.

Checkpoint directories are limited to 100,000 files and 16 GiB in this prototype.
Use the exact same standalone binary when capturing and restoring; cross-version
or cross-platform migration is outside this physical format. Restore does not
delete a failed existing world or attempt automatic repair.

Verification:

```sh
python3 -m unittest discover -s server/local-spacetime/tests -p 'test_checkpoint.py' -v
python3 -m unittest discover -s server/local-spacetime/tests -p 'test_world_lock.py' -v
python3 server/local-spacetime/run.py --verify-checkpoint
```

The last command uses only disposable worlds. It runs the shared gameplay
scenario before capturing a checkpoint, then compares all module tables,
performs independent parent/child actions, restarts both stores, starts the
child through the production runner, and creates a descendant checkpoint/fork.
Acceptance passed: all 41 module tables matched at the fork boundary after the
two-player gameplay scenario. Parent/player-1 and child/player-2 each consumed
exactly one of their own apples without changing the other world; both changes
survived separate restarts. The production runner started the child with its
stored module and unchanged gameplay rows. A new checkpoint of that child
successfully created a further descendant with the correct ancestry.

Nine format/failure tests and three process-lock tests cover invalid input,
exclusive destinations, interruption markers, private permissions, and active
world exclusion. A read-only lock attempt against the actual running shared
database was refused, and its existing gateway process remained running.

The complete regression run also passed 45 Python tests (including these format
and lock tests), five Rust rules tests, database restart checks, and the real
Swift GameConnection/SmeltWorkflow smoke. No client source edits were included.
