write_site_assets() {
  # Keep the checked-in interface as the canonical template. The updater only
  # refreshes catalog data, so design changes are not overwritten on each run.
  cp "${SITE_DIR}/app.js" "${TMP_DIR}/site/app.js"
  cp "${SITE_DIR}/index.html" "${TMP_DIR}/site/index.html"
}

build_site() {
  local updated_at="${1}"
  local emote_count="${2}"
  local piece_count="${3}"
  local emote_dir="${4}"
  local piece_dir="${5}"

  mkdir -p "${TMP_DIR}/site/data/persona_emote" "${TMP_DIR}/site/data/persona_piece"

  jq -nc --arg ts "${updated_at}" --argjson emotes "${emote_count}" --argjson pieces "${piece_count}" '{updatedAt:$ts, counts:{persona_emote:$emotes, persona_piece:$pieces}}' > "${DATA_DIR}/index.json"
  jq -nc --arg ts "${updated_at}" --argjson emotes "${emote_count}" --argjson pieces "${piece_count}" '{updatedAt:$ts, counts:{persona_emote:$emotes, persona_piece:$pieces}}' > "${TMP_DIR}/site/index.json"

  cp "${emote_dir}/items.json" "${TMP_DIR}/site/data/persona_emote/items.json"
  cp "${piece_dir}/items.json" "${TMP_DIR}/site/data/persona_piece/items.json"
  write_site_assets

  rm -rf "${SITE_DIR}"
  mkdir -p "${SITE_DIR}"
  cp -R "${TMP_DIR}/site/." "${SITE_DIR}/"
}
