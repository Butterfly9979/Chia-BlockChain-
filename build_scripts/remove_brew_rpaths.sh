#!/usr/bin/env bash
set -eo pipefail

# Removes rpath loader commands from _ssl.cpython-*.so which are sometimes
# added on Apple M-series CPUs, prefer bundled dynamic libraries for which
# there is an rpath added already as "@loader_path/.." -- however, the
# homebrew rpaths appear with higher precedence, potentially causing issues.
# See: #18099

echo ""
echo "Stripping brew rpaths..."

# Verify required tools are available
for cmd in otool install_name_tool find; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    >&2 echo "Required tool not found: $cmd"
    exit 1
  fi
done

# Common Homebrew rpath locations
rpath_names=(
  /opt/homebrew/lib
  /usr/local/lib
)

# Find one or more matching shared objects
mapfile -t so_paths < <(find "dist/daemon/_internal/lib-dynload" -name "_ssl.cpython-*.so" 2>/dev/null || true)
if [[ ${#so_paths[@]} -eq 0 ]]; then
  >&2 echo "No _ssl.cpython-*.so found under dist/daemon/_internal/lib-dynload; skipping"
  exit 0
fi

for so_path in "${so_paths[@]}"; do
  echo "Found '_ssl.cpython-*.so' at '$so_path':"
  otool -l "$so_path" || true
  echo ""

  # Attempt to delete each known rpath repeatedly until it no longer exists
  for rpath_name in "${rpath_names[@]}"; do
    while true; do
      set +e
      nt_output=$(install_name_tool -delete_rpath "$rpath_name" "$so_path" 2>&1)
      status=$?
      set -e
      if [[ $status -ne 0 ]]; then
        # If the error indicates the rpath wasn't present, it's fine; otherwise report
        if [[ -n "$nt_output" ]] && ! grep -q "no LC_RPATH load command with path:" <<<"$nt_output"; then
          >&2 echo "install_name_tool reported an unexpected error:"
          >&2 echo "$nt_output"
        fi
        break
      fi
    done
  done

  echo "After stripping, current load commands for '$so_path':"
  otool -l "$so_path" || true
  echo ""
done

echo "Done."
echo ""
