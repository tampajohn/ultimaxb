"""Private offline world checkpoints. These contain credentials; never share them."""
import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import uuid
from urllib.parse import urlparse

from world_lock import offline_lock, runner_lock

FORMAT = 'ultima-local-checkpoint'
VERSION = 1
ROOTS = {'gateway.json', 'jwt-private-pkcs8.pem', 'jwt-public.pem',
         'config.toml', 'metadata.toml', 'control-db', 'replicas', 'program-bytes',
         'branch.json'}
REQUIRED = ROOTS - {'branch.json'}
IGNORED = {'.ultima-world.lock', 'spacetime.pid', 'server.log', 'logs', 'cache',
           'jwt-private.pem', '.fork-incomplete'}
MAX_FILES = 100_000
MAX_BYTES = 16 * 1024**3


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True).encode()


def write_json(path, value):
    with os.fdopen(os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600), 'wb') as stream:
        stream.write(canonical(value))
        stream.flush()
        os.fsync(stream.fileno())


def read_json(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('Duplicate JSON key')
            result[key] = value
        return result
    if Path(path).stat().st_size > 32 * 1024**2:
        raise ValueError('Checkpoint metadata is too large')
    return json.loads(Path(path).read_bytes(), object_pairs_hook=unique)


def uuid_string(value):
    if not isinstance(value, str) or str(uuid.UUID(value)) != value:
        raise ValueError('Invalid branch or checkpoint identity')
    return value


def sha_string(value):
    if not isinstance(value, str) or len(value) != 64 or any(c not in '0123456789abcdef' for c in value):
        raise ValueError('Invalid content digest')
    return value


def validate_branch(branch):
    if not isinstance(branch, dict) or set(branch) - {'id', 'parent', 'runtime_sha256'}:
        raise ValueError('Invalid branch metadata')
    uuid_string(branch['id'])
    parent = branch['parent']
    if parent is not None:
        if not isinstance(parent, dict) or set(parent) != {'branch', 'checkpoint', 'manifest_sha256'}:
            raise ValueError('Invalid ancestry reference')
        uuid_string(parent['branch'])
        uuid_string(parent['checkpoint'])
        sha_string(parent['manifest_sha256'])
    if 'runtime_sha256' in branch:
        sha_string(branch['runtime_sha256'])
    return branch


def checked_tree(root):
    """No links/special files; bounded traversal and portable relative paths."""
    root = Path(root)
    if root.is_symlink() or not root.is_dir():
        raise ValueError('Expected a real directory')
    files = {}
    total = 0
    for directory, dirs, names in os.walk(root, followlinks=False):
        for name in dirs + names:
            path = Path(directory) / name
            info = path.lstat()
            relative = path.relative_to(root).as_posix()
            if '\\' in relative or any(ord(c) < 32 for c in relative):
                raise ValueError('Unsupported checkpoint filename')
            if stat.S_ISDIR(info.st_mode):
                continue
            if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
                raise ValueError('Checkpoint contains a link or special file')
            total += info.st_size
            if len(files) >= MAX_FILES or total > MAX_BYTES:
                raise ValueError('Checkpoint exceeds local format limits')
            files[relative] = {'size': info.st_size, 'sha256': digest(path)}
    return dict(sorted(files.items()))


def disjoint(first, second):
    first, second = Path(first).resolve(), Path(second).resolve()
    if first == second or first in second.parents or second in first.parents:
        raise ValueError('Source and destination directories must not overlap')


@contextmanager
def new_directory(destination):
    """Reserve exclusively; never replace an existing destination, even if empty."""
    destination = Path(destination)
    destination.mkdir(mode=0o700)
    try:
        yield destination
    except BaseException:
        shutil.rmtree(destination)
        raise


def copy_store(source, destination, files):
    destination.mkdir(mode=0o700, exist_ok=True)
    for relative in files:
        source_file, target = source / relative, destination / relative
        target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        with source_file.open('rb') as src:
            with os.fdopen(os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'wb') as dst:
                shutil.copyfileobj(src, dst)
                dst.flush()
                os.fsync(dst.fileno())


def world_files(data):
    children = {p.name for p in data.iterdir()}
    if not REQUIRED <= children or children - ROOTS - IGNORED:
        raise ValueError('World has missing or unrecognized root entries')
    files = {}
    for name in sorted(ROOTS & children):
        path = data / name
        info = path.lstat()
        if path.is_symlink():
            raise ValueError('Linked world entry')
        if path.is_dir():
            files.update({name + '/' + k: v for k, v in checked_tree(path).items()})
        elif stat.S_ISREG(info.st_mode) and info.st_nlink == 1:
            files[name] = {'size': info.st_size, 'sha256': digest(path)}
        else:
            raise ValueError('Invalid world entry')
    if len(files) > MAX_FILES or sum(row['size'] for row in files.values()) > MAX_BYTES:
        raise ValueError('World exceeds checkpoint limits')
    return dict(sorted(files.items()))


def capture(data, destination, runtime):
    data, destination = Path(data).absolute(), Path(destination).absolute()
    if data.is_symlink() or not data.is_dir():
        raise ValueError('Expected a real world directory')
    disjoint(data, destination)
    if destination.exists() or destination.is_symlink():
        raise FileExistsError('Checkpoint destination already exists')
    runtime_sha = digest(runtime)
    with offline_lock(data):
        if (data / '.fork-incomplete').exists():
            raise ValueError('Cannot capture an incomplete fork')
        files = world_files(data)
        branch_path = data / 'branch.json'
        if branch_path.exists():
            branch = validate_branch(read_json(branch_path))
            if branch.get('runtime_sha256', runtime_sha) != runtime_sha:
                raise ValueError('Runtime differs from the fork runtime')
        else:
            branch = {'id': str(uuid.uuid4()), 'parent': None}
            write_json(branch_path, branch)
            files = world_files(data)
        with new_directory(destination) as output:
            copy_store(data, output / 'store', files)
            if checked_tree(output / 'store') != files or world_files(data) != files:
                raise ValueError('World changed during capture')
            manifest = {'format': FORMAT, 'version': VERSION,
                        'id': str(uuid.uuid4()),
                        'created_at': datetime.now(timezone.utc).isoformat(),
                        'branch': branch, 'runtime_sha256': runtime_sha, 'files': files}
            write_json(output / 'manifest.json', manifest)
    return manifest


def verify(checkpoint, runtime):
    checkpoint = Path(checkpoint)
    if checkpoint.is_symlink() or not checkpoint.is_dir():
        raise ValueError('Expected a checkpoint directory')
    if {p.name for p in checkpoint.iterdir()} != {'manifest.json', 'store'}:
        raise ValueError('Incomplete checkpoint or unexpected entries')
    manifest_path = checkpoint / 'manifest.json'
    info = manifest_path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
        raise ValueError('Invalid manifest file')
    manifest = read_json(manifest_path)
    if set(manifest) != {'format', 'version', 'id', 'created_at', 'branch', 'runtime_sha256', 'files'}:
        raise ValueError('Invalid manifest fields')
    if manifest['format'] != FORMAT or type(manifest['version']) is not int or manifest['version'] != VERSION:
        raise ValueError('Unsupported checkpoint format')
    uuid_string(manifest['id'])
    validate_branch(manifest['branch'])
    if sha_string(manifest['runtime_sha256']) != digest(runtime):
        raise ValueError('Checkpoint requires the exact original SpacetimeDB runtime')
    files = manifest['files']
    if not isinstance(files, dict) or len(files) > MAX_FILES:
        raise ValueError('Invalid checkpoint file inventory')
    for relative, row in files.items():
        path = PurePosixPath(relative)
        if (not relative or path.is_absolute() or '..' in path.parts or
                path.as_posix() != relative or '\\' in relative or path.parts[0] not in ROOTS):
            raise ValueError('Invalid checkpoint path')
        if not isinstance(row, dict) or set(row) != {'size', 'sha256'}:
            raise ValueError('Invalid checkpoint file record')
        if type(row['size']) is not int or not 0 <= row['size'] <= MAX_BYTES:
            raise ValueError('Invalid checkpoint file size')
        sha_string(row['sha256'])
    if checked_tree(checkpoint / 'store') != files:
        raise ValueError('Checkpoint content does not match manifest')
    roots = {p.name for p in (checkpoint / 'store').iterdir()}
    if not ROOTS <= roots or roots - ROOTS:
        raise ValueError('Checkpoint store is incomplete')
    if validate_branch(read_json(checkpoint / 'store/branch.json')) != manifest['branch']:
        raise ValueError('Checkpoint ancestry differs from store')
    return manifest


def fork(checkpoint, destination, runtime, db_port):
    checkpoint, destination = Path(checkpoint).absolute(), Path(destination).absolute()
    disjoint(checkpoint, destination)
    if not 1024 <= db_port <= 65535:
        raise ValueError('Choose a database port between 1024 and 65535')
    manifest = verify(checkpoint, runtime)
    config = read_json(checkpoint / 'store/gateway.json')
    endpoint = urlparse(config['endpoint'])
    if endpoint.scheme != 'http' or endpoint.hostname != '127.0.0.1':
        raise ValueError('Checkpoint must use a local database endpoint')
    if db_port == endpoint.port:
        raise ValueError('Fork database port must differ from the parent port')
    with new_directory(destination) as output:
        with runner_lock(output):
            write_json(output / '.fork-incomplete', {'checkpoint': manifest['id']})
            copy_store(checkpoint / 'store', output, manifest['files'])
            if world_files(output) != manifest['files']:
                raise ValueError('Checkpoint changed during restore')
            config_path = output / 'gateway.json'
            config['endpoint'] = f'http://127.0.0.1:{db_port}'
            from accounts import save_private_config
            save_private_config(config_path, config)
            branch = {'id': str(uuid.uuid4()), 'parent': {
                'branch': manifest['branch']['id'], 'checkpoint': manifest['id'],
                'manifest_sha256': hashlib.sha256(canonical(manifest)).hexdigest()},
                'runtime_sha256': manifest['runtime_sha256']}
            (output / 'branch.json').unlink()
            write_json(output / 'branch.json', branch)
            (output / '.fork-incomplete').unlink()
    return branch


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime', required=True, type=Path)
    sub = parser.add_subparsers(dest='command', required=True)
    capture_parser = sub.add_parser('capture')
    capture_parser.add_argument('world', type=Path)
    capture_parser.add_argument('destination', type=Path)
    verify_parser = sub.add_parser('verify')
    verify_parser.add_argument('checkpoint', type=Path)
    fork_parser = sub.add_parser('fork')
    fork_parser.add_argument('checkpoint', type=Path)
    fork_parser.add_argument('destination', type=Path)
    fork_parser.add_argument('--db-port', required=True, type=int)
    args = parser.parse_args()
    if args.command == 'capture':
        result = capture(args.world, args.destination, args.runtime)
    elif args.command == 'verify':
        result = verify(args.checkpoint, args.runtime)
    else:
        result = fork(args.checkpoint, args.destination, args.runtime, args.db_port)
    print(f'{args.command}: {result["id"]}')


if __name__ == '__main__':
    main()
