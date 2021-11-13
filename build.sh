#!/usr/bin/env bash
# exit on error
set -o errexit

# Initial setup
mix deps.get --only prod
MIX_ENV=prod mix compile

# Compile assets
# npm install --prefix ./assets
#npm run deploy --prefix ./assets

# "deploy": "cd .. && mix assets.deploy && rm -f _build/esbuild"
#npm run deploy --prefix apps/maintenance_web/assets/
pushd apps/maintenance_web/
mix assets.deploy && rm -f _build/esbuild
popd

mix phx.digest

# Build the release and overwrite the existing release directory
MIX_ENV=prod mix release --overwrite