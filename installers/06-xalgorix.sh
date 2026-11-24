#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

runtime_directory="$WORKSPACE/tooling/xalgorix"
compose_file="$runtime_directory/compose.yml"
secret_directory="$HOME/.config/praktek-lab"
secret_file="$secret_directory/xalgorix.env"
gateway_file="$secret_directory/xalgorix-gateway.env"
image_reference="$XALGORIX_IMAGE"

if [[ -n "$XALGORIX_IMAGE_DIGEST" ]]; then
  image_reference+="@$XALGORIX_IMAGE_DIGEST"
else
  warn "Digest image Xalgorix belum final; tag kandidat $XALGORIX_IMAGE akan digunakan."
fi

if [[ "$XALGORIX_PRIVILEGED" == "1" ]]; then
  privileged_value=true
  warn "Mode privileged Xalgorix diaktifkan secara eksplisit. Gunakan hanya pada host latihan khusus."
else
  privileged_value=false
fi

ensure_directory "$runtime_directory"
if [[ "$DRY_RUN" == "1" ]]; then
  log "Akan menyalin Compose Xalgorix dan membuat credential acak di $secret_file dengan mode 0600."
  print_command install -m 0640 "$PRAKTEK_ROOT/config/xalgorix.compose.yml" "$compose_file"
  print_command docker pull "$image_reference"
  print_command docker compose --env-file "$secret_file" -f "$compose_file" up -d
  if [[ "$PROFILE" == "instructor" && -n "$XALGORIX_DOMAIN" ]]; then
    log "Akan memasang reverse proxy HTTPS + Basic Auth untuk $XALGORIX_DOMAIN tanpa mengubah firewall."
  elif [[ "$PROFILE" == "instructor" && -n "$XALGORIX_PUBLIC_IP" ]]; then
    log "Akan memasang gateway HTTPS internal + Basic Auth pada $XALGORIX_PUBLIC_IP:$XALGORIX_PUBLIC_PORT tanpa mengubah firewall."
  fi
  exit 0
fi

install -m 0640 "$PRAKTEK_ROOT/config/xalgorix.compose.yml" "$compose_file"
install -d -m 0700 "$secret_directory"

if [[ ! -e "$secret_file" ]]; then
  umask 077
  xalgorix_password="$(openssl rand -hex 24)"
  {
    printf 'XALGORIX_IMAGE=%s\n' "$image_reference"
    printf 'XALGORIX_CONTAINER_PRIVILEGED=%s\n' "$privileged_value"
    printf 'XALGORIX_USERNAME=admin\n'
    printf 'XALGORIX_PASSWORD=%s\n' "$xalgorix_password"
  } >"$secret_file"
  chmod 0600 "$secret_file"
  unset xalgorix_password
else
  chmod 0600 "$secret_file"
  if grep -q '^XALGORIX_PRIVILEGED=' "$secret_file" && ! grep -q '^XALGORIX_CONTAINER_PRIVILEGED=' "$secret_file"; then
    sed -i 's/^XALGORIX_PRIVILEGED=/XALGORIX_CONTAINER_PRIVILEGED=/' "$secret_file"
    log "Memigrasikan nama variabel privileged Compose tanpa mengubah credential."
  fi
  grep -q '^XALGORIX_USERNAME=' "$secret_file" || die "Credential Xalgorix tidak valid: $secret_file"
  grep -q '^XALGORIX_PASSWORD=' "$secret_file" || die "Credential Xalgorix tidak valid: $secret_file"
  grep -Fqx "XALGORIX_IMAGE=$image_reference" "$secret_file" || die "Pin image Xalgorix pada credential lama berbeda. Tinjau file sebelum melanjutkan."
  grep -Fqx "XALGORIX_CONTAINER_PRIVILEGED=$privileged_value" "$secret_file" || die "Mode privileged Xalgorix berbeda dari instalasi sebelumnya. Tinjau file sebelum melanjutkan."
  log "Mempertahankan credential Xalgorix yang sudah ada."
fi

docker_run pull "$image_reference"
docker_run compose --env-file "$secret_file" -f "$compose_file" up -d

dashboard_ready=0
for attempt in $(seq 1 30); do
  if curl --silent --output /dev/null --max-time 2 http://127.0.0.1:9137/; then
    dashboard_ready=1
    break
  fi
  sleep 2
done
[[ "$dashboard_ready" == "1" ]] || die "Dashboard Xalgorix tidak siap setelah 60 detik."

if [[ "$PROFILE" != "instructor" || ( -z "$XALGORIX_DOMAIN" && -z "$XALGORIX_PUBLIC_IP" ) ]]; then
  log "Dashboard Xalgorix hanya tersedia melalui 127.0.0.1:9137. Credential tersimpan di $secret_file."
  exit 0
fi

gateway_site=""
gateway_tls_certificate=""
gateway_tls_key=""
if [[ -n "$XALGORIX_DOMAIN" ]]; then
  [[ "$XALGORIX_DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] || die "Format domain Xalgorix tidak valid."
  gateway_site="$XALGORIX_DOMAIN"
else
  [[ "$XALGORIX_PUBLIC_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || die "Format IPv4 Xalgorix tidak valid."
  IFS=. read -r ip_a ip_b ip_c ip_d <<<"$XALGORIX_PUBLIC_IP"
  for octet in "$ip_a" "$ip_b" "$ip_c" "$ip_d"; do
    ((10#$octet >= 0 && 10#$octet <= 255)) || die "Format IPv4 Xalgorix tidak valid."
  done
  gateway_site=":$XALGORIX_PUBLIC_PORT"
  gateway_tls_certificate=/etc/caddy/certs/praktek-lab-xalgorix.crt
  gateway_tls_key=/etc/caddy/certs/praktek-lab-xalgorix.key
fi

source /etc/os-release
if [[ "$ID" == "ubuntu" ]]; then
  run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "caddy=$CADDY_PACKAGE_VERSION"
else
  run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends caddy
fi

if [[ -n "$gateway_tls_certificate" ]]; then
  run_root install -d -o root -g caddy -m 0750 /etc/caddy/certs
  if run_root test -e "$gateway_tls_certificate" || run_root test -e "$gateway_tls_key"; then
    run_root test -f "$gateway_tls_certificate" || die "Sertifikat gateway IP tidak ditemukan."
    run_root test -f "$gateway_tls_key" || die "Private key gateway IP tidak ditemukan."
    run_root openssl x509 -in "$gateway_tls_certificate" -noout -ext subjectAltName | grep -Fq "IP Address:$XALGORIX_PUBLIC_IP" || die "Sertifikat gateway dibuat untuk IP lain."
  else
    run_root openssl req -x509 -newkey rsa:3072 -sha256 -days 3650 -nodes \
      -subj "/CN=$XALGORIX_PUBLIC_IP" \
      -addext "subjectAltName=IP:$XALGORIX_PUBLIC_IP" \
      -keyout "$gateway_tls_key" \
      -out "$gateway_tls_certificate"
  fi
  run_root chown root:caddy "$gateway_tls_certificate" "$gateway_tls_key"
  run_root chmod 0644 "$gateway_tls_certificate"
  run_root chmod 0640 "$gateway_tls_key"
fi

if [[ ! -e "$gateway_file" ]]; then
  umask 077
  gateway_password="$(openssl rand -hex 24)"
  {
    printf 'GATEWAY_USERNAME=training-admin\n'
    printf 'GATEWAY_PASSWORD=%s\n' "$gateway_password"
  } >"$gateway_file"
  chmod 0600 "$gateway_file"
  unset gateway_password
else
  chmod 0600 "$gateway_file"
  log "Mempertahankan credential gateway yang sudah ada."
fi

gateway_user="$(sed -n 's/^GATEWAY_USERNAME=//p' "$gateway_file")"
gateway_password="$(sed -n 's/^GATEWAY_PASSWORD=//p' "$gateway_file")"
[[ -n "$gateway_user" && -n "$gateway_password" ]] || die "Credential gateway tidak valid."
gateway_hash="$(printf '%s\n' "$gateway_password" | caddy hash-password)"
unset gateway_password

temporary_caddy="$(mktemp)"
cleanup() {
  rm -f -- "$temporary_caddy"
}
trap cleanup EXIT
{
  printf '%s {\n' "$gateway_site"
  if [[ -n "$gateway_tls_certificate" ]]; then
    printf '  tls %s %s\n' "$gateway_tls_certificate" "$gateway_tls_key"
  fi
  printf '  basicauth {\n'
  printf '    %s %s\n' "$gateway_user" "$gateway_hash"
  printf '  }\n'
  printf '  reverse_proxy 127.0.0.1:9137 {\n'
  printf '    header_up -Authorization\n'
  printf '  }\n'
  printf '}\n'
} >"$temporary_caddy"
chmod 0600 "$temporary_caddy"

run_root install -d -m 0755 /etc/caddy/conf.d
run_root install -o root -g caddy -m 0640 "$temporary_caddy" /etc/caddy/conf.d/praktek-lab-xalgorix.caddy
if ! run_root grep -Fq 'import /etc/caddy/conf.d/*.caddy' /etc/caddy/Caddyfile; then
  printf '\nimport /etc/caddy/conf.d/*.caddy\n' | if [[ "$(id -u)" -eq 0 ]]; then
    tee -a /etc/caddy/Caddyfile >/dev/null
  else
    sudo tee -a /etc/caddy/Caddyfile >/dev/null
  fi
fi
run_root caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
run_root systemctl enable --now caddy
run_root systemctl reload caddy

if [[ -n "$XALGORIX_PUBLIC_IP" ]]; then
  public_gateway="https://$XALGORIX_PUBLIC_IP:$XALGORIX_PUBLIC_PORT"
else
  public_gateway="https://$XALGORIX_DOMAIN"
fi
log "HTTPS Xalgorix disiapkan untuk $public_gateway dengan gateway dan login native terpisah."
if [[ -n "$gateway_tls_certificate" ]]; then
  warn "Gateway IP memakai sertifikat self-signed dengan SAN IP. Browser akan menampilkan peringatan sampai sertifikat dipercaya."
fi
log "Credential gateway tersimpan di $gateway_file; nilainya tidak dicetak."
