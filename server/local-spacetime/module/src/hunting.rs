use super::*;

const RESPAWN_US:i64=60_000_000;
const STRIKE_US:i64=2_000_000;

#[spacetimedb::table(accessor = creature)]
pub struct Creature {
    #[primary_key] serial:u32,
    x:u16,y:u16,z:i8,health:u16,revision:u64,life:u64,
    next_strike:i64,respawn_at:i64,
}
#[spacetimedb::table(accessor = hunting_event)]
pub struct HuntingEvent {
    #[primary_key] revision:u64,
    life:u64,weapon:u32,damage:u16,remaining:u16,loot:u32,at:i64,
}

fn damage(graphic:Option<u16>)->u16 {
    match graphic { Some(0xf61)=>5,Some(0xf51)=>3,Some(0xf43)=>4,_=>1 }
}
fn can_respawn(health:u16,deadline:i64,now:i64)->bool { health==0 && now>=deadline }

#[spacetimedb::reducer]
pub fn seed_creature(ctx:&ReducerContext,x:u16,y:u16,z:i8)->Result<(),String> {
    authorize(ctx)?;
    if ctx.db.creature().serial().find(3).is_some() {return Ok(());}
    let avatar=ctx.db.avatar().serial().find(1).ok_or("missing player")?;
    if x>=6143 || y>=4095 || avatar.x.abs_diff(x).max(avatar.y.abs_diff(y))>6 ||
        (i16::from(avatar.z)-i16::from(z)).abs()>16 {return Err("invalid creature site".into());}
    ctx.db.creature().insert(Creature {serial:3,x,y,z,health:20,revision:0,life:1,next_strike:0,respawn_at:0});
    Ok(())
}

#[spacetimedb::reducer]
pub fn strike_creature(ctx:&ReducerContext,expected_avatar:u64,expected_inventory:u64,
    expected_scene:u64,expected_creature:u64)->Result<(),String> {
    authorize(ctx)?;check_scene(ctx,expected_scene)?;
    let avatar=ctx.db.avatar().serial().find(1).ok_or("missing player")?;
    let mut state=ctx.db.inventory_state().id().find(0).ok_or("missing inventory")?;
    let mut creature=ctx.db.creature().serial().find(3).ok_or("missing creature")?;
    if avatar.revision!=expected_avatar || state.revision!=expected_inventory || creature.revision!=expected_creature {
        return Err("stale strike".into());
    }
    check_ground(&avatar,creature.x,creature.y,creature.z)?;
    if avatar.x.abs_diff(creature.x).max(avatar.y.abs_diff(creature.y))>1 || creature.health==0 {
        return Err("target unavailable".into());
    }
    let now=ctx.timestamp.to_micros_since_unix_epoch();
    if now<creature.next_strike {return Err("strike cooling down".into());}
    let mut weapons:Vec<_>=ctx.db.equipment_slot().iter().filter(|s|s.layer==1 || s.layer==2)
        .filter_map(|s|ctx.db.inventory_item().serial().find(s.serial))
        .filter(|i|i.container==1 && [0xf61,0xf51,0xf43].contains(&i.graphic)).collect();
    weapons.sort_by_key(|i|i.serial);
    let weapon=weapons.first();
    let hit=damage(weapon.map(|w|w.graphic)).min(creature.health);
    let mut loot=0;
    if hit==creature.health {
        if ctx.db.inventory_item().iter().count()>=64 {return Err("world item capacity reached".into());}
        loot=state.next_serial;
        state.next_serial=loot.checked_add(1).ok_or("serial exhausted")?;
        if state.next_serial>=0x7fffffff {return Err("serial exhausted".into());}
        ctx.db.inventory_item().insert(InventoryItem {serial:loot,graphic:0x9f1,amount:2,container:0,
            x:creature.x,y:creature.y});
        ctx.db.ground_location().insert(GroundLocation {serial:loot,z:creature.z});
        state.revision+=1;
        ctx.db.item_action().insert(ItemAction {revision:state.revision,kind:"hunt_loot".into(),serial:loot,
            target:3,amount:2,x:creature.x,y:creature.y,z:creature.z});
        ctx.db.inventory_state().id().update(state);
        touch_scene(ctx)?;
        creature.respawn_at=now+RESPAWN_US;
    }
    creature.health-=hit;creature.next_strike=now+STRIKE_US;creature.revision+=1;
    ctx.db.hunting_event().insert(HuntingEvent {revision:creature.revision,life:creature.life,
        weapon:weapon.map_or(0,|w|w.serial),damage:hit,remaining:creature.health,loot,at:now});
    ctx.db.creature().serial().update(creature);
    Ok(())
}

#[spacetimedb::reducer]
pub fn respawn_creature(ctx:&ReducerContext,expected_scene:u64,expected_creature:u64)->Result<(),String> {
    authorize(ctx)?;check_scene(ctx,expected_scene)?;
    let mut creature=ctx.db.creature().serial().find(3).ok_or("missing creature")?;
    if creature.revision!=expected_creature || !can_respawn(creature.health,creature.respawn_at,ctx.timestamp.to_micros_since_unix_epoch()) {
        return Err("respawn not ready".into());
    }
    let avatar=ctx.db.avatar().serial().find(1).ok_or("missing player")?;
    if (avatar.x,avatar.y)==(creature.x,creature.y) || ctx.db.world_object().iter().any(|o|(o.x,o.y)==(creature.x,creature.y)) ||
        ctx.db.inventory_item().iter().any(|i|i.container==0 && (i.x,i.y)==(creature.x,creature.y)) {
        return Err("respawn site occupied".into());
    }
    creature.health=20;creature.life+=1;creature.revision+=1;creature.next_strike=0;creature.respawn_at=0;
    ctx.db.creature().serial().update(creature);Ok(())
}

#[cfg(test)] mod tests {
    use super::*;
    #[test] fn weapons_and_respawn_deadline_are_bounded() {
        assert_eq!([damage(None),damage(Some(0xf51)),damage(Some(0xf43)),damage(Some(0xf61))],[1,3,4,5]);
        assert_eq!(damage(Some(0x1b7a)),1);
        assert!(!can_respawn(0,100,99));assert!(can_respawn(0,100,100));
        assert!(!can_respawn(1,100,200));
    }
}
