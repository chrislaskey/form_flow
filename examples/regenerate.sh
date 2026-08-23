#!/usr/bin/env bash
#
# Regenerates the demo app from scratch:
#
#   1. Generates a fresh Phoenix app with `mix phx.new` (pinned version)
#   2. Applies FormFlow-specific edits (path dep, routes, Tailwind, hooks,
#      repo config, upload stub)
#   3. Copies the demo code from overlay/ over the skeleton
#   4. Installs deps, creates the SQLite database, and builds assets
#
# Run it whenever the generated skeleton drifts out of date:
#
#   ./examples/regenerate.sh
#
# The interesting demo code lives in overlay/ (version controlled); the
# generated skeleton is disposable.
#
# Every edit below is something a real app installing form_flow has to do, so
# this script doubles as the executable version of the README's Quick start.
# FormFlow pulls in phoenix_select, dynamic_form, and slab, and each has its
# own installation requirement (hooks, Tailwind sources, daisyUI, repo).

set -euo pipefail
cd "$(dirname "$0")"

PHX_NEW_VERSION="1.8.5"

# A running demo server (and its esbuild/tailwind watchers) keeps writing into
# demo/_build while this script deletes it, which makes `rm -rf` fail halfway
# and leaves a half-generated app behind. Fail loudly first instead.
# Only listening sockets count — a browser tab holding a connection open is not
# a running server.
if command -v lsof >/dev/null && lsof -ti tcp:4000 -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Something is listening on port 4000 — stop the demo server first" >&2
  exit 1
fi

# 1. Ensure the pinned Phoenix generator
if ! mix phx.new --version 2>/dev/null | grep -q "v${PHX_NEW_VERSION}$"; then
  echo "==> Installing phx_new ${PHX_NEW_VERSION}"
  mix archive.install hex phx_new "${PHX_NEW_VERSION}" --force
fi

# 2. Generate a fresh skeleton
#
# SQLite keeps the demo self-contained while still giving FormFlow's data layer
# (and Slab's query mode) a real Ecto repo to point at. daisyUI is vendored by
# phx.new 1.8+, which DynamicForm's built-in components rely on, so there is
# nothing extra to install for it.
echo "==> Generating demo app (phx.new ${PHX_NEW_VERSION})"
rm -rf demo
mix phx.new demo --module Demo --database sqlite3 --no-mailer --no-dashboard --no-gettext --no-install

# 3. FormFlow-specific edits to generated files
#
# form_flow brings phoenix_select, dynamic_form, and slab along as
# dependencies, so apps only declare form_flow itself.

echo "==> Adding form_flow as a path dependency"
perl -0777 -pi -e 's/(defp deps do\s*\n\s*\[\n)/$1      {:form_flow, path: "..\/.."},\n/' demo/mix.exs

echo "==> Replacing the default route with the demo LiveViews"
# The catch-all comes last: FormFlow.Web.Router dispatches on the path segments
# it is handed, so anything not matched by an earlier route falls through to it.
perl -pi -e 's{get "/", PageController, :home}{live "/install-check", InstallCheckLive\n    live "/flows/*path", FlowsLive\n    live "/*path", ReadmeLive}' demo/lib/demo_web/router.ex

# The generated home page test asserts the default Phoenix marketing copy,
# but the route above replaced that page with the demo index
rm -f demo/test/demo_web/controllers/page_controller_test.exs

echo "==> Declaring the route that serves FormFlow's editor bundle"
# The editor is ~390 KB of React + ReactFlow, fetched at runtime by FormFlow's
# colocated hook instead of being bundled into app.js. This must come before the
# catch-all route above, which would otherwise swallow the asset path.
perl -0777 -pi -e 's{(  scope "/", DemoWeb do)}{  import FormFlow.Web.Assets.Router\n\n  scope "/" do\n    form_flow_assets()\n  end\n\n$1}' demo/lib/demo_web/router.ex

echo "==> Pointing Tailwind at FormFlow's classes"
# All four libraries render server-side markup styled with Tailwind (plus the
# daisyUI component classes DynamicForm uses), so each needs a @source line or
# its classes never make it into the generated stylesheet.
perl -pi -e 's{\@source "\.\./\.\./lib/demo_web";}{$&\n/* FormFlow is a path dependency here, so point Tailwind at its source\n   directly. Apps installing form_flow from Hex use\n   "../../deps/form_flow/lib" instead. FormFlow renders components from\n   these libraries too, so their classes need to be scanned as well. */\n\@source "../../../../lib";\n\@source "../../deps/slab/lib";\n\@source "../../deps/dynamic_form/lib";\n\@source "../../deps/phoenix_select/lib";}' demo/assets/css/app.css

echo "==> Registering colocated JavaScript hooks"
# form_flow, slab, and phoenix_select ship their JS as colocated hooks, which
# the LiveView 1.1+ compiler extracts to phoenix-colocated/<app>. Nothing to
# npm install, but each hook set must be registered once. dynamic_form ships
# no hooks, so it has no import here.
perl -pi -e 's{import \{hooks as colocatedHooks\} from "phoenix-colocated/demo"}{$&\nimport {hooks as formFlowHooks} from "phoenix-colocated/form_flow"\nimport {hooks as slabHooks} from "phoenix-colocated/slab"\nimport {hooks as phoenixSelectHooks} from "phoenix-colocated/phoenix_select"}' demo/assets/js/app.js
perl -pi -e 's{hooks: \{\.\.\.colocatedHooks\},}{hooks: {...colocatedHooks, ...formFlowHooks, ...slabHooks, ...phoenixSelectHooks},}' demo/assets/js/app.js

echo "==> Registering a stub uploader for DynamicForm's file uploads"
# Only needed for type="file" questions, which upload directly to cloud
# storage. This stub reports instant success instead of talking to a bucket;
# real apps PUT the file to the presigned URL in entry.meta.url.
perl -0777 -pi -e 's{(const liveSocket = new LiveSocket)}{// Stub uploader for DynamicForm\x27s direct-upload fields: simulates a\n// successful upload without a real cloud bucket. Real apps PUT the file to\n// the presigned URL in entry.meta.url.\nconst GoogleStorage = (entries, _onViewError) => {\n  entries.forEach(entry => setTimeout(() => entry.progress(100), 300))\n}\n\n$1}' demo/assets/js/app.js
perl -pi -e 's{params: \{_csrf_token: csrfToken\},}{$&\n  uploaders: {GoogleStorage},}' demo/assets/js/app.js

echo "==> Configuring the repos"
# FormFlow.Data.Repo wraps the parent app's repo, and Slab's query mode uses
# its own configured repo unless a table passes one explicitly.
perl -0777 -pi -e 's/(# Import environment specific config)/# FormFlow.Data.Repo wraps the parent app\x27s repo\nconfig :form_flow, repo: Demo.Repo\n\n# Slab query mode uses this repo unless a table passes one explicitly\nconfig :slab, repo: Demo.Repo\n\n$1/' demo/config/config.exs

echo "==> Making library changes reload without restarting the server"
# FormFlow is a path dependency here, so the demo has to opt into reloading it.
# Three separate things are needed, and Phoenix.LiveReloader documents the same
# combination for umbrella siblings:
#
#   1. a live_reload pattern matching the library's source, or the watcher
#      ignores the change
#   2. :dirs, because the watcher only looks at the current app's directory by
#      default, and the library lives outside it
#   3. reloadable_apps, so the code reloader recompiles the library on the next
#      request — the demo itself must stay in this list, since setting it
#      replaces the default of "just this app"
#
# Apps installing form_flow from Hex need none of this.
#
# Only the pattern has to be edited in place; the rest is appended, so new
# Phoenix versions can add dev.exs settings without this script fighting them.
perl -0777 -pi -e 's{(\bpatterns: \[\n)}{$1      # FormFlow source, since it is a path dependency in this demo\n      ~r"lib/.*\\.(ex|heex)\$"E,\n}' demo/config/dev.exs

grep -qF '~r"lib/.*\.(ex|heex)$"E' demo/config/dev.exs || {
  echo "Could not add the live_reload pattern — did the generated dev.exs change?" >&2
  exit 1
}

cat >> demo/config/dev.exs <<'DEV_EXS'

# FormFlow is a path dependency in this demo, so the code reloader has to be
# told about it. Without reloadable_apps, library edits need a server restart;
# :demo has to stay in the list or the demo's own code stops reloading. :dirs
# puts the library's source under the file watcher, which otherwise only watches
# this app's directory, so the browser reloads on library changes too.
config :demo, DemoWeb.Endpoint, reloadable_apps: [:demo, :form_flow]

config :phoenix_live_reload, dirs: [Path.expand("../../../lib", __DIR__)]
DEV_EXS

# 4. Copy the demo code over the skeleton
#
# This includes priv/repo/migrations/*_add_form_flow.exs, which was generated by
# `mix form_flow.gen.migration` and committed with a fixed timestamp so
# regenerating stays reproducible. `mix setup` below applies it.
echo "==> Applying overlay/"
cp -R overlay/. demo/

# 5. Install deps, create the database, build assets
echo "==> mix setup (deps, database, assets)"
(cd demo && mix setup)

echo
echo "Done. Run the demo with:"
echo
echo "    cd examples/demo && mix phx.server"
echo
echo "then open http://localhost:4000"
