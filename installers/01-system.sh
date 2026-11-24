#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

packages=(
  ca-certificates
  curl
  file
  git
  gnupg
  jq
  lsb-release
  openssl
  poppler-utils
  python3
  python3-venv
  ripgrep
  sqlite3
  tmux
  tree
  unzip
  zip
)

run_root apt-get update
run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}"

ensure_directory "$WORKSPACE"
ensure_directory "$WORKSPACE/tooling"
ensure_directory "$WORKSPACE/tooling/sources"
ensure_directory "$WORKSPACE/sesi1/targets"
ensure_directory "$WORKSPACE/sesi1/engagements"
ensure_directory "$WORKSPACE/sesi1/evidence"
ensure_directory "$WORKSPACE/sesi1/reports"
ensure_directory "$WORKSPACE/sesi2/procureflow"
ensure_directory "$WORKSPACE/sesi2/evidence"
ensure_directory "$WORKSPACE/sesi2/transcript"
ensure_directory "$WORKSPACE/sesi2/submission"

scope_file="$WORKSPACE/scope.env"
if [[ ! -e "$scope_file" ]]; then
  run install -m 0600 "$PRAKTEK_ROOT/config/scope.env.example" "$scope_file"
else
  log "Mempertahankan scope yang sudah ada: $scope_file"
fi

log "Paket dasar siap. Tidak ada perubahan pada SSH atau firewall."
