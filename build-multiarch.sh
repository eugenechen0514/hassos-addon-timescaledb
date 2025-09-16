#!/bin/bash

# Multi-architecture build script for TimescaleDB addon
# Usage: ./build-multiarch.sh [tag] [arch1] [arch2] ...
# Example: ./build-multiarch.sh latest aarch64 amd64
# Example: ./build-multiarch.sh v1.0.0 amd64

set -e

# Configuration
REGISTRY="docker.io/eugenechen0514"
IMAGE_NAME="timescaledb"
TAG=${1:-"latest"}
ADDON_PATH="./timescaledb"

# Get architectures from command line or default to aarch64 and amd64
if [ $# -gt 1 ]; then
    ARCHITECTURES=("${@:2}")
else
    ARCHITECTURES=("aarch64" "amd64")
fi

# All supported architectures from config.yaml
ALL_ARCHITECTURES=("armhf" "aarch64" "amd64" "armv7" "i386")

# Validate architectures
for ARCH in "${ARCHITECTURES[@]}"; do
    if [[ ! " ${ALL_ARCHITECTURES[*]} " =~ " ${ARCH} " ]]; then
        echo "❌ Error: Unsupported architecture: $ARCH"
        echo "Supported architectures: ${ALL_ARCHITECTURES[*]}"
        exit 1
    fi
done

echo "Building multi-architecture images for TimescaleDB addon"
echo "Registry: $REGISTRY"
echo "Tag: $TAG"
echo "Architectures: ${ARCHITECTURES[*]}"

# Create buildx builder if not exists
if ! docker buildx ls | grep -q multiarch-builder; then
    echo "Creating buildx builder..."
    docker buildx create --name multiarch-builder --use
    docker buildx inspect --bootstrap
else
    echo "Using existing buildx builder..."
    docker buildx use multiarch-builder
fi

# Build and push each architecture
for ARCH in "${ARCHITECTURES[@]}"; do
    echo "Building for architecture: $ARCH"

    # Map Home Assistant architectures to Docker platforms
    case $ARCH in
        "aarch64") PLATFORM="linux/arm64" ;;
        "amd64") PLATFORM="linux/amd64" ;;
        "armhf") PLATFORM="linux/arm/v6" ;;
        "armv7") PLATFORM="linux/arm/v7" ;;
        "i386") PLATFORM="linux/386" ;;
        *) echo "Unknown architecture: $ARCH"; exit 1 ;;
    esac

    # Get base image from build.yaml
    BASE_IMAGE=$(grep -A 10 "build_from:" $ADDON_PATH/build.yaml | grep "  $ARCH:" | cut -d':' -f2- | xargs)

    echo "  Platform: $PLATFORM"
    echo "  Base image: $BASE_IMAGE"

    # Build and push single architecture image
    docker buildx build \
        --platform $PLATFORM \
        --build-arg BUILD_FROM=$BASE_IMAGE \
        --build-arg BUILD_ARCH=$ARCH \
        --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
        --build-arg BUILD_REF="$(git rev-parse --short HEAD)" \
        --build-arg BUILD_VERSION="$TAG" \
        --build-arg BUILD_REPOSITORY="$(git config --get remote.origin.url)" \
        --build-arg CACHE_BUST="$(date +%s)" \
        -t $REGISTRY/$IMAGE_NAME-$ARCH:$TAG \
        -f $ADDON_PATH/Dockerfile \
        --push \
        $ADDON_PATH

    echo "✅ Built and pushed: $REGISTRY/$IMAGE_NAME-$ARCH:$TAG"
done

echo "🎉 All architectures built and pushed successfully!"
echo "Images:"
for ARCH in "${ARCHITECTURES[@]}"; do
    echo "  - $REGISTRY/$IMAGE_NAME-$ARCH:$TAG"
done