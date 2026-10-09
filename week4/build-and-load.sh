#!/bin/bash

set -euo pipefail

echo ""
echo "======================================"
echo " Cloud Native Notes - Backend Builder"
echo "======================================"
echo ""

# ----------------------------------------
# Ask for image version
# ----------------------------------------

read -rp "Enter backend image version (e.g. 1.0): " VERSION

if [[ -z "$VERSION" ]]; then
    echo "❌ Version cannot be empty."
    exit 1
fi

BACKEND_IMAGE="cloud-native-notes:${VERSION}"

# ----------------------------------------
# Find Kind clusters
# ----------------------------------------

echo ""
echo "🔍 Looking for Kind clusters..."

mapfile -t CLUSTERS < <(kind get clusters 2>/dev/null)

if [[ ${#CLUSTERS[@]} -eq 0 ]]; then
    echo "❌ No Kind clusters found."
    exit 1
fi

echo ""
echo "Available Kind clusters:"
echo ""

for i in "${!CLUSTERS[@]}"; do
    echo "  $((i + 1))) ${CLUSTERS[$i]}"
done

echo ""

read -rp "Select cluster [1-${#CLUSTERS[@]}]: " CLUSTER_NUMBER

if ! [[ "$CLUSTER_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "❌ Invalid selection."
    exit 1
fi

if (( CLUSTER_NUMBER < 1 || CLUSTER_NUMBER > ${#CLUSTERS[@]} )); then
    echo "❌ Invalid cluster selection."
    exit 1
fi

CLUSTER_NAME="${CLUSTERS[$((CLUSTER_NUMBER - 1))]}"

echo ""
echo "✅ Selected Kind cluster: $CLUSTER_NAME"
echo "📦 Backend image: $BACKEND_IMAGE"

# ----------------------------------------
# Build image
# ----------------------------------------

echo ""
echo "🔨 Building backend image..."

docker build \
    -t "$BACKEND_IMAGE" \
    ./backend

# ----------------------------------------
# Load image into Kind
# ----------------------------------------

echo ""
echo "📦 Loading image into Kind cluster: $CLUSTER_NAME"

kind load docker-image \
    "$BACKEND_IMAGE" \
    --name "$CLUSTER_NAME"

# ----------------------------------------
# Done
# ----------------------------------------

echo ""
echo "======================================"
echo "✅ Backend image ready and loaded to cluster!"
echo "======================================"
echo ""
echo "Image:   $BACKEND_IMAGE"
echo "Cluster: $CLUSTER_NAME"
echo ""

