"""HTTP transport for one owner gateway with commit-triggered session notifications.
Multiple gateways will require DB subscriptions. A database failure fails the operation.
"""
import json
import time
from collections import deque
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from urllib.parse import quote, urlparse
from navigation import NavigationError


class BackendError(RuntimeError):
    pass


BACKPACK = 0x40000100
BARREL = 0x40000002
FORGE = 0x40000003
ITEMS = {
    0xeed: ('Gold',None), 0xf51: ('Dagger',1), 0x170b: ('Boots',3),
    0x152e: ('Short pants',4), 0x1517: ('Shirt',5), 0x140e: ('Nose helm',6),
    0x1b76: ('Heater shield',2), 0xf61: ('Longsword',1), 0xf43: ('Hatchet',2),
    0xe86: ('Pickaxe',1), 0x13e3: ("Smith's hammer",1),
    0x19b8: ('Iron ore',None), 0x1bf2: ('Iron ingots',None),
    0x9f1: ('Raw ribs',None), 0x9f2: ('Cooked ribs',None), 0x9d0: ('Apple',None), 0x1bdd: ('Logs',None), 0x1b7a: ('Wooden shield',2),
}


class Backend:
    def __init__(self, endpoint, database, token, navigation=None, player=1, backpack=BACKPACK, write_token=None):
        parsed = urlparse(endpoint)
        if parsed.scheme != 'http' or parsed.hostname != '127.0.0.1':
            raise ValueError('this prototype requires a loopback SpacetimeDB endpoint')
        self.endpoint = endpoint.rstrip('/')
        self.database = database
        self.token = token
        self.write_token = write_token or token
        self.player = player
        self.backpack = backpack
        self.navigation = navigation
        self.on_change = None

    def request(self, path, data=None, method='POST', content_type='application/json'):
        req = Request(self.endpoint + path, data=data, method=method,
                      headers={'Authorization': 'Bearer ' + (self.write_token if '/call/' in path else self.token),
                               'Content-Type': content_type})
        try:
            with urlopen(req, timeout=5) as response:
                return response.read()
        except HTTPError as error:
            # Do not log tokens, request bodies, or potentially private replies.
            code = error.code
            error.close()
            raise BackendError(f'SpacetimeDB rejected request (HTTP {code})') from None
        except OSError:
            raise BackendError('SpacetimeDB unavailable') from None
        finally:
            if '/call/' in path and self.on_change is not None:
                self.on_change(self.player)

    @property
    def path(self):
        return '/v1/database/' + quote(self.database, safe='')

    def avatar(self):
        result = json.loads(self.request(self.path + '/sql',
            f'SELECT serial, name, x, y, z, direction, revision FROM avatar WHERE serial = {self.player}'.encode(),
            content_type='text/plain'))
        rows = result[0]['rows']
        if len(rows) != 1:
            raise BackendError('expected exactly one local avatar')
        return dict(zip(('serial', 'name', 'x', 'y', 'z', 'direction', 'revision'), rows[0]))

    def walk(self, revision, direction):
        avatar = self.avatar()
        scene_revision, objects = self.world()
        if avatar['revision'] != revision or direction < 0 or direction & ~0x87:
            raise BackendError('Stale revision or invalid direction')
        if self.navigation is None:
            raise BackendError('Movement requires asset-backed navigation')
        if avatar['direction'] & 7 != direction & 7:
            target = avatar
        else:
            try:
                target = self.navigation.query('step', avatar, direction, objects=objects)
            except NavigationError as error:
                raise BackendError(str(error)) from error
            if target is None:
                raise BackendError('Blocked by terrain or obstacle')
        self.request(self.path + '/call/walk', json.dumps([revision, direction, target['z'], scene_revision]).encode())
        return self.avatar()

    def settle(self):
        avatar = self.avatar()
        scene_revision, objects = self.world()
        if self.navigation is None:
            raise BackendError('World entry requires asset-backed navigation')
        try:
            target = self.navigation.query('settle', avatar, objects=objects)
        except NavigationError as error:
            raise BackendError(str(error)) from error
        if target is None:
            raise BackendError('No safe standing point near saved position')
        if any(target[key] != avatar[key] for key in ('x', 'y', 'z')):
            self.request(self.path + '/call/settle', json.dumps([
                avatar['revision'], target['x'], target['y'], target['z'], scene_revision]).encode())
            return self.avatar()
        return avatar

    def _revision(self,table):
        rows=json.loads(self.request(self.path+'/sql',
            f'SELECT revision FROM {table} WHERE id = 0'.encode(),content_type='text/plain'))[0]['rows']
        return rows[0][0] if rows else 0

    def stable_snapshot(self,table,read):
        # Multiple SQL requests can straddle a committed transfer. Retry reads
        # only when a revision proves that happened; never replay a mutation.
        for _ in range(5):
            before=self._revision(table)
            try:result=read()
            except BackendError:
                if self._revision(table)!=before:continue
                raise
            if self._revision(table)==before:return result
        raise BackendError('The world changed repeatedly. Try again.')

    def world(self):
        return self.stable_snapshot('scene',self._world_snapshot)

    def _world_snapshot(self):
        # Read revision BEFORE geometry. A concurrent change either appears in
        # this snapshot or causes the reducer's expected_scene check to fail.
        result = json.loads(self.request(self.path + '/sql',
            b'SELECT revision FROM scene WHERE id = 0', content_type='text/plain'))
        revision = result[0]['rows'][0][0] if result[0]['rows'] else 0
        result = json.loads(self.request(self.path + '/sql',
            b'SELECT serial, graphic, x, y, z, home_x, home_y, is_door, opened FROM world_object',
            content_type='text/plain'))
        keys = ('serial', 'graphic', 'x', 'y', 'z', 'home_x', 'home_y', 'is_door', 'opened')
        objects = [dict(zip(keys, row)) for row in result[0]['rows']]
        locations = self.ground_locations()
        result = json.loads(self.request(self.path + '/sql',
            b'SELECT serial, graphic, amount, x, y FROM inventory_item WHERE container = 0',content_type='text/plain'))
        for serial,graphic,amount,x,y in result[0]['rows']:
            if serial not in locations:
                raise BackendError('Ground item lacks elevation')
            objects.append(dict(serial=serial,graphic=graphic,amount=amount,x=x,y=y,z=locations[serial],
                                home_x=x,home_y=y,is_door=False,opened=False,movable=True))
        if len(objects) > 128:
            raise BackendError('World exceeds current dynamic-object limit')
        return revision, sorted(objects, key=lambda item: item['serial'])

    def prepare(self):
        if self.player!=1:
            raise BackendError('Only the administrator initializes world fixtures.')
        self.prepare_objects()
        self.request(self.path + '/call/seed_inventory', b'[]')
        self.request(self.path + '/call/seed_starter_kit', b'[]')
        self.request(self.path + '/call/seed_mining_kit', b'[]')
        self.prepare_merchant()
        self.prepare_forge()
        self.prepare_creature()
        self.request(self.path+'/call/seed_vitality',b'[]')
        self.request(self.path+'/call/seed_player_accounts',b'[]')

    def avatars(self):
        return sorted(json.loads(self.request(self.path+'/sql',b'SELECT * FROM avatar',content_type='text/plain'))[0]['rows'])

    def multiplayer_state(self):
        tables=('player_account','player_presence','avatar','nutrition','vitality','harvest_clock','melee_clock',
                'player_skill','player_skill_event','player_movement','player_combat_event',
                'inventory_actor','hunting_actor')
        return {table:sorted(json.loads(self.request(self.path+'/sql',('SELECT * FROM '+table).encode(),
            content_type='text/plain'))[0]['rows']) for table in tables}

    def player_accounts(self):
        return json.loads(self.request(self.path+'/sql',b'SELECT * FROM player_account',content_type='text/plain'))[0]['rows']

    def vitality(self):
        rows=json.loads(self.request(self.path+'/sql',f'SELECT * FROM vitality WHERE serial = {self.player}'.encode(),content_type='text/plain'))[0]['rows']
        return dict(zip(('serial','health','revision','recover_at'),rows[0]))

    def combat_state(self):
        queries={
            'vitality':f'SELECT * FROM vitality WHERE serial = {self.player}',
            'combat_event':('SELECT * FROM combat_event' if self.player==1 else
                f'SELECT revision, kind, creature_revision, protection, damage, remaining, at FROM player_combat_event WHERE player = {self.player}')}
        return {name:sorted(json.loads(self.request(self.path+'/sql',sql.encode(),
            content_type='text/plain'))[0]['rows']) for name,sql in queries.items()}

    def melee_deadline(self):
        rows=json.loads(self.request(self.path+'/sql',
            f'SELECT next_strike FROM melee_clock WHERE player = {self.player}'.encode(),
            content_type='text/plain'))[0]['rows']
        return rows[0][0] if rows else (self.creature()['next_strike'] if self.player==1 else 0)

    def recover(self):
        vital=self.vitality()
        self.request(self.path+'/call/recover_player',json.dumps([vital['revision']]).encode())

    def creature(self):
        rows=json.loads(self.request(self.path+'/sql',b'SELECT * FROM creature',content_type='text/plain'))[0]['rows']
        return dict(zip(('serial','x','y','z','health','revision','life','next_strike','respawn_at'),rows[0])) if rows else None

    def hunting_state(self):
        return {table:sorted(json.loads(self.request(self.path+'/sql',('SELECT * FROM '+table).encode(),
            content_type='text/plain'))[0]['rows']) for table in ('creature','hunting_event')}

    def prepare_creature(self):
        if self.creature() is not None:return
        if self.navigation is None:raise BackendError('Creature placement requires assets.')
        avatar=self.avatar();objects=self.world()[1];vendor=self.merchant()
        reserved={(o['x'],o['y']) for o in objects}
        if vendor:reserved.add((vendor['x'],vendor['y']))
        start=self.navigation.query('settle',avatar,objects=objects)
        if start is None:raise BackendError('No creature site.')
        queue,seen=deque([start]),set()
        for _ in range(400):
            if not queue:break
            p=queue.popleft();key=tuple(p[k] for k in ('x','y','z'))
            if key in seen:continue
            seen.add(key)
            distance=max(abs(p['x']-avatar['x']),abs(p['y']-avatar['y']))
            if distance==4 and (p['x'],p['y']) not in reserved and abs(p['z']-avatar['z'])<=16:
                self.request(self.path+'/call/seed_creature',json.dumps(list(key)).encode());return
            for direction in range(8):
                target=self.navigation.query('step',p,direction,objects=objects)
                if target and max(abs(target['x']-avatar['x']),abs(target['y']-avatar['y']))<=5:queue.append(target)
        raise BackendError('No reachable creature site.')

    def refresh_creature(self):
        creature=self.creature()
        if creature and creature['health']==0 and int(time.time()*1_000_000)>=creature['respawn_at']:
            scene,objects=self.world();avatar=self.avatar()
            occupied=any((o['x'],o['y'])==(creature['x'],creature['y']) for o in objects)
            if not occupied and (avatar['x'],avatar['y'])!=(creature['x'],creature['y']):
                if self.navigation and self.navigation.query('stand',creature,objects=objects)=={k:creature[k] for k in ('x','y','z')}:
                    try:self.request(self.path+'/call/respawn_creature',json.dumps([scene,creature['revision']]).encode())
                    except BackendError:pass # Never retry an uncertain write.
                    creature=self.creature()
        return creature

    def strike_creature(self):
        avatar=self.avatar();revision,_=self.inventory();scene,objects=self.world();creature=self.creature()
        if self.vitality()['health']==0:raise BackendError('You are defeated. Enter peace mode and say recover after thirty seconds.')
        if creature is None or creature['health']==0:raise BackendError('Target is dead.')
        if max(abs(avatar['x']-creature['x']),abs(avatar['y']-creature['y']))>1:raise BackendError('Move closer to strike.')
        self.check_reach(creature,avatar,objects)
        if int(time.time()*1_000_000)<self.melee_deadline():return None
        self.request(self.path+'/call/strike_creature',json.dumps([avatar['revision'],revision,scene,creature['revision']]).encode())
        return self.creature()

    def prepare_forge(self):
        scene,objects=self.world()
        if any(o['serial']==FORGE for o in objects): return
        if self.navigation is None: raise BackendError('Forge placement requires world assets.')
        avatar=self.avatar(); vendor=self.merchant()
        reserved={(o['x'],o['y']) for o in objects}
        reserved.update((o['home_x'],o['home_y']) for o in objects)
        reserved.update((o['home_x']-1,o['home_y']+1) for o in objects if o['is_door'])
        if vendor: reserved.add((vendor['x'],vendor['y']))
        start=self.navigation.query('settle',avatar,objects=objects)
        if start is None: raise BackendError('No safe forge site.')
        queue,seen=deque([start]),set()
        for _ in range(100):
            if not queue: break
            point=queue.popleft(); key=tuple(point[k] for k in ('x','y','z'))
            if key in seen: continue
            seen.add(key)
            distance=max(abs(point['x']-avatar['x']),abs(point['y']-avatar['y']))
            if distance==2 and (point['x'],point['y']) not in reserved and abs(point['z']-avatar['z'])<=16:
                proposed=objects+[dict(point,serial=FORGE,graphic=0xfb1)]
                try: self.check_reach(point,avatar,proposed)
                except BackendError: pass
                else:
                    self.request(self.path+'/call/seed_forge',json.dumps([scene,*key]).encode())
                    return
            for direction in range(8):
                next_point=self.navigation.query('step',point,direction,objects=objects)
                if next_point and max(abs(next_point['x']-avatar['x']),abs(next_point['y']-avatar['y']))<=2:
                    queue.append(next_point)
        raise BackendError('No safe reachable forge site.')

    def merchant(self):
        rows=json.loads(self.request(self.path+'/sql',b'SELECT * FROM merchant',content_type='text/plain'))[0]['rows']
        return dict(zip(('serial','x','y','z','stock','gold','revision'),rows[0])) if rows else None

    def merchant_state(self):
        return {table:json.loads(self.request(self.path+'/sql',('SELECT * FROM '+table).encode(),
                content_type='text/plain'))[0]['rows'] for table in ('merchant','purchase_event','merchant_goods','sale_event')}

    def prepare_merchant(self):
        if self.merchant() is not None: return
        if self.navigation is None: raise BackendError('Merchant placement requires world assets.')
        avatar=self.avatar()
        _,objects=self.world()
        start=self.navigation.query('settle',avatar,objects=objects)
        if start is None: raise BackendError('No safe merchant site.')
        queue,seen=deque([start]),set()
        for _ in range(80):
            if not queue: break
            point=queue.popleft()
            key=tuple(point[k] for k in ('x','y','z'))
            if key in seen: continue
            seen.add(key)
            distance=max(abs(point['x']-avatar['x']),abs(point['y']-avatar['y']))
            reserved={(o['x'],o['y']) for o in objects}
            reserved.update((o['home_x'],o['home_y']) for o in objects)
            reserved.update((o['home_x']-1,o['home_y']+1) for o in objects if o['is_door'])
            if distance==2 and (point['x'],point['y']) not in reserved and abs(point['z']-avatar['z'])<=16:
                self.request(self.path+'/call/seed_merchant',json.dumps(list(key)).encode())
                return
            for direction in range(8):
                next_point=self.navigation.query('step',point,direction,objects=objects)
                if next_point and max(abs(next_point['x']-avatar['x']),abs(next_point['y']-avatar['y']))<=2:
                    queue.append(next_point)
        raise BackendError('No safe merchant site within reach.')

    def merchant_quote(self):
        revision,_=self.inventory()
        vendor=self.merchant()
        if vendor is None: raise BackendError('Merchant unavailable.')
        self.check_reach(vendor,self.avatar(),self.world()[1])
        return dict(inventory=revision,vendor=vendor)

    def buy_apples(self,quote,quantity):
        avatar=self.avatar()
        scene,objects=self.world()
        self.check_reach(quote['vendor'],avatar,objects)
        self.request(self.path+'/call/buy_apples',json.dumps([quote['inventory'],avatar['revision'],scene,
            quote['vendor']['revision'],quantity]).encode())

    def merchant_sell_quote(self):
        revision,items=self.inventory()
        vendor=self.merchant()
        if vendor is None: raise BackendError('Merchant unavailable.')
        self.check_reach(vendor,self.avatar(),self.world()[1])
        logs=sorted((i for i in items if i['container']==self.backpack and i['graphic']==0x1bdd),key=lambda i:i['serial'])
        item=dict(logs[0],amount=min(logs[0]['amount'],vendor['gold'])) if logs and vendor['gold'] else None
        return dict(inventory=revision,vendor=vendor,item=item)

    def sell_logs(self,quote,serial,quantity):
        if quote['item'] is None or serial!=quote['item']['serial'] or quantity<=0 or quantity>quote['item']['amount']:
            raise BackendError('Choose the quoted logs and quantity.')
        avatar=self.avatar(); scene,objects=self.world()
        self.check_reach(quote['vendor'],avatar,objects)
        self.request(self.path+'/call/sell_logs',json.dumps([quote['inventory'],avatar['revision'],scene,
            quote['vendor']['revision'],serial,quantity]).encode())

    def prepare_objects(self):
        _, objects = self.world()
        if objects:
            return
        if self.navigation is None:
            raise BackendError('World preparation requires navigation')
        avatar = self.avatar()
        start = self.navigation.query('settle', avatar, objects=[])
        if start is None:
            raise BackendError('Cannot find a safe fixture site near saved avatar')
        queue, sites = deque([start]), []
        seen = {(start['x'], start['y'], start['z'])}
        for _ in range(160):
            if not queue:
                break
            point = queue.popleft()
            distance = max(abs(point['x']-avatar['x']), abs(point['y']-avatar['y']))
            if 2 <= distance <= 6:
                sites.append(point)
            for direction in range(8):
                target = self.navigation.query('step', point, direction)
                if target and max(abs(target['x']-avatar['x']), abs(target['y']-avatar['y'])) <= 6:
                    key = tuple(target[k] for k in ('x', 'y', 'z'))
                    if key not in seen:
                        seen.add(key)
                        queue.append(target)
        for door in sites:
            swing = dict(door, x=door['x']-1, y=door['y']+1)
            if (swing['x'], swing['y']) in [(avatar['x'],avatar['y']), (start['x'],start['y'])]:
                continue
            supported = self.navigation.query('stand', swing)
            if supported != swing:
                continue
            barrel = next((p for p in sites if (p['x'],p['y']) not in
                           [(door['x'],door['y']), (swing['x'],swing['y'])]), None)
            if barrel:
                self.request(self.path + '/call/seed_objects', json.dumps([
                    door['x'],door['y'],door['z'],barrel['x'],barrel['y'],barrel['z']]).encode())
                return
        raise BackendError('No safe neighboring door/barrel sites found')

    def inventory(self):
        return self.stable_snapshot('inventory_state',self._inventory_snapshot)

    def _inventory_snapshot(self):
        result = json.loads(self.request(self.path + '/sql',
            b'SELECT revision FROM inventory_state WHERE id = 0', content_type='text/plain'))
        if not result[0]['rows']:
            raise BackendError('Inventory not initialized')
        revision = result[0]['rows'][0][0]
        result = json.loads(self.request(self.path + '/sql',
            b'SELECT serial, graphic, amount, container, x, y FROM inventory_item', content_type='text/plain'))
        keys = ('serial','graphic','amount','container','x','y')
        items = [dict(zip(keys,row)) for row in result[0]['rows']]
        locations = self.ground_locations()
        for item in items:
            if item['container'] == 0:
                if item['serial'] not in locations:
                    raise BackendError('Ground item lacks elevation')
                item['z'] = locations[item['serial']]
        if len(items) > 64:
            raise BackendError('Inventory exceeds current limit')
        return revision, sorted(items,key=lambda item:item['serial'])

    def ground_locations(self):
        result = json.loads(self.request(self.path + '/sql',
            b'SELECT serial, z FROM ground_location',content_type='text/plain'))
        return dict(result[0]['rows'])

    def check_container(self, serial, avatar, objects):
        if serial == self.backpack:
            return
        if serial != BARREL or self.navigation is None:
            raise BackendError('Unsupported container')
        barrel = next((o for o in objects if o['serial'] == BARREL), None)
        if barrel is None:
            raise BackendError('Missing barrel')
        self.check_reach(barrel,avatar,objects)

    def check_reach(self, target, avatar, objects):
        if self.navigation is None or max(abs(avatar['x']-target['x']),abs(avatar['y']-target['y'])) > 2 or abs(avatar['z']-target['z']) > 16:
            raise BackendError('Item out of reach')
        def adjacent(point):
            dx,dy = target['x']-point['x'],target['y']-point['y']
            if max(abs(dx),abs(dy)) > 1 or abs(point['z']-target['z']) > 16:
                return False
            return not (dx and dy) or all(self.navigation.query('step',point,d,objects=objects)
                for d in (2 if dx > 0 else 6,4 if dy > 0 else 0))
        try:
            if adjacent(avatar):
                return
            for direction in range(8):
                point = self.navigation.query('step',avatar,direction,objects=objects)
                if point and adjacent(point):
                    return
        except NavigationError as error:
            raise BackendError(str(error)) from error
        raise BackendError('Cannot reach item through an obstacle')

    def container(self, serial):
        self.check_container(serial,self.avatar(),self.world()[1])
        return [item for item in self.inventory()[1] if item['container'] == serial]

    def equipment(self):
        return self.stable_snapshot('inventory_state',self._equipment_snapshot)

    def _equipment_snapshot(self):
        result = json.loads(self.request(self.path + '/sql',
            b'SELECT serial, layer FROM equipment_slot',content_type='text/plain'))
        slots = dict(result[0]['rows'])
        return [dict(item,layer=slots[item['serial']]) for item in self.inventory()[1]
                if item['container']==self.player and item['serial'] in slots]

    def check_source(self, item, avatar, objects):
        if item['container'] == 0:
            self.check_reach(item,avatar,objects)
            return
        if item['container'] == self.player:
            return
        self.check_container(item['container'],avatar,objects)

    def lift(self, serial, amount):
        revision, items = self.inventory()
        item = next((item for item in items if item['serial'] == serial),None)
        if item is None or not 1 <= amount <= item['amount']:
            raise BackendError('Invalid lift')
        self.check_source(item,self.avatar(),self.world()[1])
        return dict(revision=revision,item=item,amount=amount)

    def transfer(self, lift, serial, container, x, y, z=None):
        if serial != lift['item']['serial']:
            raise BackendError('Drop does not match lift')
        avatar = self.avatar()
        scene, objects = self.world()
        self.check_source(lift['item'],avatar,objects)
        if container == 0xffffffff:
            container = 0
            if max(abs(x-avatar['x']),abs(y-avatar['y'])) > 2 or self.navigation is None:
                raise BackendError('Ground too far away')
            others = [o for o in objects if o['serial'] != serial]
            try:
                target = self.navigation.query('stand',dict(x=x,y=y,z=avatar['z']),objects=others)
            except NavigationError as error:
                raise BackendError(str(error)) from error
            if target is None or (z is not None and target['z'] != z):
                raise BackendError('No supported ground at requested height')
            self.check_reach(target,avatar,others)
            z = target['z']
        elif container in (self.backpack,BARREL):
            self.check_container(container,avatar,objects)
            if x == 0xffff and y == 0xffff:
                x,y = 65,65
            bounds = (44,140,65,140) if container == self.backpack else (33,98,36,139)
            if not (bounds[0] <= x <= bounds[1] and bounds[2] <= y <= bounds[3]):
                raise BackendError('Place the item inside the container')
            z = 0
        else:
            target = next((i for i in self.inventory()[1] if i['serial']==container),None)
            if target is None:
                raise BackendError('Unknown target stack')
            self.check_source(target,avatar,objects)
            x,y,z = target['x'],target['y'],target.get('z',0)
        self.request(self.path + '/call/place_item',json.dumps([
            lift['revision'],avatar['revision'],scene,serial,lift['amount'],container,x,y,z]).encode())

    def equip(self, lift, serial, layer, owner):
        if serial != lift['item']['serial'] or lift['amount'] != 1 or owner != self.player:
            raise BackendError('Invalid equipment request')
        avatar = self.avatar()
        scene, objects = self.world()
        self.check_source(lift['item'],avatar,objects)
        self.request(self.path + '/call/equip_item',json.dumps([
            lift['revision'],avatar['revision'],scene,serial,layer,owner]).encode())

    def eat(self, lift):
        avatar = self.avatar()
        scene,objects = self.world()
        self.check_source(lift['item'],avatar,objects)
        self.request(self.path + '/call/eat_item',json.dumps([
            lift['revision'],avatar['revision'],scene,lift['item']['serial']]).encode())

    def nutrition(self):
        result = json.loads(self.request(self.path + '/sql',f'SELECT serial, fullness, movement_revision FROM nutrition WHERE serial = {self.player}'.encode(),
                                        content_type='text/plain'))
        return result[0]['rows']

    def player_status(self):
        avatar = self.avatar()
        avatar['health']=self.vitality()['health']
        avatar['max_health']=50
        avatar['gold'] = sum(item['amount'] for item in self.inventory()[1]
                             if item['container']==self.backpack and item['graphic']==0xeed)
        return avatar

    def skill_state(self):
        queries={'skill_progress':'SELECT * FROM skill_progress','skill_event':'SELECT * FROM skill_event'}
        if self.player!=1:
            queries={'skill_progress':f'SELECT id, value, actions FROM player_skill WHERE player = {self.player}',
                     'skill_event':f'SELECT revision, skill, before, after FROM player_skill_event WHERE player = {self.player}'}
        return {name:sorted(json.loads(self.request(self.path+'/sql',sql.encode(),
                content_type='text/plain'))[0]['rows']) for name,sql in queries.items()}

    def skills(self):
        rows=self.skill_state()['skill_progress']
        values={7:0,11:0,44:0,45:0}
        values.update({row[0]:row[1] for row in rows})
        return values

    def gathering_state(self, history=True):
        state = {}
        tables = ('resource_bank','harvest_clock','gathering_event','crafting_event','metal_event') if history else ('resource_bank','harvest_clock')
        for table in tables:
            result = json.loads(self.request(self.path + '/sql',('SELECT * FROM '+table).encode(),
                                            content_type='text/plain'))
            state[table] = sorted(result[0]['rows'])
        return state

    def cooking_state(self):
        return json.loads(self.request(self.path+'/sql',b'SELECT * FROM cooking_event',
            content_type='text/plain'))[0]['rows']

    def begin_tool(self, serial):
        held = self.lift(serial,1)
        item = held['item']
        if not ((item['container']==self.player and item['graphic'] in (0xf43,0xf51,0xe86,0x13e3)) or
                (item['container']==self.backpack and item['graphic'] in (0x19b8,0x9f1))):
            raise BackendError('Equip the tool or use backpack ore or raw ribs.')
        return dict(tool=serial,graphic=item['graphic'],revision=held['revision'])

    def perform_tool(self, context, target):
        revision,items = self.inventory()
        if revision != context['revision']:
            raise BackendError('Your inventory changed. Use the tool again.')
        avatar = self.avatar()
        scene,objects = self.world()
        tool = next((i for i in items if i['serial']==context['tool']),None)
        if tool is None or tool['container'] != (self.backpack if context['graphic'] in (0x19b8,0x9f1) else self.player) or tool['graphic'] != context['graphic']:
            raise BackendError('Equip the tool first.')
        args = [revision,avatar['revision'],scene,tool['serial']]
        if tool['graphic'] in (0xf43,0xe86):
            mining = tool['graphic']==0xe86
            if target['serial'] != 0 or max(abs(target['x']-avatar['x']),abs(target['y']-avatar['y'])) > 1:
                raise BackendError('That is too far away.')
            if self.navigation is None:
                raise BackendError('World assets are unavailable.')
            try:
                tree = self.navigation.query('ore' if mining else 'tree',target,objects=objects,graphic=target['graphic'])
            except NavigationError as error:
                raise BackendError(str(error)) from error
            if tree is None:
                raise BackendError("You cannot harvest that target.")
            self.check_reach(tree,avatar,objects)
            now = int(time.time()*1_000_000)
            state = self.gathering_state(history=False)
            bank_id = (target['x']//8*512 + target['y']//8) | (0x80000000 if mining else 0)
            if any(bank==bank_id and remaining<2 and now<refill
                   for bank,remaining,refill in state['resource_bank']):
                raise BackendError("There is no metal here to mine." if mining else "There's not enough wood here to harvest.")
            if any(player==self.player and now < next_at for player,next_at in state['harvest_clock']):
                raise BackendError('Let the tool recover for two seconds.')
            self.request(self.path+('/call/mine_ore' if mining else '/call/harvest_tree'),json.dumps(args+[
                target['x'],target['y'],target['z'],target['graphic']]).encode())
            return 'You dig some ore and put it in your backpack.' if mining else 'You put some logs in your backpack.'
        if tool['graphic'] in (0x19b8,0x13e3,0x9f1):
            if self.navigation is None:
                raise BackendError('World assets are unavailable.')
            smithing = tool['graphic']==0x13e3
            if smithing:
                ingredient = next((i for i in items if i['serial']==target['serial']),None)
                if ingredient is None or ingredient['container']!=self.backpack or ingredient['graphic']!=0x1bf2 or ingredient['amount']<5:
                    raise BackendError('Target at least five backpack ingots beside a forge.')
                forge = next((o for o in objects if o['serial']==FORGE and
                    max(abs(o['x']-avatar['x']),abs(o['y']-avatar['y']))<=2 and abs(o['z']-avatar['z'])<=16),None)
                if forge is None: forge = self.navigation.query('near_forge',avatar,objects=objects)
            else:
                ingredient = tool
                if max(abs(target['x']-avatar['x']),abs(target['y']-avatar['y']))>2:
                    raise BackendError('That is too far away.')
                if target['serial']==0:
                    forge = self.navigation.query('forge',target,objects=objects,graphic=target['graphic'])
                else:
                    forge = next((o for o in objects if o['serial']==FORGE and
                        all(o[k]==target[k] for k in ('serial','graphic','x','y','z'))),None)
            if forge is None:
                raise BackendError('You must be beside a forge.')
            try: self.check_reach(forge,avatar,objects)
            except BackendError: raise BackendError("You can't see that.") from None
            if tool['graphic']==0x9f1:
                self.request(self.path+'/call/cook_ribs',json.dumps([
                    revision,avatar['revision'],scene,ingredient['serial'],
                    forge['x'],forge['y'],forge['z']]).encode())
                return 'You cook the ribs and put them in your backpack.'
            self.request(self.path+'/call/work_metal',json.dumps([
                revision,avatar['revision'],scene,ingredient['serial'],tool['serial'] if smithing else 0,
                forge['x'],forge['y'],forge['z']]).encode())
            return ('You forge five iron ingots into a nose helm.' if smithing else
                    'You smelt the ore removing the impurities and put the metal in your backpack.')
        logs = next((i for i in items if i['serial']==target['serial']),None)
        if logs is None or logs['container'] != self.backpack or logs['graphic'] != 0x1bdd or logs['amount'] < 5:
            raise BackendError('Target a stack of at least five logs in your backpack.')
        self.request(self.path+'/call/carve_shield',json.dumps(args+[logs['serial']]).encode())
        return 'You carve five logs into a wooden shield.'

    def use_door(self, serial):
        avatar = self.avatar()
        revision, objects = self.world()
        door = next((item for item in objects if item['serial'] == serial), None)
        if door is None or not door['is_door']:
            raise BackendError('That object cannot be opened')
        if self.navigation is None:
            raise BackendError('Door interaction requires navigation')
        if max(abs(avatar['x']-door['x']),abs(avatar['y']-door['y'])) > 2 or abs(avatar['z']-door['z']) > 16:
            raise BackendError('That is too far away')
        # Conservative reach: a direct neighboring tile or one unobstructed
        # step to one. Diagonal reach must not cut through a blocked corner.
        def adjacent(point):
            dx, dy = door['x']-point['x'], door['y']-point['y']
            if max(abs(dx),abs(dy)) > 1:
                return False
            if dx and dy:
                horizontal, vertical = (2 if dx > 0 else 6), (4 if dy > 0 else 0)
                return all(self.navigation.query('step',point,d,objects=objects) is not None
                           for d in (horizontal,vertical))
            return True
        try:
            reachable = adjacent(avatar)
            if not reachable:
                for direction in range(8):
                    point = self.navigation.query('step',avatar,direction,objects=objects)
                    if point and abs(point['z']-door['z']) <= 16 and adjacent(point):
                        reachable = True
                        break
            if not reachable:
                raise BackendError('You cannot reach that through an obstacle')
            destination = dict(x=door['home_x'] if door['opened'] else door['home_x']-1,
                               y=door['home_y'] if door['opened'] else door['home_y']+1,z=door['z'])
            if (avatar['x'],avatar['y']) == (destination['x'],destination['y']) and abs(avatar['z']-door['z']) < 20:
                raise BackendError('You are in the way of the door')
            others = [item for item in objects if item['serial'] != serial]
            if self.navigation.query('stand',destination,objects=others) != destination:
                raise BackendError('Something blocks the door')
        except NavigationError as error:
            raise BackendError(str(error)) from error
        self.request(self.path + '/call/use_door', json.dumps([avatar['revision'],revision,serial]).encode())
        return self.world()[1]


def load_backend(config):
    data = json.loads(Path(config).read_text())
    return Backend(data['endpoint'], data['database'], data['token'])
