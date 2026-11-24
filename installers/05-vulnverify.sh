#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "$SCRIPT_DIR/../lib/common.sh"

source_directory="$WORKSPACE/tooling/vulnverify-skills"
project_directory="$WORKSPACE/tooling/redteam-agent"
marker="$project_directory/.praktek-lab-vulnverify-commit"

clone_pinned_repository "$VULNVERIFY_REPOSITORY" "$VULNVERIFY_REF" "$VULNVERIFY_COMMIT" "$source_directory"

if [[ "$DRY_RUN" == "1" ]]; then
  log "Akan memasang VulnVerify pada project scope RedteamAgent: $project_directory"
  print_command sh "$source_directory/scripts/install.sh" detect
  print_command sh "$source_directory/scripts/install.sh" install --project "$project_directory" --client opencode --dry-run
  print_command sh "$source_directory/scripts/install.sh" install --project "$project_directory" --client opencode
  print_command sh "$source_directory/scripts/install.sh" check --project "$project_directory" --client opencode
  exit 0
fi

[[ -d "$project_directory" ]] || die "Runtime RedteamAgent belum tersedia: $project_directory"

if [[ ! -f "$marker" ]]; then
  sh "$source_directory/scripts/install.sh" detect
  sh "$source_directory/scripts/install.sh" install --project "$project_directory" --client opencode --dry-run
  sh "$source_directory/scripts/install.sh" install --project "$project_directory" --client opencode
  printf '%s\n' "$VULNVERIFY_COMMIT" >"$marker"
  chmod 0600 "$marker"
else
  [[ "$(<"$marker")" == "$VULNVERIFY_COMMIT" ]] || die "VulnVerify terpasang dari commit berbeda."
fi

sh "$source_directory/scripts/install.sh" check --project "$project_directory" --client opencode
log "VulnVerify commit $VULNVERIFY_COMMIT siap pada project scope."
