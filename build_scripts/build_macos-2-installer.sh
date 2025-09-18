#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

# Anchor to script directory for stable relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

git status || true
git submodule || true

# If the env variable NOTARIZE and the username and password variables are
# set, this will attempt to Notarize the signed DMG.

if [ ! "${CHIA_INSTALLER_VERSION-}" ]; then
  echo "WARNING: No environment variable CHIA_INSTALLER_VERSION set. Using 0.0.0."
  CHIA_INSTALLER_VERSION="0.0.0"
fi
echo "Chia Installer Version is: $CHIA_INSTALLER_VERSION"

echo "Installing npm utilities"
command -v npm >/dev/null 2>&1 || { echo "npm is required" >&2; exit 1; }
cd npm_macos || exit 1
npm ci
NPM_PATH="$(pwd)/node_modules/.bin"
cd .. || exit 1

echo "Create dist/"
if command -v sudo >/dev/null 2>&1; then
  sudo rm -rf dist || rm -rf dist || true
else
  rm -rf dist || true
fi
mkdir -p dist

echo "Create executables with pyinstaller"
command -v python >/dev/null 2>&1 || { echo "python is required" >&2; exit 1; }
command -v pyinstaller >/dev/null 2>&1 || { echo "pyinstaller is required" >&2; exit 1; }
SPEC_FILE=$(python -c 'import sys; from pathlib import Path; path = Path(sys.argv[1]); print(path.absolute().as_posix())' "pyinstaller.spec")
if ! pyinstaller --log-level=INFO "$SPEC_FILE"; then
  echo >&2 "pyinstaller failed!"
  exit 1
fi

# Creates a directory of licenses
echo "Building pip and NPM license directory"
pwd
bash ./build_license_directory.sh

# Remove rpaths on some libraries to homebrew directories that
# appears sometimes m-series chips (prefer bundled from @loader_path/..)
bash ./remove_brew_rpaths.sh

if [ -d dist/daemon ]; then
  cp -r dist/daemon ../chia-blockchain-gui/packages/gui
else
  echo "dist/daemon not found" >&2
  exit 1
fi
# Change to the gui package
cd ../chia-blockchain-gui/packages/gui || exit 1

# sets the version for chia-blockchain in package.json
if ! command -v jq >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    brew install jq
  else
    echo "jq not found and Homebrew not available. Please install jq." >&2
    exit 1
  fi
fi
cp package.json package.json.orig
jq --arg VER "$CHIA_INSTALLER_VERSION" '.version=$VER' package.json >temp.json && mv temp.json package.json

echo "Building macOS Electron app"
OPT_ARCH="--x64"
if [ "$(arch)" = "arm64" ]; then
  OPT_ARCH="--arm64"
fi
PRODUCT_NAME="Chia"
if [ "${NOTARIZE-}" = true ]; then
  echo "Setting credentials for signing"
  export CSC_LINK=$APPLE_DEV_ID_APP
  export CSC_KEY_PASSWORD=$APPLE_DEV_ID_APP_PASS
  export PUBLISH_FOR_PULL_REQUEST=true
  export CSC_FOR_PULL_REQUEST=true
else
  echo "Not on ci or no secrets so not signing"
  export CSC_IDENTITY_AUTO_DISCOVERY=false
fi
echo "${NPM_PATH}/electron-builder" build --mac "${OPT_ARCH}" \
  --config.productName="$PRODUCT_NAME" \
  --config.mac.minimumSystemVersion="11" \
  --config ../../../build_scripts/electron-builder.json
"${NPM_PATH}/electron-builder" build --mac "${OPT_ARCH}" \
  --config.productName="$PRODUCT_NAME" \
  --config.mac.minimumSystemVersion="11" \
  --config ../../../build_scripts/electron-builder.json
LAST_EXIT_CODE=$?
ls -l dist/mac*/chia.app/Contents/Resources/app.asar || true

# reset the package.json to the original
mv package.json.orig package.json

if [ "$LAST_EXIT_CODE" -ne 0 ]; then
  echo >&2 "electron-builder failed!"
  exit $LAST_EXIT_CODE
fi

mkdir -p ../../../build_scripts/dist
mv dist/* ../../../build_scripts/dist/
cd ../../../build_scripts || exit 1

mkdir -p final_installer
# Determine actual DMG produced by electron-builder
ORIGINAL_DMG_NAME="chia-${CHIA_INSTALLER_VERSION}.dmg"
set +e
FOUND_DMG=$(ls dist/*${CHIA_INSTALLER_VERSION}*.dmg 2>/dev/null | head -n 1)
set -e
if [ -n "${FOUND_DMG}" ]; then
  ORIGINAL_DMG_NAME=$(basename "${FOUND_DMG}")
fi
if [ "$(arch)" = "arm64" ]; then
  DMG_NAME=Chia-${CHIA_INSTALLER_VERSION}-arm64.dmg
else
  # NOTE: when coded, this changes the case to Chia
  DMG_NAME=Chia-${CHIA_INSTALLER_VERSION}.dmg
fi
if [ ! -f "dist/${ORIGINAL_DMG_NAME}" ]; then
  echo "Could not locate DMG dist/${ORIGINAL_DMG_NAME}" >&2
  exit 1
fi
mv "dist/${ORIGINAL_DMG_NAME}" "final_installer/${DMG_NAME}"

ls -lh final_installer

if [ "${NOTARIZE-}" = true ]; then
  echo "Notarize $DMG_NAME on ci"
  cd final_installer || exit 1
  xcrun notarytool submit --wait --apple-id "$APPLE_NOTARIZE_USERNAME" --password "$APPLE_NOTARIZE_PASSWORD" --team-id "$APPLE_TEAM_ID" "$DMG_NAME"
  xcrun stapler staple "$DMG_NAME"
  echo "Notarization step complete"
else
  echo "Not on ci or no secrets so skipping Notarize"
fi

# Notes on how to manually notarize
#
# Ask for username and password. password should be an app specific password.
# Generate app specific password https://support.apple.com/en-us/HT204397
# xcrun notarytool submit --wait --apple-id username --password password --team-id team-id Chia-0.1.X.dmg
# Wait until the command returns a success message
#
# Once that is successful, execute the following command":
# xcrun stapler staple Chia-0.1.X.dmg
#
# Validate DMG:
# xcrun stapler validate Chia-0.1.X.dmg
