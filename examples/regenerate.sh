#!/usr/bin/env bash
#
# Regenerates the demo app from scratch:
#
#   1. Generates a fresh Phoenix app with `mix phx.new` (pinned version)
#   2. Applies FormFlow-specific edits (path dep, routes, Tailwind)
#   3. Copies the demo code from overlay/ over the skeleton
#   4. Installs deps and builds assets
#
# Run it whenever the generated skeleton drifts out of date:
#
#   ./examples/regenerate.sh
#
# The interesting demo code lives in overlay/ (version controlled); the
# generated skeleton is disposable.

set -euo pipefail
cd "$(dirname "$0")"

PHX_NEW_VERSION="1.8.5"

# 1. Ensure the pinned Phoenix generator
if ! mix phx.new --version 2>/dev/null | grep -q "v${PHX_NEW_VERSION}$"; then
  echo "==> Installing phx_new ${PHX_NEW_VERSION}"
  mix archive.install hex phx_new "${PHX_NEW_VERSION}" --force
fi

# 2. Generate a fresh skeleton
#
# No database yet: FormFlow.Data.Repo wraps the parent app's repo, but nothing
# in the demo persists anything so far. When the data layer lands, regenerate
# with `--database sqlite3` instead of `--no-ecto` and add
# `config :form_flow, repo: Demo.Repo` below.
echo "==> Generating demo app (phx.new ${PHX_NEW_VERSION})"
rm -rf demo
mix phx.new demo --module Demo --no-ecto --no-mailer --no-dashboard --no-gettext --no-install

# 3. FormFlow-specific edits to generated files

echo "==> Adding form_flow as a path dependency"
perl -0777 -pi -e 's/(defp deps do\s*\n\s*\[\n)/$1      {:form_flow, path: "..\/.."},\n/' demo/mix.exs

echo "==> Replacing the default route with the demo LiveViews"
perl -pi -e 's{get "/", PageController, :home}{live "/", ReadmeLive}' demo/lib/demo_web/router.ex

# The generated home page test asserts the default Phoenix marketing copy,
# but the route above replaced that page with the demo index
rm -f demo/test/demo_web/controllers/page_controller_test.exs

echo "==> Pointing Tailwind at FormFlow's classes"
perl -pi -e 's{\@source "\.\./\.\./lib/demo_web";}{$&\n/* FormFlow is a path dependency here, so point Tailwind at its source\n   directly. Apps installing form_flow from Hex use\n   "../../deps/form_flow/lib" instead. FormFlow builds on these libraries,\n   so their classes need to be scanned too. */\n\@source "../../../../lib";\n\@source "../../deps/slab/lib";\n\@source "../../deps/dynamic_form/lib";\n\@source "../../deps/phoenix_select/lib";}' demo/assets/css/app.css

# 4. Copy the demo code over the skeleton
echo "==> Applying overlay/"
cp -R overlay/. demo/

# 5. Install deps and build assets
echo "==> mix setup (deps, assets)"
(cd demo && mix setup)

echo
echo "Done. Run the demo with:"
echo
echo "    cd examples/demo && mix phx.server"
echo
echo "then open http://localhost:4000"
