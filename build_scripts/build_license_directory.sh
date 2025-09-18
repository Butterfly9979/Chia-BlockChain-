#!/usr/bin/env bash

set -euo pipefail

# Move to the script directory so relative paths are reliable
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Ensure required commands exist
for cmd in npm jq python3 python pip; do
  command -v "$cmd" >/dev/null 2>&1 || true
done
command -v npm >/dev/null 2>&1 || { echo "npm is required"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }

# PULL IN LICENSES USING NPM - LICENSE CHECKER
npm install -g license-checker --no-fund --no-audit

cd ../chia-blockchain-gui || exit 1

npm ci

sum=$(license-checker --summary)
printf "%s\n" "$sum"

# Collect license file paths (filter out nulls) and normalize path separators
license_list=$(license-checker --json | jq -r 'to_entries[] | select(.value.licenseFile != null) | .value.licenseFile' | sed '/^$/d')

# Split the license list by newline character into an array
IFS=$'\n' read -rd '' -a licenses_array <<<"${license_list//$'\r'/}"

# Print the contents of the array (debug/info)
printf '%s\n' "${licenses_array[@]}"

# Fresh licenses dir
rm -rf licenses

for i in "${licenses_array[@]}"; do
  # Normalize Windows backslashes to POSIX forward slashes
  i_norm=$(printf "%s" "$i" | tr '\\' '/')
  base_dir=$(dirname "$i_norm")
  last_segment=$(printf "%s" "$base_dir" | awk -F'/' '{print $NF}')
  dirname="licenses/${last_segment}"
  mkdir -p "$dirname"
  echo "$dirname"
  # Use -- to avoid issues with filenames starting with hyphen
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
