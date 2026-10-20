use super::*;

// Installed 1998 SKILLS.IDX IDs. Values are tenths; this sandbox grants 0.1
// per successful action, capped at 100.0. Skills do not gate existing recipes.
#[spacetimedb::table(accessor = skill_progress)]
pub struct SkillProgress {
    #[primary_key] id: u16,
    value: u16,
    actions: u64,
}

#[spacetimedb::table(accessor = skill_event)]
pub struct SkillEvent {
    #[primary_key] revision: u64,
    skill: u16,
    before: u16,
    after: u16,
}

#[spacetimedb::table(accessor = player_skill)]
pub struct PlayerSkill {
    #[primary_key] key:String,
    player:u32, id:u16, value:u16, actions:u64,
}

#[spacetimedb::table(accessor = player_skill_event)]
pub struct PlayerSkillEvent {
    #[primary_key] revision:u64,
    player:u32, skill:u16, before:u16, after:u16,
}

fn next_value(value: u16) -> u16 { value.saturating_add(1).min(1000) }

// Deliberately not a reducer: clients and the gateway cannot award arbitrary
// gains. Call only within the inventory transaction that performs the action.
pub(super) fn gain(ctx: &ReducerContext, revision: u64, id: u16) -> Result<(),String> {
    if ![7,11,44,45].contains(&id) { return Err("unsupported skill".into()); }
    let player=players::actor(ctx)?;
    if player!=1 {
        let key=format!("{player}:{id}");
        let old=ctx.db.player_skill().key().find(&key);
        let before=old.as_ref().map_or(0,|s|s.value);
        let value=next_value(before);
        let actions=old.as_ref().map_or(0,|s|s.actions).checked_add(1).ok_or("skill history exhausted")?;
        let progress=PlayerSkill {key,player,id,value,actions};
        if old.is_some() {ctx.db.player_skill().key().update(progress);}
        else {ctx.db.player_skill().insert(progress);}
        ctx.db.player_skill_event().insert(PlayerSkillEvent {revision,player,skill:id,before,after:value});
        return Ok(());
    }
    let old=ctx.db.skill_progress().id().find(id);
    let before=old.as_ref().map_or(0,|s|s.value);
    let value=next_value(before);
    let actions=old.as_ref().map_or(0,|s|s.actions).checked_add(1).ok_or("skill history exhausted")?;
    let progress=SkillProgress {id,value,actions};
    if old.is_some() { ctx.db.skill_progress().id().update(progress); }
    else { ctx.db.skill_progress().insert(progress); }
    ctx.db.skill_event().insert(SkillEvent {revision,skill:id,before,after:value});
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn gains_are_tenths_and_cannot_exceed_the_cap() {
        assert_eq!(next_value(0),1);
        assert_eq!(next_value(998),999);
        assert_eq!(next_value(999),1000);
        assert_eq!(next_value(1000),1000);
        assert_eq!(next_value(u16::MAX),1000);
        let mut value=0;
        for _ in 0..10000 { value=next_value(value); }
        assert_eq!(value,1000);
    }
}
