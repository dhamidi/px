:- module(px_assets,
          [ compile_assets/0,
            load_manifest/0,
            asset_path/2,          % +Logical, -Path
            serve_asset/2,         % +Env0, -Env  (pipeline/route handler)
            stylesheet_tag/2,      % ?Logical, +Stream   (render_helper/2 hook)
            javascript_importmap_tags/1, % +Stream         (render_helper/2 hook)
            image_tag/3,           % ?Logical, ?Attrs, +Stream (render_helper/2 hook)
            bake_asset_blobs/0     % adr/0033: snapshot public/assets/ into facts
          ]).

/** <module> The asset pipeline (adr/0025): Propshaft + importmap-rails,
    modelled on Rails 8.

No bundler, no transpiler, no package manager, no network at build or run
time (adr/0003's vendoring philosophy, extended). `assets/{css,js,img}/`
holds plain files -- JS is plain ES modules, no JSX/TS. compile_assets/0
content-hashes every file into `public/assets/<name>-<hash12>.<ext>`,
writes a gzip sibling, and records the mapping in
`public/assets/.manifest.json`. asset_path/2 resolves a logical name
("css/app.css") to its hashed `/assets/...` URL; serve_asset/2 is the
route handler that serves those URLs back, gzip-negotiated, with an
immutable long-lived cache-control header (safe precisely because the
filename changes whenever the content does -- adr/0025 section on
cache-control explains the reasoning). stylesheet_tag/2,
javascript_importmap_tags/1 and image_tag/3 are px_template's
render_helper/2 hooks (adr/0019) so app templates use them like any other
bare call.

Binary safety: files are read with read_file_to_string/3 and
encoding(iso_latin_1) -- an isomorphic byte<->code-point mapping -- and
served as px_env's `raw_bytes(Binary)` response body (adr/0017's
write_response/2 extension for this ADR), which switches the one-shot
response stream to octet encoding before writing so the bytes are not
re-encoded as UTF-8 on the wire. This is what lets a gzip'd asset's
compressed bytes survive the trip unchanged.

Baking (adr/0033): bake_asset_blobs/0 reads every file under
public/assets/ -- hashed originals, gzip siblings, the manifest --
into asset_blob/2 facts, the same iso_latin_1 byte-string shape as
above, so `px build`'s qsave_program/2 snapshots them as part of the
Prolog database. serve_asset/2 falls back to a blob when the disk
file is absent, which is the normal case once the app runs as a
moved single binary with no public assets files beside it at all --
the disk path (a dev checkout) always wins when present, and that
branch is untouched.
*/

:- use_module(library(filesex)).
:- use_module(library(http/json)).
:- use_module(library(crypto)).
:- use_module(library(zlib)).
:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(error)).

:- use_module(px_env,      [respond/3, respond/4, not_found/2]).
:- use_module(px_template, [render_tag/4]).

%   prolog_load_context/2 only answers inside a directive running AT
%   LOAD TIME -- called later, from an ordinary predicate (repo_root/1
%   below, invoked per-request), it simply fails. So the source
%   directory is captured ONCE, right here, into a fact.
:- dynamic px_assets_source_dir/1.
:- prolog_load_context(directory, Dir),
   assertz(px_assets_source_dir(Dir)).

           /*******************************
           *          LOCATIONS           *
           *******************************/

%!  repo_root(-Dir) is det.
%
%   The repository root, resolved once relative to this file
%   (prolog/px_assets.pl -> ..).
repo_root(Dir) :-
    px_assets_source_dir(Here),
    atomic_list_concat([Here, '/..'], Rel),
    absolute_file_name(Rel, Dir, [file_type(directory)]).

%!  assets_source_dir(-Dir) is det.
%
%   assets/ at the repo root. Fails (rather than throws) if it does
%   not exist yet -- compile_assets/0 turns that into a clear error.
assets_source_dir(Dir) :-
    repo_root(Root),
    atomic_list_concat([Root, '/assets'], Dir).

%!  public_assets_dir(-Dir) is det.
%
%   public/assets/, the compiled-output directory. Created on demand
%   by compile_assets/0; not committed (gitignored, adr/0025).
public_assets_dir(Dir) :-
    repo_root(Root),
    atomic_list_concat([Root, '/public/assets'], Dir).

manifest_path(Path) :-
    public_assets_dir(Dir),
    atomic_list_concat([Dir, '/.manifest.json'], Path).


           /*******************************
           *          COMPILATION         *
           *******************************/

%!  compile_assets is det.
%
%   Walk assets/, content-hash every regular file, copy each to
%   public/assets/<basename>-<hash12>.<ext>, write a gzip sibling
%   (<hashed>.gz), and (re)write public/assets/.manifest.json mapping
%   each logical name -- its path relative to assets/, forward-slash
%   separated, e.g. "css/app.css" -- to its hashed filename.
%
%   Idempotent: the same source content always hashes to the same
%   name, so re-running just overwrites the same bytes. Hashed files
%   left over from a PREVIOUS compile whose logical name no longer
%   maps to them (content changed, or the source file is gone) are
%   deleted, so public/assets/ never accumulates garbage.
compile_assets :-
    assets_source_dir(SrcDir),
    (   exists_directory(SrcDir)
    ->  true
    ;   throw(error(existence_error(directory, SrcDir),
                    context(px_assets:compile_assets/0,
                            'no assets/ directory at the repository root')))
    ),
    public_assets_dir(OutDir),
    make_directory_path(OutDir),
    previous_hashed_files(OldHashed),
    findall(Logical-Hashed,
            compile_one_asset(SrcDir, OutDir, Logical, Hashed),
            Pairs),
    list_to_set(Pairs, UniquePairs),
    write_manifest(UniquePairs),
    new_hashed_files(UniquePairs, NewHashed),
    subtract(OldHashed, NewHashed, Stale),
    forall(member(File, Stale), remove_hashed_file(OutDir, File)),
    retractall(manifest_entry(_, _)),
    forall(member(Logical-Hashed, UniquePairs),
           assertz(manifest_entry(Logical, Hashed))),
    (   manifest_loaded -> true ; assertz(manifest_loaded) ).

%!  compile_one_asset(+SrcDir, +OutDir, -Logical, -Hashed) is nondet.
%
%   One solution per regular file under SrcDir (recursive). Computes
%   the sha256 of the file, copies it to its hashed name in OutDir,
%   and writes the gzip sibling.
compile_one_asset(SrcDir, OutDir, Logical, Hashed) :-
    directory_member(SrcDir, Path, [recursive(true)]),
    exists_file(Path),
    \+ is_manifest_file(Path),
    relative_logical_name(SrcDir, Path, Logical),
    hashed_name(Path, Hashed),
    atomic_list_concat([OutDir, '/', Hashed], OutPath),
    copy_file(Path, OutPath),
    write_gzip_sibling(Path, OutPath).

is_manifest_file(Path) :-
    file_base_name(Path, Base),
    sub_atom(Base, 0, 1, _, '.').

%!  relative_logical_name(+SrcDir, +Path, -Logical) is det.
%
%   Path relative to SrcDir, forward-slash separated, as a string:
%   ".../assets/css/app.css" -> "css/app.css".
relative_logical_name(SrcDir, Path, Logical) :-
    atom_concat(SrcDir, '/', Prefix),
    atom_concat(Prefix, RelAtom, Path),
    atom_string(RelAtom, Logical).

%!  hashed_name(+Path, -Hashed) is det.
%
%   "<basename-without-extension>-<first-12-hex-of-sha256>.<ext>", as
%   a STRING -- the type manifest_entry/2 uses throughout (matching
%   what a JSON round-trip and Env.params values are: adr/0017 path/
%   query params are always strings, and that is exactly what
%   serve_asset/2 compares a requested filename against). A file with
%   no extension gets no trailing dot.
hashed_name(Path, Hashed) :-
    file_base_name(Path, Base),
    crypto_file_hash(Path, FullHash0, [algorithm(sha256)]),
    atom_string(FullHash0, FullHash),
    sub_string(FullHash, 0, 12, _, Short),
    (   file_name_extension(Stem, Ext, Base), Ext \== ''
    ->  format(string(Hashed), '~w-~w.~w', [Stem, Short, Ext])
    ;   format(string(Hashed), '~w-~w', [Base, Short])
    ).

%!  write_gzip_sibling(+SrcPath, +HashedOutPath) is det.
%
%   Writes HashedOutPath + ".gz": the same bytes, gzip-compressed.
%   Binary-safe throughout: the source is read with iso_latin_1 (a
%   lossless byte<->code mapping) and the gzip stream is opened
%   type(binary), so no encoding step can touch the bytes.
write_gzip_sibling(SrcPath, HashedOutPath) :-
    read_file_to_string(SrcPath, Content, [encoding(iso_latin_1)]),
    atom_concat(HashedOutPath, '.gz', GzPath),
    setup_call_cleanup(
        gzopen(GzPath, write, GzOut, [type(binary)]),
        format(GzOut, "~s", [Content]),
        close(GzOut)).

%!  previous_hashed_files(-Files) is det.
%
%   The hashed filenames (strings, basenames only) recorded in the
%   manifest ON DISK before this compile started -- the baseline for
%   stale-file cleanup. Empty list if no manifest exists yet.
previous_hashed_files(Files) :-
    manifest_path(Path),
    (   exists_file(Path)
    ->  read_manifest_pairs(Path, Pairs),
        maplist([_-H,H]>>true, Pairs, Files)
    ;   Files = []
    ).

new_hashed_files(Pairs, Files) :-
    maplist([_-H,H]>>true, Pairs, Files).

remove_hashed_file(OutDir, File) :-
    atomic_list_concat([OutDir, '/', File], Path),
    atom_concat(Path, '.gz', GzPath),
    ignore(( exists_file(Path), delete_file(Path) )),
    ignore(( exists_file(GzPath), delete_file(GzPath) )).

%!  write_manifest(+Pairs) is det.
%
%   Pairs is a list of Logical-Hashed (both strings/atoms of text).
%   Written as pretty-printed JSON, one object, sorted by logical
%   name so the file diffs cleanly between compiles.
write_manifest(Pairs) :-
    manifest_path(Path),
    msort(Pairs, Sorted),
    maplist([L-H, LA-H]>>atom_string(LA, L), Sorted, AtomPairs),
    dict_create(Dict, assets, AtomPairs),
    setup_call_cleanup(
        open(Path, write, Out),
        json_write_dict(Out, Dict),
        close(Out)).


           /*******************************
           *   BAKING (adr/0033 BUILD)    *
           *******************************/

%   asset_blob(RelPath, Bytes): RelPath is a file's path relative to
%   public/assets/, forward-slash separated, as a string (e.g.
%   "app-<hash>.css", "app-<hash>.css.gz", ".manifest.json"); Bytes is
%   its content, iso_latin_1-decoded like every other read in this
%   file -- an isomorphic byte<->code-point string, ready to hand
%   straight to px_env's raw_bytes/1 response body. Populated by
%   bake_asset_blobs/0, part of the dynamic database px build's
%   qsave_program/2 snapshots.
:- dynamic asset_blob/2.

%!  bake_asset_blobs is det.
%
%   Read every regular file under public/assets/ (recursively --
%   hashed originals, ".gz" siblings, ".manifest.json", whatever
%   compile_assets/0 left there) into an asset_blob/2 fact, replacing
%   any previous set. A no-op (zero facts) when public/assets/ does
%   not exist -- fine for a build run before compile_assets/0 ever
%   created it, though `px build` always runs this after
%   prologex_load/0, which does not skip it either way.
bake_asset_blobs :-
    retractall(asset_blob(_, _)),
    public_assets_dir(Dir),
    (   exists_directory(Dir)
    ->  findall(Rel-Bytes, blob_source(Dir, Rel, Bytes), Pairs)
    ;   Pairs = []
    ),
    forall(member(Rel-Bytes, Pairs), assertz(asset_blob(Rel, Bytes))),
    length(Pairs, N),
    maplist([_-B,L]>>string_length(B, L), Pairs, Lengths),
    sum_list(Lengths, TotalBytes),
    TotalKB is TotalBytes / 1024,
    format(user_error, "px_assets: baked ~w asset blob(s), ~1f KB~n",
           [N, TotalKB]).

blob_source(Dir, Rel, Bytes) :-
    directory_member(Dir, Path, [recursive(true)]),
    exists_file(Path),
    relative_logical_name(Dir, Path, Rel),
    read_file_to_string(Path, Bytes, [encoding(iso_latin_1)]).


           /*******************************
           *      MANIFEST (IN MEMORY)    *
           *******************************/

:- dynamic manifest_entry/2.    % ?LogicalString, ?HashedString
:- dynamic manifest_loaded/0.

%!  load_manifest is det.
%
%   (Re)load public/assets/.manifest.json from disk into the in-memory
%   manifest_entry/2 table. compile_assets/0 keeps the table current
%   itself (no need to call this right after); load_manifest/0 is for
%   a process that wants asset_path/2 to work WITHOUT re-compiling --
%   e.g. a second worker, or a test that only reads what an earlier
%   compile_assets/0 already wrote. Reloadable: safe to call again
%   after the manifest file changes underneath the process.
load_manifest :-
    retractall(manifest_entry(_, _)),
    manifest_path(Path),
    (   exists_file(Path)
    ->  read_manifest_pairs(Path, Pairs),
        forall(member(L-H, Pairs), assertz(manifest_entry(L, H)))
    ;   true
    ),
    (   manifest_loaded -> true ; assertz(manifest_loaded) ).

read_manifest_pairs(Path, Pairs) :-
    setup_call_cleanup(
        open(Path, read, In),
        json_read_dict(In, Dict, [value_string_as(string)]),
        close(In)),
    dict_pairs(Dict, _, RawPairs),
    maplist([K-V, Ls-V]>>atom_string(K, Ls), RawPairs, Pairs).

ensure_manifest_loaded :-
    (   manifest_loaded
    ->  true
    ;   load_manifest
    ).

%!  asset_path(+Logical, -Path) is det.
%
%   "/assets/<hashed>" for the logical asset name (e.g. "css/app.css",
%   "js/turbo.js"). Throws existence_error(asset, Logical) -- naming
%   the logical path that was looked up -- when it is not in the
%   manifest (never compiled, or a typo).
asset_path(Logical, Path) :-
    ensure_manifest_loaded,
    to_string(Logical, LogicalS),
    (   manifest_entry(LogicalS, Hashed)
    ->  format(string(Path), "/assets/~w", [Hashed])
    ;   throw(error(existence_error(asset, LogicalS),
                    context(px_assets:asset_path/2,
                            'not in public/assets/.manifest.json -- is it under assets/, and has compile_assets/0 run?')))
    ).

to_string(T, S) :- string(T), !, S = T.
to_string(T, S) :- atom(T),   !, atom_string(T, S).


           /*******************************
           *           SERVING            *
           *******************************/

%!  serve_asset(+Env0, -Env) is det.
%
%   Route handler for `get "/assets/:file"`. The whitelist is the
%   manifest's hashed filenames ONLY -- a File that is not a value in
%   the manifest is not served, full stop, regardless of what exists
%   on disk (so this can never become a path-traversal or directory-
%   listing door). Content-Type is derived from the extension;
%   cache-control is `public, max-age=31536000, immutable` -- safe
%   BECAUSE the filename is content-hashed: this exact URL can only
%   ever mean this exact content, so there is nothing to revalidate,
%   ever (adr/0025). When the client's accept-encoding includes gzip
%   and a ".gz" sibling exists, that sibling's bytes are served with
%   content-encoding: gzip and vary: accept-encoding instead.
serve_asset(Env0, Env) :-
    File = Env0.params.file,
    ensure_manifest_loaded,
    (   manifest_entry(_, File)
    ->  public_assets_dir(Dir),
        atomic_list_concat([Dir, '/', File], Path),
        content_type(File, ContentType),
        CacheControl = "public, max-age=31536000, immutable",
        atom_concat(Path, '.gz', GzPath),
        (   accepts_gzip(Env0),
            exists_file(GzPath)
        ->  read_file_to_string(GzPath, Bytes, [encoding(iso_latin_1)]),
            respond(Env0, raw_bytes(Bytes),
                    [ header("content-type", ContentType),
                      header("cache-control", CacheControl),
                      header("content-encoding", "gzip"),
                      header("vary", "accept-encoding")
                    ], Env)
        ;   exists_file(Path)
        ->  read_file_to_string(Path, Bytes, [encoding(iso_latin_1)]),
            respond(Env0, raw_bytes(Bytes),
                    [ header("content-type", ContentType),
                      header("cache-control", CacheControl)
                    ], Env)
        %   adr/0033 fallback: no disk file (a moved single-binary
        %   build has no public/assets/ tree at all) but the content
        %   rode into the saved state as an asset_blob/2 fact -- same
        %   headers, same gzip negotiation, disk always wins above
        %   when present.
        ;   accepts_gzip(Env0),
            gz_blob_key(File, GzKey),
            asset_blob(GzKey, Bytes)
        ->  respond(Env0, raw_bytes(Bytes),
                    [ header("content-type", ContentType),
                      header("cache-control", CacheControl),
                      header("content-encoding", "gzip"),
                      header("vary", "accept-encoding")
                    ], Env)
        ;   asset_blob(File, Bytes)
        ->  respond(Env0, raw_bytes(Bytes),
                    [ header("content-type", ContentType),
                      header("cache-control", CacheControl)
                    ], Env)
        ;   not_found(Env0, Env)
        )
    ;   not_found(Env0, Env)
    ).

gz_blob_key(File, GzKey) :-
    (   string(File) -> FileS = File ; atom_string(File, FileS) ),
    string_concat(FileS, ".gz", GzKey).

accepts_gzip(Env0) :-
    get_dict(headers, Env0, Headers),
    member("accept-encoding"-Value, Headers),
    sub_string(Value, _, _, _, "gzip"),
    !.

%!  content_type(+FileName, -ContentType) is det.
%
%   Extension -> Content-Type. Falls back to application/octet-stream
%   for anything not listed, so an unrecognised (but manifest-listed)
%   asset still serves rather than erroring.
content_type(FileName, ContentType) :-
    file_name_extension(_, Ext0, FileName),
    downcase_atom(Ext0, Ext),
    (   ext_content_type(Ext, ContentType)
    ->  true
    ;   ContentType = "application/octet-stream"
    ).

ext_content_type(css,   "text/css; charset=utf-8").
ext_content_type(js,    "text/javascript; charset=utf-8").
ext_content_type(mjs,   "text/javascript; charset=utf-8").
ext_content_type(json,  "application/json; charset=utf-8").
ext_content_type(map,   "application/json; charset=utf-8").
ext_content_type(svg,   "image/svg+xml").
ext_content_type(png,   "image/png").
ext_content_type(jpg,   "image/jpeg").
ext_content_type(jpeg,  "image/jpeg").
ext_content_type(gif,   "image/gif").
ext_content_type(webp,  "image/webp").
ext_content_type(ico,   "image/x-icon").
ext_content_type(woff,  "font/woff").
ext_content_type(woff2, "font/woff2").
ext_content_type(ttf,   "font/ttf").
ext_content_type(txt,   "text/plain; charset=utf-8").


           /*******************************
           *      TEMPLATE HELPERS        *
           *******************************/

%!  stylesheet_tag(+Logical, +Stream) is det.
%
%   px_template:render_helper/2 registration: bare call
%   `stylesheet_tag("css/app.css")` in a template body renders
%   `<link rel="stylesheet" href="/assets/app-<hash>.css">`.
:- multifile px_template:render_helper/2.
:- dynamic   px_template:render_helper/2.

stylesheet_tag(Logical, S) :-
    asset_path(Logical, Path),
    px_template:render(S, link([rel(stylesheet), href(Path)])).

px_template:render_helper(stylesheet_tag(Logical), S) :-
    px_assets:stylesheet_tag(Logical, S).

%!  image_tag(+Logical, +Attrs, +Stream) is det.
%
%   Bare call `image_tag("img/logo.png", [class(logo)])` renders
%   `<img src="/assets/logo-<hash>.png" class="logo">`. image_tag/2
%   (no extra attrs) is also registered.
image_tag(Logical, Attrs, S) :-
    asset_path(Logical, Path),
    px_template:render(S, img([src(Path)|Attrs])).

px_template:render_helper(image_tag(Logical), S) :-
    px_assets:image_tag(Logical, [], S).
px_template:render_helper(image_tag(Logical, Attrs), S) :-
    px_assets:image_tag(Logical, Attrs, S).

%!  javascript_importmap_tags(+Stream) is det.
%
%   Called in a template body as `\javascript_importmap_tags` -- the
%   explicit `\Goal` escape (adr/0019), because this helper is
%   zero-arity: a BARE atom in body position is always a text node in
%   px_template's dispatch (only compound terms resolve
%   element/template/helper), so the escape is required here, exactly
%   what it exists for. Renders two script tags:
%
%     1. `<script type="importmap">{"imports": {...}}</script>` --
%        one entry per compiled JS asset, keyed by its BARE module
%        name (the logical name under assets/js/, minus the ".js"
%        extension: "js/turbo.js" -> "turbo", "js/components/foo.js"
%        -> "components/foo"), valued by its hashed /assets/ URL.
%        This is what lets app code write `import "turbo"` and have
%        the browser resolve it with no bundler (Rails 8's
%        importmap-rails model).
%     2. `<script type="module">import "app";</script>` -- the
%        entrypoint, only emitted when assets/js/app.js exists (and
%        therefore compiled to "js/app.js" in the manifest); apps
%        with no app.js get only the import map.
javascript_importmap_tags(S) :-
    ensure_manifest_loaded,
    findall(Bare-Path, js_import_entry(Bare, Path), Entries),
    imports_json(Entries, Json),
    format(string(ImportMap), "{\"imports\": ~w}", [Json]),
    px_template:render(S, script(type(importmap), raw(ImportMap))),
    (   manifest_entry("js/app.js", _)
    ->  px_template:render(S, script(type(module), raw("import \"app\";")))
    ;   true
    ).

px_template:render_helper(javascript_importmap_tags, S) :-
    px_assets:javascript_importmap_tags(S).

js_import_entry(Bare, Path) :-
    manifest_entry(Logical, Hashed),
    atom_string(LogicalA, Logical),
    atom_concat('js/', BareA0, LogicalA),
    atom_concat(BareA, '.js', BareA0),
    atom_string(BareA, Bare),
    format(string(Path), "/assets/~w", [Hashed]).

%!  imports_json(+Pairs, -Json) is det.
%
%   Hand-rolled (no dependency on http/json's dict machinery here,
%   since bare module names like "components/foo" are exactly the
%   kind of atom dict keys are awkward with): a JSON object literal
%   string, "bare" keys and "/assets/..." values, both JSON-escaped.
imports_json(Pairs, Json) :-
    msort(Pairs, Sorted),
    maplist(import_entry_json, Sorted, Entries),
    atomic_list_concat(Entries, ', ', Body),
    format(string(Json), "{~w}", [Body]).

import_entry_json(Bare-Path, Entry) :-
    json_escape(Bare, BareEsc),
    json_escape(Path, PathEsc),
    format(string(Entry), "\"~w\": \"~w\"", [BareEsc, PathEsc]).

%   Minimal JSON string escaping: backslash and double-quote only --
%   sufficient for the bare module names and /assets/ URLs this
%   predicate ever sees (no control characters, no user input).
json_escape(Text, Escaped) :-
    to_string(Text, S),
    split_string(S, "", "", [S1]),
    string_codes(S1, Codes),
    escape_codes(Codes, EscCodes),
    string_codes(Escaped, EscCodes).

escape_codes([], []).
escape_codes([C|Cs], Out) :-
    (   C == 0'\\ -> Out = [0'\\, 0'\\|Rest]
    ;   C == 0'"  -> Out = [0'\\, 0'"|Rest]
    ;   Out = [C|Rest]
    ),
    escape_codes(Cs, Rest).
