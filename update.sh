#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(pwd)"
SCRIPT_DIR="${ROOT_DIR}/scripts"

source "${SCRIPT_DIR}/env.sh"
source "${SCRIPT_DIR}/playfab.sh"
source "${SCRIPT_DIR}/site.sh"
source "${SCRIPT_DIR}/readme.sh"

login_playfab

EMOTE_KEY="persona_emote"
PIECE_KEY="persona_piece"

EMOTE_DIR="${DATA_DIR}/${EMOTE_KEY}"
PIECE_DIR="${DATA_DIR}/${PIECE_KEY}"

EMOTE_FILTER="(contentType eq 'PersonaDurable' and displayProperties/pieceType eq '${EMOTE_KEY}')"
PIECE_FILTER="(contentType eq 'PersonaDurable' and displayProperties/pieceType ne '${EMOTE_KEY}')"

fetch_all "${EMOTE_KEY}" "${EMOTE_FILTER}" "${EMOTE_DIR}" || true
fetch_all "${PIECE_KEY}" "${PIECE_FILTER}" "${PIECE_DIR}" || true

ensure_json "${EMOTE_DIR}/items.json"
ensure_json "${PIECE_DIR}/items.json"

EMOTE_COUNT="$(jq -r 'length' "${EMOTE_DIR}/items.json")"
PIECE_COUNT="$(jq -r 'length' "${PIECE_DIR}/items.json")"

EMOTE_SUMMARY="$(changes_summary "${EMOTE_DIR}/changes.json")"
PIECE_SUMMARY="$(changes_summary "${PIECE_DIR}/changes.json")"

CHANGED="false"
if has_changes "${EMOTE_DIR}/changes.json"; then CHANGED="true"; fi
if has_changes "${PIECE_DIR}/changes.json"; then CHANGED="true"; fi

PAGES_URL="$(resolve_pages_url)"

UPDATED_AT=""
if [ -f "${STATE_DIR}/global.json" ]; then
  UPDATED_AT="$(jq -r '.updatedAt // ""' "${STATE_DIR}/global.json")"
fi
if [ -z "${UPDATED_AT}" ]; then
  UPDATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
fi

build_readme "${UPDATED_AT}" "${PAGES_URL}" "${EMOTE_COUNT}" "${PIECE_COUNT}" "${EMOTE_SUMMARY}" "${PIECE_SUMMARY}"

if [ "${CHANGED}" != "true" ]; then
  exit 0
fi

UPDATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
build_site "${UPDATED_AT}" "${EMOTE_COUNT}" "${PIECE_COUNT}" "${EMOTE_DIR}" "${PIECE_DIR}"
build_readme "${UPDATED_AT}" "${PAGES_URL}" "${EMOTE_COUNT}" "${PIECE_COUNT}" "${EMOTE_SUMMARY}" "${PIECE_SUMMARY}"

jq -nc --arg ts "${UPDATED_AT}" '{updatedAt:$ts}' > "${STATE_DIR}/global.json"
