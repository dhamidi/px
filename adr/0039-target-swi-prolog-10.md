# 0039. Target SWI-Prolog 10

Status: Accepted

## Context

Development happened on the VM's distro SWI-Prolog 9.0.4 (Ubuntu
24.04's package). A user's first fresh clone ran on macOS Homebrew's
SWI-Prolog 10.0.2 and hit two crashes that were invisible on 9.x —
because 10.x changed behavior the framework depended on. Testing only
on 9 while users run 10 is the actual defect; the fix is to make 10
the target and test on it.

## Decision

**SWI-Prolog 10 is the supported version.** The development VM now
runs 10.0.2 (from `ppa:swi-prolog/stable`, matching Homebrew); the
whole test suite runs on it. README documents the PPA for Ubuntu
(the distro package is 9.x) and `brew install swi-prolog` for macOS,
which is already 10.x.

Two 10.x incompatibilities were found and fixed, both from real 10
behavior changes:

1. **`halt/1` is now a catchable stack unwind.** 10 implements
   `halt(Code)` as `throw(unwind(halt(Code)))` so cleanups run on the
   way out; 9 exited the process immediately. The CLI ran each
   command's `halt(0)`/`halt(1)` from inside `catch(main(Argv), E,
   ...)`, so on 10 that catch caught the halt-unwind of a *successful*
   command and forced `halt(1)` — every `px` command exited 1 despite
   doing its work, breaking `px new && ...` and the scripted developer
   flow entirely. Fix: the CLI's recovery re-throws `unwind(_)` so a
   halt reaches the top level and sets the real exit code. The rule
   generalizes: a broad `catch/3` around a goal that may `halt/1` must
   re-throw halt unwinds, on 10.

2. **A built-in `file_search_path(app, swi(app))`.** 10 ships an `app`
   search path (a compound value) that 9 lacks. `px_reload:app_dir/1`
   read the first `file_search_path(app, Dir)` and `atom_concat`ed
   `Dir` — getting the compound `swi(app)`, crashing `bin/px server`
   at boot. Fix: `app_dir/1` requires `atom(Dir)`, skipping the
   non-atomic built-in. (SWI's own `app(...)` resolution already
   handles the compound built-in; only our `atom_concat` did not.)

## Consequences

The framework, both demo services, the CLI, and the full test suite
run on SWI-Prolog 10. The class of bug that shipped here — a 10-only
behavior change invisible on the 9.x dev box — is closed by the dev
environment now being 10.x; a future 11.x will want the same
treatment (dev on the target, run the suite). The two fixes are
compatible with 9.x as well (the halt clause is never reached where
halt isn't an exception; `atom(Dir)` is a no-op where there is no
compound built-in), so nothing regresses for anyone still on 9.
