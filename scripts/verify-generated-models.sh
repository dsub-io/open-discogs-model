#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
generated_model="$repository_root/model/schema.gen.go"
before_hash="$(git hash-object "$generated_model")"

"$repository_root/scripts/generate-go-models.sh"
after_hash="$(git hash-object "$generated_model")"
if [[ "$before_hash" != "$after_hash" ]]; then
  printf 'Generated Go model was stale; regenerate and commit model/schema.gen.go.\n' >&2
  exit 1
fi
