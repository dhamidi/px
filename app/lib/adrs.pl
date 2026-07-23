:- module(adrs,
          [ adr_slugs/1,            % -Slugs
            adr_markdown/2          % +Slug, -Markdown
          ]).

/** <module> The decision log as a data source (adr/0027 app/lib):
plain relations, no HTTP anywhere.
*/

:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(readutil)).

%   Where the ADRs live, resolved once at load time relative to this
%   file (app/lib/ -> repo root -> adr/).

:- dynamic adr_dir/1.

:- prolog_load_context(directory, Here),
   atomic_list_concat([Here, '/../../adr'], Rel),
   absolute_file_name(Rel, Dir, [file_type(directory)]),
   assertz(adr_dir(Dir)).

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
