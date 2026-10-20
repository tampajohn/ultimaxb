"""Private local demo-account provisioning; game clients never receive DB tokens."""
import json
import os
from pathlib import Path
import tempfile

from backend import Backend, BackendError


def save_private_config(path, data):
    """Atomically persist identity before registration, including uncertain writes."""
    path=Path(path)
    fd, temporary=tempfile.mkstemp(prefix='.gateway-',dir=path.parent)
    try:
        with os.fdopen(fd,'w') as stream:
            json.dump(data,stream)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary,path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def ensure_local_accounts(backend, config):
    """Return separately bound backends after idempotent administrator provisioning."""
    if backend.player!=1:
        raise BackendError('Account provisioning requires the administrator.')
    data=json.loads(Path(config).read_text())
    accounts=backend.player_accounts()
    existing=next((row for row in accounts if row[0]==4),None)
    credential=data.get('players',{}).get('local2')
    if credential is None:
        if existing is not None:
            raise BackendError('Second player identity is missing from the private gateway configuration; restore the saved configuration.')
        identity=json.loads(backend.request('/v1/identity',b''))
        credential={'identity':identity['identity'],'token':identity['token']}
        data.setdefault('players',{})['local2']=credential
        save_private_config(config,data)
    if existing is None:
        if backend.navigation is None:
            raise BackendError('Player placement requires installed world assets.')
        avatar=backend.avatar()
        _,objects=backend.world()
        reserved={(row[2],row[3]) for row in backend.avatars()} | {(o['x'],o['y']) for o in objects}
        for mobile in (backend.merchant(),backend.creature()):
            if mobile:reserved.add((mobile['x'],mobile['y']))
        site=None
        for distance in (1,2):
            for dx,dy in ((0,distance),(distance,0),(0,-distance),(-distance,0)):
                candidate=dict(x=avatar['x']+dx,y=avatar['y']+dy,z=avatar['z'])
                if (candidate['x'],candidate['y']) in reserved:continue
                point=backend.navigation.query('stand',candidate,objects=objects)
                if point is None:continue
                try:backend.check_reach(point,avatar,objects)
                except BackendError:continue
                site=point
                break
            if site is not None:break
        if site is None:
            raise BackendError('No reachable standing point for the second player.')
    else:
        # An existing binding is checked by the reducer before it considers site.
        site=backend.avatar()
    backend.request(backend.path+'/call/register_second_player',json.dumps([
        credential['identity'],site['x'],site['y'],site['z']]).encode())
    row=next(row for row in backend.player_accounts() if row[0]==4)
    second=Backend(backend.endpoint,backend.database,backend.token,navigation=backend.navigation,
                   player=4,backpack=row[3],write_token=credential['token'])
    return {'local':backend,'local2':second}
