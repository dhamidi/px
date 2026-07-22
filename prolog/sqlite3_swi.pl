:- module(sqlite3_swi,
          [ sqlite3_open/2,             % sqlite3_open_v2
            sqlite3_close/1,            % sqlite3_close
            sqlite3_prepare/3,          % sqlite3_prepare_v2
            sqlite3_bind/3,             % sqlite3_bind_{int64,double,text,null}
            sqlite3_step/2,             % sqlite3_step
            sqlite3_column/3,           % sqlite3_column_type + accessor
            sqlite3_column_count/2,     % sqlite3_column_count
            sqlite3_column_name/3,      % sqlite3_column_name
            sqlite3_finalize/1,         % sqlite3_finalize
            sqlite3_reset/1,            % sqlite3_reset
            sqlite3_last_insert_rowid/2,% sqlite3_last_insert_rowid
            sqlite3_changes/2,          % sqlite3_changes
            sqlite3_errmsg/2            % sqlite3_errmsg
          ]).

/** <module> Loader for c/sqlite3_swi.so, the 1:1 SQLite FFI (adr/0002, adr/0020).

Foreign predicates registered by a shared library land in whatever
module is "current" when use_foreign_library/1 runs -- which, without
this dedicated loader module, would silently be whichever module
happens to load the library first. Giving the library its own module
with an explicit export list means every predicate below is reliably
importable from any module via use_module/1, regardless of load order.
*/

:- prolog_load_context(directory, Dir),
   atomic_list_concat([Dir, '/../c/sqlite3_swi'], LibBase),
   use_foreign_library(LibBase).
