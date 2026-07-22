#!/usr/bin/env bash
#
# deploy/run.sh -- entrypoint used by deploy/prologex.service.
#
# Resolves the repo root relative to this script's own location (not the
# caller's cwd), cds there so the app's relative paths (adr/, apps/static/)
# resolve correctly, and execs swipl so systemd tracks the real swipl
# process rather than this wrapper shell.
#
# See adr/0012-deployment-systemd-no-tls.md for the deployment design.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR/.."

# Port/workers/database come from config/app.pl (adr/0022) -- no argv.
exec swipl apps/adr_site.pl
