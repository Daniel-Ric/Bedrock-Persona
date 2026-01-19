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

ROOT_DIR="$(pwd)"
STATE_DIR="${ROOT_DIR}/.state"
DATA_DIR="${ROOT_DIR}/data"
SITE_DIR="${ROOT_DIR}/site"

mkdir -p "${STATE_DIR}" "${DATA_DIR}" "${SITE_DIR}"

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

EMOTE_KEY="persona_emote"
PIECE_KEY="persona_piece"

EMOTE_DIR="${DATA_DIR}/${EMOTE_KEY}"
PIECE_DIR="${DATA_DIR}/${PIECE_KEY}"

EMOTE_FILTER="(contentType eq 'PersonaDurable' and displayProperties/pieceType eq '${EMOTE_KEY}')"
PIECE_FILTER="(contentType eq 'PersonaDurable' and displayProperties/pieceType ne '${EMOTE_KEY}')"

fetch_all "${EMOTE_KEY}" "${EMOTE_FILTER}" "${EMOTE_DIR}" || true
fetch_all "${PIECE_KEY}" "${PIECE_FILTER}" "${PIECE_DIR}" || true

UPDATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if [ ! -f "${EMOTE_DIR}/items.json" ]; then echo '[]' > "${EMOTE_DIR}/items.json"; fi
if [ ! -f "${PIECE_DIR}/items.json" ]; then echo '[]' > "${PIECE_DIR}/items.json"; fi

EMOTE_COUNT="$(jq -r 'length' "${EMOTE_DIR}/items.json")"
PIECE_COUNT="$(jq -r 'length' "${PIECE_DIR}/items.json")"

EMOTE_SUMMARY="added=0, removed=0, changed=0"
PIECE_SUMMARY="added=0, removed=0, changed=0"
if [ -f "${EMOTE_DIR}/changes.json" ]; then EMOTE_SUMMARY="$(jq -r '"added=" + ((.added|length)|tostring) + ", removed=" + ((.removed|length)|tostring) + ", changed=" + ((.changed|length)|tostring)' "${EMOTE_DIR}/changes.json")"; fi
if [ -f "${PIECE_DIR}/changes.json" ]; then PIECE_SUMMARY="$(jq -r '"added=" + ((.added|length)|tostring) + ", removed=" + ((.removed|length)|tostring) + ", changed=" + ((.changed|length)|tostring)' "${PIECE_DIR}/changes.json")"; fi

REPO="${GITHUB_REPOSITORY:-}"
OWNER="${GITHUB_REPOSITORY_OWNER:-}"
PAGES_URL=""
if [ -n "${REPO}" ] && [ -n "${OWNER}" ]; then
  NAME="${REPO#*/}"
  if [ "${NAME}" = "${OWNER}.github.io" ]; then
    PAGES_URL="https://${OWNER}.github.io/"
  else
    PAGES_URL="https://${OWNER}.github.io/${NAME}/"
  fi
fi

jq -nc --arg ts "${UPDATED_AT}" --argjson emotes "${EMOTE_COUNT}" --argjson pieces "${PIECE_COUNT}" '{updatedAt:$ts, counts:{persona_emote:$emotes, persona_piece:$pieces}}' > "${DATA_DIR}/index.json"

mkdir -p "${SITE_DIR}/data/persona_emote" "${SITE_DIR}/data/persona_piece"
jq -nc --arg ts "${UPDATED_AT}" --argjson emotes "${EMOTE_COUNT}" --argjson pieces "${PIECE_COUNT}" '{updatedAt:$ts, counts:{persona_emote:$emotes, persona_piece:$pieces}}' > "${SITE_DIR}/index.json"
cp "${EMOTE_DIR}/items.json" "${SITE_DIR}/data/persona_emote/items.json"
cp "${PIECE_DIR}/items.json" "${SITE_DIR}/data/persona_piece/items.json"

cat > "${SITE_DIR}/styles.css" <<'CSS'
:root{--bg:#0b0f16;--card:#101826;--muted:#93a4bf;--text:#e8eef9;--accent:#4aa3ff;--border:#1e2a3d}
*{box-sizing:border-box}html,body{height:100%}
body{margin:0;font-family:ui-sans-serif,system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Cantarell,Noto Sans,sans-serif;background:linear-gradient(180deg,#070a10,#0b0f16 40%,#070a10);color:var(--text)}
a{color:var(--accent);text-decoration:none}a:hover{text-decoration:underline}
.container{max-width:1200px;margin:0 auto;padding:28px}
.header{display:flex;gap:16px;flex-wrap:wrap;align-items:flex-end;justify-content:space-between;margin-bottom:18px}
.title h1{margin:0;font-size:28px;letter-spacing:.2px}
.subtitle{margin-top:6px;color:var(--muted);font-size:14px}
.badges{display:flex;gap:10px;flex-wrap:wrap}
.badge{background:rgba(74,163,255,.12);border:1px solid rgba(74,163,255,.25);color:var(--text);padding:7px 10px;border-radius:999px;font-size:12px}
.panel{background:rgba(16,24,38,.65);border:1px solid var(--border);border-radius:16px;padding:14px;backdrop-filter: blur(8px)}
.controls{display:grid;grid-template-columns:1.2fr .6fr .6fr .6fr .6fr;gap:10px}
.controls input,.controls select{width:100%;padding:10px 10px;border-radius:12px;border:1px solid var(--border);background:#0b1320;color:var(--text);outline:none}
.controls input::placeholder{color:#6f84a6}
.grid{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin-top:14px}
@media (max-width:1100px){.grid{grid-template-columns:repeat(3,1fr)}.controls{grid-template-columns:1fr 1fr 1fr}}
@media (max-width:760px){.grid{grid-template-columns:repeat(2,1fr)}}
@media (max-width:520px){.grid{grid-template-columns:1fr}}
.card{background:rgba(16,24,38,.8);border:1px solid var(--border);border-radius:16px;overflow:hidden;display:flex;flex-direction:column;min-height:210px}
.thumb{aspect-ratio:16/10;background:#0b1320;display:flex;align-items:center;justify-content:center}
.thumb img{width:100%;height:100%;object-fit:cover;display:block}
.meta{padding:12px;display:flex;flex-direction:column;gap:8px}
.name{font-weight:650;line-height:1.2}
.small{font-size:12px;color:var(--muted);word-break:break-word}
.row{display:flex;gap:8px;flex-wrap:wrap}
.pill{font-size:12px;color:var(--text);padding:4px 8px;border-radius:999px;background:rgba(147,164,191,.10);border:1px solid rgba(147,164,191,.18)}
.footer{margin-top:18px;color:var(--muted);font-size:13px;display:flex;justify-content:space-between;flex-wrap:wrap;gap:10px}
.btn{display:inline-flex;align-items:center;gap:8px;padding:10px 12px;border-radius:12px;background:rgba(74,163,255,.12);border:1px solid rgba(74,163,255,.25);color:var(--text)}
.btn:hover{background:rgba(74,163,255,.18);text-decoration:none}
CSS

cat > "${SITE_DIR}/app.js" <<'JS'
const state={all:[],filtered:[],type:"all",q:"",sort:"title_asc",rarity:"all",creator:"all",purchasable:"all"};
const el=(id)=>document.getElementById(id);
const fmt=(v)=>(v===null||v===undefined||v==="")?"—":String(v);
const safeLower=(v)=>(v||"").toString().toLowerCase();
async function fetchJson(path){const r=await fetch(path,{cache:"no-store"});if(!r.ok) throw new Error(`Failed to load ${path}`);return await r.json();}
function buildFacets(items){const rarities=new Set();const creators=new Set();for(const it of items){if(it.rarity!==null&&it.rarity!==undefined) rarities.add(String(it.rarity));if(it.creatorName) creators.add(String(it.creatorName));}return{rarities:Array.from(rarities).sort((a,b)=>a.localeCompare(b)),creators:Array.from(creators).sort((a,b)=>a.localeCompare(b))};}
function setSelectOptions(select,values,allLabel){const cur=select.value;select.innerHTML="";const optAll=document.createElement("option");optAll.value="all";optAll.textContent=allLabel;select.appendChild(optAll);for(const v of values){const o=document.createElement("option");o.value=v;o.textContent=v;select.appendChild(o);}if([...select.options].some(o=>o.value===cur)) select.value=cur;}
function applyFilters(){const q=safeLower(state.q).trim();let items=state.all;
if(state.type!=="all") items=items.filter(x=>x.kind===state.type);
if(state.rarity!=="all") items=items.filter(x=>String(x.rarity)===state.rarity);
if(state.creator!=="all") items=items.filter(x=>String(x.creatorName||"")===state.creator);
if(state.purchasable!=="all"){const want=state.purchasable==="true";items=items.filter(x=>Boolean(x.purchasable)===want);}
if(q){items=items.filter(x=>{const hay=[x.title,x.uuid,x.offerId,x.creatorName,x.pieceType,...(Array.isArray(x.keywords)?x.keywords:[])].map(safeLower).join(" ");return hay.includes(q);});}
items=items.slice();
const s=state.sort;
const by=(fn,dir)=>items.sort((a,b)=>{const av=fn(a),bv=fn(b);if(av===bv) return 0;if(av===null||av===undefined) return 1;if(bv===null||bv===undefined) return -1;return dir*String(av).localeCompare(String(bv),undefined,{numeric:true,sensitivity:"base"});});
if(s==="title_asc") by(x=>x.title,1);
if(s==="title_desc") by(x=>x.title,-1);
if(s==="modified_desc") by(x=>x.lastModifiedDate,-1);
if(s==="start_desc") by(x=>x.startDate,-1);
if(s==="price_asc") items.sort((a,b)=>(a.price??1e18)-(b.price??1e18));
if(s==="price_desc") items.sort((a,b)=>(b.price??-1)-(a.price??-1));
state.filtered=items;render();}
function card(item){const img=item.image?`<img loading="lazy" src="${item.image}" alt="">`:"";
const rarity=item.rarity!==null?`<span class="pill">Rarity: ${fmt(item.rarity)}</span>`:"";
const price=item.price!==null?`<span class="pill">Price: ${fmt(item.price)}</span>`:"";
const purch=item.purchasable!==null?`<span class="pill">Purchasable: ${item.purchasable?"Yes":"No"}</span>`:"";
const type=`<span class="pill">${item.kind}</span>`;
const pieceType=item.pieceType?`<span class="pill">${item.pieceType}</span>`:"";
const creator=`<div class="small">Creator: ${fmt(item.creatorName)}</div>`;
const uuid=`<div class="small">UUID: ${fmt(item.uuid)}</div>`;
return `<div class="card"><div class="thumb">${img}</div><div class="meta"><div class="name">${fmt(item.title)}</div><div class="row">${type}${pieceType}${rarity}${price}${purch}</div>${creator}${uuid}</div></div>`;}
function render(){el("count").textContent=`${state.filtered.length.toLocaleString()} items`;const html=state.filtered.slice(0,2000).map(card).join("");el("grid").innerHTML=html||`<div class="small">No results.</div>`;if(state.filtered.length>2000){el("grid").insertAdjacentHTML("beforeend",`<div class="small">Showing first 2000 results. Refine filters to see more.</div>`);}}
async function init(){const idx=await fetchJson("./index.json");
el("updatedAt").textContent=`Updated: ${idx.updatedAt}`;
el("counts").textContent=`Emotes: ${idx.counts.persona_emote.toLocaleString()} • Pieces: ${idx.counts.persona_piece.toLocaleString()}`;
const emotes=await fetchJson("./data/persona_emote/items.json");
const pieces=await fetchJson("./data/persona_piece/items.json");
state.all=[...emotes.map(x=>({...x,kind:"persona_emote"})),...pieces.map(x=>({...x,kind:"persona_piece"}))];
const facets=buildFacets(state.all);
setSelectOptions(el("rarity"),facets.rarities,"All rarities");
setSelectOptions(el("creator"),facets.creators,"All creators");
el("q").addEventListener("input",(e)=>{state.q=e.target.value;applyFilters();});
el("type").addEventListener("change",(e)=>{state.type=e.target.value;applyFilters();});
el("sort").addEventListener("change",(e)=>{state.sort=e.target.value;applyFilters();});
el("rarity").addEventListener("change",(e)=>{state.rarity=e.target.value;applyFilters();});
el("creator").addEventListener("change",(e)=>{state.creator=e.target.value;applyFilters();});
el("purchasable").addEventListener("change",(e)=>{state.purchasable=e.target.value;applyFilters();});
state.filtered=state.all.slice();applyFilters();}
init().catch(err=>{el("grid").innerHTML=`<div class="small">Failed to load data: ${err.message}</div>`;});
JS

cat > "${SITE_DIR}/index.html" <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Persona Assets</title>
  <link rel="stylesheet" href="./styles.css" />
</head>
<body>
  <div class="container">
    <div class="header">
      <div class="title">
        <h1>Persona Assets</h1>
        <div class="subtitle">
          <span id="updatedAt">Updated: —</span> • <span id="counts">—</span>
        </div>
      </div>
      <div class="badges">
        <span class="badge" id="count">—</span>
        <a class="btn" href="./data/persona_emote/items.json" target="_blank" rel="noreferrer">Emotes JSON</a>
        <a class="btn" href="./data/persona_piece/items.json" target="_blank" rel="noreferrer">Pieces JSON</a>
      </div>
    </div>

    <div class="panel">
      <div class="controls">
        <input id="q" placeholder="Search title, uuid, creator, keywords..." />
        <select id="type">
          <option value="all">All types</option>
          <option value="persona_emote">persona_emote</option>
          <option value="persona_piece">persona_piece</option>
        </select>
        <select id="rarity"></select>
        <select id="creator"></select>
        <select id="purchasable">
          <option value="all">Purchasable: any</option>
          <option value="true">Purchasable: yes</option>
          <option value="false">Purchasable: no</option>
        </select>
      </div>

      <div style="margin-top:10px; display:flex; justify-content:space-between; gap:10px; flex-wrap:wrap;">
        <div class="small">Tip: sort by last modified to catch new updates quickly.</div>
        <div style="min-width:240px;">
          <select id="sort" style="width:100%; padding:10px 10px; border-radius:12px; border:1px solid var(--border); background:#0b1320; color:var(--text);">
            <option value="title_asc">Sort: Title (A→Z)</option>
            <option value="title_desc">Sort: Title (Z→A)</option>
            <option value="modified_desc">Sort: LastModifiedDate (newest)</option>
            <option value="start_desc">Sort: StartDate (newest)</option>
            <option value="price_asc">Sort: Price (low→high)</option>
            <option value="price_desc">Sort: Price (high→low)</option>
          </select>
        </div>
      </div>

      <div id="grid" class="grid"></div>

      <div class="footer">
        <div>Data source: PlayFab Economy v2 Catalog/Search</div>
        <div>UI shows up to 2000 results — use filters to narrow.</div>
      </div>
    </div>
  </div>

  <script src="./app.js"></script>
</body>
</html>
HTML

{
  echo "# Persona Assets"
  echo
  echo "Automated dataset and web viewer for Minecraft Bedrock Persona catalog assets (PlayFab Economy v2)."
  echo
  if [ -n "${PAGES_URL}" ]; then
    echo "## Live Web UI"
    echo
    echo "- ${PAGES_URL}"
    echo
  fi
  echo "## Update Schedule"
  echo
  echo "- Runs on push and every 6 hours via GitHub Actions"
  echo "- Last update (UTC): ${UPDATED_AT}"
  echo
  echo "## Counts"
  echo
  echo "- persona_emote: ${EMOTE_COUNT} (${EMOTE_SUMMARY})"
  echo "- persona_piece: ${PIECE_COUNT} (${PIECE_SUMMARY})"
  echo
  echo "## Files"
  echo
  echo "- data/index.json"
  echo "- data/persona_emote/items.json"
  echo "- data/persona_piece/items.json"
  echo "- data/*/metadata.json"
  echo "- site/ (GitHub Pages output)"
  echo
  echo "## Setup"
  echo
  echo "1. Add .github/workflows/main.yml and update.sh"
  echo "2. Add Actions secret IOS_DEVICE_ID"
  echo "3. Enable GitHub Pages: Settings → Pages → Source: GitHub Actions"
  echo "4. Run the workflow once"
} > "${ROOT_DIR}/README.md"

jq -nc --arg ts "${UPDATED_AT}" '{updatedAt:$ts}' > "${STATE_DIR}/global.json"
