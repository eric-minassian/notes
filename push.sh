#!/usr/bin/env bash
set -euo pipefail

msg="${1:-update notes}"

git add -A
git commit -m "$msg"
git push
