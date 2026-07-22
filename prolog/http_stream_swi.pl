:- module(http_stream_swi, [ uv_response_stream/2 ]).

/** <module> Loader for c/http_stream_swi.so -- the response IOSTREAM
    (adr/0007). See prolog/uv_swi.pl for why every foreign library gets
    its own small exporting module like this one.
*/

:- prolog_load_context(directory, Dir),
   atomic_list_concat([Dir, '/../c/http_stream_swi'], LibBase),
   use_foreign_library(LibBase).
