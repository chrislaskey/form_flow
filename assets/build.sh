#!/usr/bin/env bash
#
# Bundles React + ReactFlow + the flow editor into one committed file:
#
#   priv/static/form_flow_editor.mjs
#
# Only maintainers run this, and only when bumping versions or changing the
# editor. Apps installing form_flow get the built file straight out of the
# package — no npm, no node, no bundler configuration on their side. The file is
# fetched at runtime by the colocated hook in
# FormFlow.Web.Templates.Forms.Index, so it never enters the host's app.js.
#
#   ./assets/build.sh
#
# Notes on the esbuild flags:
#
#   --format=esm     the hook loads it with a runtime `import(url)`
#   --loader:.css=text  CSS becomes a string the bundle injects as one <style>
#                    tag, so there is no second asset, no second route, and
#                    ReactFlow's styles never pass through the host's Tailwind

set -euo pipefail
cd "$(dirname "$0")"

[ -d node_modules ] || npm install --no-audit --no-fund --loglevel=error

npx esbuild js/editor.jsx \
  --bundle \
  --minify \
  --format=esm \
  --target=es2020 \
  --jsx=automatic \
  --loader:.css=text \
  --define:process.env.NODE_ENV='"production"' \
  --outfile=../priv/static/form_flow_editor.mjs

echo
ls -lh ../priv/static/form_flow_editor.mjs
