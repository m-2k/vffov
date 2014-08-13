%%%-----------------------------------------------------------------------------
%%% @author Martin Wiso <martin@wiso.cz>
%%% @doc
%%% VFFOV REST API
%%% @end
%%% Created : 1 Aug 2014 by tgrk <martin@wiso.cz>
%%%-----------------------------------------------------------------------------
-module(vffov_api).
-behaviour(elli_handler).

%%TODO: notification using EventSource

%% API
-export([handle/2, handle_event/3]).

%%%============================================================================
%%% API
%%%============================================================================
handle(Req, _Args) ->
    try
        Path = elli_request:path(Req),
        case elli_request:method(Req) of
            'GET' ->
                get(Path, Req);
            'POST' ->
                post(Path, Req);
            'OPTIONS' ->
                options(Path, Req)
        end
    catch
        _Class:Reason ->
            vffov_utils:verbose(error, "Unable to handle API request - ~p!",
                                [Reason]),
            return(500, <<"Internal error">>)
    end.

handle_event(_, _, _) ->
    ok.

%%%============================================================================
%%% REST API
%%%============================================================================
get([<<"stream">>], Req) ->
    ok = vffov_notify_server:add_client(elli_request:chunk_ref(Req)),
    {chunk, [{<<"Content-Type">>, <<"text/event-stream">>}]};
get([<<"queue">>], _Req) ->
    case vffov:queue() of
        []        -> return_json({[]});
        [{[],[]}] -> return_json({[]});
        Queue     ->
            L = queue:to_list(Queue),
            io:format("debug: queue_list=~p~n", [L]),
            return_json(<<"TODO: display queue">>)
    end;
get([], _Req) ->
    Payload = lists:map(fun ({K,V}) ->
                                {K, list_to_binary(V)}
                        end, vffov:status()),
    return_json({Payload});
get([<<"plugins">>], _Req) ->
    {ok, Getpocket} = application:get_env(vffov, enable_getpocket),
    {ok, Youtube} = application:get_env(vffov, enable_youtube),
    return_json({[{<<"getpocket">>, Getpocket},
                  {<<"youtube">>,   Youtube}]});
get(_Path, _Req) ->
    return_error(not_found).

post([<<"download">>], Req) ->
    Args = elli_request:body_qs(Req),
    case proplists:get_value(<<"url">>, Args, <<>>) of
        <<>> -> return_error(bad_request);
        Url  ->
            vffov:download(binary_to_list(Url)),
            return_json(<<"downloading">>)
    end;
post(_Path, _Req) ->
    return_error(not_found).

options(_Path, _Req) ->
    {200,
     [{"Access-Control-Allow-Origin", "*"},
      {"Access-Control-Allow-Methods", "GET, POST, OPTIONS"},
      {"Access-Control-Allow-Headers", "Authorization, Content-Type"},
      {"Access-Control-Allow-Credentials", "X-PINGOTHER"}],
     <<"">>}.

%%%============================================================================
%%% Internal functions
%%%============================================================================
return_json(Struct) ->
    return(200, jiffy:encode(Struct)).

return_error(not_found) ->
    return(404, <<"Not found">>);
return_error(bad_request) ->
    return(400, <<"Bad request">>).

return(Code, Body) ->
    {Code,
     [{<<"Content-Type">>, <<"application/json">>},
      {<<"Access-Control-Allow-Origin">>, <<"*">>}
     ],
     Body
    }.