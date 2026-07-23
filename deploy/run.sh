#!/usr/bin/env bash
#
# deploy/run.sh -- entrypoint used by deploy/prologex.service.
#
# Since adr/0027 the app boots by convention (bin/server cds to the
# app root and runs prologex_run/0); this wrapper only exists so the
# systemd unit's path keeps working across restructures.
#
# See adr/0012-deployment-systemd-no-tls.md for the deployment design.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
exec "$SCRIPT_DIR/../bin/server"
