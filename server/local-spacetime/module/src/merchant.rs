use super::*;

#[spacetimedb::table(accessor = merchant)]
pub struct Merchant {
    #[primary_key] serial: u32,
    x: u16, y: u16, z: i8,
    stock: u16, gold: u32, revision: u64,
}

#[spacetimedb::table(accessor = purchase_event)]
pub struct PurchaseEvent {
    #[primary_key] revision: u64,
    merchant: u32, quantity: u16, paid: u32, output: u32,
}

#[spacetimedb::reducer]
pub fn seed_merchant(ctx: &ReducerContext, x: u16, y: u16, z: i8) -> Result<(),String> {
    authorize(ctx)?;
    if ctx.db.merchant().serial().find(2).is_some() { return Ok(()); }
    let avatar=ctx.db.avatar().serial().find(1).ok_or("missing player")?;
    check_ground(&avatar,x,y,z)?;
    if (x,y)==(avatar.x,avatar.y) || ctx.db.world_object().iter().any(|o|
        (o.x,o.y)==(x,y) || (o.home_x,o.home_y)==(x,y) ||
        (o.is_door && (o.home_x.saturating_sub(1),o.home_y+1)==(x,y))) {
        return Err("occupied merchant site".into());
    }
    ctx.db.merchant().insert(Merchant {serial:2,x,y,z,stock:20,gold:0,revision:0});
    Ok(())
}

#[spacetimedb::reducer]
pub fn buy_apples(ctx: &ReducerContext, inventory: u64, avatar_revision: u64,
    scene: u64, merchant_revision: u64, quantity: u16) -> Result<(),String> {
    authorize(ctx)?;
    check_scene(ctx,scene)?;
    let avatar=ctx.db.avatar().serial().find(1).ok_or("missing player")?;
    let mut state=ctx.db.inventory_state().id().find(0).ok_or("missing inventory")?;
    let mut vendor=ctx.db.merchant().serial().find(2).ok_or("missing merchant")?;
    if state.revision!=inventory || avatar.revision!=avatar_revision || vendor.revision!=merchant_revision {
        return Err("stale purchase".into());
    }
    check_ground(&avatar,vendor.x,vendor.y,vendor.z)?;
    if quantity==0 || quantity>vendor.stock { return Err("stock unavailable".into()); }
    let price=u32::from(quantity)*3;
    let mut coins:Vec<_>=ctx.db.inventory_item().iter().filter(|i|i.container==BACKPACK && i.graphic==0xeed).collect();
    coins.sort_by_key(|i|i.serial);
    if coins.iter().map(|i|u32::from(i.amount)).sum::<u32>()<price { return Err("not enough gold".into()); }
    let mut unpaid=price;
    for mut item in coins {
        let paid=unpaid.min(u32::from(item.amount));
        if paid==0 { break; }
        unpaid-=paid;
        if paid==u32::from(item.amount) { ctx.db.inventory_item().serial().delete(item.serial); }
        else { item.amount-=paid as u16; ctx.db.inventory_item().serial().update(item); }
    }
    let mut apples:Vec<_>=ctx.db.inventory_item().iter().filter(|i| i.container==BACKPACK &&
        i.graphic==0x9d0 && u32::from(i.amount)+u32::from(quantity)<=65535).collect();
    apples.sort_by_key(|i|i.serial);
    let output;
    if let Some(mut item)=apples.into_iter().next() {
        output=item.serial; item.amount+=quantity; ctx.db.inventory_item().serial().update(item);
    } else {
        // Errors roll back coin deductions along with the rest of this reducer.
        if ctx.db.inventory_item().iter().count()>=64 { return Err("inventory full".into()); }
        output=state.next_serial;
        state.next_serial=output.checked_add(1).ok_or("serial exhausted")?;
        if state.next_serial>=0x7fffffff { return Err("serial exhausted".into()); }
        ctx.db.inventory_item().insert(InventoryItem {serial:output,graphic:0x9d0,amount:quantity,
            container:BACKPACK,x:55,y:120});
    }
    vendor.stock-=quantity;
    vendor.gold=vendor.gold.checked_add(price).ok_or("merchant purse full")?;
    vendor.revision+=1;
    state.revision+=1;
    ctx.db.purchase_event().insert(PurchaseEvent {revision:state.revision,merchant:2,quantity,paid:price,output});
    ctx.db.merchant().serial().update(vendor);
    ctx.db.inventory_state().id().update(state);
    Ok(())
}

#[spacetimedb::table(accessor = merchant_goods)]
pub struct MerchantGoods {
    #[primary_key] graphic: u16,
    amount: u32,
}

#[spacetimedb::table(accessor = sale_event)]
pub struct SaleEvent {
    #[primary_key] revision: u64,
    merchant: u32, source: u32, quantity: u16, paid: u32, output: u32,
}

#[spacetimedb::reducer]
pub fn sell_logs(ctx: &ReducerContext, inventory: u64, avatar_revision: u64,
    scene: u64, merchant_revision: u64, source: u32, quantity: u16) -> Result<(),String> {
    authorize(ctx)?;
    check_scene(ctx,scene)?;
    let avatar=ctx.db.avatar().serial().find(1).ok_or("missing player")?;
    let mut state=ctx.db.inventory_state().id().find(0).ok_or("missing inventory")?;
    let mut vendor=ctx.db.merchant().serial().find(2).ok_or("missing merchant")?;
    if state.revision!=inventory || avatar.revision!=avatar_revision || vendor.revision!=merchant_revision {
        return Err("stale sale".into());
    }
    check_ground(&avatar,vendor.x,vendor.y,vendor.z)?;
    let mut logs=ctx.db.inventory_item().serial().find(source).ok_or("missing goods")?;
    if logs.container!=BACKPACK || logs.graphic!=0x1bdd || quantity==0 || quantity>logs.amount {
        return Err("invalid goods".into());
    }
    let paid=u32::from(quantity);
    if paid>vendor.gold { return Err("merchant cannot afford sale".into()); }
    let old=ctx.db.merchant_goods().graphic().find(0x1bdd);
    let amount=old.as_ref().map_or(0,|g|g.amount).checked_add(paid).ok_or("merchant storage full")?;
    if logs.amount==quantity { ctx.db.inventory_item().serial().delete(source); }
    else { logs.amount-=quantity; ctx.db.inventory_item().serial().update(logs); }
    let mut coins:Vec<_>=ctx.db.inventory_item().iter().filter(|i| i.container==BACKPACK &&
        i.graphic==0xeed && u32::from(i.amount)+paid<=65535).collect();
    coins.sort_by_key(|i|i.serial);
    let output;
    if let Some(mut item)=coins.into_iter().next() {
        output=item.serial; item.amount+=quantity; ctx.db.inventory_item().serial().update(item);
    } else {
        if ctx.db.inventory_item().iter().count()>=64 { return Err("inventory full".into()); }
        output=state.next_serial;
        state.next_serial=output.checked_add(1).ok_or("serial exhausted")?;
        if state.next_serial>=0x7fffffff { return Err("serial exhausted".into()); }
        ctx.db.inventory_item().insert(InventoryItem {serial:output,graphic:0xeed,amount:quantity,
            container:BACKPACK,x:65,y:65});
    }
    let goods=MerchantGoods {graphic:0x1bdd,amount};
    if old.is_some() { ctx.db.merchant_goods().graphic().update(goods); }
    else { ctx.db.merchant_goods().insert(goods); }
    vendor.gold-=paid; vendor.revision+=1; state.revision+=1;
    ctx.db.sale_event().insert(SaleEvent {revision:state.revision,merchant:2,source,quantity,paid,output});
    ctx.db.merchant().serial().update(vendor);
    ctx.db.inventory_state().id().update(state);
    Ok(())
}
