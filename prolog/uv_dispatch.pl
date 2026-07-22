:- module(uv_dispatch, [uv_invoke/2]).

/** <module> Trampoline used by c/uv_swi.c to call back into Prolog.

Every libuv callback registered from Prolog is an ordinary callable
(atom, or a compound with some arguments already bound). The C side
records that callable and, when the event fires, calls uv_invoke/2 with
the extra event arguments (the handle, the data, ...) appended. This
keeps all argument-list plumbing in Prolog instead of hand-building
arbitrary-arity terms in C.
*/

uv_invoke(Closure, Args) :-
    strip_module(Closure, M, Plain),
    Plain =.. L,
    append(L, Args, L2),
    Goal =.. L2,
    call(M:Goal).
