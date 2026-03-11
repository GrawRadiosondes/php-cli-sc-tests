#!/usr/bin/env bash
set -euo pipefail

./fetch-sc.sh

image="docker.io/grawradiosondes/php-cli-sc-tests:latest"
nix-build default.nix
podman load -i result
podman history "$image"
podman push "$image"
