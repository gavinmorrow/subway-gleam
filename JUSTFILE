start: build-client start-server

[working-directory: 'server']
start-server:
    gleam run -m subway_gleam/server

# TODO: automate this somehow?
# also maybe move into submodules
# maybe use make?

build-client: build-stops build-stop build-train

[working-directory: 'client']
build-stops:
    gleam run -m lustre/dev build subway_gleam/client/stops

[working-directory: 'client']
build-stop:
    gleam run -m lustre/dev build subway_gleam/client/stop

[working-directory: 'client']
build-train:
    gleam run -m lustre/dev build subway_gleam/client/train
