# Local Test Center

This workspace has a separate OUO world in `build/local-shard`, listening only on
`127.0.0.1:2593`. It does not share accounts or characters with UO1998.

In UltimaMac, open the connection screen (Command-L), disconnect if needed,
and click **Local Test Center**. It selects `127.0.0.1:2593` without changing
**Saved Server** settings. On the first visit, enter a new local account name and
password and click Connect; OUO creates the account. Enable Remember password
for a direct login from the Local Test Center button on later visits. Local
preferences and Keychain credentials are separate, including Forget Saved Password.
Click **Saved Server** to restore your normal shard settings. The app starts with
your normal profile. Create a new local character and choose Minoc to use the
area we have been testing.

Press Enter for chat and use these Test Center commands:

```
.set str 100
.set dex 100
.set int 100
.set all 1000
```

Skills use tenths: `1000` means 100.0. To set individual skills, use e.g.
`.set mining 1000` or `.set magery 1000`. `.set list` lists skill names/IDs.
`.set hits`, `.set mana`, and `.set stam` refill those resources; `.resurrect`
revives your dead character. `.help` lists the available commands.

New characters receive 10,000 gold in the bank, a full spellbook and a bag of
reagents. Skill/stat gain also runs at 10×. Test Center mode does not enable GM
editing or invulnerability, so combat and gathering still exercise normal rules.

## Running it again

From the repository root, run `tools/run_local_server.sh` in a terminal. It refuses
to start a second listener on port 2593. Ctrl-C requests a clean shutdown and save.
Keep `build/local-shard/.rundir` to preserve accounts and world state; do not delete
it when cleaning build outputs. Server logs and saves are private, ignored files.

Provisioning used local clones of `build/ouo` (commit
`814ea87fad53b94268cb48d9b1af0e5fcfc6fc18`) and `build/.rundir`, with a separate
runtime directory and copied server executable. The executable includes the local
`socket.c` patch binding the listener to 127.0.0.1. The `-a` flag only sets the
relay address; it is not itself a listener restriction. Source references:
https://github.com/draxinar/ouo and https://github.com/draxinar/rundir.

The client login is encrypted, so this server deliberately does **not** use
`-nocrypt`. Its selected protocol is `-client 12532`.

## Local save correction (2026-10-18)

The pinned OUO source declared `CPlayer_CancelTrade` as returning `void`, but
`CEntity_RemoveFromWorld` calls its virtual slot as returning `int`. An undefined
nonzero result skipped unlinking the player, leaving an archived player also in
the spatial grid. The next save inserted it again, forming a cycle and exhausting
the per-block buffer. `tools/server-patches/ouo-player-trade-return.patch` makes
the player override return zero: cancelling trade containers does not destroy the
player, so world removal must continue.

The correction was tested on an isolated copy: login, movement, stack split/merge,
unequip/equip, shutdown save, restart, then the same character's persisted stats
and inventory interactions. The original failing build reproduced a duplicate
spatial insertion; the corrected build completed both shutdown saves and the intervening reload.
Long-running periodic-save validation remains outstanding.

To reproduce the local executable from the pinned source, apply both patches:

```sh
git -C build/ouo apply ../../tools/server-patches/ouo-loopback.patch
git -C build/ouo apply ../../tools/server-patches/ouo-player-trade-return.patch
make -C build/ouo -j4
```

Apply them only to an unpatched checkout. Copy `build/ouo/ouo` to
`build/local-shard/run/ouo` while the server is stopped. The loopback patch is
required to keep this test server local. Existing world/account data stays in
place. Reusing `UO_LOCAL_TEST_ACCOUNT` with the opt-in integration test now checks
that the fixture's modified Test Center strength survived the restart. Only use
a disposable fixture account with that test, never a playing character.

## Skill definition header correction

`tools/server-patches/ouo-skill-header.patch` skips leading document-comment
banners before reading the skills.txt version header. Without it, the fixed-order
parser shifted every field, corrupting effective skill values and script names.
Apply this patch alongside the other server patches before building. Verified
with a disposable character: all 46 skills become exactly 100.0 after `.set all
1000`, and Anatomy returns a target cursor. The local server was saved and
restarted with this correction; reconnect to refresh displayed values.
