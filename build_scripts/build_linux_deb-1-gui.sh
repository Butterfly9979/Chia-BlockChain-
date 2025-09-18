#!/usr/bin/env bash

set -euo pipefail

# Always run relative to the repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.." || exit 1

# Ensure required tools
command -v git >/dev/null 2>&1 || { echo "git is required" >&2; exit 1; }
command -v npm >/dev/null 2>&1 || { echo "npm is required" >&2; exit 1; }

git submodule update --init chia-blockchain-gui

cd ./chia-blockchain-gui || exit 1

echo "npm build"
# Removes packages/*/node_modules non-interactively
npx -y lerna clean -y || npx --yes lerna clean -y || true
npm ci
# Audit fix does not currently work with Lerna. See https://github.com/lerna/lerna/issues/1663
# npm audit fix
if ! npm run build; then
  echo >&2 "npm run build failed!"
  exit 1
fi

# Remove unused packages
[ -d node_modules ] && rm -rf node_modules

# Other than `chia-blockchain-gui/package/gui`, all other packages are no longer necessary after build.
# Since these unused packages make cache unnecessarily fat, here unused packages are removed.
echo "Remove unused @chia-network packages to make cache slim"
[ -d packages ] && ls -l packages || true
[ -d packages/api ] && rm -rf packages/api || true
[ -d packages/api-react ] && rm -rf packages/api-react || true
[ -d packages/core ] && rm -rf packages/core || true
[ -d packages/icons ] && rm -rf packages/icons || true
[ -d packages/wallets ] && rm -rf packages/wallets || true

# Remove unused fat npm modules from the gui package
if cd ./packages/gui/node_modules 2>/dev/null; then
  echo "Remove unused node_modules in the gui package to make cache slim more"
  [ -d electron/dist ] && rm -rf electron/dist # ~186MB
  [ -d "@mui" ] && rm -rf "@mui"               # ~71MB
  [ -d typescript ] && rm -rf typescript        # ~63MB

  # Remove `packages/gui/node_modules/@chia-network` because it causes an error on later `electron-packager` command
  [ -d "@chia-network" ] && rm -rf "@chia-network"
else
  echo "packages/gui/node_modules not found; skipping node_modules pruning" >&2
fi
