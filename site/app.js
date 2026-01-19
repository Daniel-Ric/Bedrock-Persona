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
