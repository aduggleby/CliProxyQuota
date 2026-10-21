#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -d "build/CliProxy Quota.app" ]]; then ./scripts/build-app.sh; fi
"build/CliProxy Quota.app/Contents/MacOS/CliProxyQuota" --screenshots "$PWD/docs/screenshots"
