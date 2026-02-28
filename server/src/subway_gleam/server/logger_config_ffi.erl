-module(logger_config_ffi).
-import(logger, [update_primary_config/1]).
-export([configure/0]).

configure() ->
    logger:update_primary_config(#{level => all}).
