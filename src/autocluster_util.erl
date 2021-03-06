%%==============================================================================
%% @author Gavin M. Roy <gavinr@aweber.com>
%% @copyright 2015-2016 AWeber Communications
%% @end
%%==============================================================================
-module(autocluster_util).

%% API
-export([as_atom/1,
         as_integer/1,
         as_string/1,
         backend_module/0,
         nic_ipv4/1,
         node_hostname/1,
         node_name/1,
         parse_port/1,
         as_proplist/1
        ]).


%% Export all for unit tests
-ifdef(TEST).
-compile(export_all).
-endif.

-type ifopt() :: {flag,[atom()]} | {addr, inet:ip_address()} |
                 {netmask,inet:ip_address()} | {broadaddr,inet:ip_address()} |
                 {dstaddr,inet:ip_address()} | {hwaddr,[byte()]}.


%%--------------------------------------------------------------------
%% @doc
%% Return the passed in value as an atom.
%% @end
%%--------------------------------------------------------------------
-spec as_atom(atom() | binary() | string()) -> atom().
as_atom(Value) when is_atom(Value) ->
  Value;
as_atom(Value) when is_binary(Value) ->
  list_to_atom(binary_to_list(Value));
as_atom(Value) when is_list(Value) ->
  list_to_atom(Value);
as_atom(Value) ->
  autocluster_log:error("Unexpected data type for atom value: ~p~n",
                        [Value]),
  Value.


%%--------------------------------------------------------------------
%% @doc
%% Return the passed in value as an integer.
%% @end
%%--------------------------------------------------------------------
-spec as_integer(binary() | integer() | string()) -> integer().
as_integer([]) -> undefined;
as_integer(Value) when is_binary(Value) ->
  list_to_integer(as_string(Value));
as_integer(Value) when is_list(Value) ->
  list_to_integer(Value);
as_integer(Value) when is_integer(Value) ->
  Value;
as_integer(Value) ->
  autocluster_log:error("Unexpected data type for integer value: ~p~n",
                        [Value]),
  Value.


%%--------------------------------------------------------------------
%% @doc
%% Return the passed in value as a string.
%% @end
%%--------------------------------------------------------------------
-spec as_string(Value :: atom() | binary() | integer() | string())
    -> string().
as_string([]) -> "";
as_string(Value) when is_atom(Value) ->
  as_string(atom_to_list(Value));
as_string(Value) when is_binary(Value) ->
  as_string(binary_to_list(Value));
as_string(Value) when is_integer(Value) ->
  as_string(integer_to_list(Value));
as_string(Value) when is_list(Value) ->
  lists:flatten(Value);
as_string(Value) ->
  autocluster_log:error("Unexpected data type for list value: ~p~n",
                        [Value]),
  Value.


%%--------------------------------------------------------------------
%% @doc
%% Return the module to use for node discovery.
%% @end
%%--------------------------------------------------------------------
-spec backend_module() -> module() | undefined.
backend_module() ->
  backend_module(autocluster_config:get(backend)).


%%--------------------------------------------------------------------
%% @private
%% @doc
%% Return the module to use for node discovery.
%% @end
%%--------------------------------------------------------------------
-spec backend_module(atom()) -> module() | undefined.
backend_module(aws)          -> autocluster_aws;
backend_module(consul)       -> autocluster_consul;
backend_module(dns)          -> autocluster_dns;
backend_module(etcd)         -> autocluster_etcd;
backend_module(k8s)          -> autocluster_k8s;
backend_module(_)            -> undefined.


%%--------------------------------------------------------------------
%% @doc
%% Return the IP address for the current node for the specified
%% network interface controller.
%% @end
%%--------------------------------------------------------------------
-spec nic_ipv4(Device :: string())
    -> {ok, string()} | {error, not_found}.
nic_ipv4(Device) ->
  {ok, Interfaces} = inet:getifaddrs(),
  nic_ipv4(Device, Interfaces).


%%--------------------------------------------------------------------
%% @doc
%% Parse the interface out of the list of interfaces, returning the
%% IPv4 address if found.
%% @end
%%--------------------------------------------------------------------
-spec nic_ipv4(Device :: string(), Interfaces :: list())
    -> {ok, string()} | {error, not_found}.
nic_ipv4(_, []) -> {error, not_found};
nic_ipv4(Device, [{Interface, Opts}|_]) when Interface =:= Device ->
  {ok, nic_ipv4_address(Opts)};
nic_ipv4(Device, [_|T]) ->
  nic_ipv4(Device,T).


%%--------------------------------------------------------------------
%% @doc
%% Return the formatted IPv4 address out of the list of addresses
%% for the interface.
%% @end
%%--------------------------------------------------------------------
-spec nic_ipv4_address([ifopt()]) -> {ok, string()} | {error, not_found}.
nic_ipv4_address([]) -> {error, not_found};
nic_ipv4_address([{addr, {A,B,C,D}}|_]) ->
  inet_parse:ntoa({A,B,C,D});
nic_ipv4_address([_|T]) ->
  nic_ipv4_address(T).


%%--------------------------------------------------------------------
%% @doc
%% Return the hostname for the current node (without the tuple)
%% Hostname can be taken from network info or nodename.
%% @end
%%--------------------------------------------------------------------
-spec node_hostname(boolean()) -> string().
node_hostname(false = _FromNodename) ->
    {ok, Hostname} = inet:gethostname(),
    Hostname;
node_hostname(true = _FromNodename) ->
    {match, [Hostname]} = re:run(atom_to_list(node()), "@(.*)",
                                 [{capture, [1], list}]),
    Hostname.

%%--------------------------------------------------------------------
%% @doc
%% Return the proper node name for clustering purposes
%% @end
%%--------------------------------------------------------------------
-spec node_name(Value :: atom() | binary() | string()) -> atom().
node_name(Value) when is_atom(Value) ->
    node_name(atom_to_list(Value));
node_name(Value) when is_binary(Value) ->
    node_name(binary_to_list(Value));
node_name(Value) when is_list(Value) ->
  case lists:member($@, Value) of
      true ->
          list_to_atom(Value);
      false ->
          list_to_atom(string:join([node_prefix(),
                                    node_name_parse(as_string(Value))],
                                   "@"))
  end.

%%--------------------------------------------------------------------
%% @doc
%% Parse the value passed into nodename, checking if it's an ip
%% address. If so, return it. If not, then check to see if longname
%% support is turned on. if so, return it. If not, extract the left
%% most part of the name, delimited by periods.
%% @end
%%--------------------------------------------------------------------
-spec node_name_parse(Value :: string()) -> string().
node_name_parse(Value) ->
  case inet:parse_ipv4strict_address(Value) of
    {ok, _} ->
      Value;
    {error, einval} ->
      node_name_parse(autocluster_config:get(longname), Value)
  end.


%%--------------------------------------------------------------------
%% @doc
%% Continue the parsing logic from node_name_parse/1. This is where
%% result of the IPv4 check is processed.
%% @end
%%--------------------------------------------------------------------
-spec node_name_parse(IsIPv4 :: true | false, Value :: string())
    -> string().
node_name_parse(true, Value) -> Value;
node_name_parse(false, Value) ->
  Parts = string:tokens(Value, "."),
  node_name_parse(length(Parts), Value, Parts).


%%--------------------------------------------------------------------
%% @doc
%% Properly deal with returning the hostname if it's made up of
%% multiple segments like www.rabbitmq.com, returning www, or if it's
%% only a single segment, return that.
%% @end
%%--------------------------------------------------------------------
-spec node_name_parse(Segments :: integer(),
                      Value :: string(),
                      Parts :: [string()])
    -> string().
node_name_parse(1, Value, _) -> Value;
node_name_parse(_, _, Parts) ->
  as_string(lists:nth(1, Parts)).


%%--------------------------------------------------------------------
%% @doc
%% Extract the "local part" of the ``RABBITMQ_NODENAME`` environment
%% variable, if set, otherwise use the default node name value
%% (rabbit).
%% @end
%%--------------------------------------------------------------------
-spec node_prefix() -> string().
node_prefix() ->
  Value = autocluster_config:get(node_name),
  lists:nth(1, string:tokens(Value, "@")).


%%--------------------------------------------------------------------
%% @doc
%% Returns the port, even if Docker linking overwrites a configuration
%% value to be a URI instead of numeric value
%% @end
%%--------------------------------------------------------------------
-spec parse_port(Value :: integer() | string()) -> integer().
parse_port(Value) when is_list(Value) ->
  as_integer(lists:last(string:tokens(Value, ":")));
parse_port(Value) -> as_integer(Value).


%%--------------------------------------------------------------------
%% @doc
%% Returns a proplist from a JSON structure (environment variable) or
%% the settings key (already a proplist).
%% @end
%%--------------------------------------------------------------------
-spec as_proplist(Value :: string() | [{string(), string()}]) ->
                         [{string(), string()}].
as_proplist([Tuple | _] = Json) when is_tuple(Tuple) ->
    Json;
as_proplist([]) ->
    [];
as_proplist(List) when is_list(List) ->
    case rabbit_misc:json_decode(List) of
        {ok, {struct, _} = Json} ->
            [{binary_to_list(K), binary_to_list(V)}
             || {K, V} <- rabbit_misc:json_to_term(Json)];
        _ ->
            autocluster_log:error("Unexpected data type for proplist value: ~p. JSON parser returned an error!~n",
                                  [List]),
            []
    end;
as_proplist(Value) ->
    autocluster_log:error("Unexpected data type for proplist value: ~p.~n",
                          [Value]),
    [].
