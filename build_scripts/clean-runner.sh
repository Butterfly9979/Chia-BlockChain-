#!/usr/bin/env bash
# Cleans up files/directories that may be left over from previous runs for a clean slate before starting a new build

set -euo pipefail

# Anchor to repository root based on this script's location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Local virtualenvs and build artifacts
rm -rf -- ../venv || true
rm -rf -- venv || true
rm -rf -- chia_blockchain.egg-info || true
rm -rf -- build_scripts/final_installer || true
rm -rf -- build_scripts/dist || true
rm -rf -- build_scripts/pyinstaller || true

# GUI artifacts
rm -rf -- chia-blockchain-gui/build || true
rm -rf -- chia-blockchain-gui/daemon || true
rm -rf -- chia-blockchain-gui/node_modules || true
rm -f -- chia-blockchain-gui/temp.json || true

# Reset package-lock.json if the GUI repo exists
if [ -d "$REPO_ROOT/chia-blockchain-gui" ]; then
  git -C "$REPO_ROOT/chia-blockchain-gui" checkout -- package-lock.json || true
fi

# Clean up old globally installed node_modules that might conflict with the current build (macOS/Homebrew)
if [ -d /opt/homebrew/lib/node_modules ]; then
  rm -rf -- /opt/homebrew/lib/node_modules || true
fi

# Clean up any installed versions of node so we can start fresh (macOS/Homebrew only)
if command -v brew >/dev/null 2>&1; then
  brew list 2>/dev/null | grep -E "^node(@|$)" | xargs -L1 brew uninstall || true
fi
