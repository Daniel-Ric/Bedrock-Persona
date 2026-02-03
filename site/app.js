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
