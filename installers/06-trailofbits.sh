#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

source_directory="$WORKSPACE/tooling/trailofbits-skills"
project_directory="$WORKSPACE/tooling/redteam-agent"
skills_directory="$project_directory/.opencode/skills"
marker="$project_directory/.praktek-lab-trailofbits-skills-commit"

skill_names=(sharp-edges cvss-scoring)
skill_sources=(
  plugins/sharp-edges/skills/sharp-edges
  plugins/cvss-scoring/skills/cvss-scoring
)

clone_pinned_repository \
  "$TRAILOFBITS_SKILLS_REPOSITORY" \
  "$TRAILOFBITS_SKILLS_REF" \
  "$TRAILOFBITS_SKILLS_COMMIT" \
  "$source_directory"

if [[ "$DRY_RUN" == "1" ]]; then
  log "Akan memasang skill Trail of Bits allowlist ke $skills_directory: $TRAILOFBITS_SKILLS_ALLOWLIST"
  log "Folder .calcifier, plugin, hook, workflow, agent, dan skill lain tidak akan diaktifkan."
  exit 0
fi

[[ -d "$project_directory" ]] || die "Runtime RedteamAgent belum tersedia: $project_directory"

if [[ -f "$marker" ]]; then
  [[ "$(<"$marker")" == "$TRAILOFBITS_SKILLS_COMMIT" ]] || die "Trail of Bits Skills terpasang dari commit berbeda."
else
  install -d -m 0750 "$skills_directory"
  for index in "${!skill_names[@]}"; do
    skill_name="${skill_names[$index]}"
    source_path="$source_directory/${skill_sources[$index]}"
    destination_path="$skills_directory/$skill_name"

    [[ -f "$source_path/SKILL.md" ]] || die "SKILL.md tidak ditemukan untuk $skill_name"
    first_symlink="$(find "$source_path" -type l -print -quit)"
    if [[ -n "$first_symlink" ]]; then
      die "Symlink tidak diizinkan dalam bundle skill $skill_name"
    fi
    [[ ! -e "$destination_path" ]] || die "Tujuan skill sudah ada tanpa marker installer: $destination_path"

    install -d -m 0750 "$destination_path"
    while IFS= read -r -d '' item; do
      cp -a -- "$item" "$destination_path/"
    done < <(find "$source_path" -mindepth 1 -maxdepth 1 ! -name .calcifier -print0)
    [[ ! -e "$destination_path/.calcifier" ]] || die "Folder .calcifier tidak boleh diaktifkan."
  done

  printf '%s\n' "$TRAILOFBITS_SKILLS_COMMIT" >"$marker"
  chmod 0600 "$marker"
fi

for skill_name in "${skill_names[@]}"; do
  [[ -f "$skills_directory/$skill_name/SKILL.md" ]] || die "Skill Trail of Bits tidak lengkap: $skill_name"
done

log "Trail of Bits Skills siap pada project scope: $TRAILOFBITS_SKILLS_ALLOWLIST"
