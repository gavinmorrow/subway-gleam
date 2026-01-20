# subway_gleam

This is a little web app to view subway arrival times for the NYC Subway :]

It uses lustre server-side, and sends over fully rendered static HTML.

## Development

To run the project, use `gleam run` and then go to `localhost:8000` in your web
browser of choice.

If this is your first time running it, make sure that the flags for `st` in
`src/comp_flags.gleam` are set to fetch from the internet and save the values
to disk. After doing `gleam run` once followed by `gleam run -m gen_schedule`,
they will be saved, so development can continue locally without re-fetching and
parsing each time. The folder `./src/subway_gleam/schedule_sample/` may need to
be created.
