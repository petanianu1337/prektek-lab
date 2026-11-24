#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

source_directory="$WORKSPACE/tooling/sources/redteam-agent"
runtime_directory="$WORKSPACE/tooling/redteam-agent"
staging_directory="$WORKSPACE/tooling/.redteam-agent.installing"
marker="$runtime_directory/.praktek-lab-redteam-commit"
installer_path="$PATH"
build_directory="$WORKSPACE/tooling/build"
pinned_kali_dockerfile="$build_directory/redteam-kali.Dockerfile"
katana_reference="$REDTEAM_KATANA_IMAGE@$REDTEAM_KATANA_DIGEST_AMD64"
kali_base_reference="$REDTEAM_KALI_BASE_IMAGE@$REDTEAM_KALI_BASE_DIGEST_AMD64"

apply_metasploit_policy() {
  local target_directory="$1"
  local config_file="$target_directory/.opencode/opencode.json"
  local policy_marker="$target_directory/.praktek-lab-metasploit-disabled"
  local metasploit_filter temporary_config

  [[ -f "$config_file" ]] || die "Konfigurasi OpenCode RedteamAgent tidak ditemukan: $config_file"
  [[ -f "$policy_marker" ]] && return 0
  if jq -e '.mcp.metasploit' "$config_file" >/dev/null; then
    metasploit_filter='.mcp.metasploit.enabled = false'
  elif jq -e '.mcp.servers.metasploit' "$config_file" >/dev/null; then
    metasploit_filter='.mcp.servers.metasploit.enabled = false'
  else
    die "Entry MCP Metasploit upstream berubah; kebijakan harus direview."
  fi
  temporary_config="$(mktemp)"
  if ! jq "$metasploit_filter" "$config_file" >"$temporary_config"; then
    rm -f -- "$temporary_config"
    die "Gagal menonaktifkan MCP Metasploit opsional."
  fi
  install -m 0640 "$temporary_config" "$config_file"
  rm -f -- "$temporary_config"
  printf '%s\n' "disabled-by-default: not-used-in-training" >"$policy_marker"
  chmod 0600 "$policy_marker"
  log "MCP Metasploit opsional dinonaktifkan; materi menggunakan source/web analysis tanpa msfrpcd."
}

if [[ "$DRY_RUN" != "1" ]] && ! docker info >/dev/null 2>&1; then
  installer_path="$PRAKTEK_ROOT/lib/docker-shim:$PATH"
  run_root docker info >/dev/null
  warn "RedteamAgent memakai shim sudo docker hanya selama sesi instalasi pertama."
fi

clone_pinned_repository "$REDTEAM_REPOSITORY" "$REDTEAM_REF" "$REDTEAM_COMMIT" "$source_directory"

prepare_redteam_images() {
  local upstream_dockerfile="$source_directory/agent/docker/kali-redteam/Dockerfile"
  local expected_from='FROM kalilinux/kali-rolling:latest'
  local existing_base_label existing_commit_label

  if [[ "$DRY_RUN" == "1" ]]; then
    log "Akan menarik Katana dengan digest tetap dan membangun kali-redteam dari base image digest tetap."
    print_command docker pull "$katana_reference"
    print_command docker tag "$katana_reference" projectdiscovery/katana:latest
    print_command docker build --label "io.praktek-lab.base-image=$kali_base_reference" --label "io.praktek-lab.redteam-commit=$REDTEAM_COMMIT" -t kali-redteam:latest -f "$pinned_kali_dockerfile" "$source_directory/agent/docker/kali-redteam"
    return 0
  fi

  [[ "$(uname -m)" == "x86_64" ]] || die "Digest image RedteamAgent saat ini hanya dikalibrasi untuk x86_64."
  [[ -f "$upstream_dockerfile" ]] || die "Dockerfile Kali RedteamAgent tidak ditemukan."
  [[ "$(head -n 1 "$upstream_dockerfile")" == "$expected_from" ]] || die "Base image upstream RedteamAgent berubah; pin harus direview ulang."

  docker_run pull "$katana_reference"
  docker_run tag "$katana_reference" projectdiscovery/katana:latest

  existing_base_label="$(docker_read image inspect --format '{{index .Config.Labels "io.praktek-lab.base-image"}}' kali-redteam:latest 2>/dev/null || :)"
  existing_commit_label="$(docker_read image inspect --format '{{index .Config.Labels "io.praktek-lab.redteam-commit"}}' kali-redteam:latest 2>/dev/null || :)"
  if [[ "$existing_base_label" == "$kali_base_reference" && "$existing_commit_label" == "$REDTEAM_COMMIT" ]]; then
    log "Image kali-redteam dengan provenance yang sesuai sudah tersedia."
    return 0
  fi

  install -d -m 0750 "$build_directory"
  {
    printf 'FROM %s\n' "$kali_base_reference"
    tail -n +2 "$upstream_dockerfile"
  } >"$pinned_kali_dockerfile"
  chmod 0640 "$pinned_kali_dockerfile"
  docker_run build \
    --label "io.praktek-lab.base-image=$kali_base_reference" \
    --label "io.praktek-lab.redteam-commit=$REDTEAM_COMMIT" \
    -t kali-redteam:latest \
    -f "$pinned_kali_dockerfile" \
    "$source_directory/agent/docker/kali-redteam"
}

prepare_redteam_images

if [[ "$DRY_RUN" == "1" ]]; then
  log "Akan memvalidasi installer RedteamAgent, memasang ke staging, lalu memindahkan hasil sukses ke $runtime_directory"
  print_command env REDTEAM_SKIP_DOCKER_IMAGE_CHECKS=1 bash "$source_directory/install.sh" --dry-run opencode "$staging_directory"
  print_command env REDTEAM_SKIP_DOCKER_IMAGE_CHECKS=1 bash "$source_directory/install.sh" opencode "$staging_directory"
  exit 0
fi

if [[ -f "$marker" ]]; then
  [[ "$(<"$marker")" == "$REDTEAM_COMMIT" ]] || die "Runtime RedteamAgent berasal dari commit lain: $runtime_directory"
  apply_metasploit_policy "$runtime_directory"
  log "RedteamAgent commit $REDTEAM_COMMIT sudah terpasang."
  exit 0
fi

if [[ -d "$runtime_directory" ]]; then
  existing_entry="$(find "$runtime_directory" -mindepth 1 -print -quit)"
  if [[ -n "$existing_entry" ]]; then
    partial_runtime="${runtime_directory}.partial-$(date -u +%Y%m%dT%H%M%SZ)-$$"
    mv -- "$runtime_directory" "$partial_runtime"
    warn "Runtime RedteamAgent tanpa marker dipindahkan ke backup: $partial_runtime"
  fi
fi

if [[ -d "$staging_directory" ]]; then
  abandoned_staging="${staging_directory}.failed-$(date -u +%Y%m%dT%H%M%SZ)-$$"
  mv -- "$staging_directory" "$abandoned_staging"
  warn "Staging RedteamAgent lama dipindahkan ke $abandoned_staging"
fi

install -d -m 0750 "$staging_directory"
install_complete=0
preserve_failed_staging() {
  if [[ "$install_complete" != "1" && -d "$staging_directory" ]]; then
    failed_staging="${staging_directory}.failed-$(date -u +%Y%m%dT%H%M%SZ)-$$"
    if mv -- "$staging_directory" "$failed_staging"; then
      warn "Instalasi gagal; staging dipertahankan di $failed_staging"
    fi
  fi
}
trap preserve_failed_staging EXIT

(
  cd "$source_directory"
  PATH="$installer_path" REDTEAM_SKIP_DOCKER_IMAGE_CHECKS=1 bash ./install.sh --dry-run opencode "$staging_directory"
  PATH="$installer_path" REDTEAM_SKIP_DOCKER_IMAGE_CHECKS=1 bash ./install.sh opencode "$staging_directory"
)
apply_metasploit_policy "$staging_directory"
printf '%s\n' "$REDTEAM_COMMIT" >"$staging_directory/.praktek-lab-redteam-commit"
chmod 0600 "$staging_directory/.praktek-lab-redteam-commit"
if [[ -d "$runtime_directory" ]]; then
  rmdir -- "$runtime_directory"
fi
mv -- "$staging_directory" "$runtime_directory"
install_complete=1
trap - EXIT
log "RedteamAgent dipasang ke $runtime_directory."
