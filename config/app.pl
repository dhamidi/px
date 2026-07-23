%% config/app.pl -- application configuration for this repo (adr/0022).
%%
%% Loaded by px_config:load_config/1 into the reserved module
%% px_config_data; query it only through px_config:config/2 and
%% px_config:require_config/2, never directly.
%%
%% Shapes:
%%   config(Key, Value).         base fact, valid in every environment
%%   config(Env, Key, Value).    overlay, only when PROLOGEX_ENV=Env
%%
%% Values may be env('NAME', Default) / env('NAME') terms, resolved
%% against the OS environment at lookup time (numeric strings come
%% back as numbers). Secrets never appear here as literals -- they
%% enter as env(...) terms set by the systemd unit (adr/0012).

config(port, env('PORT', 8090)).
config(workers, 2).
config(database, "data/prologex.db").

%% Environment overlay: applies only when PROLOGEX_ENV=production.
%% Env-driven (adr/0022) so a real system install points at
%% /var/lib via DATABASE_PATH, while this --user sandbox deploy just
%% keeps the writable local data dir -- no hardcoded system path that
%% the running user may not be able to create.
config(production, database, env('DATABASE_PATH', "data/prologex.db")).
