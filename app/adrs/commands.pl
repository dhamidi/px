:- module(adrs_commands,
          [ adr_slugs/1,            % -Slugs
            adr_markdown/2          % +Slug, -Markdown
          ]).

/** <module> The decision log's side effects (adr/0029): this
feature's commands are file reads. Plain relations, no HTTP anywhere.
*/

:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(readutil)).

%   Where the ADRs live, resolved once at load time relative to this
%   file (app/adrs/ -> repo root -> adr/) -- a legitimate
%   prolog_load_context use per adr/0030: file location, not imports.

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
