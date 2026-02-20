#!/usr/bin/env bash
 
set -euo pipefail
 
# Set defaults for required variables
TERRAFORM="${TERRAFORM:-terraform}"
JQ="${JQ:-jq}"
REPO_ROOT="${REPO_ROOT:-.}"
 
b64decode() {
  if base64 --help >/dev/null 2>&1; then
    base64 --decode
  elif echo "test" | base64 -d >/dev/null 2>&1; then
    base64 -d
  else
    base64 -D
  fi
}
 
state_file="$(mktemp -t tfstate.XXXXXX)"
 
cleanup() {
  rm -f -- "$state_file" 2>/dev/null || true
}
trap cleanup EXIT
 
if ! "$TERRAFORM" state pull >"$state_file" 2>/dev/null; then
  exit 0
fi
 
if [[ ! -s "$state_file" ]]; then
  exit 0
fi
 
"$JQ" -r '.resources[]? | select(.mode=="managed" and .type=="local_file") | .instances[]? | .attributes | @base64' <"$state_file" |
  while read -r enc; do
    [[ -z "$enc" ]] && continue
 
    attrs_json=$(echo "$enc" | b64decode 2>/dev/null) || continue
 
    filename=$(echo "$attrs_json" | "$JQ" -r '.filename // empty' 2>/dev/null)
    [[ -z "$filename" ]] && continue
 
    content=$(echo "$attrs_json" | "$JQ" -r '.content // empty' 2>/dev/null)
    if [[ -z "$content" ]]; then
      content_b64=$(echo "$attrs_json" | "$JQ" -r '.content_base64 // empty' 2>/dev/null)
      if [[ -n "$content_b64" ]]; then
        content=$(echo "$content_b64" | b64decode 2>/dev/null)
      fi
    fi
 
    file_perm=$(echo "$attrs_json" | "$JQ" -r '.file_permission // empty' 2>/dev/null)
    dir_perm=$(echo "$attrs_json" | "$JQ" -r '.directory_permission // empty' 2>/dev/null)
 
    if [[ "$filename" == *".."* ]]; then
      continue
    fi
 
    if [[ "$filename" == /* ]]; then
      target="$filename"
      if [[ "$target" != "$REPO_ROOT/"* ]]; then
        continue
      fi
    else
      target="${REPO_ROOT}/${filename}"
    fi
 
    mkdir -p "$(dirname "$target")"
 
    if [[ -n "$dir_perm" ]]; then
      chmod "$dir_perm" "$(dirname "$target")" 2>/dev/null || true
    fi
 
    printf '%s' "$content" >"$target"
 
    if [[ -n "$file_perm" ]]; then
      chmod "$file_perm" "$target" 2>/dev/null || true
    fi
  done