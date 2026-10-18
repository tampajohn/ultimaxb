# Local Test Center

This workspace has a separate OUO world in `build/local-shard`, listening only on
`127.0.0.1:2593`. It does not share accounts or characters with UO1998.

In UltimaMac, open the connection screen (Command-L), disconnect if needed,
and set Server to `127.0.0.1`, Port to `2593`. Use a new local account name and
password: OUO creates the account on its first successful login. Create a new
character; choose Minoc to use the area we have been testing.

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
