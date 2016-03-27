%%%-----------------------------------------------------------------------------
%%% @author Martin Wiso <martin@wiso.cz>
%%% @doc
%%% Main VFFOV supervisor
%%% @end
%%% Created : 5 Mar 2013 by tgrk <martin@wiso.cz>
%%%-----------------------------------------------------------------------------
-module(vffov_sup).
-include("vffov.hrl").
-behaviour(supervisor).

%% API
-export([start_link/0, start_worker/2]).
-export([get_stats/0]).

%% Supervisor callbacks
-export([init/1]).

%%=============================================================================
%% API functions
%%=============================================================================
-spec start_link() -> {ok, pid()} | ignore | {error, any()}.
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

-spec start_worker(workers(), url()) -> pid() | no_return().
start_worker(vffov_parallel_worker = Worker, Url) ->
    case supervisor:start_child(?MODULE, get_child(Worker, Url)) of
        {error, Reason} ->
            throw({unable_to_start_worker, Worker, Reason});
        {ok, Pid} ->
            update_stats(downloads),
            Pid
    end;
start_worker(vffov_queued_worker = Worker, Url) ->
    case get_queue_worker_pids() of
        [WorkerPid] ->
            ok = gen_server:cast(WorkerPid, {enqueue, Url}),
            update_stats(downloads),
            WorkerPid;
        [] ->
            case supervisor:start_child(?MODULE, get_child(Worker, Url)) of
                {error, Reason} ->
                    throw({unable_to_start_worker, Worker, Reason});
                {ok, Pid} ->
                    update_stats(downloads),
                    Pid
            end
    end.

-spec get_stats() -> [{{vffov, workers}, integer()}].
get_stats() ->
    StatsPL = supervisor:count_children(?MODULE),
    [{{vffov, workers}, proplists:get_value(workers, StatsPL, 0)}].

%%=============================================================================
%% Supervisor callbacks
%%=============================================================================
init([]) ->
    ChildSpecs = [
                  statman_aggregator(),
                  statman_elli(),
                  elli(),
                  notifications_server()
                 ],
    {ok, {{one_for_one, 5, 10}, lists:flatten(ChildSpecs)}}.

%%%============================================================================
%%% Internal functions
%%%============================================================================
get_child(vffov_queued_worker = Worker, Arg) ->
    {Worker, {Worker, start_link, [Arg]}, temporary, brutal_kill,
     worker, [Worker]};
get_child(Worker, Arg) ->
    {_, _, Mics} = erlang:now(),
    Name = list_to_atom(atom_to_list(Worker) ++ "_" ++ integer_to_list(Mics)),
    {Name, {Worker, start_link, [Name, Arg]}, temporary, brutal_kill,
     worker, [Worker]}.

update_stats(downloads) ->
    Count = length([PL || {_, PL, _} <- simple_cache:ops_list(),
                          proplists:get_value(status, PL) =:= finished]),
    statman_gauge:set(downloads, Count).

notifications_server() ->
    case is_api_enabled() of
        true  -> {vffov_notify_server, {vffov_notify_server, start_link, []},
                  permanent, 5000, worker, []};
        false -> []
    end.

get_queue_worker_pids() ->
    lists:filtermap(
      fun ({_Id, _Pid, worker, [vffov_parallel_worker]}) ->
              false;
          ({_Id, Pid, worker, [vffov_queued_worker]}) ->
              {true, Pid};
          (_) ->
              false
      end, supervisor:which_children(vffov_sup)).

%% Childspecs required by statman dashboard
statman_aggregator() ->
    {statman_aggregator, {statman_aggregator, start_link, []},
     permanent, 5000, worker, []}.

statman_elli() ->
    {statman_elli, {statman_elli_server, start_link, []},
     permanent, 5000, worker, []}.

elli() ->
    Opts = [{callback, elli_middleware},
            {callback_args, [{mods, get_elli_mods()}]},
            {port, application:get_env(vffov, api_port, 8081)}
           ],
    {elli, {elli, start_link, [Opts]}, permanent, 5000, worker, []}.

get_elli_mods() ->
    {ok, Cwd} = file:get_cwd(),
    StatmanConfig = [{name, collect_statman_elli},
                     {docroot, filename:join(
                                 [Cwd, "deps/statman_elli/priv/docroot"]
                                )
                     }],
    DefaultMods = [{statman_elli, StatmanConfig},
                   {elli_access_log, []}],

    ApiMod = case is_api_enabled() of
                 true  -> [{vffov_api, []}];
                 false -> []
             end,
    lists:concat([DefaultMods, ApiMod]).

is_api_enabled() ->
    {ok, Enabled} =  application:get_env(vffov, enable_api),
    Enabled.
