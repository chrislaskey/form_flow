# FormFlow demo app

A full Phoenix application exercising FormFlow — no database or external
services required.

## Running it

```
cd examples/demo
mix setup
mix phx.server
```

Then open [http://localhost:4000](http://localhost:4000). The home page lists
every demo.

Right now there is only the index, which confirms the library is wired up
(compiled version, module structure) without calling into it yet. Each new
demo gets a route in `regenerate.sh` and a LiveView in `overlay/`.

## Layout

- `demo/` — the generated app. The interesting files are:
  - `lib/demo_web/live/readme_live.ex` — the demo index
  - `assets/css/app.css` — the Tailwind `@source` lines (pointing at
    FormFlow's source directly, since the demo uses a path dependency;
    Hex-installed apps use `../../deps/form_flow/lib`), plus the lines for
    the libraries FormFlow builds on (`slab`, `dynamic_form`,
    `phoenix_select`)
  - `mix.exs` — the `{:form_flow, path: "../.."}` dependency
- `overlay/` — the FormFlow-specific demo code, copied over the generated
  skeleton by the regenerate script
- `regenerate.sh` — regenerates `demo/` from scratch with a pinned
  `phx.new` version, reapplies the edits and overlay, and builds assets.
  Run it whenever the skeleton drifts out of date.

The demo is generated with `--no-ecto`: `FormFlow.Data.Repo` wraps the parent
app's repo, but nothing in the demo persists anything yet. When the data layer
lands, regenerate with `--database sqlite3` and add
`config :form_flow, repo: Demo.Repo` — see the comments in `regenerate.sh`.

## Distribution note

None of this ships to library users installing from Hex — the package includes
only the files whitelisted in `mix.exs` (`lib`, `guides`, `mix.exs`,
`README.md`, `LICENSE.md`). Git dependencies clone the repo including this
directory, but it is a few hundred KB of text and is never compiled as part of
the dependency.
