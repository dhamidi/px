:- module(guestbook_messages, []).

/** <module> The guestbook's HTTP intent vocabulary (adr/0029).
Posting the sign form delivers sign(ok(Values)) or
sign(invalid(Values, Errors)) to the controller's update/4 --
validation happens at the edge, before any update clause runs.
*/

:- use_module(library(prologex)).

:- form(sign,
     [ field(author, text,     [required, max_length(80)]),
       field(body,   textarea, [required, max_length(1000)])
     ]).
