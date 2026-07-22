/* Milestone 6: a real HTTP request over a real socket, parsed by llhttp,
   handled by a Prolog goal, and answered through the http_stream
   response IOSTREAM -- the whole stack (adr/0005 worker model,
   adr/0007 streaming, adr/0002 1:1 FFI split) wired together end to
   end, proven with a real curl client rather than raw nc bytes. */

:- prolog_load_context(directory, Dir),
   atomic_list_concat([Dir, '/../prolog/worker'], WorkerLib),
   atomic_list_concat([Dir, '/../prolog/http_stream'], HttpStreamLib),
   use_module(WorkerLib),
   use_module(HttpStreamLib).

my_handler(Request, Stream) :-
    format(string(Body), "you asked for ~w ~w~n", [Request.method, Request.url]),
    string_length(Body, Len),
    format(Stream,
           "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: ~w\r\nConnection: close\r\n\r\n~w",
           [Len, Body]),
    close(Stream).

on_conn(Id, Loop, Client) :-
    call(http_stream:handle_connection(user:my_handler), Id, Loop, Client).

:- initialization(main, main).

main :-
    current_prolog_flag(argv, [PortAtom]),
    !,
    atom_number(PortAtom, Port),
    start_workers(Port, 1, user:on_conn),
    thread_get_message(_).
main :-
    start_workers(7006, 1, user:on_conn),
    thread_get_message(_).
