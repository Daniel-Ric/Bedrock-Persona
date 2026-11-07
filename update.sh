#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(pwd)"
SCRIPT_DIR="${ROOT_DIR}/scripts"

source "${SCRIPT_DIR}/env.sh"

LAST_CHECKED="$(jq -sr '[.[] | .lastCheckedAt // .updatedAt // empty] | max // ""' "${STATE_DIR}"/*.json 2>/dev/null || true)"
if [ -n "${LAST_CHECKED}" ] && [ "$(( $(date -u +%s) - $(date -u -d "${LAST_CHECKED}" +%s) ))" -lt 432000 ]; then
  exit 0
fi

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

CHANGED="false"
for KEY in "${EMOTE_KEY}" "${PIECE_KEY}"; do
  if [ "${KEY}" = "${EMOTE_KEY}" ]; then FILTER="${EMOTE_FILTER}"; else FILTER="${PIECE_FILTER}"; fi
  if fetch_all "${KEY}" "${FILTER}" "${DATA_DIR}/${KEY}"; then
    if has_changes "${DATA_DIR}/${KEY}/changes.json"; then CHANGED="true"; fi
  else
    STATUS=$?
    if [ "${STATUS}" -ne 1 ]; then exit "${STATUS}"; fi
  fi
done

if [ ! -f "${STATE_DIR}/global.json" ]; then echo '{}' > "${STATE_DIR}/global.json"; fi
jq --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '.lastCheckedAt = $ts' "${STATE_DIR}/global.json" > "${TMP_DIR}/global.json"
mv "${TMP_DIR}/global.json" "${STATE_DIR}/global.json"

ensure_json "${EMOTE_DIR}/items.json"
ensure_json "${PIECE_DIR}/items.json"

EMOTE_COUNT="$(jq -r 'length' "${EMOTE_DIR}/items.json")"
PIECE_COUNT="$(jq -r 'length' "${PIECE_DIR}/items.json")"

EMOTE_SUMMARY="$(changes_summary "${EMOTE_DIR}/changes.json")"
PIECE_SUMMARY="$(changes_summary "${PIECE_DIR}/changes.json")"

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

jq --arg ts "${UPDATED_AT}" '.updatedAt = $ts' "${STATE_DIR}/global.json" > "${TMP_DIR}/global.json"
mv "${TMP_DIR}/global.json" "${STATE_DIR}/global.json"
