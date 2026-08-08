#!/usr/bin/env bash
set -euo pipefail

# clone or pull the latest version
readonly repo="grawgo"
if cd $repo; then
  git reset --hard HEAD
  git pull
  cd ..
else
  git clone "git@github.com:GrawRadiosondes/$repo.git"
fi
