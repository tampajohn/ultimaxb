use super::*;
use crate::combat::vitality;

pub(super) const SECOND_PLAYER:u32=4;

#[spacetimedb::table(accessor = player_account)]
pub struct PlayerAccount {
    #[primary_key] pub serial:u32,
    #[unique] pub account:String,
    #[unique] pub identity:Identity,
    #[unique] pub backpack:u32,
}

#[spacetimedb::table(accessor = inventory_actor)]
pub struct InventoryActor {
    #[primary_key] revision:u64,
    player:u32,
}

#[spacetimedb::table(accessor = player_presence)]
pub struct PlayerPresence {
    #[primary_key] player:u32,
}

#[spacetimedb::reducer]
pub fn enter_world(ctx:&ReducerContext)->Result<(),String> {
    let player=actor(ctx)?;
    if ctx.db.player_presence().player().find(player).is_none() {
        ctx.db.player_presence().insert(PlayerPresence {player});
    }
    Ok(())
}

#[spacetimedb::reducer]
pub fn leave_world(ctx:&ReducerContext)->Result<(),String> {
    ctx.db.player_presence().player().delete(actor(ctx)?);
    Ok(())
}

#[spacetimedb::reducer]
pub fn reset_presence(ctx:&ReducerContext)->Result<(),String> {
    authorize_admin(ctx)?;
    for row in ctx.db.player_presence().iter() {
        ctx.db.player_presence().player().delete(row.player);
    }
    Ok(())
}

pub(super) fn occupied(ctx:&ReducerContext,x:u16,y:u16,z:i8,height:i16)->bool {
    ctx.db.player_presence().iter().filter_map(|p|ctx.db.avatar().serial().find(p.player))
        .any(|a|(a.x,a.y)==(x,y) && (i16::from(a.z)-i16::from(z)).abs()<height)
}

#[spacetimedb::table(accessor = player_movement)]
pub struct PlayerMovement {
    #[primary_key] key:String,
    player:u32, revision:u64,
    from_x:u16, from_y:u16, from_z:i8,
    to_x:u16, to_y:u16, to_z:i8,
    direction:u8, settled:bool,
}

pub(super) fn record_inventory(ctx:&ReducerContext,revision:u64)->Result<(),String> {
    ctx.db.inventory_actor().insert(InventoryActor {revision,player:actor(ctx)?});
    Ok(())
}

pub(super) fn record_movement(ctx:&ReducerContext,avatar:&Avatar,x:u16,y:u16,z:i8,direction:u8,settled:bool) {
    let revision=avatar.revision+1;
    ctx.db.player_movement().insert(PlayerMovement {key:format!("{}:{revision}",avatar.serial),
        player:avatar.serial,revision,from_x:avatar.x,from_y:avatar.y,from_z:avatar.z,
        to_x:x,to_y:y,to_z:z,direction,settled});
}

// Migration adds metadata only. Existing rows and inventory revisions do not
// change, and repeated startup never regenerates belongings.
#[spacetimedb::reducer]
pub fn seed_player_accounts(ctx:&ReducerContext)->Result<(),String> {
    authorize_admin(ctx)?;
    if ctx.db.player_account().serial().find(1).is_none() {
        let owner=ctx.db.gateway().id().find(0).ok_or("missing gateway")?.owner;
        ctx.db.avatar().serial().find(1).ok_or("missing original player")?;
        ctx.db.player_account().insert(PlayerAccount {serial:1,account:"local".into(),
            identity:owner,backpack:BACKPACK});
    }
    Ok(())
}

// The administrator supplies an asset-validated nearby standing point. This
// reducer is atomic: a failed registration cannot leave half a starter kit.
#[spacetimedb::reducer]
pub fn register_second_player(ctx:&ReducerContext,identity:String,x:u16,y:u16,z:i8)->Result<(),String> {
    authorize_admin(ctx)?;
    let identity=Identity::from_hex(identity).map_err(|_|"invalid player identity")?;
    let owner=ctx.db.gateway().id().find(0).ok_or("missing gateway")?.owner;
    if identity==owner {return Err("players need distinct identities".into());}
    if let Some(existing)=ctx.db.player_account().serial().find(SECOND_PLAYER) {
        return if existing.identity==identity {Ok(())} else {Err("second account already registered".into())};
    }
    ctx.db.player_account().serial().find(1).ok_or("initialize original account first")?;
    if ctx.db.avatar().serial().find(SECOND_PLAYER).is_some() {return Err("mobile serial occupied".into());}
    let original=ctx.db.avatar().serial().find(1).ok_or("missing original player")?;
    check_ground(&original,x,y,z)?;
    if (x,y)==(original.x,original.y) || ctx.db.world_object().iter().any(|o|(o.x,o.y)==(x,y)) ||
        ctx.db.inventory_item().iter().any(|i|i.container==0 && (i.x,i.y)==(x,y)) {
        return Err("second player site occupied".into());
    }
    let kit=[(0x170b,3,1),(0x152e,4,1),(0x1517,5,1),(0x140e,0,1),
        (0x1b76,0,1),(0xf61,0,1),(0xf43,0,1),(0x9d0,0,5),
        (0xf51,0,1),(0xe86,0,1),(0x13e3,0,1)];
    if ctx.db.inventory_item().iter().count()+kit.len()>64 {return Err("starter kit needs space".into());}
    let mut state=ctx.db.inventory_state().id().find(0).ok_or("missing inventory")?;
    let backpack=allocate(&mut state)?;
    for (graphic,layer,amount) in kit {
        let serial=allocate(&mut state)?;
        ctx.db.inventory_item().insert(InventoryItem {serial,graphic,amount,
            container:if layer==0 {backpack} else {SECOND_PLAYER},x:65,y:85});
        if layer!=0 {ctx.db.equipment_slot().insert(EquipmentSlot {serial,layer});}
    }
    ctx.db.avatar().insert(Avatar {serial:SECOND_PLAYER,name:"Local Adventurer".into(),
        x,y,z,direction:3,revision:0});
    ctx.db.player_account().insert(PlayerAccount {serial:SECOND_PLAYER,account:"local2".into(),identity,backpack});
    ctx.db.vitality().insert(combat::Vitality {serial:SECOND_PLAYER,health:50,revision:0,recover_at:0});
    state.revision+=1;
    ctx.db.inventory_actor().insert(InventoryActor {revision:state.revision,player:SECOND_PLAYER});
    ctx.db.inventory_state().id().update(state);
    Ok(())
}

fn allocate(state:&mut InventoryState)->Result<u32,String> {
    let serial=state.next_serial;
    state.next_serial=serial.checked_add(1).ok_or("serial exhausted")?;
    if state.next_serial>=0x7fffffff {return Err("serial exhausted".into());}
    Ok(serial)
}

pub(super) fn actor(ctx:&ReducerContext)->Result<u32,String> {
    let owner=ctx.db.gateway().id().find(0).ok_or("missing gateway")?.owner;
    if ctx.sender()==owner {return Ok(1);}
    ctx.db.player_account().identity().find(ctx.sender()).map(|p|p.serial).ok_or("unknown player identity".into())
}

pub(super) fn backpack(ctx:&ReducerContext,player:u32)->Result<u32,String> {
    if player==1 {return Ok(BACKPACK);}
    ctx.db.player_account().serial().find(player).map(|p|p.backpack).ok_or("unknown player".into())
}
