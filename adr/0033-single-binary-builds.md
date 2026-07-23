# 0033. px build: the app as one executable

Status: Accepted

## Context

Deployment currently means a framework checkout, an app tree, a C
build, and a systemd unit pointing a shell script at swipl. Rails
never solved this; Go did, and it is the deployment story users
expect from a modern framework: one file you scp to a server and
run. SWI-Prolog has the primitives — `qsave_program/2` produces a
saved state that is a zip archive appended to an emulator
(`stand_alone(true)`), and `foreign(save)` embeds loaded shared
objects into that archive, extracted and dlopened at restore.

Two discoveries shaped the design:

1. **`foreign(save)` only saves libraries loaded through the
   `foreign(...)` file-search alias.** qsave's
   `find_foreign_library/5` head-matches `FileSpec = foreign(Name)`;
   a library loaded by absolute path is silently unsavable and
   `qsave_program/2` just fails (returns false, no message). Our
   four loader modules loaded `c/*.so` by concatenated absolute
   path. They now register `c/` on the `foreign` alias and load
   `foreign(uv_swi)` etc. — which is also what adr/0030 says a
   module reference should look like.

2. **"Single binary" means single deployable file, not zero
   dynamic linking.** The produced ELF depends on the system's
   `libswipl.so.9`, `libuv.so.1` and the libc family — verified
   with ldd — exactly as any C program depends on libc. The target
   host needs `apt install swi-prolog-nox libuv1` once; llhttp and
   sqlite are vendored amalgamations compiled into our own .so files
   and ride inside the binary. A fully-static emulator would need a
   custom SWI build; out of scope, recorded as the known boundary.

## Decision

`px build` (adr/0032) runs the boot's load phase, then saves:

1. **Load = compile.** `prologex_load/0` runs exactly as a server
   boot would: config, app tree, routes registered, forms declared,
   pipeline and layout installed, assets compiled and hashed. The
   entire resulting Prolog database — code AND the dynamic facts
   boot produced (route table, form definitions, asset manifest) —
   is what `qsave_program/2` snapshots. The binary's entry goal is
   `prologex_serve/0`: it does none of that again, just opens the
   port. Config values that must stay deploy-time flexible already
   are: `env('PORT', 8090)` terms resolve against the OS environment
   at lookup, not at bake time (adr/0022).

2. **Assets bake as blobs.** After compile_assets, every file under
   `public/assets/` (hashed originals, gzip siblings, importmap) is
   read into `px_assets:asset_blob(RelPath, Bytes)` facts — part of
   the saved database. `serve_asset/2` gains one fallback: when the
   file is absent on disk, serve the blob with the same headers
   (immutable cache, content-type, gzip negotiation). On a dev
   checkout the disk path wins and nothing changes.

3. **App data earns baking by being loaded at load time.** The
   framework does not invent a virtual filesystem: a feature whose
   content is static reads it in its *load-time* directives —
   the adrs feature now slurps `adr/*.md` into `adr_doc/2` facts at
   load — and the facts ride into the state like all others. What
   is genuinely runtime state stays external and declared:
   `config(database, ...)` names a writable path the binary opens on
   first request, exactly as in dev.

4. `qsave_program/2` options: `stand_alone(true)`,
   `foreign(save)`, `goal(prologex_serve)`, and generous
   `stack_limit`. Output defaults to the app directory's name;
   `px build -o FILE` overrides.

## Consequences

`px build && scp app server: && ssh server ./app` is the whole
deployment. The binary serves its assets from memory, its content
from baked facts, and needs beside it only its sqlite data directory
and two apt packages. The build is also a smoke test: it cannot
succeed unless the app fully loads. Costs: the state snapshots the
build machine's view — a changed adr/ or reconfigured route needs a
rebuild (that is the point of a binary); and foreign saving ties the
binary to the build architecture (`x86_64-linux`), like any compiled
program. milestone19 proves the loop end to end: build, move the
binary, run it against a fresh data dir, serve pages, assets and a
guestbook POST, then SIGTERM it gracefully (adr/0031).
