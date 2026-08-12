# FormFlow demo app

A full Phoenix application exercising FormFlow against a local SQLite
database — no external services required.

## Running it

```
cd examples/demo
mix setup
mix phx.server
```

Then open [http://localhost:4000](http://localhost:4000):

- `/` — the index: renders FormFlow's optional path-based router (mounted on
  the `/*path` catch-all, so `/forms` and friends land here too) and lists what
  each dependency needs at install time
- `/forms` — the flow editor: `FormFlow.Web.Templates.Forms.Index`, a ReactFlow
  canvas. Drag a step, connect two, or click "Add step" and the step and
  connection counts above the canvas update from the server — that round trip is
  the point of the page
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
| `form_flow_assets()` route | `lib/demo_web/router.ex` | FormFlow's flow editor bundle |
| Stub `GoogleStorage` uploader | `assets/js/app.js` | dynamic_form's file fields |

The demo points Tailwind at `../../../../lib` rather than
`../../deps/form_flow/lib` because FormFlow is a path dependency here. Apps
installing from Hex use the `deps/` path.

The uploader is a stub: it reports instant success instead of talking to a
bucket, which is enough to exercise the wiring without cloud credentials.

The flow editor's ~390 KB of React and ReactFlow never enters `app.js`: the
`form_flow_assets()` route serves the prebuilt bundle from FormFlow's own
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
  - `priv/repo/migrations/*_add_form_flow.exs` — the generated migration
  - `test/form_flow/migration_test.exs` — the migration, against real SQLite
  - `assets/js/app.js`, `assets/css/app.css`, `config/config.exs` — the
    installation requirements above
- `overlay/` — the FormFlow-specific demo code, copied over the generated
  skeleton by the regenerate script
- `regenerate.sh` — regenerates `demo/` from scratch with a pinned
  `phx.new` version, reapplies the edits and overlay, sets up the database,
  and builds assets. Run it whenever the skeleton drifts out of date.

Stop the demo server before regenerating — the script deletes `demo/` and a
running server (plus its asset watchers) keeps writing into it. The script
checks port 4000 and aborts if something is listening.

## Distribution note

None of this ships to library users installing from Hex — the package includes
only the files whitelisted in `mix.exs` (`lib`, `guides`, `mix.exs`,
`README.md`, `LICENSE.md`). Git dependencies clone the repo including this
directory, but it is a few hundred KB of text and is never compiled as part of
the dependency.
