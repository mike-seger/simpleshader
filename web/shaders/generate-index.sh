#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")"

title_case() {
  local name
  name=${1%.glsl}
  name=${name//-/ }
  name=${name//_/ }
  awk '{ for (i = 1; i <= NF; i++) $i = toupper(substr($i, 1, 1)) substr($i, 2); print }' <<< "$name"
}

{
  cat <<'EOF'
/**
 * Shader index — single source of truth for all available shaders.
 * Each entry: { path: relative to repo root index.html, name: display name }
 * Grouped by folder.
 */
const SHADER_INDEX = [
EOF

  for dir in $(find . -mindepth 1 -maxdepth 1 -type d | grep -v '^\./lib$' | sort); do
    folder=${dir#./}
    files=$(find "$dir" -maxdepth 1 -type f -name '*.glsl'| grep -v -- '-sound.glsl$'  |sort)
    [ -n "$files" ] || continue

    cat <<EOF
  {
    folder: "$folder",
    shaders: [
EOF

    while IFS= read -r file; do
      [ -n "$file" ] || continue
      base=${file##*/}
      name=$(title_case "$base")
      path="web/shaders/${file#./}"
      printf '      { name: "%s", path: "%s" },\n' "$name" "$path"
    done <<< "$files"

    cat <<'EOF'
    ],
  },
EOF
  done

  cat <<'EOF'
];

export default SHADER_INDEX;
EOF
} > index.js

echo "Wrote web/shaders/index.js"