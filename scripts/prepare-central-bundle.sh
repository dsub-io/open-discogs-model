#!/usr/bin/env bash

set -euo pipefail

version="${1:?usage: prepare-central-bundle.sh VERSION}"
group_id="io.dsub.opendiscogs"
artifact_id="open-discogs-model-jooq"
group_path="${group_id//.//}"
staging_dir="build/central-staging/$group_path/$artifact_id/$version"
bundle_root="$(mktemp -d "build/central-bundle.XXXXXX")"
artifact_dir="$bundle_root/$group_path/$artifact_id/$version"
output_path="$PWD/build/$artifact_id-$version-central-bundle.zip"

if [[ -e "$output_path" ]]; then
  echo "Bundle already exists: $output_path" >&2
  exit 1
fi

mkdir -p "$artifact_dir"

artifacts=(
  "$artifact_id-$version.jar"
  "$artifact_id-$version-sources.jar"
  "$artifact_id-$version-javadoc.jar"
  "$artifact_id-$version.pom"
)

for artifact in "${artifacts[@]}"; do
  source_path="$staging_dir/$artifact"
  if [[ ! -f "$source_path" ]]; then
    echo "Missing staged artifact: $source_path" >&2
    exit 1
  fi
  cp "$source_path" "$artifact_dir/"
done

signing_key="$(
  gpg --batch --with-colons --list-secret-keys |
    awk -F: '$1 == "sec" { print $5; exit }'
)"

if [[ -z "$signing_key" ]]; then
  echo "No GPG secret key is available for release signing." >&2
  exit 1
fi

for artifact in "${artifacts[@]}"; do
  artifact_path="$artifact_dir/$artifact"
  if [[ -n "${GPG_PRIVATE_KEY_PASSWORD:-}" ]]; then
    printf '%s' "$GPG_PRIVATE_KEY_PASSWORD" |
      gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 \
        --armor --detach-sign --local-user "$signing_key" "$artifact_path"
  else
    gpg --batch --yes --armor --detach-sign \
      --local-user "$signing_key" "$artifact_path"
  fi
  openssl dgst -md5 "$artifact_path" | sed 's/^.*= //' > "$artifact_path.md5"
  openssl dgst -sha1 "$artifact_path" | sed 's/^.*= //' > "$artifact_path.sha1"
done

(
  cd "$bundle_root"
  zip -qr "$output_path" "$group_path"
)

unzip -t "$output_path" >/dev/null
printf '%s\n' "$output_path"
