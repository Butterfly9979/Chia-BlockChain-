#!/usr/bin/env bash

set -euo pipefail

# Anchor to script directory so relative paths are stable
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

git status || true
git submodule || true

if [ "${1-}" = "" ]; then
  echo "This script requires either amd64 or arm64 as an argument"
  exit 1
elif [ "$1" = "amd64" ]; then
  export REDHAT_PLATFORM="x86_64"
else
  export REDHAT_PLATFORM="arm64"
fi

# If the env variable NOTARIZE and the username and password variables are
# set, this will attempt to Notarize the signed DMG

if [ ! "${CHIA_INSTALLER_VERSION-}" ]; then
  echo "WARNING: No environment variable CHIA_INSTALLER_VERSION set. Using 0.0.0."
  CHIA_INSTALLER_VERSION="0.0.0"
fi
echo "Chia Installer Version is: $CHIA_INSTALLER_VERSION"

echo "Installing npm and electron packagers"
command -v npm >/dev/null 2>&1 || { echo "npm is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
cd npm_linux || exit 1
npm ci
NPM_PATH="$(pwd)/node_modules/.bin"
cd .. || exit 1

echo "Create dist/"
rm -rf dist
mkdir dist

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

# Builds CLI only rpm
CLI_RPM_BASE="chia-blockchain-cli-$CHIA_INSTALLER_VERSION-1.$REDHAT_PLATFORM"
mkdir -p "dist/$CLI_RPM_BASE/opt/chia"
mkdir -p "dist/$CLI_RPM_BASE/usr/bin"
mkdir -p "dist/$CLI_RPM_BASE/etc/systemd/system"
if [ -d dist/daemon ]; then
  cp -r dist/daemon/* "dist/$CLI_RPM_BASE/opt/chia/"
else
  echo "dist/daemon not found" >&2
  exit 1
fi
cp assets/systemd/*.service "dist/$CLI_RPM_BASE/etc/systemd/system/"

ln -s ../../opt/chia/chia "dist/$CLI_RPM_BASE/usr/bin/chia"
# This is built into the base build image; tolerate environments without rvm
# shellcheck disable=SC1091
if [ -f /etc/profile.d/rvm.sh ]; then
  . /etc/profile.d/rvm.sh
  rvm use ruby-3 || true
fi

export FPM_EDITOR="cat >dist/cli.spec <"

# /usr/lib64/libcrypt.so.1 is marked as a dependency specifically because newer versions of fedora bundle
# libcrypt.so.2 by default, and the libxcrypt-compat package needs to be installed for the other version
# Marking as a dependency allows yum/dnf to automatically install the libxcrypt-compat package as well
command -v fpm >/dev/null 2>&1 || echo "warning: fpm not found; expecting system-provided fpm or rvm environment" >&2
fpm -s dir -t rpm \
  --edit \
  -C "dist/$CLI_RPM_BASE" \
  --directories "/opt/chia" \
  -p "dist/$CLI_RPM_BASE.rpm" \
  --name chia-blockchain-cli \
  --license Apache-2.0 \
  --version "$CHIA_INSTALLER_VERSION" \
  --architecture "$REDHAT_PLATFORM" \
  --description "Chia is a modern cryptocurrency built from scratch, designed to be efficient, decentralized, and secure." \
  --rpm-tag 'Recommends: libxcrypt-compat' \
  --rpm-tag '%define _build_id_links none' \
  --rpm-tag '%undefine _missing_build_ids_terminate_build' \
  --before-install=assets/rpm/before-install.sh \
  --rpm-tag 'Requires(pre): findutils' \
  --rpm-compression xzmt \
  --rpm-compression-level 6 \
  .
# CLI only rpm done
cp -r dist/daemon ../chia-blockchain-gui/packages/gui
# Change to the gui package
cd ../chia-blockchain-gui/packages/gui || exit 1

# sets the version for chia-blockchain in package.json
cp package.json package.json.orig
jq --arg VER "$CHIA_INSTALLER_VERSION" '.version=$VER' package.json >temp.json && mv temp.json package.json

export FPM_EDITOR="cat >../../../build_scripts/dist/gui.spec <"
jq '.rpm.fpm |= . + ["--edit"]' ../../../build_scripts/electron-builder.json >temp.json && mv temp.json ../../../build_scripts/electron-builder.json

echo "Building Linux(rpm) Electron app"
OPT_ARCH="--x64"
if [ "$REDHAT_PLATFORM" = "arm64" ]; then
  OPT_ARCH="--arm64"
fi
PRODUCT_NAME="chia"
echo "${NPM_PATH}/electron-builder" build --linux rpm "${OPT_ARCH}" \
  --config.extraMetadata.name=chia-blockchain \
  --config.productName="${PRODUCT_NAME}" --config.linux.desktop.Name="Chia Blockchain" \
  --config.rpm.packageName="chia-blockchain" \
  --config ../../../build_scripts/electron-builder.json
"${NPM_PATH}/electron-builder" build --linux rpm "${OPT_ARCH}" \
  --config.extraMetadata.name=chia-blockchain \
  --config.productName="${PRODUCT_NAME}" --config.linux.desktop.Name="Chia Blockchain" \
  --config.rpm.packageName="chia-blockchain" \
  --config ../../../build_scripts/electron-builder.json
LAST_EXIT_CODE=$?
ls -l dist/linux*-unpacked/resources || true

# reset the package.json to the original
mv package.json.orig package.json

if [ "$LAST_EXIT_CODE" -ne 0 ]; then
  echo >&2 "electron-builder failed!"
  exit $LAST_EXIT_CODE
fi

GUI_RPM_NAME="chia-blockchain-${CHIA_INSTALLER_VERSION}-1.${REDHAT_PLATFORM}.rpm"
# Try to auto-detect the generated .rpm from electron-builder
EB_RPM_CANDIDATE=""
if [ -f "dist/${PRODUCT_NAME}-${CHIA_INSTALLER_VERSION}.rpm" ]; then
  EB_RPM_CANDIDATE="dist/${PRODUCT_NAME}-${CHIA_INSTALLER_VERSION}.rpm"
else
  set +e
  EB_RPM_CANDIDATE=$(ls dist/*${CHIA_INSTALLER_VERSION}*${REDHAT_PLATFORM}*.rpm 2>/dev/null | head -n 1)
  if [ -z "${EB_RPM_CANDIDATE}" ]; then
    EB_RPM_CANDIDATE=$(ls dist/*.rpm 2>/dev/null | head -n 1)
  fi
  set -e
fi
if [ -z "${EB_RPM_CANDIDATE}" ] || [ ! -f "${EB_RPM_CANDIDATE}" ]; then
  echo "Could not locate electron-builder .rpm in dist/" >&2
  exit 1
fi
mv "${EB_RPM_CANDIDATE}" "../../../build_scripts/dist/${GUI_RPM_NAME}"
cd ../../../build_scripts || exit 1

echo "Create final installer"
rm -rf final_installer
mkdir final_installer

mv "dist/${GUI_RPM_NAME}" final_installer/
# Move the cli only rpm into final installers as well, so it gets uploaded as an artifact
mv "dist/$CLI_RPM_BASE.rpm" final_installer/

ls -l final_installer/
