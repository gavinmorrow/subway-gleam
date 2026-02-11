# subway_gleam

This is a little web app to view subway arrival times for the NYC Subway :]

It uses lustre server-side, and sends over fully rendered static HTML.

## Subprojects

- `server`: The code for the HTTP server. Targets Erlang. Run via
            `gleam run -m subway_gleam/server`. The client must be built first.
- `shared`: Shared code between the server and client. It contains all of the
            lustre view code—ie `fn view()` and `type Model`. This allows for
            server-side rendering.
- `client`: Contains code that runs exclusively in the browser. It contains all
            the interactive bits of lustre code—ie `fn init()`, `fn update()`,
            and `type Msg`. Build with
            `gleam run -m lustre/dev build subway_gleam/client/[route]`.
-   `gtfs`: GTFS parsing code for both static and realtime.

## Development

To run the project: build the client, start the server, then go to
`localhost:8000` in your web browser of choice.

If this is your first time running it, make sure that the flags for `st` in
`src/comp_flags.gleam` are set to fetch from the internet and save the values
to disk. After doing `gleam run` once followed by
`gleam run -m subway_gleam/gtfs/st/gen_schedule`, they will be saved, so
development can continue locally without re-fetching and parsing each time.
The folder `./gtfs/src/subway_gleam/gtfs/st/schedule_sample/` may need to be
created. Disable the fetch and save to disk flags afterwards, and only enable
when needed.
