/* Milestone 16 (adr/0025): the asset pipeline, prolog/px_assets.pl,
   standalone -- no HTTP server, no sockets. Runs compile_assets/0
   against the REAL assets/ directory (assets/css/app.css,
   assets/js/app.js, assets/js/turbo.js -- the only three files it
   ships with) and REAL public/assets/ output, since compile_assets/0
   is a zero-argument predicate over fixed, repo-root-relative paths
   (adr/0025 section 2) -- there is nothing to sandbox. Every test that
   mutates a source file (the stale-cleanup test) restores it in a
   setup_call_cleanup/3 cleanup goal and recompiles at the very end, so
   the repository is left exactly as it was found.

   Covers:
     - compile_assets/0 creates a hashed copy + ".gz" sibling for every
       source file, and public/assets/.manifest.json round-trips
       through JSON to the same logical->hashed mapping the in-memory
       table holds
     - idempotent: recompiling with no source changes reproduces byte-
       identical hashed filenames
     - stale-file cleanup: changing a source file's content orphans
       its old hashed file (and .gz), which the next compile deletes
     - asset_path/2 resolves a known logical name and throws
       existence_error(asset, Logical) for an unknown one
     - serve_asset/2: the manifest is the whitelist (an unlisted
       filename is a 404, not a filesystem check); a known hashed file
       serves 200 with cache-control: public, max-age=31536000,
       immutable; an Accept-Encoding: gzip request against a file with
       a .gz sibling gets content-encoding: gzip + vary: accept-
       encoding, and THOSE BYTES GUNZIP BACK to the original source
       (the binary-safety round-trip adr/0025 section 4 is about)

   Run:  swipl test/milestone16_assets.pl
*/

:- prolog_load_context(directory, Dir),
   atomic_list_concat([Dir, '/../prolog/px_assets'], PxAssetsLib),
   use_module(PxAssetsLib).

:- use_module(library(zlib)).
:- use_module(library(http/json)).

:- discontiguous test/1.

:- initialization(main, main).

main :-
    Tests = [ compile_creates_hashed_and_gz_and_manifest,
              manifest_json_roundtrips,
              idempotent_recompile,
              asset_path_resolves_known,
              asset_path_unknown_throws,
              stale_file_cleanup,
              serve_asset_whitelist_only,
              serve_asset_plain_headers,
              serve_asset_gzip_negotiation_roundtrips
            ],
    run_tests(Tests, 0, Failed),
    length(Tests, N),
    ( Failed =:= 0
    -> format("milestone16_assets: all ~w tests passed~n", [N]),
       halt(0)
    ;  format(user_error, "milestone16_assets: ~w of ~w test(s) FAILED~n",
             [Failed, N]),
       halt(1)
    ).

run_tests([], Failed, Failed).
run_tests([T|Ts], Failed0, Failed) :-
    ( catch(test(T), Error,
            ( print_message(error, Error), fail ))
    -> format("  ok: ~w~n", [T]),
       Failed1 = Failed0
    ;  format(user_error, "  FAILED: ~w~n", [T]),
       Failed1 is Failed0 + 1
    ),
    run_tests(Ts, Failed1, Failed).

expect(Goal) :-
    ( call(Goal)
    -> true
    ;  format(user_error, "    expected to succeed: ~q~n", [Goal]),
       fail
    ).

           /*******************************
           *          HELPERS             *
           *******************************/

%   prolog_load_context/2 only answers inside a directive running AT
%   LOAD TIME -- called later from an ordinary predicate it just
%   fails, so the test directory is captured once, here.
:- dynamic test_dir/1.
:- prolog_load_context(directory, Dir),
   assertz(test_dir(Dir)).

repo_asset_path(Rel, Path) :-
    test_dir(Dir),
    atomic_list_concat([Dir, '/../', Rel], Path0),
    absolute_file_name(Path0, Path).

public_asset_file(Hashed, Path) :-
    test_dir(Dir),
    atomic_list_concat([Dir, '/../public/assets/', Hashed], Path).

fake_env(Headers, Params,
         env{ method: get, path: "/assets/x", raw_path: "/assets/x",
              headers: Headers, params: Params, body: "",
              worker: 1, config: px_config,
              response: _{status: 200, headers: [], body: none} }).

           /*******************************
           *           TESTS              *
           *******************************/

%   compile_assets/0 over the real three-file assets/ tree: a hashed
%   copy + gzip sibling for each, and the in-memory manifest agrees.
test(compile_creates_hashed_and_gz_and_manifest) :-
    compile_assets,
    forall(member(Logical, ["css/app.css", "js/app.js", "js/turbo.js"]),
           ( px_assets:manifest_entry(Logical, Hashed),
             public_asset_file(Hashed, Path),
             atom_concat(Path, '.gz', GzPath),
             expect(exists_file(Path)),
             expect(exists_file(GzPath))
           )).

%   public/assets/.manifest.json, read back through the JSON round
%   trip, names exactly the hashed files the in-memory table has.
test(manifest_json_roundtrips) :-
    compile_assets,
    test_dir(Dir),
    atomic_list_concat([Dir, '/../public/assets/.manifest.json'], ManifestPath),
    setup_call_cleanup(
        open(ManifestPath, read, In),
        json_read_dict(In, Dict, [value_string_as(string)]),
        close(In)),
    dict_pairs(Dict, _, Pairs),
    forall(member(K-V, Pairs),
           ( atom_string(K, Ks),
             expect(px_assets:manifest_entry(Ks, V))
           )).

%   Recompiling with nothing changed reproduces the exact same
%   manifest -- the hash is a pure function of content.
test(idempotent_recompile) :-
    compile_assets,
    findall(L-H, px_assets:manifest_entry(L, H), P1),
    compile_assets,
    findall(L-H, px_assets:manifest_entry(L, H), P2),
    expect(P1 == P2).

test(asset_path_resolves_known) :-
    compile_assets,
    asset_path("css/app.css", Path),
    px_assets:manifest_entry("css/app.css", Hashed),
    format(string(Expected), "/assets/~w", [Hashed]),
    expect(Path == Expected).

test(asset_path_unknown_throws) :-
    compile_assets,
    expect(catch(( asset_path("nope/does-not-exist.css", _), fail),
                 error(existence_error(asset, "nope/does-not-exist.css"), _),
                 true)).

%   Changing assets/css/app.css's content orphans its current hashed
%   file; the next compile both mints the new one AND deletes the old
%   hashed file + its .gz. The source is restored (and re-compiled
%   back to its original hash) in the cleanup goal no matter how the
%   test body finishes.
test(stale_file_cleanup) :-
    repo_asset_path('assets/css/app.css', SrcPath),
    read_file_to_string(SrcPath, Original, [encoding(iso_latin_1)]),
    setup_call_cleanup(
        true,
        run_stale_cleanup_body(SrcPath, Original),
        restore_and_recompile(SrcPath, Original)).

run_stale_cleanup_body(SrcPath, Original) :-
    compile_assets,
    px_assets:manifest_entry("css/app.css", OldHashed),
    public_asset_file(OldHashed, OldPath),
    atom_concat(OldPath, '.gz', OldGzPath),
    expect(exists_file(OldPath)),
    % Mutate the source (append a comment -- still valid CSS) and
    % recompile.
    string_concat(Original, "\n/* milestone16 stale-cleanup probe */\n", Mutated),
    setup_call_cleanup(
        open(SrcPath, write, Out, [encoding(iso_latin_1)]),
        format(Out, "~s", [Mutated]),
        close(Out)),
    compile_assets,
    px_assets:manifest_entry("css/app.css", NewHashed),
    expect(NewHashed \== OldHashed),
    public_asset_file(NewHashed, NewPath),
    atom_concat(NewPath, '.gz', NewGzPath),
    expect(exists_file(NewPath)),
    expect(exists_file(NewGzPath)),
    % The OLD hashed file and its .gz are gone -- stale cleanup.
    expect(\+ exists_file(OldPath)),
    expect(\+ exists_file(OldGzPath)).

restore_and_recompile(SrcPath, Original) :-
    setup_call_cleanup(
        open(SrcPath, write, Out, [encoding(iso_latin_1)]),
        format(Out, "~s", [Original]),
        close(Out)),
    compile_assets.

%   The whitelist is the manifest's values, full stop -- an arbitrary
%   filename (even one shaped exactly like a hashed name) that is not
%   actually in the manifest is a 404, never a filesystem lookup.
test(serve_asset_whitelist_only) :-
    compile_assets,
    fake_env([], _{file: "not-a-real-asset-000000000000.css"}, Env0),
    serve_asset(Env0, Env),
    expect(Env.response.status == 404).

test(serve_asset_plain_headers) :-
    compile_assets,
    px_assets:manifest_entry("css/app.css", Hashed),
    fake_env([], _{file: Hashed}, Env0),
    serve_asset(Env0, Env),
    expect(Env.response.status == 200),
    expect(memberchk("content-type"-"text/css; charset=utf-8", Env.response.headers)),
    expect(memberchk("cache-control"-"public, max-age=31536000, immutable",
                     Env.response.headers)),
    expect(Env.response.body = raw_bytes(_)).

%   Accept-Encoding: gzip against a file with a .gz sibling serves
%   THOSE bytes (content-encoding: gzip, vary: accept-encoding), and
%   they gunzip back to the untouched original source -- the binary-
%   safety round trip (adr/0025 section 4).
test(serve_asset_gzip_negotiation_roundtrips) :-
    compile_assets,
    px_assets:manifest_entry("css/app.css", Hashed),
    fake_env(["accept-encoding"-"gzip, deflate, br"], _{file: Hashed}, Env0),
    serve_asset(Env0, Env),
    expect(Env.response.status == 200),
    expect(memberchk("content-encoding"-"gzip", Env.response.headers)),
    expect(memberchk("vary"-"accept-encoding", Env.response.headers)),
    Env.response.body = raw_bytes(GzBytes),
    setup_call_cleanup(
        open('/tmp/milestone16_gzip_roundtrip.gz', write, Out, [encoding(octet)]),
        write(Out, GzBytes),
        close(Out)),
    setup_call_cleanup(
        gzopen('/tmp/milestone16_gzip_roundtrip.gz', read, In, [type(binary)]),
        read_string(In, _, Decompressed),
        close(In)),
    repo_asset_path('assets/css/app.css', SrcPath),
    read_file_to_string(SrcPath, Original, [encoding(iso_latin_1)]),
    expect(Decompressed == Original),
    delete_file('/tmp/milestone16_gzip_roundtrip.gz').
