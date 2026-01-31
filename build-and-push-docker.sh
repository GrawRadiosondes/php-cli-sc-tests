#!/usr/bin/env bash
set -euo pipefail

./fetch-sc.sh

docker buildx build --platform linux/amd64 -t docker.io/grawradiosondes/php-cli-sc-tests:latest --push .
