"""Publish a local module without modifying the user's global CLI identity."""
import argparse
import json
import os
from pathlib import Path
from urllib.request import Request, urlopen
from backend import Backend, load_backend


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', default='build/spacetime-data/gateway.json')
    parser.add_argument('--wasm', default='build/spacetime-module/wasm32-unknown-unknown/release/ultima_local_world.wasm')
    parser.add_argument('--database', default='ultima-local-protocol')
    parser.add_argument('--port', type=int, default=3000)
    args = parser.parse_args()
    path = Path(args.config)
    if path.exists():
        backend = load_backend(path)
    else:
        endpoint = f'http://127.0.0.1:{args.port}'
        with urlopen(Request(endpoint + '/v1/identity', data=b'', method='POST'), timeout=5) as response:
            identity = json.load(response)
        config = {'endpoint': endpoint, 'database': args.database, 'token': identity['token']}
        path.parent.mkdir(parents=True, exist_ok=True)
        with os.fdopen(os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600), 'w') as output:
            json.dump(config, output)
        backend = load_backend(path)
    # No clear=true: publishing updates must never silently reset the world.
    backend.request(backend.path, Path(args.wasm).read_bytes(), method='PUT', content_type='application/wasm')
    backend.avatar()
    print('Local world published; gateway configuration saved at', path)


if __name__ == '__main__':
    main()
