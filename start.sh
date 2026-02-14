#! /bin/sh

if ! [ "$1" = "--no-client" ]; then
  pushd ./client

  if [ "$1" = "--client" ]; then
    gleam run -m lustre/dev build subway_gleam/client/$2
  else
    # TODO: automate this somehow?
    gleam run -m lustre/dev build subway_gleam/client/stops
    gleam run -m lustre/dev build subway_gleam/client/stop
    gleam run -m lustre/dev build subway_gleam/client/train
  fi

  popd
fi


pushd ./server

gleam run -m subway_gleam/server

popd
