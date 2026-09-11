# FormFlow demo app

A full Phoenix application exercising FormFlow against a local SQLite
database — no external services required.

## Running it

```
cd examples/demo
mix setup
mix phx.server
```

Then open [http://localhost:4001](http://localhost:4001):

- `/` — the index: renders FormFlow's optional path-based router (mounted on
  the `/*path` catch-all, so `/forms` and friends land here too) and lists what
  each dependency needs at install time
- `/flows` — the flow editor: `FormFlow.Web.Templates.Flows.Index`, a ReactFlow
  canvas. Drag a step, connect two, or click "Add step" and the step and
  connection counts above the canvas update from the server — that round trip is
  the point of the page
- The header's user switcher — the demo is viewed as one of four hardcoded
  users (`Demo.Users`: docs reader, pet license reviewer, dog owner, cat
  owner) with no sign-in. Choosing one posts to `/switch-user/:user_id`, which
  stores the id in the session and reloads the page; `DemoWeb.UserHook`
  assigns it as `current_user` on every LiveView
- `/docs/data-modeling` — the tables the generated migration creates, drawn as
  a schema diagram: `DemoWeb.DataModelingLive`. Columns, Postgres types, and
  every foreign key's `ON DELETE` are read off FormFlow's Ecto schemas, so the
  page describes the library the demo is compiled against. It is the demo's
  second ReactFlow canvas and the only one that loads React from a CDN —
  `cdn.jsdelivr.net`, at runtime, in the page's own colocated hook — rather
  than from FormFlow's prebuilt bundle, which is what lets it register a node
  type of its own
- `/install-check` — one component from each library FormFlow depends on:
  `PhoenixSelect.select`, `DynamicForm.form`, and `Slab.table`. A missing
  colocated hook, Tailwind `@source`, or absent daisyUI shows up here first

## Installation requirements, applied

The demo is wired up exactly the way the [main README's Quick
start](../README.md#quick-start) describes, and `regenerate.sh` is the
executable version of it:

| Requirement | Where | For |
|---|---|---|
| `{:form_flow, path: "../.."}` | `mix.exs` | all four libraries (the rest are transitive) |
| Colocated hook imports | `assets/js/app.js` | form_flow, slab, phoenix_select |
| Tailwind `@source` lines | `assets/css/app.css` | all four libraries |
| daisyUI | vendored by `phx.new` 1.8+ | dynamic_form's built-in components |
| `config :form_flow, repo:` | `config/config.exs` | FormFlow's data layer |
| `config :slab, repo:` | `config/config.exs` | Slab's query mode |
| A generated migration | `priv/repo/migrations/` | FormFlow's tables |
| `form_flow_router_asset_routes()` route | `lib/demo_web/router.ex` | FormFlow's flow editor bundle |
| `form_flow_router_download_routes()` route | `lib/demo_web/router.ex` | saving and printing a form's answers |
| Stub `GoogleStorage` uploader | `assets/js/app.js` | dynamic_form's file fields |

The demo points Tailwind at `../../../../lib` rather than
`../../deps/form_flow/lib` because FormFlow is a path dependency here. Apps
installing from Hex use the `deps/` path.

The uploader is a stub: it reports instant success instead of talking to a
bucket, which is enough to exercise the wiring without cloud credentials.

The `form_flow_router_download_routes()` route is what the Download PDF and
Print links on a form's page point at — a LiveView holds a websocket and cannot
send a file, so both are ordinary `GET`s, one route apart only by a query
param. The demo mounts them inside `:browser` and nothing
else; a real app puts them behind whatever authenticates it, since FormFlow does
not authorize them yet.

The flow editor's ~390 KB of React and ReactFlow never enters `app.js`: the
`form_flow_router_asset_routes()` route serves the prebuilt bundle from FormFlow's own
`priv/static`, and FormFlow's colocated hook fetches it at runtime on the pages
that use it. `app.js` grows by about a kilobyte — the hook. You can check
that for yourself:

```
grep -c xyflow priv/static/assets/js/app.js   # 0
```

The migration was produced by `mix form_flow.gen.migration` and then committed
to `overlay/` with a fixed timestamp, so regenerating the demo is reproducible.
`test/form_flow/migration_test.exs` runs against the migrated SQLite database —
the library's own tests use repo stubs and never issue DDL, so this is where the
migration is proven to actually run.

## Layout

- `demo/` — the generated app. The interesting files are:
  - `lib/demo_web/live/readme_live.ex` — the index and the router usage
  - `lib/demo_web/live/install_check_live.ex` — one component per dependency
  - `lib/demo_web/live/data_modeling_live.ex` and
    `data_modeling_live/diagram.ex` — the schema diagram, and the Ecto
    reflection behind it
  - `priv/repo/migrations/*_add_form_flow.exs` — the generated migration
  - `priv/repo/form_flow_snapshot.sql` and
    `priv/repo/migrations/*_load_form_flow_snapshot.exs` — the pet licensing
    flows and forms as SQL, and the migration that replays them (below)
  - `test/form_flow/migration_test.exs` — the migration, against real SQLite
  - `assets/js/app.js`, `assets/css/app.css`, `config/config.exs` — the
    installation requirements above
- `overlay/` — the FormFlow-specific demo code, copied over the generated
  skeleton by the regenerate script
- `regenerate.sh` — regenerates `demo/` from scratch with a pinned
  `phx.new` version, reapplies the edits and overlay, sets up the database,
  and builds assets. Run it whenever the skeleton drifts out of date.
- `snapshot.sh` — rewrites the SQL snapshot from the running demo's
  database after the flows have been edited in the admin UI.

Stop the demo server before regenerating — the script deletes `demo/` and a
running server (plus its asset watchers) keeps writing into it. The script
checks port 4001 and aborts if something is listening.

## The demo's data

The pet licensing flows (`archive/plans/pet-licensing.md`) are built by hand
in the admin UI, not in code, so the demo has to carry them as data. It does
so as SQL: `snapshot.sh` dumps every FormFlow table in `demo/demo_dev.db` to
`overlay/priv/repo/form_flow_snapshot.sql`, one `INSERT` per row, and the
migration `*_load_form_flow_snapshot.exs` replays that file when `mix setup`
builds a fresh database. Ids are kept as built, so subflow references,
`related_form` paths, and review `source` paths survive the round trip.

The cycle after editing a flow at `/admin`:

```
./examples/snapshot.sh    # rewrites the SQL under overlay/ and demo/
git diff examples/overlay/priv/repo/form_flow_snapshot.sql
```

The migration loads nothing into the test database, whose tests count on
empty tables, or into a database that already has flows — which is the case
on the very database the snapshot came from, where the migration shows up
as pending. `mix ecto.reset` in `demo/` is how to reload from the SQL.

Instance rows (applications in progress) are dumped too if any exist, but
the plan's recommendation is to seed those through the data layer instead
(`pet-licensing.md` §8), so the snapshot is expected to stay templates only.

## Distribution note

None of this ships to library users installing from Hex — the package includes
only the files whitelisted in `mix.exs` (`lib`, `priv`, `guides`, `mix.exs`,
`README.md`, `LICENSE.md`). Git dependencies clone the repo including this
directory, but it is a few hundred KB of text and is never compiled as part of
the dependency.
