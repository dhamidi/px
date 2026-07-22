# 0022. Config is a Prolog file

Status: Accepted

## Context

v1 has no config subsystem at all. `apps/adr_site.pl` hardcodes its
port as an argv fallback in `main/0`, `deploy/run.sh` passes `8090` as
a command-line argument, and every path the app needs is computed
inline with `prolog_load_context/2` at load time. Changing the port
means editing a shell script; adding a second configurable value means
inventing a second ad-hoc mechanism. adr/0012 records what that costs
in practice: the first deploy failed because 8080 was already taken on
the VM, and fixing it meant touching code and scripts rather than
flipping one value.

adr/0016 (the syntax north star) already reserved the shape: config is
declared as plain `config/2` facts with environment overlays, and
queried with an ordinary predicate — rule 3, "declarations are
directives; lookups are relations". Its worked example names the file:
`config/app.pl`, loaded automatically. This ADR specifies that
subsystem.

Rails solves the same problem with YAML — and then, because YAML
cannot compute anything, has to embed ERB inside it
(`pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>`): a template
language inside a data language inside a Ruby app. We are a Prolog
framework; our data language *is* a programming language.

## Decision

### The file: `config/app.pl`

Configuration lives in one file, `config/app.pl`, containing plain
facts:

```prolog
%% config/app.pl
config(port, env('PORT', 8090)).
config(database, "blog.db").
config(session_secret, env('SESSION_SECRET')).

% Environment overlay: applies only when PROLOGEX_ENV=production.
config(production, database, "/var/lib/blog.db").

% Computed config -- it's just Prolog, so a fact may have a body.
config(workers, N) :- current_prolog_flag(cpu_count, N).
```

Two shapes:

- `config(Key, Value)` — a base fact, valid in every environment.
- `config(Env, Key, Value)` — an overlay fact, valid only when `Env`
  is the current environment.

Because the file is consulted, not parsed as inert data, a "fact" may
be a rule. `config(workers, N) :- current_prolog_flag(cpu_count, N).`
is the whole story for sizing the worker pool to the machine — the
thing Rails needs ERB-in-YAML for costs nothing here.

The framework consults `config/app.pl` at startup into a reserved
module of its own (`prologex_config`), never into `user`. App code
cannot accidentally redefine framework internals from the config file,
and the config facts do not collide with any `config/2` an application
module might define for its own purposes. The public lookup predicates
below are the only supported access path.

### Environment selection and lookup precedence

The current environment is taken from the OS environment variable
`PROLOGEX_ENV`; if unset, it is `development`. The systemd unit for
production sets it once:

```ini
# deploy/prologex.service
[Service]
Environment=PROLOGEX_ENV=production
```

Apps use exactly one lookup predicate, `config/2`. Its rule:

> `config(Key, Value)` first tries the overlay
> `config(CurrentEnv, Key, V)`; if no overlay fact for `Key` exists in
> the current environment, it falls back to the base fact
> `config(Key, V)`.

With the `config/app.pl` above:

```prolog
% PROLOGEX_ENV unset (development):
?- config(database, D).
D = "blog.db".                      % base fact; no dev overlay

% PROLOGEX_ENV=production:
?- config(database, D).
D = "/var/lib/blog.db".             % overlay wins over base
```

One file to read tells you what every environment does; the diff
between dev and production is exactly the set of `config/3` overlay
facts.

### Bridging OS environment variables: `env(Name, Default)`

A value may be the term `env(Name, Default)` (or `env(Name)` with no
default). At lookup time the framework resolves it against the OS
environment: if `Name` is set, its value is used; otherwise `Default`
(or the lookup fails, for `env/1` — pair it with `require_config/2`
below). Resolved values are typed: if the environment string parses as
a number via `number_codes/2`, a number comes back, not an atom.

```prolog
config(port, env('PORT', 8090)).
```

```prolog
% No PORT in the environment:
?- config(port, P).
P = 8090.

% systemd unit sets Environment=PORT=8091:
?- config(port, P).
P = 8091.                           % a number, not 'PORT' text
```

This is the fix for adr/0012's port-collision incident. When the unit
first failed to bind because 8080/8081/8082/9999 were already taken on
the VM, the remedy was editing code and `deploy/run.sh`. Under this
design it is one line in the unit file — `Environment=PORT=...` — with
no edit to the repo at all.

### Consumers

- **The framework itself** reads `port`, `workers`, and `database` at
  startup — `prologex_run` (adr/0016) needs no arguments and
  `deploy/run.sh` passes none.
- **Handlers** read config through the env dict (adr/0017):
  `Env.config` is a snapshot of resolved configuration, so a handler
  writes `Env0.config.database` — no direct calls into
  `prologex_config` from request code.

Config is read once, at startup. There is no hot reload, and that is a
deliberate non-goal for now: under systemd (adr/0012) a restart is one
`systemctl restart` away and the process comes back in well under a
second. If reload is ever wanted, it can be added behind the same
`config/2` interface without touching app code.

### Missing keys: `config/2` fails, `require_config/2` throws

`config/2` is a relation like any other: looking up a key with no
fact simply fails. That is the right behavior for optional config —

```prolog
( config(analytics_id, Id) -> render_snippet(Id) ; true )
```

For config the app cannot run without, use `require_config/2`. Same
arguments, but a missing key throws a clear error instead of failing
silently:

```prolog
?- require_config(session_secret, S).
ERROR: prologex config: missing required key `session_secret`
ERROR:   looked in config/app.pl (environment: production)
ERROR:   define config(session_secret, ...) or set the OS environment
ERROR:   variable named in its env(...) term.
```

Per adr/0016 rule 2, no new punctuation: a Ruby-flavored `config!` was
rejected in favor of the plainly-named `require_config/2`. The
framework uses `require_config/2` internally for `port` — a server
that cannot know its port should say so at startup, loudly, naming the
file to edit.

## Consequences

`apps/adr_site.pl` loses its hardcoded port: the argv-parsing line in
`main/0` goes away, the value moves to `config/app.pl`, and
`deploy/run.sh`'s `exec swipl apps/adr_site.pl 8090` drops the trailing
`8090`. `deploy/prologex.service` gains `Environment=` lines as the
place deployment-specific values live — exactly the division adr/0012
wanted between the unit and the script. To understand a deployment you
now read one Prolog file plus one systemd unit.

Config being executable Prolog is a power tool with the usual edge:
a rule body runs at lookup, so a slow or throwing body makes config
slow or throwing. The convention is that bodies stay small and pure
(flag lookups, arithmetic); anything heavier belongs in app code.

Secrets: `config/app.pl` is plain text committed to the repo. Secret
values must never appear as committed facts — they enter as
`env('SESSION_SECRET')` terms resolved from `Environment=` directives
in the systemd unit (or an `EnvironmentFile=` outside the repo). The
config file then documents *which* secrets exist without containing
any of them, and `require_config/2` turns a forgotten directive into a
named startup error instead of a mystery.
