-module(health_check_SUITE).

-include_lib("common_test/include/ct.hrl").

%% common_test exports
-export([all/0
        ,groups/0
        ,init_per_suite/1
        ,end_per_suite/1
        ,init_per_testcase/2
        ,end_per_testcase/2
        ]).

%% test cases
-export([cluster_is_assembled/1
        ]).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Common test callbacks
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
all() ->
    autocluster_testing:optional(autocluster_testing:has_etcd(),
                                 {group, etcd_group}).

groups() ->
    autocluster_testing:optional(autocluster_testing:has_etcd(),
                                 {etcd_group, [], [cluster_is_assembled
                                                  ]}).

init_per_suite(Config0) ->
    rabbit_ct_helpers:log_environment(),
    rabbit_ct_helpers:run_setup_steps(Config0).

end_per_suite(Config) ->
    rabbit_ct_helpers:run_teardown_steps(Config).

init_per_testcase(cluster_is_assembled, Config0) ->
    {ok, Process, PortNumber} = autocluster_testing:start_etcd(?config(priv_dir, Config0)),
    Config1 = [{rmq_nodes_count, 3}
              ,{rmq_nodes_clustered, false}
              ,{broker_with_plugins, true}
              ,{etcd_process, Process}
              ,{etcd_port_num, PortNumber}
               | Config0],
    rabbit_ct_helpers:run_steps(Config1,
                                [fun generate_erlang_node_config/1]
                                ++ rabbit_ct_broker_helpers:setup_steps());

init_per_testcase(_, Config) ->
    Config.

end_per_testcase(cluster_is_assembled, Config) ->
    autocluster_testing:stop_etcd(?config(etcd_process, Config)),
    rabbit_ct_helpers:run_steps(Config,
                                rabbit_ct_broker_helpers:teardown_steps());

end_per_testcase(_, Config) ->
    Config.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Test cases
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
cluster_is_assembled(Config) ->
    ExpectedNodes = lists:sort(rabbit_ct_broker_helpers:get_node_configs(Config, nodename)),
    case lists:sort(rabbit_ct_broker_helpers:rpc(Config, 1, rabbit_mnesia, cluster_nodes, [running])) of
        ExpectedNodes ->
            ok;
        GotNodes ->
            ct:pal(error, "Nodes in cluster are ~p when ~p was expected", [GotNodes, ExpectedNodes])
    end,
    ok.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Helpers
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
generate_erlang_node_config(Config) ->
    ErlangNodeConfig = [{rabbit, [{dummy_param_for_comma, true}
                                 ,{cluster_partition_handling, ignore}
                                 ]},
                        {autocluster, [{dummy_param_for_comma, true}
                                      ,{autocluster_log_level, debug}
                                      ,{backend, etcd}
                                      ,{autocluster_failure, stop}
                                      ,{cleanup_interval, 10}
                                      ,{cluster_cleanup, true}
                                      ,{cleanup_warn_only, false}
                                      ,{etcd_scheme, http}
                                      ,{etcd_host, "localhost"}
                                      ,{etcd_port, ?config(etcd_port_num, Config)}
                                      ]}],
    rabbit_ct_helpers:merge_app_env(Config, ErlangNodeConfig).
