# Bounded combat rules

This milestone extends the existing stationary creature encounter. These rules
describe the implemented sandbox encounter.

- Player health starts at 50 on first migration and persists independently of
  inventory and position. Reconnecting never replenishes it.
- Each accepted player strike uses the existing two-second database cooldown.
  If the creature survives, it retaliates in the same transaction. There is no
  retaliation on a killing blow, without melee reach, after defeat, or without
  an active connected attack loop. Peace, disconnect, and leaving reach stop it.
- Retaliation deals 6 damage before protection. An equipped nose helm removes
  1 damage; an equipped wooden or heater shield removes 2. Protection is capped
  at 3, and damage cannot take health below zero. Carried equipment does not help.
- Zero health means defeated, not classic UO ghost death. Attacks are rejected;
  the gateway clears target and war mode. Inventory stays owned and equipped,
  and movement remains available. No corpse or dropped equipment is created.
- Say `recover` in peace mode after thirty seconds without incoming damage.
  Recovery restores 50 health, including from defeat. It is an explicit durable
  transaction with revision and deadline checks, not regeneration or food healing.
- Classic health/status and mobile-action packets provide feedback. Animation
  groups must be checked against installed assets and decoded by the real client.
- Private combat events record incoming damage, protection, remaining health,
  and recovery. Uncertain writes refresh authoritative state and are not retried.

Verification must cover armor versus carried items, range, cooldown, replay,
authorization, peace/disconnect, defeat and recovery, inventory conservation,
installed animation art, client packet decoding, restart persistence (including
while defeated), and preservation of existing save rows during migration.
