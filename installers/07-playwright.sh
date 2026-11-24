#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

runtime_directory="$WORKSPACE/tooling/redteam-agent"
opencode_bin="$HOME/.opencode/bin/opencode"
image_reference="$PLAYWRIGHT_MCP_IMAGE"
allowed_origins="https://$TRAINING_TARGET_HOST;https://$TRAINING_TARGET_HOST:8443;https://$TRAINING_TARGET_HOST:8444;https://$TRAINING_TARGET_HOST:8445;https://$TRAINING_TARGET_HOST:8446;https://$TRAINING_TARGET_HOST:8447;http://127.0.0.1:*;https://127.0.0.1:*;http://localhost:*;https://localhost:*"
opencode_path="$PATH"

if [[ -n "$PLAYWRIGHT_MCP_IMAGE_DIGEST" ]]; then
  image_reference+="@$PLAYWRIGHT_MCP_IMAGE_DIGEST"
else
  warn "Digest image Playwright MCP belum final; tag kandidat $PLAYWRIGHT_MCP_IMAGE akan digunakan."
fi

if [[ "$DRY_RUN" == "1" ]]; then
  print_command docker pull "$image_reference"
  log "Akan menambahkan MCP Playwright pada project RedteamAgent dengan guardrail origin lab."
  print_command "$opencode_bin" mcp add playwright -- docker run -i --rm --init --network host --pull never "$image_reference" --headless --browser chromium --allowed-origins "$allowed_origins"
  exit 0
fi

[[ -x "$opencode_bin" ]] || die "OpenCode tidak ditemukan: $opencode_bin"
[[ -d "$runtime_directory" ]] || die "Runtime RedteamAgent tidak ditemukan: $runtime_directory"
docker_run pull "$image_reference"

if ! docker info >/dev/null 2>&1; then
  opencode_path="$PRAKTEK_ROOT/lib/docker-shim:$PATH"
  run_root docker info >/dev/null
  warn "Playwright MCP memakai shim sudo docker hanya selama verifikasi sesi pertama."
fi

mcp_output="$(cd "$runtime_directory" && PATH="$opencode_path" "$opencode_bin" mcp list 2>&1 || :)"
if grep -qE '(^|[[:space:]])playwright([[:space:]]|$)' <<<"$mcp_output"; then
  log "MCP Playwright sudah terdaftar; konfigurasi dipertahankan."
else
  (
    cd "$runtime_directory"
    PATH="$opencode_path" "$opencode_bin" mcp add playwright -- docker run -i --rm --init --network host --pull never "$image_reference" --headless --browser chromium --allowed-origins "$allowed_origins"
  )
fi
unset mcp_output

log "Playwright MCP terdaftar tanpa membuka target atau menjalankan browser scan."
