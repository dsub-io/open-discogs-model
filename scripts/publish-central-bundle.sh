#!/usr/bin/env bash

set -euo pipefail

bundle_path="${1:?usage: publish-central-bundle.sh BUNDLE_PATH DEPLOYMENT_NAME}"
deployment_name="${2:?usage: publish-central-bundle.sh BUNDLE_PATH DEPLOYMENT_NAME}"

: "${CENTRAL_TOKEN_USERNAME:?CENTRAL_TOKEN_USERNAME is required}"
: "${CENTRAL_TOKEN_PASSWORD:?CENTRAL_TOKEN_PASSWORD is required}"

if [[ ! -f "$bundle_path" ]]; then
  echo "Central bundle does not exist: $bundle_path" >&2
  exit 1
fi

if [[ ! "$deployment_name" =~ ^[A-Za-z0-9._:-]+$ ]]; then
  echo "Deployment name contains unsupported characters." >&2
  exit 1
fi

authorization="$(
  printf '%s:%s' "$CENTRAL_TOKEN_USERNAME" "$CENTRAL_TOKEN_PASSWORD" |
    base64 |
    tr -d '\n'
)"
echo "::add-mask::$authorization"

deployment_id="$(
  curl --fail-with-body --silent --show-error \
    --request POST \
    --header "Authorization: Bearer $authorization" \
    --form "bundle=@$bundle_path" \
    "https://central.sonatype.com/api/v1/publisher/upload?publishingType=AUTOMATIC&name=$deployment_name" |
    tr -d '"[:space:]'
)"

if [[ ! "$deployment_id" =~ ^[0-9a-fA-F-]{36}$ ]]; then
  echo "Maven Central returned an invalid deployment ID." >&2
  exit 1
fi

echo "Maven Central deployment: $deployment_id"

for attempt in $(seq 1 120); do
  status_json="$(
    curl --fail-with-body --silent --show-error \
      --request POST \
      --header "Authorization: Bearer $authorization" \
      "https://central.sonatype.com/api/v1/publisher/status?id=$deployment_id"
  )"
  state="$(jq -r '.deploymentState' <<<"$status_json")"

  case "$state" in
    PUBLISHED)
      echo "Maven Central publication completed."
      exit 0
      ;;
    FAILED)
      echo "Maven Central validation failed." >&2
      jq . <<<"$status_json" >&2
      exit 1
      ;;
    PENDING|VALIDATING|VALIDATED|PUBLISHING)
      echo "Maven Central state: $state (attempt $attempt/120)"
      ;;
    *)
      echo "Unexpected Maven Central state: $state" >&2
      jq . <<<"$status_json" >&2
      exit 1
      ;;
  esac

  sleep 15
done

echo "Timed out waiting for Maven Central publication." >&2
exit 1
