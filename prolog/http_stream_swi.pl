:- module(http_stream_swi, [ uv_response_stream/2 ]).

/** <module> Loader for c/http_stream_swi.so -- the response IOSTREAM
    (adr/0007). See prolog/uv_swi.pl for why every foreign library gets
    its own small exporting module like this one.
*/

%   Load through the `foreign` alias, not a raw path: qsave's
%   foreign(save) can only embed alias-loaded libraries (adr/0033),
%   and adr/0030 wants the location expressed, not computed.
:- prolog_load_context(directory, Dir),
   atomic_list_concat([Dir, '/../c'], CRel),
   absolute_file_name(CRel, CDir),
   (   user:file_search_path(foreign, CDir)
   ->  true
   ;   assertz(user:file_search_path(foreign, CDir))
   ),
   use_foreign_library(foreign(http_stream_swi)).
