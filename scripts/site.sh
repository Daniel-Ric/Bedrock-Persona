write_site_assets() {
  cat > "${TMP_DIR}/site/app.js" <<'JS'
const state={all:[],filtered:[],type:"all",q:"",sort:"title_asc",rarity:"all",creator:"all",purchasable:"all"};
const el=(id)=>document.getElementById(id);
const fmt=(v)=>(v===null||v===undefined||v==="")?"—":String(v);
const safeLower=(v)=>(v||"").toString().toLowerCase();
const collator=new Intl.Collator(undefined,{numeric:true,sensitivity:"base"});
async function fetchJson(path){const r=await fetch(path,{cache:"no-store"});if(!r.ok) throw new Error(`Failed to load ${path}`);return await r.json();}
function buildFacets(items){const rarities=new Set();const creators=new Set();for(const it of items){if(it.rarity!==null&&it.rarity!==undefined) rarities.add(String(it.rarity));if(it.creatorName) creators.add(String(it.creatorName));}return{rarities:Array.from(rarities).sort((a,b)=>collator.compare(a,b)),creators:Array.from(creators).sort((a,b)=>collator.compare(a,b))};}
function setSelectOptions(select,values,allLabel){const cur=select.value;select.innerHTML="";const optAll=document.createElement("option");optAll.value="all";optAll.textContent=allLabel;select.appendChild(optAll);for(const v of values){const o=document.createElement("option");o.value=v;o.textContent=v;select.appendChild(o);}if([...select.options].some(o=>o.value===cur)) select.value=cur;}
function applyFilters(){const q=safeLower(state.q).trim();let items=state.all;
if(state.type!=="all") items=items.filter(x=>x.kind===state.type);
if(state.rarity!=="all") items=items.filter(x=>String(x.rarity)===state.rarity);
if(state.creator!=="all") items=items.filter(x=>String(x.creatorName||"")===state.creator);
if(state.purchasable!=="all"){const want=state.purchasable==="true";items=items.filter(x=>Boolean(x.purchasable)===want);}
if(q){items=items.filter(x=>x.searchKey.includes(q));}
items=items.slice();
const s=state.sort;
const by=(fn,dir)=>items.sort((a,b)=>{const av=fn(a),bv=fn(b);if(av===bv) return 0;if(av===null||av===undefined) return 1;if(bv===null||bv===undefined) return -1;return dir*collator.compare(String(av),String(bv));});
if(s==="title_asc") by(x=>x.title,1);
if(s==="title_desc") by(x=>x.title,-1);
if(s==="modified_desc") by(x=>x.lastModifiedDate,-1);
if(s==="start_desc") by(x=>x.startDate,-1);
if(s==="price_asc") items.sort((a,b)=>(a.price??1e18)-(b.price??1e18));
if(s==="price_desc") items.sort((a,b)=>(b.price??-1)-(a.price??-1));
state.filtered=items;render();}
function card(item){const img=item.image?`<img loading="lazy" src="${item.image}" alt="" class="h-full w-full object-cover">`:`<div class="text-xs text-slate-400">No image</div>`;
const rarity=item.rarity!==null?`<span class="inline-flex items-center rounded-full border border-slate-700/70 bg-slate-800/70 px-2.5 py-1 text-xs font-medium">Rarity: ${fmt(item.rarity)}</span>`:"";
const price=item.price!==null?`<span class="inline-flex items-center rounded-full border border-slate-700/70 bg-slate-800/70 px-2.5 py-1 text-xs font-medium">Price: ${fmt(item.price)}</span>`:"";
const purch=item.purchasable!==null?`<span class="inline-flex items-center rounded-full border border-slate-700/70 bg-slate-800/70 px-2.5 py-1 text-xs font-medium">Purchasable: ${item.purchasable?"Yes":"No"}</span>`:"";
const type=`<span class="inline-flex items-center rounded-full border border-indigo-400/30 bg-indigo-500/10 px-2.5 py-1 text-xs font-medium text-indigo-100">${item.kind}</span>`;
const pieceType=item.pieceType?`<span class="inline-flex items-center rounded-full border border-slate-700/70 bg-slate-800/70 px-2.5 py-1 text-xs font-medium">${item.pieceType}</span>`:"";
const creator=`<div class="text-xs text-slate-400">Creator: ${fmt(item.creatorName)}</div>`;
const uuid=`<div class="text-xs text-slate-500">UUID: ${fmt(item.uuid)}</div>`;
return `<div class="group flex h-full flex-col overflow-hidden rounded-2xl border border-slate-800/70 bg-slate-900/60 shadow-lg shadow-slate-950/40 transition hover:-translate-y-1 hover:border-indigo-400/50"><div class="flex aspect-[16/10] items-center justify-center bg-slate-950/60">${img}</div><div class="flex flex-1 flex-col gap-3 p-4"><div class="text-sm font-semibold text-slate-100">${fmt(item.title)}</div><div class="flex flex-wrap gap-2">${type}${pieceType}${rarity}${price}${purch}</div>${creator}${uuid}</div></div>`;}
function render(){el("count").textContent=`${state.filtered.length.toLocaleString()} items`;const limit=2000;const html=state.filtered.slice(0,limit).map(card).join("");el("grid").innerHTML=html||`<div class="rounded-2xl border border-dashed border-slate-700/70 bg-slate-900/40 p-6 text-sm text-slate-400">No results.</div>`;if(state.filtered.length>limit){el("grid").insertAdjacentHTML("beforeend",`<div class="rounded-2xl border border-dashed border-slate-700/70 bg-slate-900/40 p-6 text-sm text-slate-400">Showing first ${limit.toLocaleString()} results. Refine filters to see more.</div>`);}}
async function init(){const idx=await fetchJson("./index.json");
el("updatedAt").textContent=`Updated: ${idx.updatedAt}`;
el("counts").textContent=`Emotes: ${idx.counts.persona_emote.toLocaleString()} • Pieces: ${idx.counts.persona_piece.toLocaleString()}`;
const emotes=await fetchJson("./data/persona_emote/items.json");
const pieces=await fetchJson("./data/persona_piece/items.json");
state.all=[...emotes.map(x=>({...x,kind:"persona_emote"})),...pieces.map(x=>({...x,kind:"persona_piece"}))].map(item=>({
  ...item,
  searchKey:[item.title,item.uuid,item.offerId,item.creatorName,item.pieceType,...(Array.isArray(item.keywords)?item.keywords:[])].map(safeLower).join(" ")
}));
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
init().catch(err=>{el("grid").innerHTML=`<div class="rounded-2xl border border-dashed border-rose-500/40 bg-rose-500/10 p-6 text-sm text-rose-200">Failed to load data: ${err.message}</div>`;});
JS

  cat > "${TMP_DIR}/site/index.html" <<'HTML'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Persona Assets</title>
  <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="min-h-screen bg-slate-950 text-slate-100">
  <div class="relative overflow-hidden">
    <div class="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_top,#1e293b,transparent_55%)]"></div>
    <div class="relative mx-auto flex max-w-6xl flex-col gap-8 px-6 py-10">
      <header class="flex flex-col gap-6 rounded-3xl border border-slate-800/70 bg-slate-900/60 p-6 shadow-xl shadow-slate-950/40 backdrop-blur">
        <div class="flex flex-wrap items-start justify-between gap-6">
          <div>
            <p class="text-xs uppercase tracking-[0.2em] text-slate-400">Minecraft Bedrock</p>
            <h1 class="mt-2 text-3xl font-semibold text-white">Persona Assets</h1>
            <p class="mt-2 text-sm text-slate-400"><span id="updatedAt">Updated: —</span> • <span id="counts">—</span></p>
          </div>
          <div class="flex flex-wrap items-center gap-3">
            <span class="rounded-full border border-indigo-400/40 bg-indigo-500/10 px-4 py-2 text-sm font-medium text-indigo-100" id="count">—</span>
            <a class="inline-flex items-center gap-2 rounded-full border border-slate-700/70 bg-slate-900/60 px-4 py-2 text-sm font-medium text-slate-200 transition hover:border-indigo-400/70 hover:text-white" href="./data/persona_emote/items.json" target="_blank" rel="noreferrer">Emotes JSON</a>
            <a class="inline-flex items-center gap-2 rounded-full border border-slate-700/70 bg-slate-900/60 px-4 py-2 text-sm font-medium text-slate-200 transition hover:border-indigo-400/70 hover:text-white" href="./data/persona_piece/items.json" target="_blank" rel="noreferrer">Pieces JSON</a>
          </div>
        </div>
      </header>

      <section class="rounded-3xl border border-slate-800/70 bg-slate-900/70 p-6 shadow-xl shadow-slate-950/40 backdrop-blur">
        <div class="grid gap-4 md:grid-cols-2 xl:grid-cols-6">
          <input id="q" class="h-12 rounded-2xl border border-slate-800 bg-slate-950/60 px-4 text-sm text-white placeholder:text-slate-500 focus:border-indigo-400/70 focus:outline-none xl:col-span-2" placeholder="Search title, uuid, creator, keywords..." />
          <select id="type" class="h-12 rounded-2xl border border-slate-800 bg-slate-950/60 px-4 text-sm text-white focus:border-indigo-400/70 focus:outline-none">
            <option value="all">All types</option>
            <option value="persona_emote">persona_emote</option>
            <option value="persona_piece">persona_piece</option>
          </select>
          <select id="rarity" class="h-12 rounded-2xl border border-slate-800 bg-slate-950/60 px-4 text-sm text-white focus:border-indigo-400/70 focus:outline-none"></select>
          <select id="creator" class="h-12 rounded-2xl border border-slate-800 bg-slate-950/60 px-4 text-sm text-white focus:border-indigo-400/70 focus:outline-none"></select>
          <select id="purchasable" class="h-12 rounded-2xl border border-slate-800 bg-slate-950/60 px-4 text-sm text-white focus:border-indigo-400/70 focus:outline-none">
            <option value="all">Purchasable: any</option>
            <option value="true">Purchasable: yes</option>
            <option value="false">Purchasable: no</option>
          </select>
        </div>

        <div class="mt-5 flex flex-wrap items-center justify-between gap-4">
          <p class="text-xs text-slate-400">Tip: sort by last modified to catch new updates quickly.</p>
          <div class="w-full sm:w-72">
            <select id="sort" class="h-12 w-full rounded-2xl border border-slate-800 bg-slate-950/60 px-4 text-sm text-white focus:border-indigo-400/70 focus:outline-none">
              <option value="title_asc">Sort: Title (A→Z)</option>
              <option value="title_desc">Sort: Title (Z→A)</option>
              <option value="modified_desc">Sort: LastModifiedDate (newest)</option>
              <option value="start_desc">Sort: StartDate (newest)</option>
              <option value="price_asc">Sort: Price (low→high)</option>
              <option value="price_desc">Sort: Price (high→low)</option>
            </select>
          </div>
        </div>

        <div id="grid" class="mt-6 grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"></div>

        <div class="mt-6 flex flex-wrap justify-between gap-3 text-xs text-slate-400">
          <span>Data source: PlayFab Economy v2 Catalog/Search</span>
          <span>UI shows up to 2000 results — use filters to narrow.</span>
        </div>
      </section>
    </div>
  </div>

  <script src="./app.js"></script>
</body>
</html>
HTML
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
