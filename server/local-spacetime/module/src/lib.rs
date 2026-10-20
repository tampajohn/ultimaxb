use spacetimedb::{Identity, ReducerContext, Table};
mod gathering;
mod skills;
mod hunting;
mod cooking;
mod combat;
mod merchant;

// Private tables: only the publishing gateway identity can read or mutate them.
#[spacetimedb::table(accessor = gateway)]
pub struct Gateway {
    #[primary_key]
    id: u8,
    owner: Identity,
}

#[spacetimedb::table(accessor = avatar)]
pub struct Avatar {
    #[primary_key]
    serial: u32,
    name: String,
    x: u16,
    y: u16,
    z: i8,
    direction: u8,
    revision: u64,
}

// A transactional semantic journal, not yet a fork/merge format. Sequence IDs
// are local to this database and must not be used as cross-world identities.
#[spacetimedb::table(accessor = movement_event)]
pub struct MovementEvent {
    #[primary_key]
    revision: u64,
    from_x: u16,
    from_y: u16,
    to_x: u16,
    to_y: u16,
    direction: u8,
}

// Additive table preserves existing saves and the original journal schema.
// Older revisions have no height record; never invent missing historical Z.
#[spacetimedb::table(accessor = movement_height)]
pub struct MovementHeight {
    #[primary_key]
    revision: u64,
    from_z: i8,
    to_z: i8,
    settled: bool,
}

#[spacetimedb::table(accessor = scene)]
pub struct Scene {
    #[primary_key]
    id: u8,
    revision: u64,
}

#[spacetimedb::table(accessor = world_object)]
pub struct WorldObject {
    #[primary_key]
    serial: u32,
    graphic: u16,
    x: u16,
    y: u16,
    z: i8,
    home_x: u16,
    home_y: u16,
    is_door: bool,
    opened: bool,
}

#[spacetimedb::table(accessor = door_event)]
pub struct DoorEvent {
    #[primary_key]
    revision: u64,
    serial: u32,
    opened: bool,
}

fn authorize(ctx: &ReducerContext) -> Result<(), String> {
    let gateway = ctx.db.gateway().id().find(0).ok_or("missing gateway")?;
    if ctx.sender() != gateway.owner { return Err("unauthorized gateway".into()); }
    Ok(())
}

const BACKPACK: u32 = 0x40000100;
const BARREL: u32 = 0x40000002;

#[spacetimedb::table(accessor = inventory_state)]
pub struct InventoryState {
    #[primary_key]
    id: u8,
    revision: u64,
    next_serial: u32,
}

#[spacetimedb::table(accessor = inventory_item)]
pub struct InventoryItem {
    #[primary_key]
    serial: u32,
    graphic: u16,
    amount: u16,
    container: u32,
    x: u16,
    y: u16,
}

#[spacetimedb::table(accessor = inventory_event)]
pub struct InventoryEvent {
    #[primary_key]
    revision: u64,
    serial: u32,
    amount: u16,
    from_container: u32,
    to_container: u32,
    remainder_serial: u32,
}

#[spacetimedb::table(accessor = equipment_slot)]
pub struct EquipmentSlot {
    #[primary_key]
    serial: u32,
    layer: u8,
}

#[spacetimedb::table(accessor = equipment_event)]
pub struct EquipmentEvent {
    #[primary_key]
    revision: u64,
    serial: u32,
    layer: u8,
    displaced: Vec<u32>,
}

#[spacetimedb::table(accessor = starter_kit)]
pub struct StarterKit {
    #[primary_key]
    version: u8,
}

#[spacetimedb::table(accessor = ground_location)]
pub struct GroundLocation {
    #[primary_key]
    serial: u32,
    z: i8,
}

#[spacetimedb::table(accessor = item_action)]
pub struct ItemAction {
    #[primary_key]
    revision: u64,
    kind: String,
    serial: u32,
    target: u32,
    amount: u16,
    x: u16,
    y: u16,
    z: i8,
}

#[spacetimedb::table(accessor = nutrition)]
pub struct Nutrition {
    #[primary_key]
    serial: u32,
    fullness: u8,
    movement_revision: u64,
}

#[spacetimedb::reducer]
pub fn eat_item(ctx: &ReducerContext, expected_inventory: u64, expected_avatar: u64,
                expected_scene: u64, serial: u32) -> Result<(), String> {
    authorize(ctx)?;
    check_scene(ctx,expected_scene)?;
    let mut state = ctx.db.inventory_state().id().find(0).ok_or("missing inventory")?;
    if state.revision != expected_inventory { return Err("stale inventory".into()); }
    let avatar = ctx.db.avatar().serial().find(1).ok_or("missing avatar")?;
    if avatar.revision != expected_avatar { return Err("stale avatar".into()); }
    let mut item = ctx.db.inventory_item().serial().find(serial).ok_or("unknown item")?;
    check_source(ctx,&avatar,&item)?;
    if ![0x9d0,0x9f2].contains(&item.graphic) || item.amount == 0 { return Err("not edible".into()); }
    // Simple travel-based appetite, not a simulation of the original UO rules.
    let current = ctx.db.nutrition().serial().find(1);
    let fullness = current.as_ref().map_or(0,|n|
        n.fullness.saturating_sub(((avatar.revision.saturating_sub(n.movement_revision))/100).min(20) as u8));
    if fullness >= 20 { return Err("you are full".into()); }
    let needs = Nutrition {serial:1,fullness:(fullness+4).min(20),movement_revision:avatar.revision};
    if current.is_some() { ctx.db.nutrition().serial().update(needs); }
    else { ctx.db.nutrition().insert(needs); }
    let z = ctx.db.ground_location().serial().find(serial).map_or(0,|l|l.z);
    state.revision += 1;
    ctx.db.item_action().insert(ItemAction {revision:state.revision,kind:"eat".into(),serial,
        target:0,amount:1,x:item.x,y:item.y,z});
    if item.container == 0 { touch_scene(ctx)?; }
    if item.amount == 1 {
        ctx.db.inventory_item().serial().delete(serial);
        ctx.db.ground_location().serial().delete(serial);
    } else {
        item.amount -= 1;
        ctx.db.inventory_item().serial().update(item);
    }
    ctx.db.inventory_state().id().update(state);
    Ok(())
}

fn check_ground(avatar: &Avatar, x: u16, y: u16, z: i8) -> Result<(), String> {
    if x >= 6143 || y >= 4095 || avatar.x.abs_diff(x).max(avatar.y.abs_diff(y)) > 2 ||
        (i16::from(avatar.z)-i16::from(z)).abs() > 16 { return Err("ground out of reach".into()); }
    Ok(())
}

fn touch_scene(ctx: &ReducerContext) -> Result<(), String> {
    let mut scene = ctx.db.scene().id().find(0).ok_or("missing scene")?;
    scene.revision += 1;
    ctx.db.scene().id().update(scene);
    Ok(())
}

// Explicit prototype catalogue, checked against the installed 1998 tiledata.
// Layer 2 includes shields and two-handed weapons; the hatchet needs both hands.
fn wearable(graphic: u16) -> Option<(u8,bool)> {
    match graphic {
        0xf51 | 0xf61 | 0xe86 | 0x13e3 => Some((1,false)),
        0x1b76 | 0x1b7a => Some((2,false)),
        0xf43 => Some((2,true)),
        0x170b => Some((3,false)),
        0x152e => Some((4,false)),
        0x1517 => Some((5,false)),
        0x140e => Some((6,false)),
        _ => None,
    }
}

#[spacetimedb::reducer]
pub fn seed_starter_kit(ctx: &ReducerContext) -> Result<(), String> {
    authorize(ctx)?;
    if ctx.db.starter_kit().version().find(1).is_some() { return Ok(()); }
    let mut state = ctx.db.inventory_state().id().find(0).ok_or("missing inventory")?;
    let kit = [(0x170b,3,1,50,70),(0x152e,4,1,70,70),(0x1517,5,1,90,70),
               (0x140e,0,1,50,90),(0x1b76,0,1,90,100),(0xf61,0,1,115,75),
               (0xf43,0,1,120,115),(0x9d0,0,5,55,120)];
    if ctx.db.inventory_item().iter().count()+kit.len() > 64 { return Err("starter kit needs inventory space".into()); }
    for (graphic,layer,amount,x,y) in kit {
        let serial = state.next_serial;
        state.next_serial += 1;
        // Never replace equipment an existing player has already chosen.
        let wear = layer != 0 && !ctx.db.equipment_slot().iter().any(|s| s.layer == layer);
        ctx.db.inventory_item().insert(InventoryItem { serial,graphic,amount,
            container:if wear {1} else {BACKPACK},x,y });
        if wear { ctx.db.equipment_slot().insert(EquipmentSlot {serial,layer}); }
    }
    state.revision += 1;
    ctx.db.inventory_state().id().update(state);
    ctx.db.starter_kit().insert(StarterKit {version:1});
    Ok(())
}

fn check_source(ctx: &ReducerContext, avatar: &Avatar, item: &InventoryItem) -> Result<(), String> {
    if item.container == 0 {
        let location = ctx.db.ground_location().serial().find(item.serial).ok_or("missing ground location")?;
        return check_ground(avatar,item.x,item.y,location.z);
    }
    if item.container == 1 {
        ctx.db.equipment_slot().serial().find(item.serial).ok_or("missing equipment slot")?;
        return Ok(());
    }
    check_container(ctx,avatar,item.container)
}

#[spacetimedb::reducer]
pub fn equip_item(ctx: &ReducerContext, expected_inventory: u64, expected_avatar: u64,
                  expected_scene: u64, serial: u32, layer: u8, owner: u32) -> Result<(), String> {
    authorize(ctx)?;
    check_scene(ctx,expected_scene)?;
    if owner != 1 { return Err("not your equipment".into()); }
    let mut state = ctx.db.inventory_state().id().find(0).ok_or("missing inventory")?;
    if state.revision != expected_inventory { return Err("stale inventory".into()); }
    let avatar = ctx.db.avatar().serial().find(1).ok_or("missing avatar")?;
    if avatar.revision != expected_avatar { return Err("stale avatar".into()); }
    let mut item = ctx.db.inventory_item().serial().find(serial).ok_or("unknown item")?;
    check_source(ctx,&avatar,&item)?;
    let (correct_layer,two_hands) = wearable(item.graphic).ok_or("not wearable")?;
    if layer != correct_layer || item.amount != 1 { return Err("invalid equipment layer or quantity".into()); }
    let slots: Vec<_> = ctx.db.equipment_slot().iter().collect();
    let mut displaced = Vec::new();
    for slot in slots {
        if slot.serial == serial { continue; }
        let mut other = ctx.db.inventory_item().serial().find(slot.serial).ok_or("missing worn item")?;
        let other_two_hands = wearable(other.graphic).ok_or("invalid worn item")?.1;
        if slot.layer == layer || (two_hands && slot.layer == 1) || (layer == 1 && other_two_hands) {
            other.container=BACKPACK; other.x=65; other.y=85;
            ctx.db.inventory_item().serial().update(other);
            ctx.db.equipment_slot().serial().delete(slot.serial);
            displaced.push(slot.serial);
        }
    }
    let source = item.container;
    if source == 0 {
        ctx.db.ground_location().serial().delete(serial);
        touch_scene(ctx)?;
    }
    item.container=1; item.x=0; item.y=0;
    ctx.db.inventory_item().serial().update(item);
    if ctx.db.equipment_slot().serial().find(serial).is_some() {
        ctx.db.equipment_slot().serial().update(EquipmentSlot {serial,layer});
    } else { ctx.db.equipment_slot().insert(EquipmentSlot {serial,layer}); }
    state.revision += 1;
    ctx.db.inventory_event().insert(InventoryEvent {revision:state.revision,serial,amount:1,
        from_container:source,to_container:1,remainder_serial:0});
    ctx.db.equipment_event().insert(EquipmentEvent {revision:state.revision,serial,layer,displaced});
    ctx.db.inventory_state().id().update(state);
    Ok(())
}

#[spacetimedb::reducer]
pub fn seed_inventory(ctx: &ReducerContext) -> Result<(), String> {
    authorize(ctx)?;
    if ctx.db.inventory_state().id().find(0).is_some() { return Ok(()); }
    ctx.db.world_object().serial().find(BARREL).ok_or("missing barrel")?;
    ctx.db.inventory_item().insert(InventoryItem { serial:0x40000101, graphic:0xeed,
        amount:100,container:BARREL,x:65,y:65 });
    ctx.db.inventory_item().insert(InventoryItem { serial:0x40000102, graphic:0xf51,
        amount:1,container:BACKPACK,x:75,y:75 });
    ctx.db.inventory_state().insert(InventoryState { id:0,revision:0,next_serial:0x40000103 });
    Ok(())
}

fn check_container(ctx: &ReducerContext, avatar: &Avatar, serial: u32) -> Result<(), String> {
    if serial == BACKPACK { return Ok(()); }
    if serial != BARREL { return Err("unsupported container".into()); }
    let barrel = ctx.db.world_object().serial().find(BARREL).ok_or("missing barrel")?;
    if avatar.x.abs_diff(barrel.x).max(avatar.y.abs_diff(barrel.y)) > 2 ||
        (i16::from(avatar.z)-i16::from(barrel.z)).abs() > 16 { return Err("barrel out of reach".into()); }
    Ok(())
}

// A lift reserves an item only in the connection. A successful drop is the
// single durable transaction, so disconnects cannot strand or duplicate items.
#[spacetimedb::reducer]
pub fn transfer_item(ctx: &ReducerContext, expected_inventory: u64, expected_avatar: u64,
                     expected_scene: u64, serial: u32, amount: u16,
                     container: u32, x: u16, y: u16) -> Result<(), String> {
    // Retain the original container reducer signature for existing callers.
    if container != BACKPACK && container != BARREL { return Err("unsupported container".into()); }
    place_item(ctx,expected_inventory,expected_avatar,expected_scene,serial,amount,container,x,y,0)
}

#[spacetimedb::reducer]
pub fn place_item(ctx: &ReducerContext, expected_inventory: u64, expected_avatar: u64,
                  expected_scene: u64, serial: u32, amount: u16,
                  container: u32, x: u16, y: u16, z: i8) -> Result<(), String> {
    authorize(ctx)?;
    check_scene(ctx, expected_scene)?;
    let mut state = ctx.db.inventory_state().id().find(0).ok_or("missing inventory")?;
    if state.revision != expected_inventory { return Err("stale inventory".into()); }
    let avatar = ctx.db.avatar().serial().find(1).ok_or("missing avatar")?;
    if avatar.revision != expected_avatar { return Err("stale avatar".into()); }
    let mut item = ctx.db.inventory_item().serial().find(serial).ok_or("unknown item")?;
    check_source(ctx, &avatar, &item)?;
    if amount == 0 || amount > item.amount { return Err("invalid amount".into()); }
    let from_container = item.container;
    if container != 0 && container != BACKPACK && container != BARREL {
        let mut target = ctx.db.inventory_item().serial().find(container).ok_or("unknown stack")?;
        check_source(ctx,&avatar,&target)?;
        if serial == target.serial || item.graphic != target.graphic ||
            ![0xeed,0x9d0,0x9f1,0x9f2,0x1bdd,0x19b8,0x1bf2].contains(&item.graphic) { return Err("incompatible stack".into()); }
        target.amount = target.amount.checked_add(amount).ok_or("stack full")?;
        let target_container = target.container;
        let target_z = ctx.db.ground_location().serial().find(target.serial).map_or(0,|l| l.z);
        ctx.db.item_action().insert(ItemAction {revision:state.revision+1,kind:"merge".into(),serial,
            target:target.serial,amount,x:target.x,y:target.y,z:target_z});
        ctx.db.inventory_item().serial().update(target);
        if item.amount == amount {
            ctx.db.inventory_item().serial().delete(serial);
            ctx.db.ground_location().serial().delete(serial);
        } else {
            item.amount -= amount;
            ctx.db.inventory_item().serial().update(item);
        }
        if from_container == 0 || target_container == 0 { touch_scene(ctx)?; }
        state.revision += 1;
        ctx.db.inventory_event().insert(InventoryEvent {revision:state.revision,serial,amount,
            from_container,to_container:target_container,remainder_serial:0});
        ctx.db.inventory_state().id().update(state);
        return Ok(());
    }
    if container == 0 {
        // The gateway validates support and obstacle reach from installed assets.
        check_ground(&avatar,x,y,z)?;
    } else {
        check_container(ctx, &avatar, container)?;
        let (min_x,max_x,min_y,max_y) = if container == BACKPACK { (44,140,65,140) } else { (33,98,36,139) };
        if !(min_x..=max_x).contains(&x) || !(min_y..=max_y).contains(&y) {
            return Err("invalid container position".into());
        }
    }
    let old_z = ctx.db.ground_location().serial().find(serial).map_or(0,|l| l.z);
    if from_container == 1 { ctx.db.equipment_slot().serial().delete(serial); }
    let mut remainder_serial = 0;
    if amount < item.amount {
        if ctx.db.inventory_item().iter().count() >= 64 { return Err("inventory full".into()); }
        remainder_serial = state.next_serial;
        state.next_serial = state.next_serial.checked_add(1).ok_or("serial exhausted")?;
        if state.next_serial >= 0x7fffffff { return Err("serial exhausted".into()); }
        ctx.db.inventory_item().insert(InventoryItem { serial:remainder_serial, graphic:item.graphic,
            amount:item.amount-amount,container:item.container,x:item.x,y:item.y });
        if from_container == 0 {
            ctx.db.ground_location().insert(GroundLocation {serial:remainder_serial,z:old_z});
        }
    }
    ctx.db.ground_location().serial().delete(serial);
    if container == 0 { ctx.db.ground_location().insert(GroundLocation {serial,z}); }
    if from_container == 0 || container == 0 { touch_scene(ctx)?; }
    item.amount=amount; item.container=container; item.x=x; item.y=y;
    ctx.db.inventory_item().serial().update(item);
    state.revision += 1;
    ctx.db.item_action().insert(ItemAction {revision:state.revision,kind:"place".into(),
        serial,target:container,amount,x,y,z});
    ctx.db.inventory_event().insert(InventoryEvent { revision:state.revision,serial,amount,
        from_container,to_container:container,remainder_serial });
    ctx.db.inventory_state().id().update(state);
    Ok(())
}

fn check_scene(ctx: &ReducerContext, expected: u64) -> Result<(), String> {
    let current = ctx.db.scene().id().find(0).ok_or("world objects not initialized")?;
    if current.revision != expected { return Err("stale world geometry".into()); }
    Ok(())
}

// Idempotent local-world decoration. Coordinates are chosen from asset-valid
// neighboring surfaces by the trusted gateway. Existing objects are retained.
#[spacetimedb::reducer]
pub fn seed_objects(ctx: &ReducerContext, x: u16, y: u16, z: i8,
                    barrel_x: u16, barrel_y: u16, barrel_z: i8) -> Result<(), String> {
    authorize(ctx)?;
    if ctx.db.world_object().serial().find(0x40000001).is_some() { return Ok(()); }
    let avatar = ctx.db.avatar().serial().find(1).ok_or("missing avatar")?;
    for (px, py, pz) in [(x,y,z), (barrel_x,barrel_y,barrel_z)] {
        if !(1..6142).contains(&px) || !(1..4094).contains(&py) ||
            avatar.x.abs_diff(px).max(avatar.y.abs_diff(py)) > 8 ||
            (avatar.x,avatar.y) == (px,py) || (i16::from(avatar.z)-i16::from(pz)).abs() > 20 {
            return Err("invalid fixture placement".into());
        }
    }
    if (x,y)==(barrel_x,barrel_y) || (x-1,y+1)==(barrel_x,barrel_y) ||
        (x-1,y+1)==(avatar.x,avatar.y) { return Err("overlapping fixtures".into()); }
    ctx.db.world_object().insert(WorldObject { serial:0x40000001, graphic:0x675, x,y,z,
        home_x:x, home_y:y, is_door:true, opened:false });
    ctx.db.world_object().insert(WorldObject { serial:0x40000002, graphic:0xe77,
        x:barrel_x,y:barrel_y,z:barrel_z,home_x:barrel_x,home_y:barrel_y,is_door:false,opened:false });
    if let Some(mut scene) = ctx.db.scene().id().find(0) {
        scene.revision += 1; ctx.db.scene().id().update(scene);
    } else { ctx.db.scene().insert(Scene { id:0, revision:1 }); }
    Ok(())
}

#[spacetimedb::reducer]
pub fn use_door(ctx: &ReducerContext, expected_avatar: u64, expected_scene: u64, serial: u32) -> Result<(), String> {
    authorize(ctx)?;
    check_scene(ctx,expected_scene)?;
    let avatar = ctx.db.avatar().serial().find(1).ok_or("missing avatar")?;
    if avatar.revision != expected_avatar { return Err("stale avatar".into()); }
    let mut door = ctx.db.world_object().serial().find(serial).ok_or("unknown object")?;
    if !door.is_door { return Err("not a door".into()); }
    if avatar.x.abs_diff(door.x).max(avatar.y.abs_diff(door.y)) > 2 ||
        (i16::from(avatar.z)-i16::from(door.z)).abs() > 16 { return Err("door out of reach".into()); }
    let opened = !door.opened;
    // Classic 0x675/0x676 pair swings west one tile and south one tile.
    let (x,y) = if opened { (door.home_x-1,door.home_y+1) } else { (door.home_x,door.home_y) };
    if (avatar.x,avatar.y) == (x,y) &&
        (i16::from(avatar.z)-i16::from(door.z)).abs() < 20 { return Err("door would hit player".into()); }
    if ctx.db.world_object().iter().any(|o| o.serial != serial && (o.x,o.y)==(x,y) &&
        (i16::from(o.z)-i16::from(door.z)).abs() < 20) { return Err("door would hit object".into()); }
    if ctx.db.inventory_item().iter().any(|o| o.container == 0 && (o.x,o.y)==(x,y) &&
        ctx.db.ground_location().serial().find(o.serial).is_some_and(|l|
            (i16::from(l.z)-i16::from(door.z)).abs() < 20)) { return Err("door would hit item".into()); }
    door.x=x; door.y=y; door.opened=opened; door.graphic=if opened {0x676} else {0x675};
    ctx.db.world_object().serial().update(door);
    let mut scene = ctx.db.scene().id().find(0).ok_or("missing scene")?;
    scene.revision += 1;
    ctx.db.door_event().insert(DoorEvent { revision:scene.revision,serial,opened });
    ctx.db.scene().id().update(scene);
    Ok(())
}

#[spacetimedb::reducer(init)]
pub fn init(ctx: &ReducerContext) {
    ctx.db.gateway().insert(Gateway { id: 0, owner: ctx.sender() });
    ctx.db.avatar().insert(Avatar {
        serial: 1, name: "Local Avatar".into(),
        x: 1435, y: 1695, z: 0, direction: 3, revision: 0,
    });
}

#[spacetimedb::reducer]
pub fn walk(ctx: &ReducerContext, expected_revision: u64, direction: u8, target_z: i8, expected_scene: u64) -> Result<(), String> {
    let gateway = ctx.db.gateway().id().find(0).ok_or("missing gateway")?;
    if ctx.sender() != gateway.owner { return Err("unauthorized gateway".into()); }
    check_scene(ctx,expected_scene)?;
    let mut avatar = ctx.db.avatar().serial().find(1).ok_or("missing avatar")?;
    if avatar.revision != expected_revision { return Err("stale revision".into()); }
    let (x, y) = destination(avatar.x, avatar.y, avatar.direction, direction)?;
    if avatar.direction & 7 != direction & 7 && target_z != avatar.z {
        return Err("a turn cannot change elevation".into());
    }
    // Only the owner gateway can invoke this reducer. It validates target_z
    // against the installed map/statics using UOCore before committing. The
    // expected revision ties that decision to the exact source position.
    ctx.db.movement_event().insert(MovementEvent {
        revision: avatar.revision + 1, from_x: avatar.x, from_y: avatar.y,
        to_x: x, to_y: y, direction,
    });
    ctx.db.movement_height().insert(MovementHeight {
        revision: avatar.revision + 1, from_z: avatar.z, to_z: target_z, settled: false,
    });
    avatar.x = x; avatar.y = y; avatar.z = target_z;
    avatar.direction = direction; avatar.revision += 1;
    ctx.db.avatar().serial().update(avatar);
    Ok(())
}

// Asset-backed placement on login, including recovery of old flat-world saves.
#[spacetimedb::reducer]
pub fn settle(ctx: &ReducerContext, expected_revision: u64, x: u16, y: u16, z: i8, expected_scene: u64) -> Result<(), String> {
    let gateway = ctx.db.gateway().id().find(0).ok_or("missing gateway")?;
    if ctx.sender() != gateway.owner { return Err("unauthorized gateway".into()); }
    check_scene(ctx,expected_scene)?;
    let mut avatar = ctx.db.avatar().serial().find(1).ok_or("missing avatar")?;
    if avatar.revision != expected_revision { return Err("stale revision".into()); }
    if x >= 6143 || y >= 4095 || avatar.x.abs_diff(x).max(avatar.y.abs_diff(y)) > 8 {
        return Err("invalid grounding destination".into());
    }
    if (avatar.x, avatar.y, avatar.z) == (x, y, z) { return Ok(()); }
    ctx.db.movement_event().insert(MovementEvent {
        revision: avatar.revision + 1, from_x: avatar.x, from_y: avatar.y,
        to_x: x, to_y: y, direction: avatar.direction,
    });
    ctx.db.movement_height().insert(MovementHeight {
        revision: avatar.revision + 1, from_z: avatar.z, to_z: z, settled: true,
    });
    avatar.x = x; avatar.y = y; avatar.z = z; avatar.revision += 1;
    ctx.db.avatar().serial().update(avatar);
    Ok(())
}

// Map edge checks remain in the transaction; terrain collision is gateway-owned.
fn destination(x: u16, y: u16, facing: u8, direction: u8) -> Result<(u16, u16), String> {
    if direction & !0x87 != 0 { return Err("invalid direction".into()); }
    if facing & 7 != direction & 7 { return Ok((x, y)); }
    let (dx, dy) = [(0,-1),(1,-1),(1,0),(1,1),(0,1),(-1,1),(-1,0),(-1,-1)][(direction & 7) as usize];
    let (x, y) = (i32::from(x) + dx, i32::from(y) + dy);
    if !(0..6143).contains(&x) || !(0..4095).contains(&y) {
        return Err("outside classic map".into());
    }
    Ok((x as u16, y as u16))
}

#[cfg(test)]
mod tests {
    use super::destination;
    #[test]
    fn turns_do_not_move_and_invalid_steps_fail() {
        assert_eq!(destination(1435,1695,3,2).unwrap(), (1435,1695));
        assert_eq!(destination(1435,1695,2,0x82).unwrap(), (1436,1695));
        assert_eq!(destination(1443,1695,2,2).unwrap(), (1444,1695));
        assert!(destination(6142,1695,2,2).is_err());
        assert!(destination(0,1695,6,6).is_err());
        assert!(destination(1435,1695,2,0x42).is_err());
    }
}
