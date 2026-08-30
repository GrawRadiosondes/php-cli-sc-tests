#!/usr/bin/env bash
#
# Assert a freshly built image can actually do the four jobs grawgo asks of it, before it
# reaches the registry. A broken image caught here costs one workflow run; caught in grawgo
# it blocks every branch at once, which is the failure mode this whole repo exists to avoid.
#
# Usage: scripts/smoke-test.sh <image>

set -euo pipefail

IMAGE="${1:-}"

if [ -z "$IMAGE" ]; then
    echo "Usage: $0 <image>" >&2
    exit 1
fi

# Explicitly installed in the Dockerfile.
BUILT_EXTENSIONS=(bcmath gd intl mysqli pcntl pdo_mysql pdo_pgsql pgsql sockets zip)

# Compiled into php:*-cli, so nothing in the Dockerfile installs them — but grawgo's
# composer.lock requires them all the same, directly or through a dependency (ext-sqlite3
# and pdo_sqlite carry the whole sqlite_testing suite). Asserted so a base image that quietly
# stops shipping one fails here instead of in grawgo. This is the same set grawgo's
# `composer check-platform-reqs` step walks, minus the extensions installed above.
BUNDLED_EXTENSIONS=(
    ctype curl date dom fileinfo filter hash iconv json libxml mbstring openssl pcre
    pdo pdo_sqlite phar Reflection session SimpleXML sqlite3 tokenizer xml xmlreader
    xmlwriter zlib
)

failed=0

check() {
    local label="$1"
    shift
    if "$@" > /tmp/smoke-output 2>&1; then
        printf '  ok    %s\n' "$label"
    else
        printf '  FAIL  %s\n' "$label"
        sed 's/^/          /' /tmp/smoke-output
        failed=1
    fi
}

echo "smoke testing ${IMAGE}"

# Reported on every run so a layer creeping back in is visible rather than inferred.
#
# Both figures, because only one of them answers the question anyone actually asks. What a
# registry stores — and what four CI jobs pull per push — is the compressed size, and the
# predecessor php-cli-sc-tests:latest measured 543 MB that way (14 layers, summed from its
# manifest). `docker image inspect` reports the uncompressed size, which is roughly 3x larger
# and comparing the two would flatter this image by a factor of three.
#
# The compressed figure is approximate: docker save tars the layers uncompressed and this
# gzips the whole stream, where a registry gzips each layer separately. Close enough to
# compare against 543 MB and to see which direction a change moved it.
printf 'uncompressed size:          %s MB\n' \
    "$(($(docker image inspect --format '{{.Size}}' "$IMAGE") / 1000 / 1000))"
printf 'compressed size (approx):   %s MB   (predecessor: 543 MB)\n' \
    "$(($(docker save "$IMAGE" | gzip -1 -c | wc -c) / 1000 / 1000))"

echo
echo "tooling"
for tool in "php --version" "composer --version" "bun --version" "node --version" "git --version"; do
    # shellcheck disable=SC2086 # deliberate word splitting: each entry is a command line
    check "$tool" docker run --rm "$IMAGE" $tool
done

echo
echo "php extensions"
modules="$(docker run --rm "$IMAGE" php -m)"

for extension in "${BUILT_EXTENSIONS[@]}" "${BUNDLED_EXTENSIONS[@]}"; do
    if grep -qix "$extension" <<< "$modules"; then
        printf '  ok    %s present\n' "$extension"
    else
        printf '  FAIL  %s missing\n' "$extension"
        failed=1
    fi
done

echo
echo "coverage driver"
if grep -qix pcov <<< "$modules"; then
    printf '  ok    pcov present\n'
else
    printf '  FAIL  pcov missing — pest --coverage cannot run\n'
    failed=1
fi

# Not a style preference: with both loaded, xdebug wins and the coverage run silently gets
# slow again, which is exactly the regression this image just fixed.
if grep -qix xdebug <<< "$modules"; then
    printf '  FAIL  xdebug present — it would take over coverage from pcov\n'
    failed=1
else
    printf '  ok    xdebug absent\n'
fi

echo
echo "php.ini"
check "memory_limit = 1G" docker run --rm "$IMAGE" \
    php -r 'exit(ini_get("memory_limit") === "1G" ? 0 : 1);'
check "pcov.directory = app" docker run --rm "$IMAGE" \
    php -r 'exit(ini_get("pcov.directory") === "app" ? 0 : 1);'

echo
echo "playwright"
# The image bakes install-deps but no browser binaries, so the only way to prove the
# dependency list was sufficient is to install a browser the way grawgo's tests job does
# and launch it. --no-sandbox because CI containers run as root.
check "chromium installs and launches" docker run --rm "$IMAGE" bash -euc "
    cd \"\$(mktemp -d)\"
    bun init -y > /dev/null 2>&1
    bun add playwright${PLAYWRIGHT_VERSION:+@${PLAYWRIGHT_VERSION}}
    bunx playwright install chromium
    cat > launch.js <<'JS'
import { chromium } from 'playwright'

const browser = await chromium.launch({ args: ['--no-sandbox'] })
console.log('chromium', browser.version())
await browser.close()
JS
    bun run launch.js
"

echo
if [ "$failed" -ne 0 ]; then
    echo "smoke test FAILED — not publishing ${IMAGE}"
    exit 1
fi

echo "smoke test passed"
