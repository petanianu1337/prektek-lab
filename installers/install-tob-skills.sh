#!/usr/bin/env bash
# install-tob-skills.sh
#
# Install skill dari marketplace plugin trailofbits/skills ke opencode.
# Cocok untuk Kali Linux (atau distro Linux lain yang punya git/bash standar).
#
# Contoh pakai:
#   ./install-tob-skills.sh -l                  # lihat daftar skill yang tersedia
#   ./install-tob-skills.sh                      # install SEMUA skill, global (~/.config/opencode/skills)
#   ./install-tob-skills.sh -p                   # install SEMUA skill, khusus project ini (./.opencode/skills)
#   ./install-tob-skills.sh -s fp-check,c-review # install skill tertentu saja

set -euo pipefail

REPO_URL="https://github.com/trailofbits/skills.git"
SCOPE="global"
LIST_ONLY=0
SELECTED_SKILLS=()

usage() {
  cat <<EOF
Usage: $0 [-g|-p] [-s skill1,skill2,...] [-l] [-h]
  -g        install global -> ~/.config/opencode/skills (default)
  -p        install project-local -> ./.opencode/skills
  -s LIST   nama skill yang mau diinstall, pisahkan dengan koma (default: semua)
  -l        cuma tampilkan daftar skill yang tersedia di repo, lalu keluar
  -h        tampilkan bantuan ini
EOF
  exit 1
}

while getopts "gps:lh" opt; do
  case "$opt" in
    g) SCOPE="global" ;;
    p) SCOPE="project" ;;
    s) IFS=',' read -r -a SELECTED_SKILLS <<< "$OPTARG" ;;
    l) LIST_ONLY=1 ;;
    h) usage ;;
    *) usage ;;
  esac
done

if [ "$SCOPE" = "global" ]; then
  TARGET_DIR="$HOME/.config/opencode/skills"
else
  TARGET_DIR="$(pwd)/.opencode/skills"
fi

command -v git >/dev/null 2>&1 || {
  echo "[!] git tidak ditemukan. Install dulu: sudo apt install -y git" >&2
  exit 1
}

CLONE_DIR="$(mktemp -d /tmp/tob-skills.XXXXXX)"
cleanup() { rm -rf "$CLONE_DIR"; }
trap cleanup EXIT

echo "[*] Cloning trailofbits/skills ..."
git clone --depth=1 "$REPO_URL" "$CLONE_DIR" >/dev/null

PLUGINS_DIR="$CLONE_DIR/plugins"
[ -d "$PLUGINS_DIR" ] || {
  echo "[!] Direktori plugins/ tidak ditemukan di repo (struktur repo mungkin berubah)." >&2
  exit 1
}

# Setiap skill hidup di: plugins/<plugin>/skills/<skill>/SKILL.md
mapfile -t SKILL_PATHS < <(find "$PLUGINS_DIR" -mindepth 3 -maxdepth 3 -type d -path "*/skills/*" | sort)

if [ "${#SKILL_PATHS[@]}" -eq 0 ]; then
  echo "[!] Tidak ada skill ditemukan di repo." >&2
  exit 1
fi

if [ "$LIST_ONLY" -eq 1 ]; then
  echo "Skill yang tersedia:"
  for p in "${SKILL_PATHS[@]}"; do
    echo "  - $(basename "$p")  (plugin: $(basename "$(dirname "$(dirname "$p")")")"
  done
  exit 0
fi

mkdir -p "$TARGET_DIR"

installed=0
skipped=0
for skill_path in "${SKILL_PATHS[@]}"; do
  skill_name="$(basename "$skill_path")"

  if [ "${#SELECTED_SKILLS[@]}" -gt 0 ]; then
    match=0
    for s in "${SELECTED_SKILLS[@]}"; do
      [ "$s" = "$skill_name" ] && match=1 && break
    done
    [ "$match" -eq 1 ] || continue
  fi

  if [ ! -f "$skill_path/SKILL.md" ]; then
    echo "  [skip] $skill_name: tidak ada SKILL.md"
    skipped=$((skipped + 1))
    continue
  fi

  rm -rf "${TARGET_DIR:?}/$skill_name"
  cp -r "$skill_path" "$TARGET_DIR/$skill_name"
  echo "  [ok]   $skill_name -> $TARGET_DIR/$skill_name"
  installed=$((installed + 1))
done

echo
echo "[*] Selesai. $installed skill terpasang, $skipped dilewati."
echo "[*] Lokasi: $TARGET_DIR"
