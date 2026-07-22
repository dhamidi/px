%% apps/adr_site.pl -- the prologex demo app, v2 (adr/0016 surface).
%%
%% The same ADR browser as v1 -- list adr/*.md at "/", render one as
%% HTML at "/adr/:id" through the framework's own markdown engine,
%% serve the stylesheet and vendored turbo.js through the content-hashed
%% asset pipeline (adr/0025) -- rewritten on the Rails layer, plus a
%% sqlite-backed guestbook (/comments) proving the full stack: resources
%% routing, forms with validation and 422 re-render, the query builder,
%% and Turbo streams/frames.
%%
%% Everything below is north-star syntax: `~>` templates, env-relation
%% handlers, path-helper terms, respond/redirect -- no format-string
%% HTML, no module-qualified handlers, no Stream variables.

:- prolog_load_context(directory, Here),
   atomic_list_concat([Here, '/../prolog/prologex'], PrologexLib),
   use_module(PrologexLib).

%% Where the ADRs live, resolved once at load time.

:- dynamic adr_dir/1.

:- prolog_load_context(directory, Here),
   atomic_list_concat([Here, '/../adr'], AdrRel),
   absolute_file_name(AdrRel, AdrDir, [file_type(directory)]),
   assertz(adr_dir(AdrDir)).

%% Routes (adr/0018). "/assets/:file" is the asset pipeline (adr/0025):
%% serve_asset/2 is px_assets:serve_asset/2, reexported by the prologex
%% facade and therefore already imported into this module by
%% `use_module(PrologexLib)` above -- no local wrapper needed, same as
%% respond/3 or row/2.

:- route(get, "/", home_page).
:- route(get, "/adr/:id", adr_show).
:- route(get, "/assets/:file", serve_asset).
:- resources(comments, [only([index, create])]).

%% Guestbook schema: rides with the app, applied once per worker
%% connection right after the database opens.

:- schema("create table if not exists comments (
             id integer primary key,
             author text not null,
             body text not null,
             created_at text not null default current_timestamp)").

%% The guestbook form (adr/0023).

:- form(comment_form,
     [ field(author, text,     [required, max_length(80)]),
       field(body,   textarea, [required, max_length(1000)])
     ]).

%% Handlers: Env0 -> Env relations (adr/0017).

home_page(Env0, Env) :-
    adr_slugs(Slugs),
    respond(Env0, home_view(Slugs), Env).

adr_show(Env0, Env) :-
    Slug = Env0.params.id,
    (   adr_markdown(Slug, Markdown)
    ->  respond(Env0, adr_view(Slug, Markdown), Env)
    ;   not_found(Env0, Env)
    ).

index(Env0, Env) :-
    all_comments(Comments),
    respond(Env0, comments_view(Comments, _{}, []), Env).

create(Env0, Env) :-
    form_result(comment_form, Env0, Result),
    (   Result = ok(Values)
    ->  insert(comments, Values, Id),
        once(row(q(comments, [where(id == Id)]), Comment)),
        turbo_or_redirect(Env0, comments_path,
            [ prepend(comments, comment_card(Comment)) ], Env)
    ;   Result = invalid(Values, Errors),
        all_comments(Comments),
        respond(Env0, comments_view(Comments, Values, Errors),
                [status(422)], Env)
    ).

%% Templates (adr/0019).

layout(Title, Content) ~>
    [ raw("<!DOCTYPE html>\n"),
      html(
        [ head(
            [ meta(charset("utf-8")),
              title(Title),
              stylesheet_tag("css/app.css"),
              stylesheet_tag("css/ui.css"),
              \javascript_importmap_tags
            ]),
          body(div(class(page), Content))
        ])
    ].

home_view(Slugs) ~>
    layout("prologex — design decisions",
      [ h1("prologex — design decisions"),
        p("An experimental SWI-Prolog HTTP framework: llhttp and libuv bound via SWI's C FFI, a Rails-flavoured layer built on top in pure Prolog, and this page itself — rendered from the markdown decision log below by the framework's own markdown engine."),
        p(link_to("Sign the guestbook →", comments_path)),
        ul(class("adr-list"), each(Slugs, adr_item))
      ]).

adr_item(Slug) ~>
    li(link_to(Slug, path_for(adr_show, [id=Slug]))).

adr_view(Slug, Markdown) ~>
    layout(Slug,
      [ p(class(back), link_to("← all decisions", "/")),
        markdown(Markdown)
      ]).

comments_view(Comments, Values, Errors) ~>
    layout("Guestbook — prologex",
      [ p(class(back), link_to("← all decisions", "/")),
        h1("Guestbook"),
        turbo_frame(comments, each(Comments, comment_card)),
        h2("Sign the guestbook"),
        form_for(comment_form, comments_path, Values, Errors)
      ]).

comment_card(C) ~>
    article(class(card),
      [ p(strong(C.author)),
        p(C.body),
        p(small(C.created_at))
      ]).

%% Plain relations feeding the handlers.

adr_slugs(Slugs) :-
    adr_dir(Dir),
    directory_files(Dir, Files),
    include([F]>>sub_atom(F, _, 3, 0, '.md'), Files, MdFiles),
    maplist([F,S]>>atom_concat(S, '.md', F), MdFiles, Slugs0),
    sort(Slugs0, Slugs).

%   The listing is the whitelist: only a slug that is actually in
%   adr/ reads a file, so a hostile :id can never leave the directory.
adr_markdown(Slug, Markdown) :-
    atom_string(SlugAtom, Slug),
    adr_slugs(Slugs),
    memberchk(SlugAtom, Slugs),
    adr_dir(Dir),
    format(atom(Path), '~w/~w.md', [Dir, SlugAtom]),
    read_file_to_string(Path, Markdown, []).

all_comments(Comments) :-
    findall(C, row(q(comments, [order_by(desc(id))]), C), Comments).

%% px_ui kitchen-sink (adr/0026).

:- prolog_load_context(directory, Here3),
   atomic_list_concat([Here3, '/../prolog/px_ui'], PxUiLib),
   use_module(PxUiLib).

:- route(get, "/ui", ui_index).
:- route(get, "/ui/:name", ui_show).

ui_index(Env0, Env) :- px_ui:ui_index(Env0, Env).
ui_show(Env0, Env)  :- px_ui:ui_show(Env0, Env).

:- initialization(prologex_run).

