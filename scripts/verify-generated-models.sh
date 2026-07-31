#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$repository_root/scripts/generate-go-models.sh"
git -C "$repository_root" diff --exit-code -- model/schema.gen.go
