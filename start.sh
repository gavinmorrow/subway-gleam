#! /bin/sh

pushd ./client

gleam run -m lustre/dev build subway_gleam/client/stop
gleam run -m lustre/dev build subway_gleam/client/train

popd


pushd ./server

gleam run -m subway_gleam/server

popd
