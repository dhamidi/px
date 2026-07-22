/* Milestone 4 (adr/0004): proves the timer and fs halves of the libuv FFI
   added alongside TCP actually round-trip through the C boundary --
   uv_timer_init/2, uv_timer_start/4, uv_timer_stop/1 and uv_fs_open/5,
   uv_fs_read/5, uv_fs_close/3. Not the framework; just the smallest
   possible proof each new predicate works end to end, same spirit as
   milestone1_echo.pl (direct uv_run in the main thread, no worker pool
   needed for a smoke test like this one). */

:- use_module('../prolog/uv_dispatch').
:- use_module('../prolog/uv_swi').

test_file('/tmp/prologex_milestone4_test.txt').

write_test_file :-
    test_file(Path),
    setup_call_cleanup(
        open(Path, write, S),
        format(S, "hello from milestone4~nsecond line~n", []),
        close(S)).

main :-
    write_test_file,
    uv_loop_new(Loop),
    nb_setval(m4_timer_count, 0),

    %% -- timer half: fires a few times, then closes itself --
    uv_timer_init(Loop, Timer),
    uv_timer_start(Timer, 100, 150, user:on_tick(Timer)),

    %% -- fs half: open -> read -> close a real file --
    test_file(Path),
    uv_fs_open(Loop, Path, 0, 0, user:on_open(Loop)),

    format(user_error, "milestone4: starting loop~n", []),
    uv_run(Loop, default),
    format(user_error, "milestone4: loop drained, done~n", []).

%% closures registered from Prolog must be module-qualified (user:...)
%% because uv_dispatch:uv_invoke/2 does strip_module/3 + call(M:Goal) --
%% see the CRITICAL note in c/uv_swi.c's predicate-registration comments.

on_tick(Timer) :-
    nb_getval(m4_timer_count, N0),
    N is N0 + 1,
    nb_setval(m4_timer_count, N),
    format("timer tick ~w~n", [N]),
    (   N >= 3
    ->  uv_timer_stop(Timer),
        uv_close(Timer, true)
    ;   true
    ).

on_open(_Loop, Fd) :-
    Fd < 0,
    !,
    format("fs_open failed, result=~w~n", [Fd]).
on_open(Loop, Fd) :-
    format("fs_open ok, fd=~w~n", [Fd]),
    uv_fs_read(Loop, Fd, 4096, 0, user:on_read(Loop, Fd)).

on_read(Loop, Fd, Result, Data) :-
    format("fs_read result=~w data=~q~n", [Result, Data]),
    uv_fs_close(Loop, Fd, user:on_fs_close).

on_fs_close(Result) :-
    format("fs_close result=~w~n", [Result]).

:- initialization(main, main).
