const PAGE_SIZE = 100;
const state = {
  all: [], filtered: [], type: "all", q: "", sort: "title_asc", rarity: "all",
  creator: "all", purchasable: "all", favoritesOnly: false, favorites: new Set(),
  visible: PAGE_SIZE, view: "grid"
};

const el = (id) => document.getElementById(id);
const fmt = (value) => value === null || value === undefined || value === "" ? "—" : String(value);
const safeLower = (value) => (value || "").toString().toLowerCase();
const escapeHtml = (value) => fmt(value).replace(/[&<>'"]/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[character]);
const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });
const dateFormatter = new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" });
const numberFormatter = new Intl.NumberFormat();

async function fetchJson(path) {
  const response = await fetch(path, { cache: "no-store" });
  if (!response.ok) throw new Error(`Failed to load ${path}`);
  return response.json();
}

function formatDate(value) {
  if (!value) return "—";
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? fmt(value) : dateFormatter.format(date);
}

function humanize(value) {
  return fmt(value).replace(/^persona_/, "").replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function loadPreferences() {
  try { state.favorites = new Set(JSON.parse(localStorage.getItem("persona-favorites") || "[]")); } catch { state.favorites = new Set(); }
  state.view = localStorage.getItem("persona-view") === "list" ? "list" : "grid";
}

function readUrlState() {
  const params = new URLSearchParams(location.search);
  for (const key of ["q", "type", "rarity", "creator", "purchasable", "sort"]) {
    if (params.has(key)) state[key] = params.get(key);
  }
}

function writeUrlState() {
  const params = new URLSearchParams();
  const defaults = { q: "", type: "all", rarity: "all", creator: "all", purchasable: "all", sort: "title_asc" };
  for (const [key, defaultValue] of Object.entries(defaults)) if (state[key] !== defaultValue) params.set(key, state[key]);
  const query = params.toString();
  history.replaceState(null, "", `${location.pathname}${query ? `?${query}` : ""}${location.hash}`);
}

function buildFacets(items) {
  const rarities = new Set();
  const creators = new Set();
  for (const item of items) {
    if (item.rarity !== null && item.rarity !== undefined) rarities.add(String(item.rarity));
    if (item.creatorName) creators.add(String(item.creatorName));
  }
  return {
    rarities: Array.from(rarities).sort(collator.compare),
    creators: Array.from(creators).sort(collator.compare)
  };
}

function setSelectOptions(select, values, allLabel) {
  select.replaceChildren(new Option(allLabel, "all"), ...values.map((value) => new Option(value, value)));
}

function isFiltering() {
  return state.q || state.type !== "all" || state.rarity !== "all" || state.creator !== "all" || state.purchasable !== "all" || state.sort !== "title_asc" || state.favoritesOnly;
}

function applyFilters({ resetPage = true } = {}) {
  const query = safeLower(state.q).trim();
  let items = state.all;
  if (state.type !== "all") items = items.filter((item) => item.kind === state.type);
  if (state.rarity !== "all") items = items.filter((item) => String(item.rarity) === state.rarity);
  if (state.creator !== "all") items = items.filter((item) => String(item.creatorName || "") === state.creator);
  if (state.purchasable !== "all") {
    const target = state.purchasable === "true";
    items = items.filter((item) => item.purchasable !== null && Boolean(item.purchasable) === target);
  }
  if (state.favoritesOnly) items = items.filter((item) => state.favorites.has(item.uuid));
  if (query) items = items.filter((item) => item.searchKey.includes(query));
  items = items.slice();
  const by = (getter, direction) => items.sort((a, b) => {
    const first = getter(a), second = getter(b);
    if (first === second) return 0;
    if (first === null || first === undefined) return 1;
    if (second === null || second === undefined) return -1;
    return direction * collator.compare(String(first), String(second));
  });
  if (state.sort === "title_asc") by((item) => item.title, 1);
  if (state.sort === "title_desc") by((item) => item.title, -1);
  if (state.sort === "modified_desc") by((item) => item.lastModifiedDate, -1);
  if (state.sort === "start_desc") by((item) => item.startDate, -1);
  if (state.sort === "price_asc") items.sort((a, b) => (a.price ?? Infinity) - (b.price ?? Infinity));
  if (state.sort === "price_desc") items.sort((a, b) => (b.price ?? -Infinity) - (a.price ?? -Infinity));
  state.filtered = items;
  if (resetPage) state.visible = PAGE_SIZE;
  writeUrlState();
  render();
}

function assetCard(item) {
  const saved = state.favorites.has(item.uuid);
  const image = item.image
    ? `<img loading="lazy" src="${escapeHtml(item.image)}" alt="" class="h-full w-full object-cover" onerror="this.hidden=true;this.nextElementSibling.hidden=false"><span class="text-xs text-mauve-600" hidden>Preview unavailable</span>`
    : `<span class="text-xs text-mauve-600">No preview</span>`;
  const price = item.price === null ? "Not listed" : `${numberFormatter.format(item.price)} Minecoins`;
  return `<article class="asset-card group relative bg-mauve-925" data-uuid="${escapeHtml(item.uuid)}">
    <button type="button" class="asset-image flex aspect-square w-full items-center justify-center overflow-hidden bg-mauve-950 text-left focus:outline-none focus:ring-2 focus:ring-inset focus:ring-mauve-400" data-action="details" aria-label="View details for ${escapeHtml(item.title)}">${image}</button>
    <div class="asset-body min-w-0 p-3.5">
      <div class="min-w-0">
        <div class="mb-2 flex items-start justify-between gap-3">
          <button type="button" class="min-w-0 text-left focus:outline-none focus:ring-2 focus:ring-mauve-400" data-action="details"><h3 class="truncate text-sm font-semibold text-mauve-50 group-hover:text-white">${escapeHtml(item.title)}</h3></button>
          <button type="button" class="-mr-1 -mt-1 grid h-8 w-8 shrink-0 place-items-center text-lg ${saved ? "text-mauve-200" : "text-mauve-600 hover:text-mauve-300"} focus:outline-none focus:ring-2 focus:ring-mauve-400" data-action="favorite" aria-label="${saved ? "Remove from" : "Save to"} favorites" aria-pressed="${saved}">${saved ? "★" : "☆"}</button>
        </div>
        <p class="truncate text-xs text-mauve-400">${escapeHtml(item.creatorName || "Unknown creator")}</p>
      </div>
      <dl class="mt-4 grid grid-cols-2 gap-x-3 gap-y-2 text-xs">
        <div><dt class="text-[10px] uppercase tracking-wider text-mauve-600">Type</dt><dd class="mt-0.5 truncate text-mauve-300">${escapeHtml(humanize(item.pieceType || item.kind))}</dd></div>
        <div><dt class="text-[10px] uppercase tracking-wider text-mauve-600">Rarity</dt><dd class="mt-0.5 truncate text-mauve-300">${escapeHtml(humanize(item.rarity))}</dd></div>
      </dl>
      <div class="mt-4 flex items-center justify-between gap-3 border-t border-mauve-800 pt-3">
        <span class="truncate text-xs font-semibold text-mauve-300">${escapeHtml(price)}</span>
        <button type="button" class="text-[11px] font-semibold uppercase tracking-wider text-mauve-500 hover:text-mauve-200 focus:outline-none focus:ring-2 focus:ring-mauve-400" data-action="copy">Copy UUID</button>
      </div>
    </div>
  </article>`;
}

function emptyState() {
  const message = state.favoritesOnly && state.favorites.size === 0 ? "Save assets with the star to build a shortlist." : "No assets match the current filters.";
  return `<div class="col-span-full bg-mauve-925 px-6 py-16 text-center"><p class="text-sm font-semibold text-mauve-200">Nothing to show</p><p class="mt-2 text-sm text-mauve-500">${message}</p>${isFiltering() ? '<button type="button" class="mt-5 border border-mauve-700 px-4 py-2 text-xs font-semibold text-mauve-200 hover:bg-mauve-850" data-action="reset">Reset filters</button>' : ""}</div>`;
}

function render() {
  const shown = Math.min(state.visible, state.filtered.length);
  el("grid").dataset.view = state.view;
  el("grid").innerHTML = state.filtered.length ? state.filtered.slice(0, shown).map(assetCard).join("") : emptyState();
  el("resultSummary").textContent = `${numberFormatter.format(state.filtered.length)} ${state.filtered.length === 1 ? "asset" : "assets"}`;
  el("favoriteCount").textContent = numberFormatter.format(state.favorites.size);
  el("clearSearch").hidden = !state.q;
  el("resetFilters").hidden = !isFiltering();
  el("favoritesOnly").setAttribute("aria-pressed", String(state.favoritesOnly));
  el("favoritesOnly").classList.toggle("bg-mauve-700", state.favoritesOnly);
  el("favoritesOnly").classList.toggle("text-mauve-50", state.favoritesOnly);
  el("loadMoreWrap").hidden = shown >= state.filtered.length;
  el("showingCount").textContent = `Showing ${numberFormatter.format(shown)} of ${numberFormatter.format(state.filtered.length)}`;
}

function setView(view) {
  state.view = view;
  localStorage.setItem("persona-view", view);
  for (const name of ["grid", "list"]) {
    const button = el(`${name}View`);
    const active = name === view;
    button.setAttribute("aria-pressed", String(active));
    button.classList.toggle("bg-mauve-700", active);
    button.classList.toggle("text-mauve-50", active);
    button.classList.toggle("text-mauve-400", !active);
  }
  render();
}

function toggleFavorite(uuid) {
  if (state.favorites.has(uuid)) state.favorites.delete(uuid); else state.favorites.add(uuid);
  localStorage.setItem("persona-favorites", JSON.stringify([...state.favorites]));
  applyFilters({ resetPage: false });
}

function resetFilters() {
  Object.assign(state, { q: "", type: "all", rarity: "all", creator: "all", purchasable: "all", sort: "title_asc", favoritesOnly: false });
  for (const id of ["q", "type", "rarity", "creator", "purchasable", "sort"]) el(id).value = state[id];
  applyFilters();
}

let toastTimer;
function toast(message) {
  clearTimeout(toastTimer);
  el("toast").textContent = message;
  el("toast").hidden = false;
  toastTimer = setTimeout(() => { el("toast").hidden = true; }, 1800);
}

async function copyUuid(uuid) {
  try { await navigator.clipboard.writeText(uuid); toast("UUID copied"); }
  catch { toast("Could not access clipboard"); }
}

function detailRow(label, value, copyValue = "") {
  const copy = copyValue ? `<button type="button" class="text-[10px] font-semibold uppercase tracking-wider text-mauve-500 hover:text-mauve-200 focus:outline-none focus:ring-2 focus:ring-mauve-400" data-copy="${escapeHtml(copyValue)}">Copy</button>` : "";
  return `<div class="border-t border-mauve-800 py-3"><dt class="text-[10px] font-semibold uppercase tracking-[0.14em] text-mauve-600">${label}</dt><dd class="mt-1 flex items-start justify-between gap-4 break-all text-sm text-mauve-200"><span>${escapeHtml(value)}</span>${copy}</dd></div>`;
}

function openDetails(item) {
  const saved = state.favorites.has(item.uuid);
  const keywords = Array.isArray(item.keywords) && item.keywords.length ? item.keywords.join(", ") : "—";
  const image = item.image ? `<img src="${escapeHtml(item.image)}" alt="" class="h-full w-full object-cover">` : '<span class="text-sm text-mauve-600">No preview</span>';
  el("detailContent").innerHTML = `<div class="flex items-center justify-between border-b border-mauve-800 px-4 py-3"><p class="text-[11px] font-semibold uppercase tracking-[0.16em] text-mauve-500">Asset details</p><button id="closeDialog" type="button" class="grid h-8 w-8 place-items-center text-xl text-mauve-400 hover:text-mauve-100 focus:outline-none focus:ring-2 focus:ring-mauve-400" aria-label="Close">×</button></div>
    <div class="grid md:grid-cols-[minmax(0,0.9fr)_minmax(0,1.1fr)]">
      <div class="flex min-h-64 items-center justify-center bg-mauve-950">${image}</div>
      <div class="p-5 sm:p-6"><div class="flex items-start justify-between gap-4"><div><h2 class="text-xl font-semibold text-mauve-50">${escapeHtml(item.title)}</h2><p class="mt-1 text-sm text-mauve-400">${escapeHtml(item.creatorName || "Unknown creator")}</p></div><button type="button" class="border border-mauve-700 px-3 py-2 text-xs font-semibold text-mauve-200 hover:bg-mauve-850 focus:outline-none focus:ring-2 focus:ring-mauve-400" data-favorite="${escapeHtml(item.uuid)}">${saved ? "★ Saved" : "☆ Save"}</button></div>
      <dl class="mt-6">${detailRow("UUID", item.uuid, item.uuid)}${detailRow("Offer ID", item.offerId, item.offerId)}${detailRow("Piece type", humanize(item.pieceType))}${detailRow("Rarity", humanize(item.rarity))}${detailRow("Price", item.price === null ? "Not listed" : `${numberFormatter.format(item.price)} Minecoins`)}${detailRow("Purchasable", item.purchasable === null ? "Unknown" : item.purchasable ? "Yes" : "No")}${detailRow("Modified", formatDate(item.lastModifiedDate))}${detailRow("Created", formatDate(item.creationDate))}${detailRow("Keywords", keywords)}</dl></div>
    </div>`;
  el("detailDialog").showModal();
  el("closeDialog").focus();
}

function bindControls() {
  for (const id of ["type", "rarity", "creator", "purchasable", "sort"]) {
    el(id).addEventListener("change", (event) => { state[id] = event.target.value; applyFilters(); });
  }
  el("q").addEventListener("input", (event) => { state.q = event.target.value; applyFilters(); });
  el("clearSearch").addEventListener("click", () => { state.q = ""; el("q").value = ""; el("q").focus(); applyFilters(); });
  el("resetFilters").addEventListener("click", resetFilters);
  el("favoritesOnly").addEventListener("click", () => { state.favoritesOnly = !state.favoritesOnly; applyFilters(); });
  el("gridView").addEventListener("click", () => setView("grid"));
  el("listView").addEventListener("click", () => setView("list"));
  el("loadMore").addEventListener("click", () => { state.visible += PAGE_SIZE; render(); });
  el("grid").addEventListener("click", (event) => {
    const control = event.target.closest("[data-action]");
    if (!control) return;
    if (control.dataset.action === "reset") return resetFilters();
    const card = control.closest("[data-uuid]");
    const item = card && state.all.find((candidate) => candidate.uuid === card.dataset.uuid);
    if (!item) return;
    if (control.dataset.action === "details") openDetails(item);
    if (control.dataset.action === "favorite") toggleFavorite(item.uuid);
    if (control.dataset.action === "copy") copyUuid(item.uuid);
  });
  el("detailDialog").addEventListener("click", (event) => {
    if (event.target === el("detailDialog")) el("detailDialog").close();
    if (event.target.closest("#closeDialog")) el("detailDialog").close();
    const copyButton = event.target.closest("[data-copy]");
    if (copyButton) copyUuid(copyButton.dataset.copy);
    const favoriteButton = event.target.closest("[data-favorite]");
    if (favoriteButton) {
      const uuid = favoriteButton.dataset.favorite;
      toggleFavorite(uuid);
      el("detailDialog").close();
      openDetails(state.all.find((item) => item.uuid === uuid));
    }
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "/" && !["INPUT", "SELECT", "TEXTAREA"].includes(document.activeElement.tagName)) { event.preventDefault(); el("q").focus(); }
  });
}

async function init() {
  loadPreferences();
  readUrlState();
  const [index, emotes, pieces] = await Promise.all([
    fetchJson("./index.json"), fetchJson("./data/persona_emote/items.json"), fetchJson("./data/persona_piece/items.json")
  ]);
  el("totalCount").textContent = `${numberFormatter.format(emotes.length + pieces.length)} assets`;
  el("counts").textContent = `${numberFormatter.format(emotes.length)} emotes · ${numberFormatter.format(pieces.length)} pieces`;
  el("updatedAt").textContent = formatDate(index.updatedAt);
  state.all = [...emotes.map((item) => ({ ...item, kind: "persona_emote" })), ...pieces.map((item) => ({ ...item, kind: "persona_piece" }))].map((item) => ({
    ...item,
    searchKey: [item.title, item.uuid, item.offerId, item.creatorName, item.pieceType, ...(Array.isArray(item.keywords) ? item.keywords : [])].map(safeLower).join(" ")
  }));
  const facets = buildFacets(state.all);
  setSelectOptions(el("rarity"), facets.rarities, "All rarities");
  setSelectOptions(el("creator"), facets.creators, "All creators");
  el("q").value = state.q;
  const defaults = { type: "all", rarity: "all", creator: "all", purchasable: "all", sort: "title_asc" };
  for (const id of Object.keys(defaults)) {
    if (Array.from(el(id).options).some((option) => option.value === state[id])) el(id).value = state[id];
    else { state[id] = defaults[id]; el(id).value = defaults[id]; }
  }
  bindControls();
  setView(state.view);
  applyFilters();
}

init().catch((error) => {
  el("resultSummary").textContent = "Catalog unavailable";
  el("grid").innerHTML = `<div class="col-span-full bg-mauve-925 px-6 py-16 text-center"><p class="text-sm font-semibold text-mauve-200">Could not load the catalog</p><p class="mt-2 text-sm text-mauve-500">${escapeHtml(error.message)}</p></div>`;
});
