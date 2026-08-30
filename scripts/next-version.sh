#!/usr/bin/env bash
#
# Print the next image version. Tags are bare SemVer (1.4.0) — no "v" prefix.
#
# A trimmed-down sibling of grawgo's scripts/ci/next-version.sh. This image has no
# pull-request-title release lever: every publish is a patch bump, because every publish
# is the same image rebuilt against newer upstream bits. Consumers move between versions
# through a Renovate pull request that has to go green first, so the number only needs to
# be monotonic and immutable, not semantically loaded.
#
# The current version is the highest tag in the repository rather than `git describe`:
# a tag whose commit was rebased away is no longer an ancestor of HEAD, and describe
# would hand out a number that is already taken. `--sort=-v:refname` sorts numerically,
# so 1.10.0 correctly outranks 1.9.0.
#
# Usage: scripts/next-version.sh [current-version]

set -euo pipefail

CURRENT="${1:-}"

if [ -z "$CURRENT" ]; then
    CURRENT="$(git tag --list '[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname | head -n 1)"
fi

# First publish. Starts at 1.0.0 rather than 0.0.1 — the image is not a preview, it is
# already what every grawgo check runs inside.
if [ -z "$CURRENT" ]; then
    echo '1.0.0'
    exit 0
fi

if [[ ! "$CURRENT" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "Error: cannot parse current version '${CURRENT}' as bare SemVer" >&2
    exit 1
fi

printf '%s.%s.%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "$((BASH_REMATCH[3] + 1))"
