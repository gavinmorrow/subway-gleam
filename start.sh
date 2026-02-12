#! /bin/sh

if ! [ "$1" = "--no-client" ]; then
  pushd ./client

  gleam run -m lustre/dev build subway_gleam/client/stop
  gleam run -m lustre/dev build subway_gleam/client/train

  popd
fi


pushd ./server

gleam run -m subway_gleam/server

popd
