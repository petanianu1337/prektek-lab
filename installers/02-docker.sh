#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

source /etc/os-release

docker_spec="$DOCKER_PACKAGE"
compose_package="$DOCKER_COMPOSE_PACKAGE"
compose_spec="$compose_package"

if [[ "$ID" == "ubuntu" ]]; then
  docker_spec+="=$DOCKER_PACKAGE_VERSION"
  compose_spec+="=$DOCKER_COMPOSE_PACKAGE_VERSION"
else
  compose_package=""
  for candidate in docker-compose-v2 docker-compose-plugin docker-compose; do
    if apt-cache show "$candidate" >/dev/null 2>&1; then
      compose_package="$candidate"
      break
    fi
  done
  [[ -n "$compose_package" ]] || die "Paket Docker Compose tidak ditemukan pada repository Kali yang aktif."
  compose_spec="$compose_package"
  warn "Kali rolling: memasang $DOCKER_PACKAGE dan $compose_package dari snapshot repository peserta, lalu memeriksa compatibility floor."
fi

if [[ "$DRY_RUN" != "1" ]]; then
  installed_docker_package="$(dpkg-query -W -f='${Version}' "$DOCKER_PACKAGE" 2>/dev/null || :)"
  installed_compose_package="$(dpkg-query -W -f='${Version}' "$compose_package" 2>/dev/null || :)"

  if command -v docker >/dev/null 2>&1 && [[ -z "$installed_docker_package" ]]; then
    die "Docker yang tidak dikelola paket $DOCKER_PACKAGE terdeteksi; installer tidak akan menimpanya."
  fi
  if [[ "$ID" == "ubuntu" ]]; then
    if [[ -n "$installed_docker_package" && "$installed_docker_package" != "$DOCKER_PACKAGE_VERSION" ]]; then
      die "Versi paket Docker berbeda: $installed_docker_package"
    fi
    if [[ -n "$installed_compose_package" && "$installed_compose_package" != "$DOCKER_COMPOSE_PACKAGE_VERSION" ]]; then
      die "Versi paket Compose berbeda: $installed_compose_package"
    fi
  fi
fi

run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$docker_spec" "$compose_spec"
run_root systemctl enable --now docker

current_user="$(id -un)"
if [[ "$current_user" != "root" ]]; then
  if ! id -nG "$current_user" | tr ' ' '\n' | grep -Fqx docker; then
    run_root usermod -aG docker "$current_user"
    if [[ "$DRY_RUN" == "1" ]]; then
      warn "User $current_user akan ditambahkan ke grup docker yang setara akses root."
    else
      warn "User $current_user ditambahkan ke grup docker. Grup ini setara akses root; gunakan hanya pada perangkat latihan khusus."
      warn "Membership aktif penuh setelah logout/login kembali. Installer memakai shim sudo terbatas selama sesi pertama."
    fi
  fi
fi

if [[ "$DRY_RUN" != "1" ]]; then
  docker_run version >/dev/null
  docker_run compose version >/dev/null
  if [[ "$ID" == "kali" ]]; then
    docker_runtime_version="$(docker_read version --format '{{.Server.Version}}')"
    compose_runtime_version="$(docker_read compose version --short)"
    compose_runtime_version="${compose_runtime_version#v}"
    dpkg --compare-versions "$docker_runtime_version" ge "$KALI_DOCKER_MIN_VERSION" || die "Docker $docker_runtime_version di bawah minimum Kali $KALI_DOCKER_MIN_VERSION."
    dpkg --compare-versions "$compose_runtime_version" ge "$KALI_COMPOSE_MIN_VERSION" || die "Compose $compose_runtime_version di bawah minimum Kali $KALI_COMPOSE_MIN_VERSION."
  fi
fi

log "Docker siap. SSH dan firewall tidak diubah."
