#!/usr/bin/env bash
# Fetch the Parquet datasets from the GitHub release into this data/ directory.
# The datasets are release artifacts, not committed in-tree (see .gitignore).
# Re-upload after regenerating: gh release upload datasets-v1 data/*.parquet --clobber --repo "$REPO"
set -euo pipefail
REPO="${REPO:-v-sekai-multiplayer-fabric/swing-twist-kusudama}"
TAG="${TAG:-datasets-v1}"
DIR="$(cd "$(dirname "$0")" && pwd)"
echo "downloading $REPO release $TAG -> $DIR"
gh release download "$TAG" --repo "$REPO" --dir "$DIR" --pattern '*.parquet' --clobber
echo "done:"
ls -1 "$DIR"/*.parquet
