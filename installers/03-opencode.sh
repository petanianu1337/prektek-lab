#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

opencode_bin="$HOME/.opencode/bin/opencode"

if [[ -x "$opencode_bin" && "$DRY_RUN" != "1" ]]; then
  installed_version="$($opencode_bin --version | awk 'NF {print $NF; exit}')"
  installed_version="${installed_version#v}"
  if [[ "$installed_version" == "$OPENCODE_VERSION" ]]; then
    log "OpenCode $OPENCODE_VERSION sudah terpasang."
    exit 0
  fi
  die "OpenCode versi lain terdeteksi ($installed_version); tidak menimpa otomatis."
fi

if [[ "$DRY_RUN" == "1" ]]; then
  log "Akan mengunduh installer OpenCode $OPENCODE_VERSION, memverifikasi SHA-256, lalu memasang tanpa mengubah shell profile."
  print_command curl --fail --silent --show-error --location "$OPENCODE_INSTALLER_URL" --output '<temporary-file>'
  print_command bash '<verified-installer>' --version "$OPENCODE_VERSION" --no-modify-path
  exit 0
fi

installer="$(mktemp)"
cleanup() {
  rm -f -- "$installer"
}
trap cleanup EXIT

curl --fail --silent --show-error --location "$OPENCODE_INSTALLER_URL" --output "$installer"
printf '%s  %s\n' "$OPENCODE_INSTALLER_SHA256" "$installer" | sha256sum --check --status || die "Checksum installer OpenCode tidak cocok."
bash "$installer" --version "$OPENCODE_VERSION" --no-modify-path

[[ -x "$opencode_bin" ]] || die "Binary OpenCode tidak ditemukan setelah instalasi."
installed_version="$($opencode_bin --version | awk 'NF {print $NF; exit}')"
installed_version="${installed_version#v}"
[[ "$installed_version" == "$OPENCODE_VERSION" ]] || die "Versi OpenCode hasil instalasi tidak sesuai: $installed_version"
log "OpenCode $OPENCODE_VERSION terpasang di $opencode_bin."
