-module(lager_honeybadger_backend).

-behaviour(gen_event).

-export([init/1,
         handle_call/2,
         handle_event/2,
         handle_info/2,
         terminate/2,
         code_change/3
]).

-define(APPS,[ibrowse, ssl]).
-define(DEFAULT_LOG_LEVEL, error).
-define(FORMAT,[time, " [", severity,"] ", message]).

-record(state, {level :: {'mask', integer()},
                api_key :: list(),
                formatter :: atom(),
                format_config :: any()}).

init(Params) ->
  case proplists:get_value(api_key, Params, undefined) of
    undefined ->
      {error, bad_config};
    ApiKey ->
      ulitos_app:ensure_started(?APPS),
      Formatter = proplists:get_value(formatter, Params, lager_default_formatter),
      FormatConfig = proplists:get_value(formatter_config, Params, ?FORMAT),
      LogLevel = validate_loglevel(proplists:get_value(level, Params, ?DEFAULT_LOG_LEVEL)),
      {ok, #state{level = LogLevel, api_key = ApiKey, formatter = Formatter, format_config = FormatConfig}}
  end.

handle_call(get_loglevel, #state{level=Level} = State) ->
    {ok, Level, State};
handle_call({set_loglevel, Level}, State) ->
   try lager_util:config_to_mask(Level) of
        Levels ->
            {ok, ok, State#state{level=Levels}}
    catch
        _:_ ->
            {ok, {error, bad_log_level}, State}
    end;
handle_call(_Request, State) ->
    {ok, ok, State}.

handle_event({log, Message}, #state{level = Level, api_key = ApiKey, formatter = Formatter, format_config = FormatConfig} = State) ->
  case lager_util:is_loggable(Message, Level, ?MODULE) of
      true ->
          send_to_honeybadger(ApiKey, lager_msg:severity(Message), lager_msg:metadata(Message), Formatter:format(Message,FormatConfig)),
          {ok, State};
      false ->
          {ok, State}
  end;
handle_event(_Event, State) ->
    {ok, State}.

handle_info(_Info, State) ->
    {ok, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

send_to_honeybadger(ApiKey, Severity, Metadata, Message) ->
  Class = msg_class(Severity, proplists:get_value(module, Metadata, undefined), proplists:get_value(line, Metadata, undefined), proplists:get_value(pid, Metadata, undefined)),
  Context = proplists:get_value(context, Metadata, {[]}),
  Params = proplists:get_value(params, Metadata, {[]}),
  Session = proplists:get_value(session, Metadata, {[]}),
  [Name, HostName] = string:tokens(atom_to_list(node()), "@"),
  Json = 
    {[
      {notifier, {[
        {name, <<"Lager Honeybadger backend">>},
        {language, <<"Erlang">>}
      ]}},
      {error, {[
        {class, list_to_binary(Class)},
        {message, list_to_binary(Message)}
      ]}},
      {request, {[
        {context, Context},
        {params, Params},
        {session, Session}
      ]}},
      {server, {[
        {environment_name, list_to_binary(Name)},
        {hostname, list_to_binary(HostName)}
      ]}}      
    ]},
  Body = jiffy:encode(Json),
  Headers = [{"X-API-Key", ApiKey}, {"Content-Type", "application/json; charset=utf-8"}, {"Accept", "application/json"}],
  ibrowse:send_req("https://api.honeybadger.io/v1/notices", Headers, post, Body).

msg_class(Severity, undefined, undefined, Pid) ->
  lists:flatten(io_lib:format("[~p] ~p ~p", [Severity, process, Pid]));

msg_class(Severity, Module, Line, _Pid) ->
  lists:flatten(io_lib:format("[~p] ~p:~p", [Severity, Module, Line])).

validate_loglevel(Level) ->
  try lager_util:config_to_mask(Level) of
      Levels ->
          Levels
  catch
      _:_ ->
          false
  end.
