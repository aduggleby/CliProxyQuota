#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -d "build/CliProxy Quota.app" ]]; then ./scripts/build-app.sh; fi
DESTINATION="${1:-$HOME/Applications}"
mkdir -p "$DESTINATION"
if pgrep -x CliProxyQuota >/dev/null; then
    echo 'Quit CliProxy Quota from its menu bar menu before updating.' >&2
    exit 1
fi
ditto "build/CliProxy Quota.app" "$DESTINATION/CliProxy Quota.app"
open "$DESTINATION/CliProxy Quota.app"
echo "Installed: $DESTINATION/CliProxy Quota.app"
