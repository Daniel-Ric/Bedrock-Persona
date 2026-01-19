client_post() {
  local path="${1}"
  local body="${2}"
  curl -sS -L -X POST "${BASE_URL}${path}" -H 'Content-Type: application/json' -d "${body}"
}

pf_post() {
  local path="${1}"
  local body="${2}"
  curl -sS -L -X POST "${BASE_URL}${path}" -H 'Content-Type: application/json' -H "X-EntityToken: ${ENTITYTOKEN}" -d "${body}"
}

login_playfab() {
  local login_result
  login_result="$(client_post "/Client/LoginWithIOSDeviceID" "$(jq -nc --arg d "$IOS_DEVICE_ID" --arg t "$TITLE_ID" '{DeviceId:$d,TitleId:$t,CreateAccount:true}')" )"
  if ! echo "${login_result}" | jq -e '.data.EntityToken.EntityToken and .data.PlayFabId' >/dev/null; then
    echo "${login_result}" | jq .
    exit 1
  fi

  local login_entity_token
  login_entity_token="$(echo "${login_result}" | jq -r '.data.EntityToken.EntityToken')"
  PLAYFABID="$(echo "${login_result}" | jq -r '.data.PlayFabId')"

  local entity_token_result
  entity_token_result="$(curl -sS -L -X POST "${BASE_URL}/Authentication/GetEntityToken" -H 'Content-Type: application/json' -H "X-EntityToken: ${login_entity_token}" -d "$(jq -nc --arg id "$PLAYFABID" '{Entity:{Id:$id,Type:"master_player_account"}}')" )"
  if ! echo "${entity_token_result}" | jq -e '.data.EntityToken' >/dev/null; then
    echo "${entity_token_result}" | jq .
    exit 1
  fi

  ENTITYTOKEN="$(echo "${entity_token_result}" | jq -r '.data.EntityToken')"
}

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

  mkdir -p "${out_dir}"

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

  build_metadata < "${items_file}" > "${out_dir}/metadata.json"

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

  rm -rf "${tmpdir}"
  return 0
}

ensure_json() {
  local f="${1}"
  local dir
  dir="$(dirname "${f}")"
  mkdir -p "${dir}"
  if [ ! -f "${f}" ]; then
    echo '[]' > "${f}"
  fi
}

changes_summary() {
  local file="${1}"
  if [ -f "${file}" ]; then
    jq -r '"added=" + ((.added|length)|tostring) + ", removed=" + ((.removed|length)|tostring) + ", changed=" + ((.changed|length)|tostring)' "${file}"
  else
    echo "added=0, removed=0, changed=0"
  fi
}

has_changes() {
  local file="${1}"
  if [ -f "${file}" ]; then
    if [ "$(jq -r '((.added|length)+(.removed|length)+(.changed|length))' "${file}")" -gt 0 ]; then
      return 0
    fi
  fi
  return 1
}
