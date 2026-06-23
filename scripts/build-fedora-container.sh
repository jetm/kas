#!/usr/bin/env bash
#
# Build the Fedora kas build-env image and (re)point :latest at it.
#
# Produces jetm/kas-build-env:<kas_version>-f<fedora_version> from
# Dockerfile.fedora. <kas_version> comes from kas/__version__.py;
# <fedora_version> defaults to the FEDORA_TAG baked into Dockerfile.fedora
# and can be overridden with -f for a cross-release comparison build.

set -euo pipefail

IMAGE=jetm/kas-build-env
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
DOCKERFILE="$REPO_ROOT/Dockerfile.fedora"

usage() {
  cat <<EOF
Usage: $(basename "$0") [-f FEDORA_VERSION] [--no-cache] [--no-latest] [-h]

Build $IMAGE:<kas_version>-f<fedora_version> from Dockerfile.fedora and tag
the result as $IMAGE:latest.

Options:
  -f, --fedora VERSION  Fedora release to build
                        (default: Dockerfile.fedora's FEDORA_TAG)
      --no-cache        Rebuild from scratch, ignoring the layer cache
      --no-latest       Do not retag $IMAGE:latest to the built image
  -h, --help            Show this help
EOF
}

FEDORA_VERSION=
NO_CACHE=
UPDATE_LATEST=y

while [ $# -gt 0 ]; do
  case "$1" in
    -f | --fedora)
      shift
      FEDORA_VERSION="${1:-}"
      ;;
    --no-cache)
      NO_CACHE=y
      ;;
    --no-latest)
      UPDATE_LATEST=n
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
  shift
done

KAS_VERSION=$(sed -n "s/^__version__ = '\(.*\)'.*/\1/p" "$REPO_ROOT/kas/__version__.py")
if [ -z "$KAS_VERSION" ]; then
  echo "error: could not read kas version from kas/__version__.py" >&2
  exit 1
fi

if [ -z "$FEDORA_VERSION" ]; then
  FEDORA_VERSION=$(sed -n 's/^ARG FEDORA_TAG=\([0-9][0-9]*\).*/\1/p' "$DOCKERFILE" | head -1)
fi
if [ -z "$FEDORA_VERSION" ]; then
  echo "error: could not determine Fedora version (pass -f)" >&2
  exit 1
fi

TAG="$IMAGE:$KAS_VERSION-f$FEDORA_VERSION"
OLD_ID=$(docker images -q "$TAG" 2>/dev/null || true)

BUILD_ARGS=(
  --file "$DOCKERFILE"
  --target kas-fedora
  --build-arg "FEDORA_TAG=$FEDORA_VERSION"
  --tag "$TAG"
)
if [ "$NO_CACHE" = y ]; then
  BUILD_ARGS+=(--no-cache)
fi

echo "Building $TAG (kas $KAS_VERSION, Fedora $FEDORA_VERSION)..."
docker build "${BUILD_ARGS[@]}" "$REPO_ROOT"

NEW_ID=$(docker images -q "$TAG")
if [ -n "$OLD_ID" ] && [ "$OLD_ID" != "$NEW_ID" ]; then
  echo "Replaced image $OLD_ID -> $NEW_ID"
  docker rmi "$OLD_ID" >/dev/null 2>&1 || true
fi

if [ "$UPDATE_LATEST" = y ]; then
  docker tag "$TAG" "$IMAGE:latest"
  echo "Tagged $IMAGE:latest -> $TAG"
fi

echo "Done: $TAG"
