:- module(uv_swi,
          [ uv_loop_new/1,
            uv_tcp_init/2,
            uv_tcp_bind_reuseport/3,
            uv_listen/3,
            uv_accept/2,
            uv_read_start/2,
            uv_read_stop/1,
            uv_write/3,
            uv_close/2,
            uv_async_init/3,
            uv_async_send/1,
            uv_timer_init/2,
            uv_timer_start/4,
            uv_timer_stop/1,
            uv_fs_open/5,
            uv_fs_read/5,
            uv_fs_close/3,
            uv_run/2,
            uv_stop/1
          ]).

/** <module> Loader for c/uv_swi.so, the 1:1 libuv FFI (adr/0002, adr/0004).

Foreign predicates registered by a shared library land in whatever
module is "current" when use_foreign_library/1 runs -- which, without
this dedicated loader module, would silently be whichever module
happens to load the library first. Giving the library its own module
with an explicit export list means every predicate below is reliably
importable from any module via use_module/1 or worker.pl's reexport,
regardless of load order.
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
   use_foreign_library(foreign(uv_swi)).
