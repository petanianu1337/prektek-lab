#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<'EOF'
Penggunaan:
  ./install.sh [opsi]

Opsi:
  --profile participant|instructor  Profil instalasi (default: participant)
  --workspace PATH                  Workspace absolut (default: ~/training-workspace)
  --dry-run                         Tampilkan rencana tanpa perubahan atau unduhan
  --allow-candidate-pins            Izinkan instalasi sebelum pin dinyatakan final
  --xalgorix-domain DOMAIN          HTTPS publik; hanya profil instructor
  --xalgorix-public-ip IP           HTTPS publik via IP; hanya profil instructor
  --xalgorix-public-port PORT       Port gateway IP (default: 9443)
  --xalgorix-privileged             Aktifkan privileged untuk container Xalgorix
  --skip-playwright                 Jangan pasang image/MCP Playwright
  -h, --help                        Tampilkan bantuan

Installer tidak mengatur provider AI, API key, SSH, atau firewall.
EOF
}

while (($# > 0)); do
  case "$1" in
    --profile)
      (($# >= 2)) || die "--profile memerlukan nilai."
      PROFILE="$2"
      shift 2
      ;;
    --workspace)
      (($# >= 2)) || die "--workspace memerlukan path."
      WORKSPACE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --allow-candidate-pins)
      ALLOW_CANDIDATE_PINS=1
      shift
      ;;
    --xalgorix-domain)
      (($# >= 2)) || die "--xalgorix-domain memerlukan domain."
      XALGORIX_DOMAIN="$2"
      shift 2
      ;;
    --xalgorix-public-ip)
      (($# >= 2)) || die "--xalgorix-public-ip memerlukan alamat IPv4."
      XALGORIX_PUBLIC_IP="$2"
      shift 2
      ;;
    --xalgorix-public-port)
      (($# >= 2)) || die "--xalgorix-public-port memerlukan port."
      XALGORIX_PUBLIC_PORT="$2"
      shift 2
      ;;
    --xalgorix-privileged)
      XALGORIX_PRIVILEGED=1
      shift
      ;;
    --skip-playwright)
      INSTALL_PLAYWRIGHT=0
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die "Opsi tidak dikenal: $1"
      ;;
  esac
done

validate_profile
validate_workspace

if [[ -n "$XALGORIX_DOMAIN" && "$PROFILE" != "instructor" ]]; then
  die "HTTPS publik Xalgorix hanya tersedia pada profil instructor."
fi
if [[ -n "$XALGORIX_PUBLIC_IP" && "$PROFILE" != "instructor" ]]; then
  die "HTTPS publik Xalgorix via IP hanya tersedia pada profil instructor."
fi
if [[ -n "$XALGORIX_DOMAIN" && -n "$XALGORIX_PUBLIC_IP" ]]; then
  die "Pilih salah satu: domain atau IP publik Xalgorix."
fi
[[ "$XALGORIX_PUBLIC_PORT" =~ ^[0-9]+$ ]] || die "Port publik Xalgorix harus numerik."
((XALGORIX_PUBLIC_PORT >= 1024 && XALGORIX_PUBLIC_PORT <= 65535)) || die "Port publik Xalgorix harus 1024-65535."

if [[ "$DRY_RUN" != "1" && "$PINS_FINALIZED" != "1" && "$ALLOW_CANDIDATE_PINS" != "1" ]]; then
  die "Pin masih kandidat. Uji dry-run dahulu atau gunakan --allow-candidate-pins secara eksplisit."
fi

export PRAKTEK_ROOT DRY_RUN PROFILE WORKSPACE XALGORIX_DOMAIN
export XALGORIX_PUBLIC_IP XALGORIX_PUBLIC_PORT
export ALLOW_CANDIDATE_PINS XALGORIX_PRIVILEGED INSTALL_PLAYWRIGHT
export PATH="$HOME/.opencode/bin:$PATH"

log "Profil: $PROFILE"
log "Workspace: $WORKSPACE"
[[ "$DRY_RUN" == "1" ]] && log "Mode dry-run aktif: tidak ada perubahan sistem."
[[ "$PINS_FINALIZED" != "1" ]] && warn "Pin versi masih berstatus kandidat dan belum dikalibrasi pada VPS-Attacker."

"$SCRIPT_DIR/checks/preflight.sh"

for module in "$SCRIPT_DIR"/installers/[0-9][0-9]-*.sh; do
  if [[ "$(basename "$module")" == "07-playwright.sh" && "$INSTALL_PLAYWRIGHT" != "1" ]]; then
    log "Melewati $(basename "$module") sesuai opsi."
    continue
  fi
  log "Menjalankan $(basename "$module")"
  "$module"
done

"$SCRIPT_DIR/checks/verify.sh"
log "Persiapan selesai. Isi dan setujui $WORKSPACE/scope.env sebelum memasukkan target ke agent atau scanner."
