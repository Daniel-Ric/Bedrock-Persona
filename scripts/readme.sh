resolve_pages_url() {
  local repo="${GITHUB_REPOSITORY:-}"
  local owner="${GITHUB_REPOSITORY_OWNER:-}"
  local pages_url=""
  if [ -n "${repo}" ] && [ -n "${owner}" ]; then
    local name="${repo#*/}"
    if [ "${name}" = "${owner}.github.io" ]; then
      pages_url="https://${owner}.github.io/"
    else
      pages_url="https://${owner}.github.io/${name}/"
    fi
  fi
  echo "${pages_url}"
}

build_readme() {
  local updated_at="${1}"
  local pages_url="${2}"
  local emote_count="${3}"
  local piece_count="${4}"
  local emote_summary="${5}"
  local piece_summary="${6}"

  {
    echo "# Persona Assets"
    echo
    echo "This repository automatically mirrors Minecraft Bedrock Persona catalog entries using PlayFab Economy v2 (Catalog/Search)."
    echo
    if [ -n "${pages_url}" ]; then
      echo "## Web UI"
      echo
      echo "- ${pages_url}"
      echo
    fi
    echo "## What gets updated"
    echo
    echo "- \\`data/persona_emote/items.json\\`: normalized persona emote entries"
    echo "- \\`data/persona_piece/items.json\\`: all other PersonaDurable entries excluding persona_emote"
    echo "- \\`data/*/metadata.json\\`: unique keyword/rarity/creator/contentType summaries"
    echo "- \\`data/*/changes.json\\`: added/removed/changed UUIDs compared to previous run"
    echo "- \\`site/\\`: static web UI published via GitHub Pages"
    echo
    echo "## Schedule"
    echo
    echo "- Runs on push and every 6 hours via GitHub Actions"
    echo "- Last update (UTC): ${updated_at}"
    echo
    echo "## Current counts"
    echo
    echo "- persona_emote: ${emote_count} (${emote_summary})"
    echo "- persona_piece: ${piece_count} (${piece_summary})"
    echo
    echo "## Setup"
    echo
    echo "1. Add the workflow + script to the repo"
    echo "2. Add the Actions secret \\`IOS_DEVICE_ID\\` (any stable unique string, UUID recommended)"
    echo "3. Enable GitHub Pages: Settings → Pages → Source: GitHub Actions"
    echo "4. Run the workflow once (Actions → Update Persona Assets → Run workflow)"
    echo
    echo "## Notes"
    echo
    echo "- No secrets are committed to the repository."
    echo "- The workflow only commits when actual catalog changes are detected."
  } > "${ROOT_DIR}/README.md"
}
