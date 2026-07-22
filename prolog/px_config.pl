:- module(px_config,
          [ load_config/1,      % +Path
            config/2,           % ?Key, ?Value
            require_config/2,   % +Key, -Value
            current_env/1       % -Env
          ]).

/** <module> Configuration subsystem, per adr/0022.

Configuration is a plain Prolog file (canonically config/app.pl)
containing facts of two shapes:

    config(Key, Value).          % base fact, valid in every environment
    config(Env, Key, Value).     % overlay, valid only when Env is current

Because the file is loaded as Prolog, a "fact" may be a rule:

    config(workers, N) :- current_prolog_flag(cpu_count, N).

load_config/1 loads the file's clauses into the reserved internal
module px_config_data -- never into user -- so app code cannot collide
with the framework and the config file cannot redefine framework
internals. The public lookup predicates below are the only supported
access path.

Lookup precedence (config/2): the overlay config(CurrentEnv, Key, V)
is tried first; if no overlay fact for Key exists in the current
environment, the base config(Key, V) is used. The current environment
comes from the OS environment variable PROLOGEX_ENV, defaulting to
`development`.

Values may be env(Name, Default) or env(Name) terms, resolved against
the OS environment at lookup time. Resolved values are typed: a value
string that parses as a number comes back as a number, not an atom
(env('PORT', 8090) with PORT=8091 yields the integer 8091).
*/

:- dynamic config_file/1.

% The reserved data module. Declared dynamic so that lookups before
% load_config/1 (or against a config file that only uses one of the
% two shapes) fail cleanly instead of raising existence errors.
:- dynamic px_config_data:config/2.
:- dynamic px_config_data:config/3.

%!  load_config(+Path) is det.
%
%   Load the configuration file at Path into px_config_data,
%   replacing any previously loaded config/2 and config/3 clauses.
%   Facts, rules (clauses with bodies), and `:- Goal` directives are
%   supported; everything is asserted/executed inside px_config_data.
load_config(Path) :-
    absolute_file_name(Path, Abs, [access(read)]),
    retractall(px_config_data:config(_, _)),
    retractall(px_config_data:config(_, _, _)),
    setup_call_cleanup(
        open(Abs, read, In),
        load_config_terms(In),
        close(In)),
    retractall(config_file(_)),
    assertz(config_file(Path)).

load_config_terms(In) :-
    read_term(In, Term, []),
    (   Term == end_of_file
    ->  true
    ;   assert_config_term(Term),
        load_config_terms(In)
    ).

assert_config_term((:- Goal)) :-
    !,
    (   catch(px_config_data:Goal, Error,
              ( print_message(error, Error), fail ))
    ->  true
    ;   true
    ).
assert_config_term((Head :- Body)) :-
    !,
    assertz(px_config_data:(Head :- Body)).
assert_config_term(Head) :-
    assertz(px_config_data:Head).

%!  current_env(-Env) is det.
%
%   The current environment: the value of the OS environment variable
%   PROLOGEX_ENV, or `development` when unset (or empty).
current_env(Env) :-
    (   getenv('PROLOGEX_ENV', Value),
        Value \== ''
    ->  Env = Value
    ;   Env = development
    ).

%!  config(?Key, -Value) is nondet.
%
%   Look up a configuration value. The overlay for the current
%   environment wins; the base fact is the fallback. env(Name,
%   Default)/env(Name) value terms are resolved against the OS
%   environment at lookup time (see resolve_value/2). Fails silently
%   for keys with no fact -- use require_config/2 for config the app
%   cannot run without.
config(Key, Value) :-
    current_env(CurrentEnv),
    (   px_config_data:config(CurrentEnv, Key, Raw)
    *-> true
    ;   px_config_data:config(Key, Raw)
    ),
    resolve_value(Raw, Value).

%!  require_config(+Key, -Value) is det.
%
%   Like config/2, but a missing key throws a clear error naming the
%   key, the config file, and the current environment, instead of
%   failing silently.
require_config(Key, Value) :-
    (   config(Key, Value0)
    ->  Value = Value0
    ;   current_env(Env),
        (   config_file(Path)
        ->  true
        ;   Path = 'config/app.pl (no config file loaded)'
        ),
        format(string(Message),
               "prologex config: missing required key `~w'. Looked in ~w (environment: ~w). Define config(~w, ...) there, or set the OS environment variable named in its env(...) term.",
               [Key, Path, Env, Key]),
        throw(error(existence_error(prologex_config, Key),
                    context(px_config:require_config/2, Message)))
    ).

%!  resolve_value(+Raw, -Value) is semidet.
%
%   Resolve env(Name, Default) / env(Name) terms against the OS
%   environment. env/1 with the variable unset fails (pair it with
%   require_config/2). Anything else passes through unchanged.
resolve_value(env(Name, Default), Value) :-
    !,
    (   getenv(Name, Text)
    ->  typed_env_value(Text, Value)
    ;   Value = Default
    ).
resolve_value(env(Name), Value) :-
    !,
    getenv(Name, Text),
    typed_env_value(Text, Value).
resolve_value(Value, Value).

typed_env_value(Text, Value) :-
    atom_codes(Text, Codes),
    (   catch(number_codes(Number, Codes), _, fail)
    ->  Value = Number
    ;   Value = Text
    ).
