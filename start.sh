#! /bin/sh

if ! [ "$1" = "--no-client" ]; then
  cd ./client

  if [ "$1" = "--client" ]; then
    gleam run -m lustre/dev build subway_gleam/client/$2
  else
    # TODO: automate this somehow?
    gleam run -m lustre/dev build subway_gleam/client/stops
    gleam run -m lustre/dev build subway_gleam/client/stop
    gleam run -m lustre/dev build subway_gleam/client/train
  fi

  cd ..
fi


cd ./server

gleam run -m subway_gleam/server

cd ..
