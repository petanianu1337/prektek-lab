#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

validate_profile
validate_workspace

[[ -r /etc/os-release ]] || die "Tidak dapat membaca /etc/os-release."
# shellcheck source=/etc/os-release
source /etc/os-release

case " $SUPPORTED_OS_IDS " in
  *" $ID "*) ;;
  *) die "OS tidak didukung: $ID. OS yang didukung: $SUPPORTED_OS_IDS." ;;
esac

if [[ "$ID" == "ubuntu" && "$VERSION_ID" != "$REFERENCE_UBUNTU_VERSION" ]]; then
  die "Versi Ubuntu tidak didukung: $VERSION_ID. Acuan: $REFERENCE_UBUNTU_VERSION."
fi
if [[ "$ID" == "kali" ]]; then
  warn "Kali Linux adalah rolling release; versi paket host akan diverifikasi terhadap compatibility floor, bukan exact apt pin Ubuntu."
fi

architecture="$(uname -m)"
case " $SUPPORTED_ARCHES " in
  *" $architecture "*) ;;
  *) die "Arsitektur tidak didukung: $architecture" ;;
esac

cpu_cores="$(nproc)"
((cpu_cores >= MIN_CPU_CORES)) || die "CPU ${cpu_cores} core kurang dari minimum ${MIN_CPU_CORES} core."
if ((cpu_cores < RECOMMENDED_CPU_CORES)); then
  warn "CPU ${cpu_cores} core memenuhi minimum, tetapi assessment akan lebih lambat; gunakan concurrency 1."
fi

memory_mb="$(awk '/MemTotal:/ {printf "%d", $2 / 1024}' /proc/meminfo)"
((memory_mb >= MIN_MEMORY_MB)) || die "RAM ${memory_mb} MB kurang dari minimum ${MIN_MEMORY_MB} MB."
if ((memory_mb < RECOMMENDED_MEMORY_MB)); then
  warn "RAM ${memory_mb} MB memenuhi minimum tetapi di bawah rekomendasi ${RECOMMENDED_MEMORY_MB} MB."
fi

disk_mb="$(df -Pm "$HOME" | awk 'NR == 2 {print $4}')"
minimum_disk_gb="$MIN_DISK_GB"
if command -v docker >/dev/null 2>&1 && docker image inspect \
  "$XALGORIX_IMAGE@$XALGORIX_IMAGE_DIGEST" kali-redteam:latest >/dev/null 2>&1; then
  minimum_disk_gb="$MIN_REINSTALL_DISK_GB"
  log "Image besar yang dikunci sudah tersedia; memakai minimum disk rerun ${minimum_disk_gb} GB."
fi
minimum_disk_mb=$((minimum_disk_gb * 1024))
((disk_mb >= minimum_disk_mb)) || die "Disk kosong ${disk_mb} MB kurang dari minimum ${minimum_disk_mb} MB."

require_command bash
require_command apt-get
require_command awk
require_command df
require_command sha256sum

if [[ "$(id -u)" -ne 0 ]]; then
  require_command sudo
  if [[ "$DRY_RUN" != "1" ]]; then
    sudo -v
  fi
fi

log "Preflight lulus: $ID ${VERSION_ID:-rolling}, $architecture, CPU ${cpu_cores} core, RAM ${memory_mb} MB, disk kosong ${disk_mb} MB."
log "Tidak ada koneksi target atau active scan yang dilakukan oleh preflight."
