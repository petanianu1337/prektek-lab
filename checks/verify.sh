#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

usage() {
  cat <<'EOF'
Penggunaan: ./checks/verify.sh [--profile participant|instructor] [--workspace PATH]
                              [--xalgorix-domain DOMAIN]
                              [--xalgorix-public-ip IP] [--xalgorix-public-port PORT]
                              [--skip-playwright]

Verifikasi ini tidak membuka target lab dan tidak menjalankan active scan.
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
    --skip-playwright)
      INSTALL_PLAYWRIGHT=0
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

if [[ "$DRY_RUN" == "1" ]]; then
  log "Dry-run: setelah instalasi nyata, verify akan memeriksa versi, commit, Docker, binding loopback, autentikasi dashboard, MCP, scope, dan environment.txt."
  log "Dry-run tidak membuka target, memulai browser, atau menjalankan active scan."
  exit 0
fi

[[ -d "$WORKSPACE" ]] || die "Workspace belum tersedia: $WORKSPACE"

opencode_bin="$HOME/.opencode/bin/opencode"
[[ -x "$opencode_bin" ]] || die "OpenCode tidak ditemukan."
installed_opencode="$($opencode_bin --version | awk 'NF {print $NF; exit}')"
installed_opencode="${installed_opencode#v}"
[[ "$installed_opencode" == "$OPENCODE_VERSION" ]] || die "Versi OpenCode tidak sesuai: $installed_opencode"

opencode_launcher=/usr/local/bin/opencode
[[ -x "$opencode_launcher" ]] || die "Launcher perintah opencode tidak ditemukan: $opencode_launcher"
cmp --silent "$PRAKTEK_ROOT/lib/opencode-launcher" "$opencode_launcher" || die "Launcher perintah opencode tidak sesuai dengan installer."
launcher_opencode="$($opencode_launcher --version | awk 'NF {print $NF; exit}')"
launcher_opencode="${launcher_opencode#v}"
[[ "$launcher_opencode" == "$OPENCODE_VERSION" ]] || die "Perintah opencode menjalankan versi yang tidak sesuai: $launcher_opencode"

require_command git
require_command curl
require_command jq
require_command rg
require_command sqlite3
require_command docker

source /etc/os-release
installed_docker_package="$(dpkg-query -W -f='${Version}' "$DOCKER_PACKAGE")"
if [[ "$ID" == "ubuntu" ]]; then
  installed_compose_package="$(dpkg-query -W -f='${Version}' "$DOCKER_COMPOSE_PACKAGE")"
  [[ "$installed_docker_package" == "$DOCKER_PACKAGE_VERSION" ]] || die "Versi paket Docker tidak sesuai: $installed_docker_package"
  [[ "$installed_compose_package" == "$DOCKER_COMPOSE_PACKAGE_VERSION" ]] || die "Versi paket Compose tidak sesuai: $installed_compose_package"
else
  docker_runtime_version="$(docker_read version --format '{{.Server.Version}}')"
  compose_runtime_version="$(docker_read compose version --short)"
  compose_runtime_version="${compose_runtime_version#v}"
  dpkg --compare-versions "$docker_runtime_version" ge "$KALI_DOCKER_MIN_VERSION" || die "Docker $docker_runtime_version di bawah minimum Kali $KALI_DOCKER_MIN_VERSION."
  dpkg --compare-versions "$compose_runtime_version" ge "$KALI_COMPOSE_MIN_VERSION" || die "Compose $compose_runtime_version di bawah minimum Kali $KALI_COMPOSE_MIN_VERSION."
fi

source_redteam="$WORKSPACE/tooling/sources/redteam-agent"
source_vulnverify="$WORKSPACE/tooling/vulnverify-skills"
source_trailofbits="$WORKSPACE/tooling/trailofbits-skills"
redteam_runtime="$WORKSPACE/tooling/redteam-agent"
[[ "$(git -C "$source_redteam" rev-parse HEAD)" == "$REDTEAM_COMMIT" ]] || die "Commit RedteamAgent tidak sesuai."
[[ "$(git -C "$source_vulnverify" rev-parse HEAD)" == "$VULNVERIFY_COMMIT" ]] || die "Commit VulnVerify tidak sesuai."
[[ "$(git -C "$source_trailofbits" rev-parse HEAD)" == "$TRAILOFBITS_SKILLS_COMMIT" ]] || die "Commit Trail of Bits Skills tidak sesuai."
[[ -f "$redteam_runtime/.praktek-lab-redteam-commit" ]] || die "Marker runtime RedteamAgent tidak ditemukan."
[[ -f "$redteam_runtime/.praktek-lab-vulnverify-commit" ]] || die "Marker VulnVerify tidak ditemukan."
[[ -f "$redteam_runtime/.praktek-lab-trailofbits-skills-commit" ]] || die "Marker Trail of Bits Skills tidak ditemukan."
[[ -f "$redteam_runtime/.praktek-lab-metasploit-disabled" ]] || die "Marker kebijakan MCP Metasploit tidak ditemukan."
jq -e '(.mcp.metasploit.enabled == false) or (.mcp.servers.metasploit.enabled == false)' "$redteam_runtime/.opencode/opencode.json" >/dev/null || die "MCP Metasploit opsional harus nonaktif secara default."
[[ -f "$redteam_runtime/.opencode/skills/sharp-edges/SKILL.md" ]] || die "Skill sharp-edges tidak ditemukan."
[[ -f "$redteam_runtime/.opencode/skills/cvss-scoring/SKILL.md" ]] || die "Skill cvss-scoring tidak ditemukan."
[[ ! -e "$redteam_runtime/.opencode/skills/cvss-scoring/.calcifier" ]] || die "Folder .calcifier Trail of Bits tidak boleh aktif."
sh "$source_vulnverify/scripts/install.sh" check --project "$redteam_runtime" --client opencode

docker_read version >/dev/null
docker_read compose version >/dev/null
katana_reference="$REDTEAM_KATANA_IMAGE@$REDTEAM_KATANA_DIGEST_AMD64"
katana_pinned_id="$(docker_read image inspect --format '{{.Id}}' "$katana_reference")"
katana_alias_id="$(docker_read image inspect --format '{{.Id}}' projectdiscovery/katana:latest)"
[[ "$katana_pinned_id" == "$katana_alias_id" ]] || die "Alias Katana latest tidak menunjuk digest yang dikunci."
kali_base_label="$(docker_read image inspect --format '{{index .Config.Labels "io.praktek-lab.base-image"}}' kali-redteam:latest)"
kali_commit_label="$(docker_read image inspect --format '{{index .Config.Labels "io.praktek-lab.redteam-commit"}}' kali-redteam:latest)"
[[ "$kali_base_label" == "$REDTEAM_KALI_BASE_IMAGE@$REDTEAM_KALI_BASE_DIGEST_AMD64" ]] || die "Base image kali-redteam tidak sesuai pin."
[[ "$kali_commit_label" == "$REDTEAM_COMMIT" ]] || die "Commit provenance kali-redteam tidak sesuai."
docker_read inspect training-xalgorix >/dev/null
container_state="$(docker_read inspect --format '{{.State.Status}}' training-xalgorix)"
[[ "$container_state" == "running" ]] || die "Container Xalgorix tidak berjalan: $container_state"

published_port="$(docker_read port training-xalgorix 9137/tcp)"
[[ "$published_port" == "127.0.0.1:9137" ]] || die "Xalgorix tidak terikat eksklusif ke loopback: $published_port"

if ! docker_read inspect --format '{{range .Config.Env}}{{println .}}{{end}}' training-xalgorix | grep -q '^XALGORIX_USERNAME='; then
  die "Username native Xalgorix tidak dikonfigurasi."
fi
if ! docker_read inspect --format '{{range .Config.Env}}{{println .}}{{end}}' training-xalgorix | grep -q '^XALGORIX_PASSWORD='; then
  die "Password native Xalgorix tidak dikonfigurasi."
fi

dashboard_code="$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 5 http://127.0.0.1:9137/)"
case "$dashboard_code" in
  200) warn "Root dashboard merespons 200; pastikan kontennya hanya halaman login sebelum kelas." ;;
  301 | 302 | 303 | 307 | 308 | 401 | 403) ;;
  *) die "Dashboard Xalgorix belum sehat; HTTP $dashboard_code" ;;
esac

if [[ "$INSTALL_PLAYWRIGHT" == "1" ]]; then
  playwright_reference="$PLAYWRIGHT_MCP_IMAGE"
  [[ -z "$PLAYWRIGHT_MCP_IMAGE_DIGEST" ]] || playwright_reference+="@$PLAYWRIGHT_MCP_IMAGE_DIGEST"
  docker_read image inspect "$playwright_reference" >/dev/null
  opencode_path="$PATH"
  if ! docker info >/dev/null 2>&1; then
    opencode_path="$PRAKTEK_ROOT/lib/docker-shim:$PATH"
    run_root docker info >/dev/null
  fi
  mcp_output=""
  mcp_status=0
  for attempt in 1 2 3; do
    if mcp_output="$(cd "$redteam_runtime" && PATH="$opencode_path" "$opencode_bin" mcp list 2>&1)"; then
      mcp_status=0
    else
      mcp_status=$?
    fi
    if grep -qE '(^|[[:space:]])playwright([[:space:]]|$)' <<<"$mcp_output"; then
      break
    fi
    if ((attempt < 3)); then
      sleep 2
    fi
  done
  grep -qE '(^|[[:space:]])playwright([[:space:]]|$)' <<<"$mcp_output" || die "MCP Playwright tidak terdaftar setelah tiga pemeriksaan (exit $mcp_status)."
  unset mcp_output
fi

if [[ "$PROFILE" == "instructor" && -n "$XALGORIX_DOMAIN" ]]; then
  gateway_code="$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 10 --resolve "$XALGORIX_DOMAIN:443:127.0.0.1" "https://$XALGORIX_DOMAIN/")"
  [[ "$gateway_code" == "401" ]] || die "Gateway publik tidak menolak request tanpa autentikasi; HTTP $gateway_code"
fi

if [[ "$PROFILE" == "instructor" && -n "$XALGORIX_PUBLIC_IP" ]]; then
  gateway_code="$(curl --insecure --silent --output /dev/null --write-out '%{http_code}' --max-time 10 "https://127.0.0.1:$XALGORIX_PUBLIC_PORT/")"
  [[ "$gateway_code" == "401" ]] || die "Gateway IP publik tidak menolak request tanpa autentikasi; HTTP $gateway_code"
fi

if [[ "$PROFILE" == "instructor" && ( -n "$XALGORIX_DOMAIN" || -n "$XALGORIX_PUBLIC_IP" ) ]]; then
  gateway_file="$HOME/.config/praktek-lab/xalgorix-gateway.env"
  [[ -f "$gateway_file" ]] || die "Credential gateway tidak ditemukan."
  [[ "$(stat -c '%a' "$gateway_file")" == "600" ]] || die "Permission credential gateway harus 0600."
  gateway_user="$(sed -n 's/^GATEWAY_USERNAME=//p' "$gateway_file")"
  gateway_password="$(sed -n 's/^GATEWAY_PASSWORD=//p' "$gateway_file")"
  [[ -n "$gateway_user" && -n "$gateway_password" ]] || die "Credential gateway tidak lengkap."
  if [[ -n "$XALGORIX_PUBLIC_IP" ]]; then
    gateway_url="https://127.0.0.1:$XALGORIX_PUBLIC_PORT"
    gateway_curl_options=(--insecure)
  else
    gateway_url="https://$XALGORIX_DOMAIN"
    gateway_curl_options=(--resolve "$XALGORIX_DOMAIN:443:127.0.0.1")
  fi
  authenticated_root_code="$(printf 'user = "%s:%s"\n' "$gateway_user" "$gateway_password" | curl --config - "${gateway_curl_options[@]}" --silent --output /dev/null --write-out '%{http_code}' --max-time 10 "$gateway_url/")"
  [[ "$authenticated_root_code" == "200" ]] || die "Basic Auth gateway tidak dapat membuka dashboard; HTTP $authenticated_root_code"
  native_api_code="$(printf 'user = "%s:%s"\n' "$gateway_user" "$gateway_password" | curl --config - "${gateway_curl_options[@]}" --silent --output /dev/null --write-out '%{http_code}' --max-time 10 "$gateway_url/api/status")"
  [[ "$native_api_code" == "401" ]] || die "API native Xalgorix tidak menuntut sesi login; HTTP $native_api_code"
  unset gateway_user gateway_password
fi

scope_file="$WORKSPACE/scope.env"
[[ -f "$scope_file" ]] || die "File persetujuan scope tidak ditemukan."
if grep -q '^SCOPE_ACCEPTED=YES$' "$scope_file"; then
  if grep -q 'INSTRUCTOR_TO_COMPLETE' "$scope_file"; then
    die "Scope ditandai YES tetapi masih memiliki placeholder."
  fi
  log "Persetujuan scope tercatat. Verifikasi ini tetap tidak mengakses target."
else
  warn "Scope belum disetujui. Jangan masukkan target ke OpenCode, RedteamAgent, Xalgorix, atau Playwright."
fi

write_environment_report
log "Verifikasi pasif lulus. Tidak ada active scan atau koneksi ke $TRAINING_TARGET_HOST."
