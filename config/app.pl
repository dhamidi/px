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

%% Env-driven (adr/0022): DATABASE_PATH overrides in any environment
%% (a real deploy points it at /var/lib; the dev instance on 8092 sets
%% its own path so its guestbook writes don't touch production's),
%% defaulting to the writable local data dir.
config(database, env('DATABASE_PATH', "data/prologex.db")).
