use super::*;

#[spacetimedb::table(accessor = cooking_event)]
pub struct CookingEvent {
    #[primary_key] revision:u64,
    source:u32, output:u32, amount:u16,
    forge_x:u16, forge_y:u16, forge_z:i8,
}

// The owner gateway verifies the selected forge against installed world art,
// just as for smelting. Players have no direct reducer access.
#[spacetimedb::reducer]
pub fn cook_ribs(ctx:&ReducerContext, expected_inventory:u64, expected_avatar:u64,
    expected_scene:u64, source:u32, x:u16, y:u16, z:i8)->Result<(),String> {
    authorize(ctx)?;
    check_scene(ctx,expected_scene)?;
    let mut state=ctx.db.inventory_state().id().find(0).ok_or("missing inventory")?;
    let avatar=ctx.db.avatar().serial().find(1).ok_or("missing player")?;
    if state.revision!=expected_inventory || avatar.revision!=expected_avatar {
        return Err("stale cooking action".into());
    }
    check_ground(&avatar,x,y,z)?;
    let mut ingredient=ctx.db.inventory_item().serial().find(source).ok_or("missing ribs")?;
    if ingredient.container!=BACKPACK || ingredient.graphic!=0x9f1 || ingredient.amount==0 {
        return Err("use raw ribs in your backpack".into());
    }
    let amount=ingredient.amount;
    let mut destinations:Vec<_>=ctx.db.inventory_item().iter().filter(|i|
        i.container==BACKPACK && i.graphic==0x9f2 &&
        u32::from(i.amount)+u32::from(amount)<=65535).collect();
    destinations.sort_by_key(|i|i.serial);
    let output;
    if let Some(mut item)=destinations.into_iter().next() {
        output=item.serial;
        item.amount+=amount;
        ctx.db.inventory_item().serial().update(item);
        ctx.db.inventory_item().serial().delete(source);
    } else {
        // Transform in place: no additional inventory slot or serial required.
        output=source;
        ingredient.graphic=0x9f2;
        ctx.db.inventory_item().serial().update(ingredient);
    }
    state.revision+=1;
    ctx.db.cooking_event().insert(CookingEvent {revision:state.revision,source,output,amount,
        forge_x:x,forge_y:y,forge_z:z});
    ctx.db.inventory_state().id().update(state);
    Ok(())
}
