#!/usr/bin/env bash
set -euo pipefail

./fetch-sc.sh

image="docker.io/grawradiosondes/php-cli-sc-tests:latest"
podman build --platform linux/amd64 -t "$image" .
podman push "$image"
