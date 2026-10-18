#!/bin/zsh
# Run the provisioned localhost Test Center; world/account data stays under build/.
set -euo pipefail
cd "${0:A:h:h}"
server_dir="$PWD/build/local-shard"
[[ -x "$server_dir/run/ouo" && -d "$server_dir/.rundir" ]] || {
  print -u2 'Local OUO world is not provisioned. See docs/LOCAL_SERVER.md.'
  exit 1
}
if lsof -nP -iTCP:2593 -sTCP:LISTEN >/dev/null 2>&1; then
  print -u2 'Port 2593 is already listening; the local server may already be running.'
  exit 1
fi
cd "$server_dir/run"
exec ./ouo -client 12532 -a 127.0.0.1 -p 2593 -test -fast 10 -watchdog 10000
