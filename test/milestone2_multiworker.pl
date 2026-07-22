/* Milestone 2 (adr/0005): several independent workers, each its own
   thread+loop+engine, all bound to the same port via SO_REUSEPORT.
   Every reply is tagged with the worker id that handled it, so hitting
   the port repeatedly and seeing more than one id come back is direct
   proof the kernel is spreading connections across workers -- not one
   worker serializing everything. */

:- prolog_load_context(directory, Dir),
   atomic_list_concat([Dir, '/../prolog/worker'], WorkerLib),
   use_module(WorkerLib).

on_conn(Id, _Loop, Client) :-
    uv_read_start(Client, user:on_data(Id)).

on_data(_Id, Client, end_of_file) :- !, uv_close(Client, true).
on_data(Id, Client, Data) :-
    string_upper(Data, Up),
    format(string(Reply), "[worker ~w] ~w", [Id, Up]),
    uv_write(Client, Reply, user:noop1).

noop1(_Status).

:- initialization(main, main).

main :-
    current_prolog_flag(argv, [PortAtom]),
    !,
    atom_number(PortAtom, Port),
    start_workers(Port, 4, user:on_conn),
    thread_get_message(_).   % block forever; workers are detached threads
main :-
    main_with_default.

main_with_default :-
    start_workers(7003, 4, user:on_conn),
    thread_get_message(_).
