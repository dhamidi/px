/* Milestone 1 (adr/0005): a single worker -- one thread, one uv_loop_t,
   one attached Prolog engine -- proving a libuv read callback can call
   directly, synchronously into Prolog on its own thread. Uppercases
   whatever it reads back to the client. Not the framework; just the
   smallest possible proof the FFI + worker model works end to end. */

:- use_module('../prolog/uv_dispatch').
:- use_module('../prolog/uv_swi').

start_worker(Port) :-
    uv_loop_new(Loop),
    uv_tcp_init(Loop, Server),
    uv_tcp_bind_reuseport(Server, '0.0.0.0', Port),
    uv_listen(Server, 128, user:on_connection(Loop)),
    format(user_error, "milestone1: listening on ~w~n", [Port]),
    uv_run(Loop, default).

on_connection(Loop, Server, _Status) :-
    uv_tcp_init(Loop, Client),
    uv_accept(Server, Client),
    uv_read_start(Client, user:on_data).

on_data(Client, end_of_file) :-
    !,
    uv_close(Client, true).
on_data(Client, Data) :-
    string_upper(Data, Up),
    uv_write(Client, Up, user:noop1).

noop1(_Status).

:- initialization(main, main).

main :-
    current_prolog_flag(argv, [PortAtom]),
    !,
    atom_number(PortAtom, Port),
    start_worker(Port).
main :-
    start_worker(7000).
