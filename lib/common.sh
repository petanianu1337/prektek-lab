#!/usr/bin/env bash

if [[ -n "${PRAKTEK_COMMON_LOADED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
PRAKTEK_COMMON_LOADED=1

PRAKTEK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../versions.env
source "$PRAKTEK_ROOT/versions.env"

DRY_RUN="${DRY_RUN:-0}"
PROFILE="${PROFILE:-participant}"
WORKSPACE="${WORKSPACE:-$HOME/training-workspace}"
XALGORIX_DOMAIN="${XALGORIX_DOMAIN:-}"
XALGORIX_PUBLIC_IP="${XALGORIX_PUBLIC_IP:-}"
XALGORIX_PUBLIC_PORT="${XALGORIX_PUBLIC_PORT:-9443}"
ALLOW_CANDIDATE_PINS="${ALLOW_CANDIDATE_PINS:-0}"
XALGORIX_PRIVILEGED="${XALGORIX_PRIVILEGED:-0}"
INSTALL_PLAYWRIGHT="${INSTALL_PLAYWRIGHT:-1}"

log() {
  printf '[praktek-lab] %s\n' "$*"
}

warn() {
  printf '[praktek-lab] PERINGATAN: %s\n' "$*" >&2
}

die() {
  printf '[praktek-lab] ERROR: %s\n' "$*" >&2
  exit 1
}

print_command() {
  local arg
  printf '  +'
  for arg in "$@"; do
    printf ' %q' "$arg"
  done
  printf '\n'
}

run() {
  print_command "$@"
  if [[ "$DRY_RUN" == "1" ]]; then
    return 0
  fi
  "$@"
}

run_quiet() {
  if [[ "$DRY_RUN" == "1" ]]; then
    print_command "$@"
    return 0
  fi
  "$@" >/dev/null
}

run_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    run "$@"
  else
    run sudo "$@"
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Perintah wajib tidak tersedia: $1"
}

validate_profile() {
  case "$PROFILE" in
    instructor | participant) ;;
    *) die "Profil harus 'instructor' atau 'participant'." ;;
  esac
}

validate_workspace() {
  [[ "$WORKSPACE" == /* ]] || die "Workspace harus berupa path absolut."
  case "$WORKSPACE" in
    / | "$HOME" | "$PRAKTEK_ROOT" | "$PRAKTEK_ROOT"/*)
      die "Workspace terlalu luas atau bertabrakan dengan repository installer: $WORKSPACE"
      ;;
  esac
}

ensure_directory() {
  local directory="$1"
  local mode="${2:-0750}"
  if [[ -d "$directory" ]]; then
    return 0
  fi
  run install -d -m "$mode" "$directory"
}

clone_pinned_repository() {
  local repository="$1"
  local ref="$2"
  local commit="$3"
  local destination="$4"
  local current_origin

  if [[ "$DRY_RUN" == "1" ]]; then
    log "Repository $repository akan dikunci ke $ref ($commit) di $destination"
    print_command git clone --filter=blob:none "$repository" "$destination"
    print_command git -C "$destination" fetch --depth 1 origin "$commit"
    print_command git -C "$destination" checkout --detach "$commit"
    return 0
  fi

  if [[ -e "$destination" && ! -d "$destination/.git" ]]; then
    die "Tujuan sudah ada tetapi bukan repository Git: $destination"
  fi

  if [[ ! -d "$destination/.git" ]]; then
    git clone --filter=blob:none "$repository" "$destination"
  fi

  current_origin="$(git -C "$destination" remote get-url origin)"
  [[ "$current_origin" == "$repository" ]] || die "Origin repository tidak sesuai di $destination"

  git -C "$destination" fetch --depth 1 origin "$commit"
  git -C "$destination" checkout --detach "$commit"
  [[ "$(git -C "$destination" rev-parse HEAD)" == "$commit" ]] || die "Commit gagal diverifikasi: $destination"
}

select_docker_prefix() {
  DOCKER_PREFIX=()
  if docker info >/dev/null 2>&1; then
    return 0
  fi
  if command -v sudo >/dev/null 2>&1 && sudo -n docker info >/dev/null 2>&1; then
    DOCKER_PREFIX=(sudo)
    return 0
  fi
  die "Docker daemon tidak dapat diakses oleh user ini maupun sudo non-interaktif."
}

docker_run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    print_command docker "$@"
    return 0
  fi
  select_docker_prefix
  print_command "${DOCKER_PREFIX[@]}" docker "$@"
  "${DOCKER_PREFIX[@]}" docker "$@"
}

docker_read() {
  select_docker_prefix
  "${DOCKER_PREFIX[@]}" docker "$@"
}

write_environment_report() {
  local output="$WORKSPACE/environment.txt"
  if [[ "$DRY_RUN" == "1" ]]; then
    log "Akan menulis metadata tanpa rahasia ke $output"
    return 0
  fi

  umask 077
  {
    printf 'generated_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'profile=%s\n' "$PROFILE"
    printf 'os=%s\n' "$(. /etc/os-release && printf '%s-%s' "$ID" "$VERSION_ID")"
    printf 'architecture=%s\n' "$(uname -m)"
    printf 'opencode=%s\n' "$OPENCODE_VERSION"
    printf 'redteam_agent_commit=%s\n' "$REDTEAM_COMMIT"
    printf 'vulnverify_commit=%s\n' "$VULNVERIFY_COMMIT"
    printf 'trailofbits_skills_commit=%s\n' "$TRAILOFBITS_SKILLS_COMMIT"
    printf 'trailofbits_skills=%s\n' "$TRAILOFBITS_SKILLS_ALLOWLIST"
    printf 'xalgorix_image=%s\n' "$XALGORIX_IMAGE"
    printf 'xalgorix_image_digest=%s\n' "$XALGORIX_IMAGE_DIGEST"
    printf 'redteam_katana_image_digest=%s\n' "$REDTEAM_KATANA_DIGEST_AMD64"
    printf 'redteam_kali_base_image_digest=%s\n' "$REDTEAM_KALI_BASE_DIGEST_AMD64"
    if [[ "$INSTALL_PLAYWRIGHT" == "1" ]]; then
      printf 'playwright_mcp_image=%s\n' "$PLAYWRIGHT_MCP_IMAGE"
      printf 'playwright_mcp_image_digest=%s\n' "$PLAYWRIGHT_MCP_IMAGE_DIGEST"
    else
      printf 'playwright_mcp_image=skipped\n'
      printf 'playwright_mcp_image_digest=skipped\n'
    fi
    printf 'pins_finalized=%s\n' "$PINS_FINALIZED"
  } >"$output"
  chmod 0600 "$output"
}
