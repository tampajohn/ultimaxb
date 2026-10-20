use super::*;

const RECOVERY_US:i64=30_000_000;

#[spacetimedb::table(accessor = vitality)]
pub struct Vitality {
    #[primary_key] pub serial:u32,
    pub health:u16, pub revision:u64, pub recover_at:i64,
}

#[spacetimedb::table(accessor = combat_event)]
pub struct CombatEvent {
    #[primary_key] revision:u64,
    kind:String, creature_revision:u64, protection:u16, damage:u16,
    remaining:u16, at:i64,
}

#[spacetimedb::reducer]
pub fn seed_vitality(ctx:&ReducerContext)->Result<(),String> {
    authorize(ctx)?;
    if ctx.db.vitality().serial().find(1).is_none() {
        ctx.db.vitality().insert(Vitality {serial:1,health:50,revision:0,recover_at:0});
    }
    Ok(())
}

pub(super) fn require_alive(ctx:&ReducerContext)->Result<(),String> {
    let vital=ctx.db.vitality().serial().find(1).ok_or("missing vitality")?;
    if vital.health==0 {return Err("You are defeated. Enter peace mode and say recover after thirty seconds.".into());}
    Ok(())
}

fn protection(layer:u8,graphic:u16)->u16 {
    match (layer,graphic) {(6,0x140e)=>1,(2,0x1b76 | 0x1b7a)=>2,_=>0}
}

pub(super) fn retaliate(ctx:&ReducerContext,creature_revision:u64)->Result<(),String> {
    let mut vital=ctx.db.vitality().serial().find(1).ok_or("missing vitality")?;
    let armor=ctx.db.equipment_slot().iter().filter_map(|slot|
        ctx.db.inventory_item().serial().find(slot.serial).filter(|i|i.container==1 && i.amount==1)
            .map(|i|protection(slot.layer,i.graphic))).sum::<u16>().min(3);
    let damage=(6-armor).min(vital.health);
    let now=ctx.timestamp.to_micros_since_unix_epoch();
    vital.health-=damage;vital.revision+=1;vital.recover_at=now+RECOVERY_US;
    ctx.db.combat_event().insert(CombatEvent {revision:vital.revision,kind:"retaliation".into(),
        creature_revision,protection:armor,damage,remaining:vital.health,at:now});
    ctx.db.vitality().serial().update(vital);
    Ok(())
}

#[spacetimedb::reducer]
pub fn recover_player(ctx:&ReducerContext,expected_vitality:u64)->Result<(),String> {
    authorize(ctx)?;
    let mut vital=ctx.db.vitality().serial().find(1).ok_or("missing vitality")?;
    let now=ctx.timestamp.to_micros_since_unix_epoch();
    if vital.revision!=expected_vitality || vital.health==50 || now<vital.recover_at {
        return Err("Recovery requires thirty seconds without incoming damage.".into());
    }
    vital.health=50;vital.revision+=1;vital.recover_at=0;
    ctx.db.combat_event().insert(CombatEvent {revision:vital.revision,kind:"recovery".into(),
        creature_revision:0,protection:0,damage:0,remaining:50,at:now});
    ctx.db.vitality().serial().update(vital);
    Ok(())
}

#[cfg(test)] mod tests {
    use super::*;
    #[test] fn only_supported_armor_in_correct_slots_protects() {
        assert_eq!(protection(6,0x140e),1);
        assert_eq!(protection(2,0x1b76),2);
        assert_eq!(protection(2,0x1b7a),2);
        assert_eq!(protection(1,0x1b76),0);
        assert_eq!(protection(2,0xf43),0);
    }
}
