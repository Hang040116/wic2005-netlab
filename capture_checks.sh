#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

python_bin=.venv/bin/python
if [[ ! -x "$python_bin" ]]; then
  echo "Python environment missing: $python_bin" >&2
  exit 1
fi

record_rejection() {
  local output=$1
  shift
  local temporary
  temporary=$(mktemp)
  if "$python_bin" "$@" > "$temporary" 2>&1; then
    echo "Expected rejection, but the input was accepted: $*" >&2
    rm -f "$temporary"
    exit 1
  fi
  if ! grep -q '^PROBLEM:' "$temporary"; then
    echo "The command failed without a validation problem: $*" >&2
    cat "$temporary" >&2
    rm -f "$temporary"
    exit 1
  fi
  cat "$temporary" >> "$output"
  rm -f "$temporary"
}

: > evidence/check.txt
record_rejection evidence/check.txt build_topo.py bad.yaml

: > evidence3/check.txt
record_rejection evidence3/check.txt build_routed.py loop.yaml
record_rejection evidence3/check.txt build_routed.py missing.yaml

echo 'Week 2/3 negative checks captured and verified'
