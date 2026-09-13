#!/usr/bin/env bash

# Vendors form_flow source into the Docker build context, then deploys to Fly.io.
#
# The demo app depends on form_flow via a relative path (../../) that sits
# outside the Docker build context. This script copies the files Docker needs
# into vendor/form_flow so the Dockerfile can COPY them. mix.exs detects
# the vendored copy automatically and uses it instead of the parent path.
#
# Usage:
#   ./deploy.sh           # standard deploy
#   ./deploy.sh --remote-only   # pass flags through to fly deploy

set -euo pipefail

cd "$(dirname "$0")"

REPO_ROOT="../.."
VENDOR_DIR="vendor/form_flow"

echo "==> Vendoring form_flow into $VENDOR_DIR"
rm -rf "$VENDOR_DIR"
mkdir -p "$VENDOR_DIR"

cp "$REPO_ROOT/mix.exs" "$VENDOR_DIR/mix.exs"
cp -R "$REPO_ROOT/lib"  "$VENDOR_DIR/lib"
cp -R "$REPO_ROOT/priv" "$VENDOR_DIR/priv"

echo "==> Running fly deploy $*"
fly deploy "$@"

echo "==> Cleaning up vendored files"
rm -rf vendor

echo "==> Done"
