#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

opencode_bin="$HOME/.opencode/bin/opencode"
launcher_source="$PRAKTEK_ROOT/lib/opencode-launcher"
launcher_target=/usr/local/bin/opencode

install_launcher() {
  [[ -f "$launcher_source" ]] || die "Launcher OpenCode tidak ditemukan: $launcher_source"

  if [[ -L "$launcher_target" ]]; then
    die "Symlink yang tidak dikelola installer sudah memakai $launcher_target; tinjau sebelum melanjutkan."
  fi
  if [[ -e "$launcher_target" ]] && ! cmp --silent "$launcher_source" "$launcher_target"; then
    die "File yang tidak dikelola installer sudah memakai $launcher_target; tinjau sebelum melanjutkan."
  fi

  run_root install -o root -g root -m 0755 "$launcher_source" "$launcher_target"
  if [[ "$DRY_RUN" != "1" ]]; then
    [[ -x "$launcher_target" ]] || die "Launcher OpenCode tidak dapat dijalankan: $launcher_target"
  fi
}

if [[ -x "$opencode_bin" && "$DRY_RUN" != "1" ]]; then
  installed_version="$($opencode_bin --version | awk 'NF {print $NF; exit}')"
  installed_version="${installed_version#v}"
  if [[ "$installed_version" == "$OPENCODE_VERSION" ]]; then
    install_launcher
    log "OpenCode $OPENCODE_VERSION sudah terpasang dan tersedia sebagai perintah opencode."
    exit 0
  fi
  die "OpenCode versi lain terdeteksi ($installed_version); tidak menimpa otomatis."
fi

if [[ "$DRY_RUN" == "1" ]]; then
  log "Akan mengunduh installer OpenCode $OPENCODE_VERSION, memverifikasi SHA-256, dan memasang launcher /usr/local/bin/opencode tanpa mengubah shell profile."
  print_command curl --fail --silent --show-error --location "$OPENCODE_INSTALLER_URL" --output '<temporary-file>'
  print_command bash '<verified-installer>' --version "$OPENCODE_VERSION" --no-modify-path
  install_launcher
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
install_launcher
launcher_version="$($launcher_target --version | awk 'NF {print $NF; exit}')"
launcher_version="${launcher_version#v}"
[[ "$launcher_version" == "$OPENCODE_VERSION" ]] || die "Launcher OpenCode menjalankan versi yang tidak sesuai: $launcher_version"
log "OpenCode $OPENCODE_VERSION terpasang dan tersedia sebagai perintah opencode."
