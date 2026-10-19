#!/bin/zsh
# Build, consistently sign, and replace this workspace's app instance.
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release --cache-path build/swift-cache --scratch-path .build
identity_file=build/signing-identity.txt
if [[ ! -f "$identity_file" ]]; then
    print -u2 'Set build/signing-identity.txt to a local code-signing identity hash first.'
    exit 1
fi
signing_identity=$(< "$identity_file")
codesign --force --sign "$signing_identity" --identifier com.ultimaxb.UltimaMac .build/release/UltimaMac
codesign --verify --strict .build/release/UltimaMac
# Resolve each candidate executable so another workspace's UltimaMac is untouched.
python3 - <<'PY'
import ctypes, os, signal, subprocess, time
from pathlib import Path
root = str(Path.cwd().resolve()) + '/'
lib = ctypes.CDLL('/usr/lib/libproc.dylib')
for line in subprocess.check_output(['ps','-ax','-o','pid=,comm='],text=True).splitlines():
    pid, command = line.strip().split(None,1)
    if Path(command).name != 'UltimaMac': continue
    path = ctypes.create_string_buffer(4096)
    if lib.proc_pidpath(int(pid),path,len(path)) > 0 and os.fsdecode(path.value).startswith(root):
        os.kill(int(pid), signal.SIGTERM)
        for _ in range(50):
            try: os.kill(int(pid),0)
            except ProcessLookupError: break
            time.sleep(.02)
        else: raise SystemExit('Existing UltimaMac did not exit; refusing to start a second copy.')
PY
# Optional original region data stays local; server music always overrides it.
region_args=()
if [[ -f build/local-shard/.rundir/uogolddemo/regions.txt ]]; then
    region_args=(--regions build/local-shard/.rundir/uogolddemo/regions.txt)
fi
exec .build/release/UltimaMac --client uo1998-client --connect "${region_args[@]}" "$@"
