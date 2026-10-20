# Local Spacetime UO protocol prototype

A loopback-only **UO 1.25.32 server adapter backed by a real local
SpacetimeDB database**. It is separate from the Swift client and the existing
OUO Test Center. The client can connect using its Local Spacetime entry.

```text
UltimaMac GameConnection -- encrypted UO TCP --> Python adapter :2594
                          -- server-owned Swift helper --> UO map/static collision
                          -- local HTTP --> SpacetimeDB :3000
                          -- Rust reducers --> persisted avatar, items, equipment, events
```

Implemented: seeded legacy encryption, account login, single-use expiring
relay tokens, Huffman-compressed game responses, existing-character selection,
world entry, status, ping, turn/walk acknowledgement and rejection, position
resynchronization, and persisted reconnect. The database atomically updates the
avatar and appends a movement event plus an elevation record. Expected revisions reject stale commands.
Only the publishing gateway identity can mutate the world; tables are private.

Movement now reads the installed UO assets through the same `ClientAssets` and
`NavigationMap` code as the client. It checks land slopes, impassable land/water,
static and server-owned dynamic obstacles, supporting surfaces, bridges, headroom, and diagonal corners.
Accepted steps persist the actual standing elevation. Turning does not move or
change elevation. The former 17-by-17 test boundary has been removed.

The collision helper is server-owned; the UO client cannot supply a destination
height. The trusted gateway validates the step, then invokes an owner-only reducer
with an expected revision and validated Z. SpacetimeDB rejects stale decisions
and atomically commits position and both journal records. Asset collision runs
in the gateway helper, not inside the WASM database module.

The local world now seeds one **metal door** and one fixed **barrel** on reachable
surfaces near the saved avatar. These are demonstration objects, not a decoration
import of all Britannia. Their serials and positions persist; restarting does not
move them back near the player. Single-click to inspect, double-click the door
to open/close it. Its classic closed/open graphics and swing position are sent as
ordinary UO ground-item updates. The barrel blocks movement and cannot be picked up.
Both objects enter/leave view within 18 tiles as the player moves.

Double-click the barrel to open its classic container gump. A backpack is equipped
on login (open it with the client's backpack shortcut). The barrel initially holds
100 gold and the backpack a dagger. These are seeded once, never replenished on
restart. Drag whole items or partial gold stacks between the two containers, or
reposition them inside a container. The barrel requires unobstructed nearby reach
both when lifting and when dropping. The backpack travels with the avatar.

Press **P** for the client's paperdoll and **B** for your backpack. A one-time
starter kit adds worn boots, short pants, and a shirt, plus a helm, heater shield,
longsword, hatchet, and five apples in the backpack. Existing items and positions
are retained when upgrading. Drag a wearable onto the paperdoll, or double-click
it to equip. Drag worn equipment back into a container or onto nearby ground;
double-clicking worn clothing or shields returns them to the backpack. Worn
hatchets and daggers instead open their tool target cursor. Occupied slots move back
to the backpack atomically. The hatchet reserves both hands; the dagger or sword
can coexist with the shield. Supported layers match the installed asset metadata.

Items can be dropped onto supported nearby ground and picked up again. Placement
checks terrain, height, range, and obstacle reach; remote or unsupported drops
are rejected. Ground item quantities/elevations persist and participate in scene
revision checks. Drop gold or apples onto a matching stack to combine them (up to
65,535 per stack). The source is reduced or removed in the same transaction.
The status panel's gold count reflects gold in the backpack.

### Chop wood and craft a shield

1. Equip the hatchet from your backpack, then double-click the worn hatchet (or
   use the client's equipped-tool action). Target a nearby tree in the map.
2. Each successful chop puts two logs in the backpack. Wait two seconds between
   chops. An 8×8 resource bank contains ten logs and refills after five minutes.
3. Equip the dagger, use it, and target a backpack stack containing at least five
   logs. It consumes five logs and creates a wooden shield.
4. Equip the crafted shield alongside the dagger, or store/drop/trade it later
   when those systems support the desired interaction.

Target cursors expire after thirty seconds, are consumed once, and do not survive
disconnect. Changing inventory before responding invalidates the tool action.
The gateway validates the exact tree XYZ/art from the installed statics and checks
reach; the database independently checks the equipped tool, range, cooldown,
depletion, and revisions. The recipe currently requires five logs in one backpack
stack; combine smaller stacks first. There is no crafting menu or skill roll yet.

Double-click apples to eat one. Consumption and fullness persist together.
This prototype uses simple travel-based appetite: each apple adds four fullness,
the maximum is twenty, and each hundred movement revisions reduces fullness by
one. Turns count as movement revisions. This is not the original UO hunger system;
there is no combat healing, stamina simulation, or starvation penalty yet.

Lifts are connection-local reservations: the source remains in the database until
the drop commits. Disconnecting mid-drag restores the original contents on the
next login. Each successful transfer atomically updates items and an inventory
journal, with inventory/avatar/scene revision checks. Splitting preserves total
quantity and allocates a new serial for the remainder. Inventory persists across
database restarts. Rejected or uncertain writes refresh authoritative contents
without retrying the operation. Nested containers are not implemented.

Door use requires nearby, unobstructed reach. Opening and closing cannot intersect
the player or another dynamic object. A scene revision changes atomically with
door geometry and its journal event; movement and grounding validate that revision
alongside the avatar revision. This prevents committing a step based on outdated
door geometry. The helper invalidates its collision cache whenever objects change.

The demo account is **local / local**, with one character, **Local Avatar**.
Only one game session may use it at a time. This is a local development gate,
not a production account system. Never use real shard credentials here.

## Run

From the repository root:

```sh
python3 server/local-spacetime/run.py
```

The runner builds the module and Swift navigation helper, starts SpacetimeDB on `127.0.0.1:3000`, publishes
without clearing existing data, and starts the UO adapter on
`127.0.0.1:2594`. Ctrl-C stops both processes it started. Existing processes
owning those ports are not terminated. The OUO server on 2593 is unaffected.

State, private gateway credentials, signing keys, and logs stay in ignored
`build/spacetime-data/`. Keep the keys and gateway configuration with the
database when backing it up. The module's private tables belong to that gateway
identity. The runner does not silently regenerate an incomplete key pair or
clear a database on publish errors.

This workspace has the standalone executable under `build/spacetime-tools/`.
For a fresh checkout, requirements are macOS with Swift, Python 3.10+, OpenSSL, Cargo/Rust with
`wasm32-unknown-unknown`, and the official SpacetimeDB standalone executable.
Use `--standalone /path/to/spacetimedb-standalone` or install it on PATH.
The Rust bindings are pinned to 2.0.3 (compatible with the installed Rust 1.95);
the tested standalone runtime is 2.12.0. No global SpacetimeDB CLI login is used.

Official runtime downloads: <https://github.com/clockworklabs/SpacetimeDB/releases>

```sh
rustup target add wasm32-unknown-unknown
python3 server/local-spacetime/run.py --standalone /path/to/spacetimedb-standalone
```

`--port` changes the UO port. `--db-port` changes the database port for a new
configuration; an existing saved endpoint must match. There is no non-loopback
bind option in this prototype.

`--client /path/to/assets` selects the server's asset directory (default:
`uo1998-client`). Use the same assets as the client. Classic 6144-by-4096 map0
and legacy tiledata are required. Missing assets or a failed helper stop movement;
there is no permissive flat-ground fallback. Original assets are never modified.

On login, the avatar is grounded on a valid local surface. For old sandbox saves
inside an obstacle, it searches for the nearest safe tile within eight tiles,
records the recovery, and persists it. If none exists, entry fails instead of
allowing movement through the obstacle. Existing journal rows are retained; the
new `movement_height` table is additive and does not fabricate Z for old events.

## Verify

```sh
python3 server/local-spacetime/run.py --verify
```

This builds and tests the Rust module, compiles a temporary snapshot of the
**actual current UOCore sources** with a standalone Swift smoke harness (macOS required), and provisions
a disposable world on temporary loopback ports. It runs the Python protocol and
live integration tests, restarts the database to check persistence, and exercises
the complete flow through `GameConnection`. It cleans up its processes and world.
It does not use the client's `.build` directory or alter the normal demo world.

The integration suite checks wrong credentials, expired/replayed relays, duplicate
sessions, reducer authorization, stale revisions, transactional journal updates,
movement sequence recovery, and rejection without mutation. Codec tests use the
existing independently generated OUO/C reference vectors and every split point
of a fragmented encrypted login stream.

Asset tests cover surface/headroom rules and actual Britain elevation, obstacle,
and corner edges. A live database test follows an asset-validated route across
the former boundary with a height change, checks its persisted height journal,
and verifies blocked movement does not mutate state. The Swift smoke chooses a
walkable neighboring tile from client assets and verifies X/Y/Z after reconnect.
The door integration test uses real encrypted UO packets to open a door, walk
through, reject closing on the player, close from outside, and reject distant use.
It also checks dynamic collision, stale scene revisions, authorization, pickup
rejection without disconnect, and persistence of object state across DB restart.
Inventory tests exercise partial and whole transfers, quantity conservation,
stale replay, authorization, distance checks, invalid drops, idempotent seeding,
and disconnect recovery. Equipment tests cover slot swaps, two-handed conflicts,
unequipping, original paperdoll art, and invalid layers/owners. Ground/stack tests
check split/merge conservation, rejected terrain/height/range, stale geometry,
same-square replacement, and ground-to-equipment transfers. Food tests verify
consumption and replay rejection. Every item mutation reducer rejects outsiders.
The Swift smoke exercises the real `ManualInventoryTransfer` confirmation path
for equipping/unequipping and decodes persisted ground stack quantities.
Database restart checks include inventory, ground locations, equipment, nutrition,
and revisions. Automated checks do not replace a rendered-client playtest.
Gathering tests target real trees, reject forged/expired/replayed cursors, deplete
a resource bank, verify durable cooldowns and action history, and carve/equip the
output. Refill deadline behavior is tested directly in Rust. The real Swift client
uses `TargetRequest` to craft the remaining five logs after a database restart,
checks ingredient removal and shield paperdoll art, and exercises cancellation.

For codec-only tests without services:

```sh
python3 -m unittest discover -s server/local-spacetime/tests -v
```

The fourteen live tests skip unless `ULTIMA_SPACETIME_CONFIG` names a gateway config.
Live tests deliberately move the demo avatar and append history if pointed at
an existing database. Prefer `run.py --verify` for an isolated test world.

## Current limits and next steps

### Development phases

| Phase | Player outcome | Acceptance criteria |
| --- | --- | --- |
| 1 — Gathering and a useful recipe (implemented) | Equip the hatchet, target an actual map tree, collect logs, then use the dagger on five backpack logs to carve a wooden shield. | Single-use expiring target cursors; server-validated tree identity and reach; durable cooldown/depletion; lazy resource recovery after idle time; atomic ingredient consumption/output creation; crafted shield equips and persists; real-client target/result decoding. |
| 2 — Mining, smithing, and progression (core loop implemented) | Mine ore, smelt at a forge, craft or repair basic metal equipment. | Asset-validated ore/forge targets; explicit recipes and material costs; durable tool wear and skill progression; no skill/loot gains on rejected or replayed requests; original target/gump protocols. Decide era-faithful rules before expanding the recipe catalogue. |
| 3 — A small inhabited adventure (merchant purchases and log sales implemented) | Trade with one vendor and fight one creature type near a safe starting area. | Finite vendor stock and money, atomic purchases/sales, deterministic attack cadence and range checks, damage/death/loot/recovery, NPC persistence, pause/resume rules for an empty world, no duplicate loot after reconnect. |
| 4 — Shared local world | Two distinct players gather, trade, and fight together. | Real accounts and character ownership, subscription-driven visibility, per-player sessions, contested resource/equipment tests, secure LAN discovery and explicit host selection. Replace proof-of-concept HTTP polling before scaling. |
| 5 — World branches and reconciliation | Fork a checkpoint, explore independently, preview a merge, and create a new reconciled world. | Stable cross-world entity/event IDs, ancestry/checkpoints, explicit item creation/transfer/consumption history, three-way merge preview, conservation checks, deterministic conflict policies, provenance for overrides, reversible import into a new branch. Never merge solely by timestamps or local revision numbers. |

Phase 1 intentionally uses a small sandbox recipe (five logs → one wooden shield),
not a claim of original-era crafting fidelity. The resource model is ten logs per
8×8 bank, two logs per successful chop, a two-second player cooldown, and a
five-minute refill evaluated on the next attempt. No background timer is required
while idle. Harvest/craft outcomes commit with the inventory and their journals.

The mining loop adds a pickaxe and smith's hammer to the backpack once, including
existing saves. Equip the pickaxe and double-click it to target an adjacent rock or
mountain tile. One successful swing produces two iron ore (0x19B8); mineral banks
hold ten ore and use the same cooldown/refill policy as lumber, in a separate bank
namespace. A verified reachable test site is rock **1250,1248,0**, approached from
**1250,1249,0**. There is no teleport command in the player protocol.

A permanent forge is placed once on reachable terrain within two tiles of the
saved avatar on upgrade. It uses original forge art, blocks movement, preserves
door swings, and is saved as part of the scene. Double-click backpack ore and
target this forge or an original map forge within two tiles.
For example, a forge at **636,2193,0** is reachable from **635,2193,0**. Each displayed
ore of this supported pile shape contains two metal units and becomes one ingot.
Near a forge, equip and use the smith's hammer, then target a backpack stack of at
least five ingots to create a nose helm. All consumption, output, and metal history
commit together; stale cursors and unauthorized calls cannot repeat the conversion.
Ore and ingots also support ordinary drag splitting/merging. This is a deliberately
small sandbox recipe, with no skill roll, tool wear, repair, or progression yet.
Only iron ore shape 0x19B8 is supported; ore-use pile combining is not implemented.
The nearby forge is a server-visible object and supports the client's existing
`SmeltWorkflow`; original static-map forges also work through manual targeting.
Dynamic forge targets must match the stored serial, graphic, and full position.
The live Swift smoke runs the actual workflow through use/target/result packets,
checks consumption and ingot creation, and then continues crafting and reconnects.

Mining integration tests use real asset targets and encrypted client packets,
deplete mineral banks independently of lumber, reject fake and distant targets,
convert ten ore to ten ingots, and consume five ingots for exactly one helmet.
Resource banks, metal journals, equipment, and remaining materials are checked
across database restart. Test-only relocation uses owner-authorized reducers in a
disposable database and never changes the saved play world.

Mara the provisioner is placed once on reachable terrain within two tiles of the
saved avatar when this upgrade first starts. Single-click for her name; stand
within two tiles and double-click to open the original vendor window. She starts
with twenty apples at three gold each. Carry gold in your backpack (move it from
the nearby barrel first), choose a quantity, and buy. Her stock decreases and her
purse increases atomically with your inventory; reconnecting never replenishes
stock. Quotes last thirty seconds, are invalidated by inventory changes, and may
be submitted only once. A refusal requires reopening the vendor window.

Say **vendor buy** to open her stock, or **vendor sell** to offer backpack logs at
one gold each. The sell window quotes one stack at a time and caps its quantity
by her available purse. Buy apples first to put gold into her initially empty
purse. Sold logs remain in her persistent goods ledger; they are not deleted or
converted into new money. Cancelled, expired, stale, and repeated sales cannot
consume goods or pay twice. Nearby reach is checked again at settlement.

Classic speech supports 1–200 Latin-1 characters and normal/emote/whisper/yell
modes through the existing client journal and overhead text. Vendor commands are
local to Mara; this remains a single-player sandbox.

The merchant, goods, and buy/sell journals persist across restarts. She never
restocks and has no wandering, combat, or mobile collision logic.
These are explicit next steps; no idle AI timer runs. Merchant tests exercise real
encrypted vendor packets, insufficient carried gold, expiry/cancellation/replay,
quantity/range/authorization checks, and conservation of both goods and currency. Twelve harvested logs become exactly
ten logs consumed for two shields and two logs retained by the merchant.
The Swift verifier decodes her stock prices and original clothing through UOCore.

Hosting and distributed execution follow the shared-world phase: measure idle
costs, checkpoint durability, wake-up behavior, and authority handoff first.
Consensus within an active shared world and reconciliation between independently
played branches are separate problems. A merge must account for spent resources
and item ownership; choosing a preferred player cannot silently duplicate items.

- One precreated avatar and one stationary merchant; no character creation/deletion,
  combat or multiplayer visibility.
- Movement uses the client's conservative collision rules, not a claim of exact
  original-server parity. Mobile blockers, placed houses/boats, mounts, ghost
  movement, and movement cadence remain unimplemented. World fixtures consist of
  the seeded door/barrel/forge and player-dropped inventory; no decoration import exists.
  Doors baked into map statics still block and cannot be opened. Dynamic door use
  currently supports the one seeded classic door orientation, with no auto-close
  timer or lock/key system. This is not yet a complete playable shard.
- Inventory supports only the seeded backpack/barrel, at most 64 item records,
  and bounded interior coordinates for each gump. There is no weight or
  capacity simulation or nested storage yet. Equipment is limited to the explicit
  starter catalogue, mining tools, wooden shields, and crafted nose helms; weapons have no combat actions yet.
  Tool use supports lumberjacking, carving, mining, smelting, and one smithing recipe.
  Health, attributes, armor, and weight remain placeholder status values.
  Ground placement uses standable terrain, not arbitrary table/container surfaces.
  Container changes refresh on interaction, not subscriptions.
- HTTP reducer calls and SQL reads are sequential and intended for the proof.
  Replace this backend with SDK/WebSocket subscriptions before adding multiplayer
  or claiming suitable gameplay throughput. Uncertain write outcomes trigger an
  authoritative read and movement rejection; the adapter does not retry blindly.
  Object changes are refreshed on entry, movement, position sync, and item use;
  there is no background subscription for edits by other sessions.
- Unsupported packet opcodes close the session instead of guessing frame lengths.
  Skills currently return an empty list; war-mode requests retain peace mode.
- The avatar and journal are real persisted state. World forks, global entity
  identities, merge/rebase policies, checkpoint import/export, and cloud hosting
  are not implemented. Local revision numbers are not cross-world event IDs.
- Protocol and movement decisions use explicit code. No model is in the gameplay
  path. Model-assisted merge proposals can be explored separately later.

Next: rendered-client playtesting, tool wear/skills, vendor restocking and a small creature/combat
loop. Fork/merge work will need stable cross-world identities and explicit rules
for item ownership and consumption; the current local journals are not sufficient.

## Sources

Wire formats follow the existing UOCore implementation and its OUO references.
The cipher and Huffman table retain the OUO attribution; see
[`LICENSES/OUO.txt`](../../LICENSES/OUO.txt).

SpacetimeDB API references:
<https://spacetimedb.com/docs/http/database/>,
<https://spacetimedb.com/docs/http/identity/>,
<https://spacetimedb.com/docs/functions/reducers/>.
