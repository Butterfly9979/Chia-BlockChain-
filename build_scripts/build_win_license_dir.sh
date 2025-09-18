#!/usr/bin/env bash

set -euo pipefail

# Anchor to script directory so relative paths are stable
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

# PULL IN LICENSES USING NPM - LICENSE CHECKER
command -v npm >/dev/null 2>&1 || { echo "npm is required" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
npm install -g license-checker --no-fund --no-audit

cd ../chia-blockchain-gui || exit 1

npm ci

sum=$(license-checker --summary)
printf "%s\n" "$sum"

# Collect license file paths, filter nulls and empty entries
license_list=$(license-checker --json | jq -r 'to_entries[] | select(.value.licenseFile != null) | .value.licenseFile' | sed '/^$/d')

# Split into array; strip CR if present
IFS=$'\n' read -rd '' -a licenses_array <<<"${license_list//$'\r'/}"

# Print for info
printf '%s\n' "${licenses_array[@]}"

# Fresh licenses dir
rm -rf licenses

for i in "${licenses_array[@]}"; do
  # Normalize Windows backslashes to POSIX slashes
  i_norm=$(printf "%s" "$i" | tr '\\' '/')
  base_dir=$(dirname "$i_norm")
  last_segment=$(printf "%s" "$base_dir" | awk -F'/' '{print $NF}')
  dirname="licenses/${last_segment}"
  echo "$dirname"
  mkdir -p "$dirname"
  cp -- "$i" "$dirname" 2>/dev/null || cp -- "$i_norm" "$dirname"
done

mkdir -p ../build_scripts/dist/daemon
mv -- licenses/ ../build_scripts/dist/daemon/
cd ../build_scripts || exit 1

# PULL IN THE LICENSES FROM PIP-LICENSE
if command -v pip >/dev/null 2>&1; then
  pip install --disable-pip-version-check pip-licenses || true
fi
if ! command -v pip-licenses >/dev/null 2>&1; then
  if command -v pip3 >/dev/null 2>&1; then
    pip3 install --disable-pip-version-check pip-licenses
  fi
fi

# capture the output of the command in a variable
output=$(pip-licenses -l -f json | jq -r '.[] | select(.LicenseFile != null and .LicenseFile != "UNKNOWN") | .LicenseFile')

# initialize an empty array
license_path_array=()

# read the output line by line into the array
while IFS= read -r line; do
  license_path_array+=("$line")
done <<<"${output//$'\r'/}"

# create a dir for each license and copy the license file over
for i in "${license_path_array[@]}"; do
  i_norm=$(printf "%s" "$i" | tr '\\' '/')
  base_dir=$(dirname "$i_norm")
  last_segment=$(printf "%s" "$base_dir" | awk -F'/' '{print $NF}')
  dirname="dist/daemon/licenses/${last_segment}"
  echo "$dirname"
  mkdir -p "$dirname"
  cp -- "$i" "$dirname" 2>/dev/null || cp -- "$i_norm" "$dirname"
  echo "$i"
done

ls -lah dist/daemon || true
