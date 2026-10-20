# Two-player migration plan

Status: implemented, verified, and deployed on October 20, 2026. The local
gateway accepts `local/local` and `local2/local2` simultaneously.

## Ownership and compatibility

Preserve avatar 1, its fixed backpack 0x40000100, and every existing save row.
Reserve mobile 4 for the second player; mobiles 2 and 3 remain the merchant and
creature. Add a private player-account table binding mobile, account name,
backpack serial, and database identity. The publisher identity remains the
administrator and first player's identity. Only it may register the second
identity or initialize shared fixtures.

Gameplay reducers derive the player from the authenticated database caller.
There is no caller-selected player argument. The gateway owns both database
tokens and authenticates the two local demo accounts before binding a session;
game clients never receive a token or direct SQL access. Read snapshots use the
administrator connection because tables remain private. Write requests use the
authenticated player's identity. No global mutable “current player” is allowed.

Allocate the second backpack and starter items from the existing serial
allocator. A backpack is private to its recorded player. Worn items use their
player's mobile serial as container. Source/destination and equipment-slot checks
must reject another player's backpack or worn goods. Ground items and the barrel
remain shared and reachable. The inventory revision and serial allocator remain
global, deliberately serializing conflicting transactions in this small world.

Nutrition, vitality, and harvesting clocks already have player-sized keys;
parameterize their lookups. Add explicit player-keyed skill state and melee
clocks rather than overloading unrelated IDs. Preserve old skill rows and
creature cooldowns during migration. Movement and combat histories need
player-qualified keys; preserve legacy journals and introduce additive tables
for new player-qualified events. Migration must never reset a deadline.

## Delivery sequence

1. Add account/ownership metadata and idempotent registration. Prove existing
   data is unchanged and non-administrators cannot register identities.
2. Parameterize every gameplay reducer and backend read. Keep the first-player
   protocol and tests working. Add player-qualified skills, clocks, and journals;
   test ownership rejection before enabling concurrent login.
3. Bind relay tickets to accounts and enforce one session per account. Bind a
   separate backend instance to each session; share immutable navigation access
   only where its synchronization permits.
4. Add commit-triggered, coalesced session notifications. Successful or uncertain
   gateway writes invalidate interested sessions; each sends authoritative
   visibility/inventory/status deltas. Retain the pending socket read across
   updates. Include other players' movement, equipment, and removal on departure.
   Bound queues and avoid periodic full-world polling. This owner-gateway change
   feed is a two-client bridge; direct database subscriptions are required before
   introducing multiple gateways or out-of-band gameplay writers.
5. Exercise two encrypted clients concurrently through movement, private
   inventory/equipment, shared ground contention, resources, trade, crafting,
   cooking, and combat. Contended transactions fail and refresh rather than
   retrying consumption blindly. Damage and loot attribution must identify the
   acting player; no passive/offline player receives retaliation.
6. Back up the live database, publish the additive module, compare all existing
   rows, and deploy the gateway only after first-player and two-player acceptance
   tests pass. Verify reconnect and restart with both players' state populated.

## Acceptance and boundaries

Both clients must simultaneously see each other's movement and equipment and
shared world changes without moving to force a refresh. Private inventories,
skills, food, health, recovery deadlines, and action cooldowns must be isolated.
The existing avatar keeps its progress. Shared-resource and loot races must
conserve quantities. Same-account double login and cross-account item actions
must fail. A disconnected or peaceful player receives no simulated attacks.

This phase is loopback-only with explicit development credentials, two avatars,
no PvP, and no account creation UI. LAN discovery, secure remote authentication,
multiple gateways, hosting, and branch reconciliation are later phases.

## Implementation checkpoint

Account metadata and atomic second-player registration are implemented locally.
The registration acceptance test verifies administrator-only access, rejection
of occupied placement, distinct backpack ownership, preservation of all original
items/equipment and gameplay state, idempotent replay, and refusal to rebind an
existing account to a different identity. Both avatar rows and account bindings
survive a standalone database restart. The existing gameplay suite and real Swift
client smoke pass with the second player's persisted starter kit present.

Gameplay reducers now derive actor identity from the database caller, while
fixture seeding and registration remain administrator-only. Backend instances
carry a separate write identity and scope avatar, backpack, equipment, nutrition,
health, and skill reads to the bound player. Movement/combat journals have
player-qualified keys, and melee clocks are independent with legacy deadlines
preserved. The acceptance test exercises second-player movement, equipment swaps,
food consumption, private-item rejection, and administrative-call rejection;
per-player rows and journals survive restart. The original gameplay suite and
Swift client smoke still pass.

Private token provisioning, account-bound relays, per-account session exclusion,
and coalesced commit notifications are now wired into the gateway. The two-client
acceptance test verifies simultaneous login, idle observation of movement and
equipment changes, foreign-item rejection, duplicate/mismatched login rejection,
disconnect removal, and persistent re-entry. The full regression suite passes,
including the original real Swift client smoke and database restarts.

The separate shared-gameplay acceptance world passes concurrent ground pickup,
harvesting, stale crafting and merchant operations, occupied-door and respawn
checks, and both players completing gathering, crafting, trading, hunting,
cooking, and eating. Assertions account for item/resource/gold conservation,
independent skill gains and cooldowns, exactly one creature loot result, wounded
reconnects, and no offline attacks. Populated state survives a database restart.
The real Swift client smoke decodes peer mobiles, worn equipment, private
backpack ownership, and peer health independently from the current player.

The release verification passed five Rust rules tests, 33 Python regression tests,
the dedicated two-client shared scenario, and the real Swift client smoke. Run
`python3 server/local-spacetime/run.py --verify` and
`python3 server/local-spacetime/run.py --verify-shared` in disposable worlds to
repeat these checks. Rendered-client playtesting remains useful beyond these
protocol and asset checks.

Deployment stopped the gateway and backed up the persisted database before the
additive module publication. A before/after audit compared all rows in all 32
original tables: existing progress was unchanged, with only the second avatar,
its 11 starter item records, three equipment slots, vitality, and the expected
inventory revision/serial allocation added to those tables. Account and event
tables are additive. Repeating preparation and provisioning changed no audited
rows. Private backup and audit files remain under ignored `build/`; credentials
and world saves are not published. The gateway now serves the migrated world at
`127.0.0.1:2594`.
