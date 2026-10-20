use super::*;

const REFILL_US: i64 = 300_000_000;
const COOLDOWN_US: i64 = 2_000_000;
const CAPACITY: u16 = 10;

#[spacetimedb::table(accessor = resource_bank)]
pub struct ResourceBank {
    #[primary_key]
    id: u32,
    remaining: u16,
    refill_at: i64,
}

#[spacetimedb::table(accessor = harvest_clock)]
pub struct HarvestClock {
    #[primary_key]
    serial: u32,
    next_at: i64,
}

#[spacetimedb::table(accessor = gathering_event)]
pub struct GatheringEvent {
    #[primary_key]
    revision: u64,
    tool: u32,
    bank: u32,
    x: u16,
    y: u16,
    z: i8,
    graphic: u16,
    output: u32,
    amount: u16,
    remaining: u16,
    at: i64,
}

#[spacetimedb::table(accessor = crafting_event)]
pub struct CraftingEvent {
    #[primary_key]
    revision: u64,
    tool: u32,
    ingredient: u32,
    consumed: u16,
    output: u32,
    output_graphic: u16,
}

fn bank_id(x: u16, y: u16) -> u32 {
    u32::from(x / 8) * 512 + u32::from(y / 8)
}

fn supply(remaining: u16, refill_at: i64, now: i64) -> (u16,i64) {
    if now >= refill_at { (CAPACITY, now + REFILL_US) } else { (remaining,refill_at) }
}

fn check_tool(ctx: &ReducerContext, serial: u32, graphic: u16, layer: u8) -> Result<(), String> {
    let item = ctx.db.inventory_item().serial().find(serial).ok_or("missing tool")?;
    let slot = ctx.db.equipment_slot().serial().find(serial).ok_or("equip the tool first")?;
    if item.container != 1 || item.amount != 1 || item.graphic != graphic || slot.layer != layer {
        return Err("wrong equipped tool".into());
    }
    Ok(())
}

fn checked_state(ctx: &ReducerContext, inventory: u64, avatar: u64, scene: u64) -> Result<(InventoryState,Avatar), String> {
    authorize(ctx)?;
    check_scene(ctx,scene)?;
    let state = ctx.db.inventory_state().id().find(0).ok_or("missing inventory")?;
    let player = ctx.db.avatar().serial().find(1).ok_or("missing player")?;
    if state.revision != inventory || player.revision != avatar { return Err("stale action".into()); }
    Ok((state,player))
}

fn allocate(state: &mut InventoryState) -> Result<u32,String> {
    let serial = state.next_serial;
    state.next_serial = serial.checked_add(1).ok_or("serial exhausted")?;
    if state.next_serial >= 0x7fffffff { return Err("serial exhausted".into()); }
    Ok(serial)
}

#[spacetimedb::reducer]
pub fn harvest_tree(ctx: &ReducerContext, expected_inventory: u64, expected_avatar: u64,
                    expected_scene: u64, tool: u32, x: u16, y: u16, z: i8, graphic: u16) -> Result<(), String> {
    harvest(ctx,expected_inventory,expected_avatar,expected_scene,tool,x,y,z,graphic,false)
}

#[spacetimedb::reducer]
pub fn mine_ore(ctx: &ReducerContext, expected_inventory: u64, expected_avatar: u64,
    expected_scene: u64, tool: u32, x: u16, y: u16, z: i8, graphic: u16) -> Result<(),String> {
    harvest(ctx,expected_inventory,expected_avatar,expected_scene,tool,x,y,z,graphic,true)
}

fn harvest(ctx: &ReducerContext, expected_inventory: u64, expected_avatar: u64,
    expected_scene: u64, tool: u32, x: u16, y: u16, z: i8, graphic: u16, mining: bool) -> Result<(),String> {
    let (mut state,avatar) = checked_state(ctx,expected_inventory,expected_avatar,expected_scene)?;
    check_tool(ctx,tool,if mining {0xe86} else {0xf43},if mining {1} else {2})?;
    check_ground(&avatar,x,y,z)?;
    if avatar.x.abs_diff(x).max(avatar.y.abs_diff(y)) > 1 { return Err("tree too far away".into()); }
    // The gateway also verifies exact XYZ/art against installed map statics,
    // including VERDATA, and checks unobstructed reach. Client art is not trusted.
    let tree_ranges = [(0xc95,0xc96),(0xc9e,0xc9e),(0xcca,0xce6),(0xce8,0xce8),
        (0xcf8,0xd03),(0xd41,0xd53),(0xd6e,0xd7f),(0xd84,0xd90),(0xd94,0xd9a),
        (0xd9c,0xdab),(0x12b6,0x12be),(0x12c0,0x12c7),(0x1323,0x1323)];
    if !mining && !tree_ranges.iter().any(|&(a,b)| (a..=b).contains(&graphic)) { return Err("not tree art".into()); }
    if mining && graphic != 0 && ![(0x25c,0x276),(0x27d,0x280),(0x53b,0x54f),
        (0x551,0x553),(0x56a,0x56a),(0x16e4,0x16f3)].iter().any(|&(a,b)| (a..=b).contains(&graphic)) {
        return Err("not mining art".into());
    }
    let now = ctx.timestamp.to_micros_since_unix_epoch();
    let clock = ctx.db.harvest_clock().serial().find(1);
    if clock.as_ref().is_some_and(|c| now < c.next_at) { return Err("tool cooling down".into()); }
    // High bit separates mineral deposits from wood at the same coordinates.
    let id = bank_id(x,y) | if mining {0x80000000} else {0};
    let output_graphic = if mining {0x19b8} else {0x1bdd};
    let old = ctx.db.resource_bank().id().find(id);
    let (remaining,refill_at) = old.as_ref().map_or((CAPACITY,now+REFILL_US),
        |b| supply(b.remaining,b.refill_at,now));
    if remaining < 2 { return Err("resource depleted".into()); }
    // Sort so identical states select the same destination stack.
    let mut stacks: Vec<_> = ctx.db.inventory_item().iter()
        .filter(|i| i.container == BACKPACK && i.graphic == output_graphic && i.amount <= 65533).collect();
    stacks.sort_by_key(|i|i.serial);
    let output;
    if let Some(mut logs) = stacks.into_iter().next() {
        output=logs.serial; logs.amount += 2;
        ctx.db.inventory_item().serial().update(logs);
    } else {
        if ctx.db.inventory_item().iter().count() >= 64 { return Err("inventory full".into()); }
        output=allocate(&mut state)?;
        ctx.db.inventory_item().insert(InventoryItem {serial:output,graphic:output_graphic,amount:2,
            container:BACKPACK,x:95,y:125});
    }
    let bank = ResourceBank {id,remaining:remaining-2,refill_at};
    if old.is_some() { ctx.db.resource_bank().id().update(bank); }
    else { ctx.db.resource_bank().insert(bank); }
    let updated_clock = HarvestClock {serial:1,next_at:now+COOLDOWN_US};
    if clock.is_some() { ctx.db.harvest_clock().serial().update(updated_clock); }
    else { ctx.db.harvest_clock().insert(updated_clock); }
    state.revision += 1;
    ctx.db.gathering_event().insert(GatheringEvent {revision:state.revision,tool,bank:id,
        x,y,z,graphic,output,amount:2,remaining:remaining-2,at:now});
    ctx.db.inventory_state().id().update(state);
    Ok(())
}

#[spacetimedb::reducer]
pub fn carve_shield(ctx: &ReducerContext, expected_inventory: u64, expected_avatar: u64,
                    expected_scene: u64, tool: u32, ingredient: u32) -> Result<(), String> {
    let (mut state,_) = checked_state(ctx,expected_inventory,expected_avatar,expected_scene)?;
    check_tool(ctx,tool,0xf51,1)?;
    let mut logs = ctx.db.inventory_item().serial().find(ingredient).ok_or("missing logs")?;
    if logs.container != BACKPACK || logs.graphic != 0x1bdd || logs.amount < 5 {
        return Err("need five logs in one backpack stack".into());
    }
    if logs.amount > 5 && ctx.db.inventory_item().iter().count() >= 64 { return Err("inventory full".into()); }
    if logs.amount == 5 { ctx.db.inventory_item().serial().delete(ingredient); }
    else { logs.amount -= 5; ctx.db.inventory_item().serial().update(logs); }
    let output = allocate(&mut state)?;
    ctx.db.inventory_item().insert(InventoryItem {serial:output,graphic:0x1b7a,amount:1,
        container:BACKPACK,x:90,y:100});
    state.revision += 1;
    ctx.db.crafting_event().insert(CraftingEvent {revision:state.revision,tool,ingredient,
        consumed:5,output,output_graphic:0x1b7a});
    ctx.db.inventory_state().id().update(state);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn depleted_banks_recover_at_the_deadline_without_idle_ticks() {
        assert_eq!(supply(0,1000,999),(0,1000));
        assert_eq!(supply(0,1000,1000),(10,1000+REFILL_US));
        assert_eq!(supply(4,1000,900),(4,1000));
        assert_eq!(supply(4,1000,1000000),(10,1000000+REFILL_US));
        assert_eq!(bank_id(1432,1696),bank_id(1439,1703));
        assert_ne!(bank_id(1439,1703),bank_id(1440,1703));
    }
}

// Versioned additions never replenish tools on reconnect or replace worn items.
#[spacetimedb::reducer]
pub fn seed_mining_kit(ctx: &ReducerContext) -> Result<(),String> {
    authorize(ctx)?;
    if ctx.db.starter_kit().version().find(2).is_some() { return Ok(()); }
    let mut state = ctx.db.inventory_state().id().find(0).ok_or("missing inventory")?;
    if ctx.db.inventory_item().iter().count()+2 > 64 { return Err("mining kit needs space".into()); }
    for graphic in [0xe86,0x13e3] {
        let serial=allocate(&mut state)?;
        ctx.db.inventory_item().insert(InventoryItem {serial,graphic,amount:1,container:BACKPACK,x:100,y:110});
    }
    state.revision+=1;
    ctx.db.inventory_state().id().update(state);
    ctx.db.starter_kit().insert(StarterKit {version:2});
    Ok(())
}

#[spacetimedb::table(accessor = metal_event)]
pub struct MetalEvent {
    #[primary_key] revision: u64,
    source: u32, consumed: u16, output: u32, produced: u16, graphic: u16,
    forge_x: u16, forge_y: u16, forge_z: i8,
}

// Forge coordinates are verified against installed static art by the gateway.
// Only that owner identity may call this reducer; clients never access the DB.
#[spacetimedb::reducer]
pub fn work_metal(ctx: &ReducerContext, expected_inventory: u64, expected_avatar: u64,
    expected_scene: u64, source: u32, tool: u32, x: u16, y: u16, z: i8) -> Result<(),String> {
    let (mut state,avatar)=checked_state(ctx,expected_inventory,expected_avatar,expected_scene)?;
    check_ground(&avatar,x,y,z)?;
    let mut ingredient=ctx.db.inventory_item().serial().find(source).ok_or("missing metal")?;
    if ingredient.container != BACKPACK { return Err("metal must be in backpack".into()); }
    let (consumed,produced,graphic)=if tool == 0 {
        if ingredient.graphic != 0x19b8 { return Err("not supported ore".into()); }
        // This pile shape contains two metal units: one ingot per displayed ore.
        (ingredient.amount,ingredient.amount,0x1bf2)
    } else {
        check_tool(ctx,tool,0x13e3,1)?;
        if ingredient.graphic != 0x1bf2 || ingredient.amount < 5 { return Err("need five ingots".into()); }
        (5,1,0x140e)
    };
    let mut destinations:Vec<_>=ctx.db.inventory_item().iter().filter(|i|
        graphic==0x1bf2 && i.container==BACKPACK && i.graphic==graphic &&
        u32::from(i.amount)+u32::from(produced)<=65535).collect();
    destinations.sort_by_key(|i|i.serial);
    let destination=destinations.into_iter().next();
    if destination.is_none() && ingredient.amount>consumed && ctx.db.inventory_item().iter().count()>=64 {
        return Err("inventory full".into());
    }
    if ingredient.amount==consumed { ctx.db.inventory_item().serial().delete(source); }
    else { ingredient.amount-=consumed; ctx.db.inventory_item().serial().update(ingredient); }
    let output;
    if let Some(mut item)=destination {
        output=item.serial; item.amount+=produced; ctx.db.inventory_item().serial().update(item);
    } else {
        output=allocate(&mut state)?;
        ctx.db.inventory_item().insert(InventoryItem {serial:output,graphic,amount:produced,container:BACKPACK,x:85,y:100});
    }
    state.revision+=1;
    ctx.db.metal_event().insert(MetalEvent {revision:state.revision,source,consumed,output,produced,graphic,
        forge_x:x,forge_y:y,forge_z:z});
    ctx.db.inventory_state().id().update(state);
    Ok(())
}

#[spacetimedb::reducer]
pub fn seed_forge(ctx: &ReducerContext, scene: u64, x: u16, y: u16, z: i8) -> Result<(),String> {
    authorize(ctx)?;
    if ctx.db.world_object().serial().find(0x40000003).is_some() { return Ok(()); }
    check_scene(ctx,scene)?;
    let avatar=ctx.db.avatar().serial().find(1).ok_or("missing player")?;
    check_ground(&avatar,x,y,z)?;
    if (x,y)==(avatar.x,avatar.y) || ctx.db.world_object().iter().any(|o|
        (o.x,o.y)==(x,y) || (o.home_x,o.home_y)==(x,y) ||
        (o.is_door && (o.home_x.saturating_sub(1),o.home_y+1)==(x,y))) ||
        ctx.db.inventory_item().iter().any(|i|i.container==0 && (i.x,i.y)==(x,y)) {
        return Err("occupied forge site".into());
    }
    ctx.db.world_object().insert(WorldObject {serial:0x40000003,graphic:0xfb1,x,y,z,
        home_x:x,home_y:y,is_door:false,opened:false});
    touch_scene(ctx)?;
    Ok(())
}
