:- module(adrs_commands,
          [ adr_slugs/1,            % -Slugs
            adr_markdown/2          % +Slug, -Markdown
          ]).

/** <module> The decision log as data (adr/0029 commands, adr/0033
decision 3): the content is static, so it is slurped ONCE at load
time into adr_doc/2 facts -- which means a `px build` binary carries
the whole log inside itself, and a running server never touches the
filesystem for it. The relations the controller sees are pure
lookups.
*/

:- use_module(library(apply)).
:- use_module(library(lists)).
:- use_module(library(readutil)).

%   adr_doc(Slug, Markdown), asserted in sorted slug order at load.
%   prolog_load_context here is a location use (adr/0030): where is
%   this file, therefore where is adr/.
:- dynamic adr_doc/2.

load_adr_docs(Here) :-
    atomic_list_concat([Here, '/../../adr'], Rel),
    absolute_file_name(Rel, Dir, [file_type(directory)]),
    directory_files(Dir, Files),
    include([F]>>sub_atom(F, _, 3, 0, '.md'), Files, MdFiles),
    maplist([F,S]>>atom_concat(S, '.md', F), MdFiles, Slugs0),
    sort(Slugs0, Slugs),
    forall(member(Slug, Slugs),
           ( format(atom(Path), '~w/~w.md', [Dir, Slug]),
             read_file_to_string(Path, Markdown, []),
             assertz(adr_doc(Slug, Markdown))
           )).

:- prolog_load_context(directory, Here),
   load_adr_docs(Here).

adr_slugs(Slugs) :-
    findall(S, adr_doc(S, _), Slugs).

%   The fact table is the whitelist: a hostile :id can only ever
%   look up a slug that was really in adr/ at load time.
adr_markdown(Slug, Markdown) :-
    atom_string(SlugAtom, Slug),
    adr_doc(SlugAtom, Markdown).
