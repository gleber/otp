%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2008-2012. All Rights Reserved.
%%
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%%
%% %CopyrightEnd%
%%

%%
-module(ssl_npn_handshake_SUITE).

%% Note: This directive should only be used in test suites.
-compile(export_all).
-include_lib("common_test/include/ct.hrl").

suite() -> [{ct_hooks,[ts_install_cth]}].

all() ->
    [{group, 'tlsv1.2'},
     {group, 'tlsv1.1'},
     {group, 'tlsv1'},
     {group, 'sslv3'}].

groups() ->
    [
     {'tlsv1.2', [], next_protocol_tests()},
     {'tlsv1.1', [], next_protocol_tests()},
     {'tlsv1', [], next_protocol_tests()},
     {'sslv3', [], next_protocol_not_supported()}
    ].

next_protocol_tests() ->
    [validate_empty_protocols_are_not_allowed,
     validate_empty_advertisement_list_is_allowed,
     validate_advertisement_must_be_a_binary_list,
     validate_client_protocols_must_be_a_tuple,
     normal_npn_handshake_server_preference,
     normal_npn_handshake_client_preference,
     fallback_npn_handshake,
     fallback_npn_handshake_server_preference,
     client_negotiate_server_does_not_support,
     no_client_negotiate_but_server_supports_npn,
     renegotiate_from_client_after_npn_handshake
    ].

next_protocol_not_supported() ->
    [npn_not_supported_client,
     npn_not_supported_server
    ].

init_per_suite(Config) ->
    catch crypto:stop(),
    try crypto:start() of
	ok ->
	    application:start(public_key),
	    ssl:start(),
	    Result =
		(catch make_certs:all(?config(data_dir, Config),
				      ?config(priv_dir, Config))),
	    test_server:format("Make certs  ~p~n", [Result]),
	    ssl_test_lib:cert_options(Config)
    catch _:_ ->
	    {skip, "Crypto did not start"}
    end.

end_per_suite(_Config) ->
    ssl:stop(),
    application:stop(crypto).


init_per_group(GroupName, Config) ->
    case ssl_test_lib:is_tls_version(GroupName) of
	true ->
	    case ssl_test_lib:sufficient_crypto_support(GroupName) of
		true ->
		    ssl_test_lib:init_tls_version(GroupName),
		    Config;
		false ->
		    {skip, "Missing crypto support"}
	    end;
	_ ->
	    ssl:start(),
	    Config
    end.


end_per_group(_GroupName, Config) ->
    Config.


%% Test cases starts here.
%%--------------------------------------------------------------------

validate_empty_protocols_are_not_allowed(Config) when is_list(Config) ->
    {error, {eoptions, {next_protocols_advertised, {invalid_protocol, <<>>}}}}
	= (catch ssl:listen(9443,
			    [{next_protocols_advertised, [<<"foo/1">>, <<"">>]}])),
    {error, {eoptions, {client_preferred_next_protocols, {invalid_protocol, <<>>}}}}
	= (catch ssl:connect({127,0,0,1}, 9443,
			     [{client_preferred_next_protocols,
			       {client, [<<"foo/1">>, <<"">>], <<"foox/1">>}}], infinity)),
    Option = {client_preferred_next_protocols, {invalid_protocol, <<"">>}},
    {error, {eoptions, Option}} = (catch ssl:connect({127,0,0,1}, 9443, [Option], infinity)).

%--------------------------------------------------------------------------------

validate_empty_advertisement_list_is_allowed(Config) when is_list(Config) ->
    Option = {next_protocols_advertised, []},
    {ok, Socket} = ssl:listen(0, [Option]),
    ssl:close(Socket).
%--------------------------------------------------------------------------------

validate_advertisement_must_be_a_binary_list(Config) when is_list(Config) ->
    Option = {next_protocols_advertised, blah},
    {error, {eoptions, Option}} = (catch ssl:listen(9443, [Option])).
%--------------------------------------------------------------------------------

validate_client_protocols_must_be_a_tuple(Config) when is_list(Config)  ->
    Option = {client_preferred_next_protocols, [<<"foo/1">>]},
    {error, {eoptions, Option}} = (catch ssl:connect({127,0,0,1}, 9443, [Option])).

%--------------------------------------------------------------------------------

normal_npn_handshake_server_preference(Config) when is_list(Config) ->
    run_npn_handshake(Config,
			   [{client_preferred_next_protocols,
			     {server, [<<"http/1.0">>, <<"http/1.1">>], <<"http/1.1">>}}],
			   [{next_protocols_advertised, [<<"spdy/2">>, <<"http/1.1">>, <<"http/1.0">>]}],
			   {ok, <<"http/1.1">>}).
%--------------------------------------------------------------------------------

normal_npn_handshake_client_preference(Config) when is_list(Config) ->
    run_npn_handshake(Config,
			   [{client_preferred_next_protocols,
			     {client, [<<"http/1.0">>, <<"http/1.1">>], <<"http/1.1">>}}],
			   [{next_protocols_advertised, [<<"spdy/2">>, <<"http/1.1">>, <<"http/1.0">>]}],
			   {ok, <<"http/1.0">>}).

%--------------------------------------------------------------------------------

fallback_npn_handshake(Config) when is_list(Config) ->
    run_npn_handshake(Config,
			   [{client_preferred_next_protocols, {client, [<<"spdy/2">>], <<"http/1.1">>}}],
			   [{next_protocols_advertised, [<<"spdy/1">>, <<"http/1.1">>, <<"http/1.0">>]}],
			   {ok, <<"http/1.1">>}).
%--------------------------------------------------------------------------------

fallback_npn_handshake_server_preference(Config) when is_list(Config) ->
    run_npn_handshake(Config,
			   [{client_preferred_next_protocols, {server, [<<"spdy/2">>], <<"http/1.1">>}}],
			   [{next_protocols_advertised, [<<"spdy/1">>, <<"http/1.1">>, <<"http/1.0">>]}],
			   {ok, <<"http/1.1">>}).

%--------------------------------------------------------------------------------

no_client_negotiate_but_server_supports_npn(Config) when is_list(Config) ->
    run_npn_handshake(Config,
			   [],
			   [{next_protocols_advertised, [<<"spdy/1">>, <<"http/1.1">>, <<"http/1.0">>]}],
			   {error, next_protocol_not_negotiated}).
%--------------------------------------------------------------------------------


client_negotiate_server_does_not_support(Config) when is_list(Config) ->
    run_npn_handshake(Config,
			   [{client_preferred_next_protocols, {client, [<<"spdy/2">>], <<"http/1.1">>}}],
			   [],
			   {error, next_protocol_not_negotiated}).

%--------------------------------------------------------------------------------
renegotiate_from_client_after_npn_handshake(Config) when is_list(Config) ->
    Data = "hello world",
    
    ClientOpts0 = ?config(client_opts, Config),
    ClientOpts = [{client_preferred_next_protocols,
		   {client, [<<"http/1.0">>], <<"http/1.1">>}}] ++ ClientOpts0,
    ServerOpts0 = ?config(server_opts, Config),
    ServerOpts = [{next_protocols_advertised,
		   [<<"spdy/2">>, <<"http/1.1">>, <<"http/1.0">>]}] ++  ServerOpts0,
    ExpectedProtocol = {ok, <<"http/1.0">>},

    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
                    {from, self()},
                    {mfa, {?MODULE, ssl_receive_and_assert_npn, [ExpectedProtocol, Data]}},
                    {options, ServerOpts}]),

    Port = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
               {host, Hostname},
               {from, self()},
               {mfa, {?MODULE, assert_npn_and_renegotiate_and_send_data, [ExpectedProtocol, Data]}},
               {options, ClientOpts}]),

    ssl_test_lib:check_result(Server, ok, Client, ok).

%--------------------------------------------------------------------------------
npn_not_supported_client(Config) when is_list(Config) ->
    ClientOpts0 = ?config(client_opts, Config),
    PrefProtocols = {client_preferred_next_protocols,
		     {client, [<<"http/1.0">>], <<"http/1.1">>}},
    ClientOpts = [PrefProtocols] ++ ClientOpts0,
    {ClientNode, _ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Client = ssl_test_lib:start_client_error([{node, ClientNode}, 
			    {port, 8888}, {host, Hostname},
			    {from, self()},  {options, ClientOpts}]),
    
    ssl_test_lib:check_result(Client, {error, 
				       {eoptions, 
					{not_supported_in_sslv3, PrefProtocols}}}).

%--------------------------------------------------------------------------------
npn_not_supported_server(Config) when is_list(Config)->
    ServerOpts0 = ?config(server_opts, Config),
    AdvProtocols = {next_protocols_advertised, [<<"spdy/2">>, <<"http/1.1">>, <<"http/1.0">>]},
    ServerOpts = [AdvProtocols] ++  ServerOpts0,
  
    {error, {eoptions, {not_supported_in_sslv3, AdvProtocols}}} = ssl:listen(0, ServerOpts).

%%--------------------------------------------------------------------
%%% Internal functions
%%--------------------------------------------------------------------

run_npn_handshake(Config, ClientExtraOpts, ServerExtraOpts, ExpectedProtocol) ->
    Data = "hello world",

    ClientOpts0 = ?config(client_opts, Config),
    ClientOpts = ClientExtraOpts ++ ClientOpts0,
    ServerOpts0 = ?config(server_opts, Config),
    ServerOpts = ServerExtraOpts ++  ServerOpts0,

    {ClientNode, ServerNode, Hostname} = ssl_test_lib:run_where(Config),
    Server = ssl_test_lib:start_server([{node, ServerNode}, {port, 0},
                    {from, self()},
                    {mfa, {?MODULE, ssl_receive_and_assert_npn, [ExpectedProtocol, Data]}},
                    {options, ServerOpts}]),

    Port = ssl_test_lib:inet_port(Server),
    Client = ssl_test_lib:start_client([{node, ClientNode}, {port, Port},
               {host, Hostname},
               {from, self()},
               {mfa, {?MODULE, ssl_send_and_assert_npn, [ExpectedProtocol, Data]}},
               {options, ClientOpts}]),

    ssl_test_lib:check_result(Server, ok, Client, ok).


assert_npn(Socket, Protocol) ->
    test_server:format("Negotiated Protocol ~p, Expecting: ~p ~n",
		       [ssl:negotiated_next_protocol(Socket), Protocol]),
    Protocol = ssl:negotiated_next_protocol(Socket).

assert_npn_and_renegotiate_and_send_data(Socket, Protocol, Data) ->
    assert_npn(Socket, Protocol),
    test_server:format("Renegotiating ~n", []),
    ok = ssl:renegotiate(Socket),
    ssl:send(Socket, Data),
    assert_npn(Socket, Protocol),
    ok.

ssl_send_and_assert_npn(Socket, Protocol, Data) ->
    assert_npn(Socket, Protocol),
    ssl_send(Socket, Data).

ssl_receive_and_assert_npn(Socket, Protocol, Data) ->
    assert_npn(Socket, Protocol),
    ssl_receive(Socket, Data).

ssl_send(Socket, Data) ->
    test_server:format("Connection info: ~p~n",
               [ssl:connection_info(Socket)]),
    ssl:send(Socket, Data).

ssl_receive(Socket, Data) ->
    ssl_receive(Socket, Data, []).

ssl_receive(Socket, Data, Buffer) ->
    test_server:format("Connection info: ~p~n",
               [ssl:connection_info(Socket)]),
    receive
    {ssl, Socket, MoreData} ->
        test_server:format("Received ~p~n",[MoreData]),
        NewBuffer = Buffer ++ MoreData,
        case NewBuffer of
            Data ->
                ssl:send(Socket, "Got it"),
                ok;
            _ ->
                ssl_receive(Socket, Data, NewBuffer)
        end;
    Other ->
        test_server:fail({unexpected_message, Other})
    after 4000 ->
        test_server:fail({did_not_get, Data})
    end.


connection_info_result(Socket) ->
    ssl:connection_info(Socket).
