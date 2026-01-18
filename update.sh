#!/usr/bin/env bash
set -euo pipefail

command -v curl >/dev/null
command -v jq >/dev/null
command -v wget >/dev/null

: "${IOS_DEVICE_ID:?Missing IOS_DEVICE_ID}"

TITLE_ID="${TITLE_ID:-20ca2}"
SCID="${SCID:-4fc10100-5f7a-4470-899b-280835760c07}"
BASE_URL="https://${TITLE_ID}.playfabapi.com"
COUNT="${COUNT:-300}"
PARALLEL_DOWNLOADS="${PARALLEL_DOWNLOADS:-8}"

ROOT_DIR="$(pwd)"
STATE_DIR="${ROOT_DIR}/.state"
DATA_DIR="${ROOT_DIR}/data"
ASSETS_DIR="${ROOT_DIR}/assets"
IMAGES_DIR="${ASSETS_DIR}/images"

EMOTE_KEY="persona_emote"
PIECE_KEY="persona_piece"

mkdir -p "${STATE_DIR}" "${DATA_DIR}" "${ASSETS_DIR}" "${IMAGES_DIR}"

pf_post() {
  local path="${1}"
  local body="${2}"
  curl -sS -L -X POST "${BASE_URL}${path}" -H 'Content-Type: application/json' -H "X-EntityToken: ${ENTITYTOKEN}" -d "${body}"
}

client_post() {
  local path="${1}"
  local body="${2}"
  curl -sS -L -X POST "${BASE_URL}${path}" -H 'Content-Type: application/json' -d "${body}"
}

LOGINRESULT="$(client_post "/Client/LoginWithIOSDeviceID" "$(jq -nc --arg d "$IOS_DEVICE_ID" --arg t "$TITLE_ID" '{DeviceId:$d,TitleId:$t,CreateAccount:true}')" )"

if ! echo "${LOGINRESULT}" | jq -e '.data.EntityToken.EntityToken and .data.PlayFabId' >/dev/null; then
  echo "${LOGINRESULT}" | jq .
  exit 1
fi

LOGINENTITYTOKEN="$(echo "${LOGINRESULT}" | jq -r '.data.EntityToken.EntityToken')"
PLAYFABID="$(echo "${LOGINRESULT}" | jq -r '.data.PlayFabId')"

ENTITYTOKENRESULT="$(curl -sS -L -X POST "${BASE_URL}/Authentication/GetEntityToken" -H 'Content-Type: application/json' -H "X-EntityToken: ${LOGINENTITYTOKEN}" -d "$(jq -nc --arg id "$PLAYFABID" '{Entity:{Id:$id,Type:"master_player_account"}}')" )"

if ! echo "${ENTITYTOKENRESULT}" | jq -e '.data.EntityToken' >/dev/null; then
  echo "${ENTITYTOKENRESULT}" | jq .
  exit 1
fi

ENTITYTOKEN="$(echo "${ENTITYTOKENRESULT}" | jq -r '.data.EntityToken')"

extract_items_array() {
  jq -c 'if .data.Items then .data.Items elif .items then .items else [] end'
}

extract_total_count() {
  jq -r 'if .data.Count then .data.Count elif .meta.total then .meta.total else 0 end'
}

normalize_items() {
  jq -c '
    [
      .[] |
      {
        id: (.Id // .id // ""),
        uuid: (.DisplayProperties.packIdentity[0].uuid // .DisplayProperties.packIdentity[0].Uuid // .Id // .id // ""),
        title: (.Title.neutral // .Title.NEUTRAL // .Title.Neutral // .title // ""),
        image: (
          (
            (.Images // []) |
            (map(select((.Type // "" | ascii_downcase) == "thumbnail" or (.Tag // "" | ascii_downcase) == "thumbnail")) | .[0].Url)
          ) // ((.Images // [])[0].Url // "")
        ),
        rarity: (.DisplayProperties.rarity // .displayProperties.rarity // null),
        keywords: (.Keywords.neutral.Values // .Keywords.NEUTRAL.Values // .keywords.neutral.Values // []),
        creatorName: (.DisplayProperties.creatorName // .displayProperties.creatorName // null),
        offerId: (.DisplayProperties.offerId // .displayProperties.offerId // null),
        price: (
          .DisplayProperties.price //
          .displayProperties.price //
          (
            (.Price.Prices[0].Amounts[0].Amount // .PriceOptions.Prices[0].Amounts[0].Amount) // null
          )
        ),
        purchasable: (.DisplayProperties.purchasable // .displayProperties.purchasable // null),
        startDate: (.StartDate // .startDate // null),
        lastModifiedDate: (.LastModifiedDate // .lastModifiedDate // null),
        creationDate: (.CreationDate // .creationDate // null),
        contentType: (.ContentType // .contentType // null),
        pieceType: (.DisplayProperties.pieceType // .displayProperties.pieceType // null),
        rating: (.Rating // .rating // null)
      }
      | select(.uuid != "")
    ]
  '
}

max_last_modified() {
  jq -r '[ .[] | .lastModifiedDate | select(. != null and . != "") ] | max // ""'
}

max_start_date() {
  jq -r '[ .[] | .startDate | select(. != null and . != "") ] | max // ""'
}

build_metadata() {
  jq -c '{
    keywords: ([.[] | .keywords[]?] | unique),
    rarities: ([.[] | .rarity] | unique),
    creators: ([.[] | .creatorName] | map(select(.!=null)) | unique),
    pieceTypes: ([.[] | .pieceType] | map(select(.!=null)) | unique),
    contentTypes: ([.[] | .contentType] | map(select(.!=null)) | unique),
    prices: ([.[] | .price] | map(select(.!=null)) | unique)
  }'
}

diff_items() {
  local old_file="${1}"
  local new_file="${2}"
  jq -n --slurpfile old "${old_file}" --slurpfile new "${new_file}" '
    def idx(a): a | map({key:.uuid, value:.}) | from_entries;
    (idx($old[0]) as $o | idx($new[0]) as $n |
      {
        added:   ($n|keys - ($o|keys)),
        removed: (($o|keys) - ($n|keys)),
        changed: (
          ($n|keys) as $keys
          | [ $keys[] | select($o[.] and ($o[.] != $n[.])) ]
        ),
        counts: { old: ($old[0]|length), new: ($new[0]|length) }
      }
    )
  '
}

safe_filter_try() {
  local base_filter="${1}"
  local extra_filter="${2}"
  local order_by="${3}"
  local skip="${4}"
  local top="${5}"

  local filter="${base_filter}"
  if [ -n "${extra_filter}" ]; then
    filter="(${base_filter} and ${extra_filter})"
  fi

  local payload
  payload="$(jq -nc --arg f "${filter}" --arg o "${order_by}" --arg scid "${SCID}" --argjson s "${skip}" --argjson t "${top}" '{Filter:$f,OrderBy:$o,scid:$scid,skip:$s,top:$t}')"
  pf_post "/Catalog/Search" "${payload}"
}

fetch_all() {
  local key="${1}"
  local base_filter="${2}"
  local out_dir="${3}"
  local images_dir="${4}"

  mkdir -p "${out_dir}" "${images_dir}"

  local state_file="${STATE_DIR}/${key}.json"
  if [ ! -f "${state_file}" ]; then
    echo '{}' > "${state_file}"
  fi

  local last_seen_modified
  last_seen_modified="$(jq -r '.lastModifiedDate // ""' "${state_file}")"
  local last_seen_start
  last_seen_start="$(jq -r '.startDate // ""' "${state_file}")"

  local quick_ok="false"
  if [ -n "${last_seen_modified}" ]; then
    local quick_res
    quick_res="$(safe_filter_try "${base_filter}" "LastModifiedDate gt '${last_seen_modified}'" "LastModifiedDate desc" 0 1 || true)"
    if echo "${quick_res}" | jq -e '(.data.Items // []) | length >= 0' >/dev/null 2>&1; then
      if [ "$(echo "${quick_res}" | jq -r '(.data.Items // []) | length')" -eq 0 ]; then
        quick_ok="true"
      fi
    fi
  fi

  if [ "${quick_ok}" = "true" ] && [ -n "${last_seen_start}" ]; then
    local quick_res
    quick_res="$(safe_filter_try "${base_filter}" "StartDate gt '${last_seen_start}'" "StartDate desc" 0 1 || true)"
    if echo "${quick_res}" | jq -e '(.data.Items // []) | length >= 0' >/dev/null 2>&1; then
      if [ "$(echo "${quick_res}" | jq -r '(.data.Items // []) | length')" -eq 0 ]; then
        echo "No changes detected for ${key}"
        return 1
      fi
    fi
  fi

  local tmpdir
  tmpdir="$(mktemp -d)"
  local skip=0
  local total=1
  local page=0

  while [ "${skip}" -lt "${total}" ]; do
    local res
    res="$(safe_filter_try "${base_filter}" "" "title/neutral asc" "${skip}" "${COUNT}")"

    local items
    items="$(echo "${res}" | extract_items_array)"

    local page_file="${tmpdir}/page_${page}.json"
    echo "${items}" | normalize_items > "${page_file}"

    if [ "${skip}" -eq 0 ]; then
      total="$(echo "${res}" | extract_total_count)"
      if [ -z "${total}" ] || [ "${total}" = "null" ]; then
        total=0
      fi
      if [ "${total}" -le 0 ]; then
        total="$(jq -r 'length' "${page_file}")"
      fi
    fi

    if [ "$(jq -r 'length' "${page_file}")" -eq 0 ] && [ "${skip}" -gt 0 ]; then
      break
    fi

    skip=$((skip + COUNT))
    page=$((page + 1))
  done

  local items_file="${out_dir}/items.json"
  if ls "${tmpdir}"/page_*.json >/dev/null 2>&1; then
    jq -s 'add' "${tmpdir}"/page_*.json > "${items_file}"
  else
    echo '[]' > "${items_file}"
  fi

  local meta_file="${out_dir}/metadata.json"
  build_metadata < "${items_file}" > "${meta_file}"

  local new_max_modified
  new_max_modified="$(max_last_modified < "${items_file}")"
  local new_max_start
  new_max_start="$(max_start_date < "${items_file}")"

  jq -nc --arg lm "${new_max_modified}" --arg sd "${new_max_start}" --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '{lastModifiedDate:$lm,startDate:$sd,updatedAt:$ts}' > "${state_file}"

  local prev_file="${out_dir}/items.prev.json"
  local changes_file="${out_dir}/changes.json"

  if [ -f "${prev_file}" ]; then
    diff_items "${prev_file}" "${items_file}" > "${changes_file}"
  else
    jq -nc --argjson n "$(jq 'length' "${items_file}")" '{added:[],removed:[],changed:[],counts:{old:0,new:$n}}' > "${changes_file}"
  fi

  cp "${items_file}" "${prev_file}"

  local removed_uuids
  removed_uuids="$(jq -r '.removed[]?' "${changes_file}" || true)"
  if [ -n "${removed_uuids}" ]; then
    while IFS= read -r u; do
      [ -n "${u}" ] || continue
      rm -f "${images_dir}/${u}.png" 2>/dev/null || true
    done <<< "${removed_uuids}"
  fi

  jq -r '.[] | select(.image != null and .image != "" and .uuid != "") | "\(.image) \(.uuid)"' "${items_file}" \
    | awk '!seen[$2]++' \
    | xargs -r -n2 -P "${PARALLEL_DOWNLOADS}" bash -lc '
        url="$0"
        uuid="$1"
        out="'"${images_dir}"'/${uuid}.png"
        if [ -f "$out" ]; then
          exit 0
        fi
        wget -q "$url" -O "$out" || true
      ' || true

  rm -rf "${tmpdir}"
  return 0
}

EMOTE_DIR="${DATA_DIR}/${EMOTE_KEY}"
PIECE_DIR="${DATA_DIR}/${PIECE_KEY}"
EMOTE_IMG_DIR="${IMAGES_DIR}/${EMOTE_KEY}"
PIECE_IMG_DIR="${IMAGES_DIR}/${PIECE_KEY}"

EMOTE_FILTER="(contentType eq 'PersonaDurable' and displayProperties/pieceType eq '${EMOTE_KEY}')"
PIECE_FILTER="(contentType eq 'PersonaDurable' and displayProperties/pieceType ne '${EMOTE_KEY}')"

changed_any="false"

if fetch_all "${EMOTE_KEY}" "${EMOTE_FILTER}" "${EMOTE_DIR}" "${EMOTE_IMG_DIR}"; then
  changed_any="true"
fi

if fetch_all "${PIECE_KEY}" "${PIECE_FILTER}" "${PIECE_DIR}" "${PIECE_IMG_DIR}"; then
  changed_any="true"
fi

if [ "${changed_any}" != "true" ]; then
  exit 0
fi

jq -nc --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '{updatedAt:$ts}' > "${STATE_DIR}/global.json"

EMOTE_COUNT="$(jq -r 'length' "${EMOTE_DIR}/items.json")"
PIECE_COUNT="$(jq -r 'length' "${PIECE_DIR}/items.json")"

EMOTE_CHANGES_SUMMARY="$(jq -r '"added=" + ((.added|length)|tostring) + ", removed=" + ((.removed|length)|tostring) + ", changed=" + ((.changed|length)|tostring)' "${EMOTE_DIR}/changes.json")"
PIECE_CHANGES_SUMMARY="$(jq -r '"added=" + ((.added|length)|tostring) + ", removed=" + ((.removed|length)|tostring) + ", changed=" + ((.changed|length)|tostring)' "${PIECE_DIR}/changes.json")"

INDEX_FILE="${DATA_DIR}/index.json"
jq -nc \
  --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --argjson emotes "${EMOTE_COUNT}" \
  --argjson pieces "${PIECE_COUNT}" \
  '{updatedAt:$ts, counts:{persona_emote:$emotes, persona_piece:$pieces}}' > "${INDEX_FILE}"

{
  echo "# Persona Assets"
  echo
  echo "This repository updates automatically every 6 hours."
  echo
  echo "- Last update (UTC): $(date -u +"%Y-%m-%d %H:%M:%S")"
  echo "- persona_emote count: ${EMOTE_COUNT} (${EMOTE_CHANGES_SUMMARY})"
  echo "- persona_piece count: ${PIECE_COUNT} (${PIECE_CHANGES_SUMMARY})"
  echo
  echo "## persona_emote"
  echo
  echo "| Image | Name | UUID |"
  echo "|-------|------|------|"
  jq -r '.[] | "| <img src=\"./assets/images/persona_emote/\(.uuid).png\" width=\"96\" height=\"96\" /> | \(.title) | \(.uuid) |"' "${EMOTE_DIR}/items.json"
  echo
  echo "## persona_piece"
  echo
  echo "| Image | Name | UUID |"
  echo "|-------|------|------|"
  jq -r '.[] | "| <img src=\"./assets/images/persona_piece/\(.uuid).png\" width=\"96\" height=\"96\" /> | \(.title) | \(.uuid) |"' "${PIECE_DIR}/items.json"
} > "${ROOT_DIR}/README.md"
