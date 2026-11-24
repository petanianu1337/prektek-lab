#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

CONFIRM=0
PURGE_DATA=0

usage() {
  cat <<'EOF'
Penggunaan: ./uninstall.sh [opsi]

Opsi:
  --profile participant|instructor  Profil instalasi
  --workspace PATH                  Workspace absolut
  --xalgorix-domain DOMAIN          Domain proxy instructor yang akan dilepas
  --xalgorix-public-ip IP           IP gateway instructor yang akan dilepas
  --xalgorix-public-port PORT       Port gateway IP (default: 9443)
  --purge-data                      Hapus volume dan credential Xalgorix
  --dry-run                         Tampilkan rencana tanpa perubahan
  --yes                             Wajib untuk eksekusi nyata
  -h, --help                        Tampilkan bantuan

Uninstaller hanya menghentikan Xalgorix dan melepas proxy yang dibuat installer.
Docker, paket sistem, OpenCode, source, evidence, dan laporan tidak dihapus.
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
    --purge-data)
      PURGE_DATA=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --yes)
      CONFIRM=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "Opsi tidak dikenal: $1" ;;
  esac
done

validate_profile
validate_workspace
if [[ "$DRY_RUN" != "1" && "$CONFIRM" != "1" ]]; then
  die "Eksekusi nyata memerlukan --yes. Jalankan --dry-run terlebih dahulu."
fi

compose_file="$WORKSPACE/tooling/xalgorix/compose.yml"
secret_directory="$HOME/.config/praktek-lab"
secret_file="$secret_directory/xalgorix.env"
gateway_file="$secret_directory/xalgorix-gateway.env"

if [[ -f "$compose_file" && -f "$secret_file" ]]; then
  if [[ "$PURGE_DATA" == "1" ]]; then
    docker_run compose --env-file "$secret_file" -f "$compose_file" down --volumes
  else
    docker_run compose --env-file "$secret_file" -f "$compose_file" down
  fi
else
  log "Compose atau credential Xalgorix tidak ditemukan; tidak ada container yang dilepas."
fi

if [[ "$PROFILE" == "instructor" ]]; then
  caddy_snippet=/etc/caddy/conf.d/praktek-lab-xalgorix.caddy
  if [[ -e "$caddy_snippet" || "$DRY_RUN" == "1" ]]; then
    run_root rm -f -- "$caddy_snippet"
    if [[ "$DRY_RUN" == "1" || -f /etc/caddy/Caddyfile ]]; then
      run_root caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
      run_root systemctl reload caddy
    fi
  fi
fi

if [[ "$PURGE_DATA" == "1" ]]; then
  run rm -f -- "$secret_file" "$gateway_file"
  log "Volume dan credential Xalgorix dihapus. Data tersebut tidak dapat dipulihkan oleh installer."
fi

log "Uninstall terbatas selesai. Workspace, evidence, source, OpenCode, Docker, SSH, dan firewall dipertahankan."
