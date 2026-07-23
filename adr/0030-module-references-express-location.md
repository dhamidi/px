# 0030. Module references express location, not mechanics

Status: Accepted

## Context

Nearly every framework module opens with a block like

```prolog
:- prolog_load_context(directory, Dir),
   atomic_list_concat([Dir, '/px_env'], EnvSpec),
   atomic_list_concat([Dir, '/px_form'], FormSpec),
   use_module(EnvSpec, [respond/3]),
   use_module(FormSpec, [form_result/3]).
```

Eight lines of string plumbing to say "import two sibling modules."
The pattern was cargo-culted from the first file onward, and it is
worse than noise: it buries the actual dependency list (the thing a
reader wants) inside path mechanics, and it *reimplements something
SWI-Prolog already does* — a relative file spec in `use_module/1,2`
is resolved against the directory of the file being loaded, not the
process working directory. The proof has been in the tree the whole
time: `px_ui.pl` says `:- use_module(px_env, [respond/3,
not_found/2]).` and works from every loading context.

## Decision

A module reference states *where the module lives in the project*,
and nothing else. Three forms, one per relationship:

1. **A sibling in the same tree** — plain relative spec, resolved by
   SWI against the referring file:

   ```prolog
   :- use_module(px_env,  [respond/3, respond/4, not_found/2]).
   :- use_module(px_form, [form_result/3]).
   :- use_module(markdown/parser).        % subdirectory sibling
   ```

2. **The framework, from anywhere** — the facade, through the
   library alias it registers for its own directory:

   ```prolog
   :- use_module(library(prologex)).
   ```

3. **App code, from app code** — the `app` alias `prologex_run/0`
   registers for the application's `app/` directory (adr/0029), so a
   cross-file reference names the feature and role:

   ```prolog
   :- use_module(app(guestbook/model)).
   :- use_module(app(shared/layout), []).
   ```

`prolog_load_context(directory, _)` is *banned for module imports*.
It remains legitimate for what it actually is — asking "where is
this source file?" — which only file-location concerns need: locating
the compiled foreign libraries in `c/`, resolving a data directory
like `adr/` relative to the app tree, finding `public/assets/`.

Import lists stay explicit for predicates (`[respond/3]`); a bare
`use_module(Spec, [])` documents "loaded for its directives or
multifile contributions, imports nothing."

## Consequences

Every framework file's prologue shrinks to its actual dependency
list, one line per dependency, greppable and diffable. New files
have an obvious pattern to copy that cannot silently break when a
file is loaded from an unexpected working directory (the old string
concatenation never could either — but only because it reimplemented
the resolution rule by hand each time). The `app(...)` alias gives
application imports the same property while reading as the feature
path they name.
