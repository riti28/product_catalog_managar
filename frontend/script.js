const API_BASE_URL = "http://127.0.0.1:8080";
const PLACEHOLDER = "data:image/svg+xml;charset=UTF-8,%3Csvg xmlns='http://www.w3.org/2000/svg' width='420' height='300'%3E%3Crect width='100%25' height='100%25' fill='%23eef2f7'/%3E%3Cpath d='M105 210h210l-52-68-38 46-28-34z' fill='%23c7d2fe'/%3E%3Ccircle cx='155' cy='112' r='24' fill='%2394a3b8'/%3E%3Ctext x='50%25' y='265' dominant-baseline='middle' text-anchor='middle' fill='%23667085' font-family='Arial' font-size='18'%3ENo product image%3C/text%3E%3C/svg%3E";

const state = {
  page: 1,
  limit: 24,
  totalPages: 1,
  search: "",
  category: "",
  brand: "",
  sort: "popularity",
  products: [],
  analytics: null,
  deleteId: null
};

const currency = new Intl.NumberFormat("en-IN", {
  style: "currency",
  currency: "INR",
  maximumFractionDigits: 0
});

const qs = (id) => document.getElementById(id);
const productGrid = qs("productGrid");
const loading = qs("loading");
const emptyState = qs("emptyState");
const PRODUCT_FORM_IDS = [
  "productId", "productName", "brand", "category", "subCategory", "price",
  "originalPrice", "rating", "reviewCount", "stockQuantity", "imageUrl",
  "productUrl", "seller", "color", "storage", "ram", "battery", "processor",
  "warranty", "features", "description"
];

function escapeHtml(value = "") {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function debounce(fn, delay = 280) {
  let timer;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), delay);
  };
}

async function fetchJson(path, options = {}) {
  const { headers = {}, ...rest } = options;
  const response = await fetch(`${API_BASE_URL}${path}`, {
    cache: "no-store",
    ...rest,
    headers: { "Content-Type": "application/json", ...headers }
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(payload.error || `API ${response.status}`);
  return payload;
}

function setFormError(message = "") {
  qs("formError").textContent = message;
}

function setStatus(online, text) {
  qs("apiStatus").textContent = text;
  qs("apiStatus").classList.toggle("offline", !online);
}

function validateFormSelectors() {
  const missing = PRODUCT_FORM_IDS.filter((id) => !qs(id));
  if (missing.length) {
    throw new Error(`Missing form inputs: ${missing.join(", ")}`);
  }
}

function queryString() {
  const params = new URLSearchParams({ page: state.page, limit: state.limit, sort: state.sort });
  if (state.search) params.set("q", state.search);
  if (state.category) params.set("category", state.category);
  if (state.brand) params.set("brand", state.brand);
  return params.toString();
}

function title(product) {
  return product.product_name || product.name || "Unnamed product";
}

function number(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function cleanText(value, fallback = "") {
  const text = String(value ?? "").trim();
  return text || fallback;
}

function renderMetrics() {
  const summary = state.analytics?.summary || {};
  qs("totalProducts").textContent = number(summary.total_products).toLocaleString("en-IN");
  qs("averagePrice").textContent = currency.format(number(summary.average_price));
  qs("inventoryValue").textContent = currency.format(number(summary.inventory_value));
  qs("lowStockCount").textContent = number(summary.low_stock_count).toLocaleString("en-IN");
}

function renderList(id, rows, valueFn, labelKey = "product_name") {
  const el = qs(id);
  el.innerHTML = "";
  if (!rows?.length) {
    el.innerHTML = '<div class="compact-row"><span>No data</span><strong>-</strong></div>';
    return;
  }
  rows.slice(0, 6).forEach((row) => {
    const label = row[labelKey] || row.main_category || row.brand || title(row);
    const div = document.createElement("div");
    div.className = "compact-row";
    div.innerHTML = `<span title="${escapeHtml(label)}">${escapeHtml(label)}</span><strong>${escapeHtml(valueFn(row))}</strong>`;
    el.appendChild(div);
  });
}

function populateSelect(id, rows, key, label) {
  const select = qs(id);
  const current = select.value;
  select.innerHTML = `<option value="">All ${label}</option>`;
  (rows || []).forEach((row) => {
    if (!row[key]) return;
    const option = document.createElement("option");
    option.value = row[key];
    option.textContent = `${row[key]} (${row.count})`;
    select.appendChild(option);
  });
  select.value = current;
}

function recommendationTitle(key) {
  return key.replaceAll("_", " ").replace(/\b\w/g, (char) => char.toUpperCase());
}

function renderRecommendations() {
  const container = qs("recommendations");
  container.innerHTML = "";
  const recommendations = state.analytics?.recommendations || {};
  Object.entries(recommendations).forEach(([key, rows]) => {
    const first = rows?.[0];
    const card = document.createElement("button");
    card.type = "button";
    card.className = "recommendation-card";
    card.innerHTML = first
      ? `<strong title="${escapeHtml(title(first))}">${escapeHtml(recommendationTitle(key))}</strong><span>${escapeHtml(title(first))}</span><b>${currency.format(number(first.price))}</b>`
      : `<strong>${escapeHtml(recommendationTitle(key))}</strong><span>No matches</span><b>-</b>`;
    if (first?.id) card.addEventListener("click", () => showDetails(first.id));
    container.appendChild(card);
  });
}

function renderAnalytics() {
  renderMetrics();
  populateSelect("categoryFilter", state.analytics?.category_count, "main_category", "Categories");
  populateSelect("brandFilter", state.analytics?.brand_analysis, "brand", "Brands");
  renderList("sellingProducts", state.analytics?.top_selling_products, (row) => currency.format(number(row.price)));
  renderList("categoryStats", state.analytics?.category_count, (row) => row.count, "main_category");
  renderList("brandStats", state.analytics?.brand_analysis, (row) => `${number(row.average_rating).toFixed(1)} rating`, "brand");
  renderList("expensiveProducts", state.analytics?.expensive_products, (row) => currency.format(number(row.price)));
  renderList("ratedProducts", state.analytics?.highest_rated_products, (row) => `${number(row.rating).toFixed(1)} rating`);
  renderList("reviewedProducts", state.analytics?.most_reviewed_products, (row) => number(row.review_count).toLocaleString("en-IN"));
  renderList("discountProducts", state.analytics?.highest_discount_products, (row) => `${number(row.discount_percentage).toFixed(0)}%`);
  renderList("lowStockProducts", state.analytics?.low_stock_products, (row) => `${number(row.stock_quantity)} left`);
  renderList("trendStats", state.analytics?.category_trends, (row) => `${number(row.demand_score).toFixed(1)} demand`, "main_category");
  renderRecommendations();
}

function imageHtml(product) {
  const src = cleanText(product.image_url || product.imageUrl, PLACEHOLDER);
  return `
    <div class="product-image">
      <img loading="lazy" src="${escapeHtml(src)}" alt="${escapeHtml(title(product))}" onerror="this.onerror=null;this.src='${PLACEHOLDER}'">
    </div>`;
}

function safeProductUrl(product) {
  const rawUrl = cleanText(product?.product_url || product?.productUrl || product?.url);
  if (!rawUrl) return "";
  try {
    const url = new URL(rawUrl);
    return ["http:", "https:"].includes(url.protocol) ? url.href : "";
  } catch {
    return "";
  }
}

function productLinkHtml(product, label = "View Product") {
  const url = safeProductUrl(product);
  if (!url) return "";
  return `<a class="product-link" href="${escapeHtml(url)}" target="_blank" rel="noopener noreferrer">${escapeHtml(label)}</a>`;
}

function mergedProductForForm(data) {
  const spec = data?.specifications || {};
  const technical = spec.technical_specifications || {};
  return {
    ...data,
    main_category: data.main_category || spec.category || data.category,
    sub_category: data.sub_category || technical.sub_category,
    rating: data.rating ?? technical.rating,
    review_count: data.review_count ?? technical.review_count,
    stock_quantity: data.stock_quantity ?? technical.stock_quantity,
    stock_status: data.stock_status || technical.stock_status,
    image_url: data.image_url || spec.image_url,
    product_url: data.product_url || spec.product_url,
    seller: spec.seller || data.seller,
    color: spec.color || data.color,
    storage: spec.storage || data.storage,
    RAM: spec.RAM || data.RAM,
    battery: spec.battery || data.battery,
    processor: spec.processor || data.processor,
    warranty: spec.warranty || data.warranty,
    features: spec.features || data.features,
    description: spec.description || data.description
  };
}

function renderProducts(payload) {
  state.products = payload.items || [];
  state.totalPages = payload.total_pages || 1;
  qs("resultInfo").textContent = `${number(payload.total).toLocaleString("en-IN")} products found`;
  qs("pageInfo").textContent = `Page ${payload.page || 1} of ${state.totalPages}`;
  qs("prevPage").disabled = state.page <= 1;
  qs("nextPage").disabled = state.page >= state.totalPages;
  productGrid.innerHTML = "";
  emptyState.hidden = state.products.length > 0;

  state.products.forEach((product) => {
    const card = document.createElement("article");
    card.className = "product-card";
    const productLink = productLinkHtml(product);
    card.innerHTML = `
      ${imageHtml(product)}
      <div class="product-info">
        <h3 title="${escapeHtml(title(product))}">${escapeHtml(title(product))}</h3>
        <div class="line"><span>${escapeHtml(product.brand || "Unknown")}</span><span class="badge">${escapeHtml(product.main_category || "Electronics")}</span></div>
        <div class="line"><span class="price">${currency.format(number(product.price))}</span><span>${number(product.rating).toFixed(1)} rating</span></div>
        <div class="line"><span>${number(product.review_count).toLocaleString("en-IN")} reviews</span><span>${number(product.stock_quantity)} stock</span></div>
        <div class="stock ${number(product.stock_quantity) <= 5 ? "risk" : ""}">${escapeHtml(product.stock_status || "In Stock")}</div>
        <div class="actions">
          <button data-action="details" data-id="${product.id}">View</button>
          <button data-action="edit" data-id="${product.id}">Edit</button>
          <button class="delete-btn" data-action="delete" data-id="${product.id}">Delete</button>
          ${productLink}
        </div>
      </div>`;
    productGrid.appendChild(card);
  });
}

async function loadProducts() {
  loading.hidden = false;
  try {
    const payload = await fetchJson(`/products?${queryString()}`);
    renderProducts(payload);
  } finally {
    loading.hidden = true;
  }
}

async function loadAnalytics() {
  state.analytics = await fetchJson("/analytics");
  renderAnalytics();
}

async function refreshAll() {
  setStatus(true, "Loading");
  try {
    await Promise.all([loadAnalytics(), loadProducts()]);
    setStatus(true, "API Online");
  } catch (error) {
    console.error(error);
    setStatus(false, "API Offline");
    loading.hidden = true;
    emptyState.hidden = false;
    emptyState.textContent = "Start Julia backend/server.jl and refresh.";
  }
}

function listBlock(values) {
  const items = Array.isArray(values) ? values : [];
  if (!items.length) return "<p>No flexible specification list available.</p>";
  return `<ul>${items.slice(0, 8).map((item) => `<li>${escapeHtml(item)}</li>`).join("")}</ul>`;
}

async function showDetails(id) {
  const data = await fetchJson(`/combined/${id}`);
  const spec = data.specifications || {};
  const merged = mergedProductForForm(data);
  qs("dialogTitle").textContent = title(data);
  qs("detailContent").innerHTML = `
    ${imageHtml(merged)}
    <div class="detail-list">
      <div><strong>Brand:</strong> ${escapeHtml(data.brand)}</div>
      <div><strong>Category:</strong> ${escapeHtml(data.main_category)} / ${escapeHtml(data.sub_category || "General")}</div>
      <div><strong>Price:</strong> ${currency.format(number(data.price))}</div>
      <div><strong>Rating:</strong> ${number(data.rating).toFixed(1)} from ${number(data.review_count).toLocaleString("en-IN")} reviews</div>
      <div><strong>Stock:</strong> ${number(data.stock_quantity)} (${escapeHtml(data.stock_status)})</div>
      <div><strong>Color:</strong> ${escapeHtml(spec.color || "Not Available")}</div>
      <div><strong>Storage:</strong> ${escapeHtml(spec.storage || "Not Available")}</div>
      <div><strong>RAM:</strong> ${escapeHtml(spec.RAM || "Not Available")}</div>
      <div><strong>Battery:</strong> ${escapeHtml(spec.battery || "Not Available")}</div>
      <div><strong>Processor:</strong> ${escapeHtml(spec.processor || "Not Available")}</div>
      <div><strong>Warranty:</strong> ${escapeHtml(spec.warranty || "Not Available")}</div>
      <div class="wide-detail">${productLinkHtml(merged, "Open Product Page")}</div>
      <div class="wide-detail"><strong>Description:</strong><p>${escapeHtml(spec.description || data.product_name || "")}</p></div>
      <div class="wide-detail"><strong>Features:</strong>${listBlock(spec.features)}</div>
    </div>`;
  qs("productDialog").showModal();
}

function openForm(product = null) {
  setFormError("");
  qs("productForm").reset();
  qs("formTitle").textContent = product ? "Edit Product" : "Add Product";
  qs("saveProduct").textContent = product ? "Save Changes" : "Save Product";
  qs("productId").value = product?.id || "";
  qs("productName").value = product?.product_name || "";
  qs("brand").value = product?.brand || "";
  qs("category").value = product?.main_category || "";
  qs("subCategory").value = product?.sub_category || "General";
  qs("price").value = product?.price ?? "";
  qs("originalPrice").value = product?.original_price ?? product?.price ?? "";
  qs("rating").value = product?.rating ?? 0;
  qs("reviewCount").value = product?.review_count ?? 0;
  qs("stockQuantity").value = product?.stock_quantity ?? 10;
  qs("imageUrl").value = product?.image_url || "";
  qs("productUrl").value = product?.product_url || "";
  qs("seller").value = product?.seller || "Amazon Marketplace";
  qs("color").value = product?.color || "";
  qs("storage").value = product?.storage || "";
  qs("ram").value = product?.RAM || "";
  qs("battery").value = product?.battery || "";
  qs("processor").value = product?.processor || "";
  qs("warranty").value = product?.warranty || "";
  qs("features").value = Array.isArray(product?.features) ? product.features.join(", ") : product?.features || "";
  qs("description").value = product?.description || "";
  qs("formDialog").showModal();
}

async function openEditForm(id) {
  setStatus(true, "Loading edit");
  try {
    const product = await fetchJson(`/combined/${id}`);
    openForm(mergedProductForForm(product));
    setStatus(true, "API Online");
  } catch (error) {
    console.error(error);
    setStatus(false, "Edit failed");
    alert(`Unable to load product details: ${error.message}`);
  }
}

function commaList(value) {
  return value.split(",").map((item) => item.trim()).filter(Boolean);
}

function formPayload() {
  validateFormSelectors();
  const productName = qs("productName").value.trim();
  const mainCategory = qs("category").value.trim();
  const subCategory = qs("subCategory").value.trim() || "General";
  const price = Number(qs("price").value);
  const originalPriceInput = qs("originalPrice").value;
  const originalPrice = Number(originalPriceInput || qs("price").value);
  const rating = Number(qs("rating").value || 0);
  const reviewCount = Number(qs("reviewCount").value || 0);
  const stockInput = Number(qs("stockQuantity").value || 0);
  const stockQuantity = Number.isFinite(stockInput) ? stockInput : 0;
  const payload = {
    product_name: productName,
    productName,
    name: productName,
    brand: qs("brand").value.trim(),
    main_category: mainCategory,
    mainCategory,
    category: mainCategory,
    sub_category: subCategory,
    subCategory,
    price: Number.isFinite(price) ? price : 0,
    original_price: Number.isFinite(originalPrice) ? originalPrice : 0,
    originalPrice: Number.isFinite(originalPrice) ? originalPrice : 0,
    discount_percentage: 0,
    discountPercentage: 0,
    rating: Number.isFinite(rating) ? rating : 0,
    review_count: Number.isFinite(reviewCount) ? reviewCount : 0,
    reviewCount: Number.isFinite(reviewCount) ? reviewCount : 0,
    reviews: Number.isFinite(reviewCount) ? reviewCount : 0,
    stock_quantity: stockQuantity,
    stockQuantity,
    stock: stockQuantity,
    stock_status: stockQuantity <= 0 ? "Out of Stock" : stockQuantity <= 5 ? "Low Stock" : stockQuantity <= 15 ? "Limited" : "In Stock",
    image_url: qs("imageUrl").value.trim(),
    imageUrl: qs("imageUrl").value.trim(),
    image: qs("imageUrl").value.trim(),
    product_url: qs("productUrl").value.trim(),
    productUrl: qs("productUrl").value.trim(),
    url: qs("productUrl").value.trim(),
    seller: qs("seller").value.trim() || "Amazon Marketplace",
    color: qs("color").value.trim() || "Not Available",
    storage: qs("storage").value.trim() || "Not Available",
    RAM: qs("ram").value.trim() || "Not Available",
    ram: qs("ram").value.trim() || "Not Available",
    battery: qs("battery").value.trim() || "Not Available",
    processor: qs("processor").value.trim() || "Not Available",
    warranty: qs("warranty").value.trim() || "Not Available",
    features: commaList(qs("features").value),
    description: qs("description").value.trim()
  };
  return payload;
}

function debugProductPayload(productData, method, path) {
  console.log("FINAL PRODUCT PAYLOAD:", productData);
  const requiredKeys = ["product_name", "category", "image_url", "price", "rating", "review_count", "stock_quantity"];
  const missingKeys = requiredKeys.filter((key) => !(key in productData));
  const emptyKeys = ["product_name", "category"].filter((key) => !String(productData[key] ?? "").trim());
  console.log("PAYLOAD TRACE:", {
    method,
    path,
    isEmpty: Object.keys(productData).length === 0,
    hasProductName: Boolean(String(productData.product_name ?? "").trim()),
    hasCategory: Boolean(String(productData.category ?? "").trim()),
    hasImageUrl: "image_url" in productData,
    numericFields: {
      price: productData.price,
      original_price: productData.original_price,
      rating: productData.rating,
      review_count: productData.review_count,
      stock_quantity: productData.stock_quantity
    },
    missingKeys,
    emptyKeys
  });
}

async function saveProduct(event) {
  event.preventDefault();
  setFormError("");
  const id = qs("productId").value;
  const productData = formPayload();
  if (!productData.product_name) {
    setFormError("Product name is required.");
    return;
  }
  if (!productData.main_category) {
    setFormError("Category is required.");
    return;
  }
  const saveButton = qs("saveProduct");
  saveButton.disabled = true;
  saveButton.textContent = "Saving...";
  try {
    if (id) {
      const path = `/products/${id}`;
      debugProductPayload(productData, "PUT", path);
      await fetchJson(path, {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(productData)
      });
    } else {
      const path = "/products";
      debugProductPayload(productData, "POST", path);
      await fetchJson(path, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(productData)
      });
    }
    qs("formDialog").close();
    await refreshAll();
  } catch (error) {
    console.error(error);
    setFormError(error.message || "Product could not be saved.");
  } finally {
    saveButton.disabled = false;
    saveButton.textContent = id ? "Save Changes" : "Save Product";
  }
}

function openDelete(product) {
  state.deleteId = product.id;
  qs("deleteText").textContent = `Delete "${title(product)}" from MySQL and MongoDB?`;
  qs("deleteDialog").showModal();
}

async function confirmDelete() {
  if (!state.deleteId) return;
  await fetchJson(`/products/${state.deleteId}`, { method: "DELETE" });
  state.deleteId = null;
  qs("deleteDialog").close();
  await refreshAll();
}

const debouncedSearch = debounce((value) => {
  state.search = value.trim();
  state.page = 1;
  loadProducts();
});

qs("searchInput").addEventListener("input", (event) => debouncedSearch(event.target.value));
qs("categoryFilter").addEventListener("change", (event) => { state.category = event.target.value; state.page = 1; loadProducts(); });
qs("brandFilter").addEventListener("change", (event) => { state.brand = event.target.value; state.page = 1; loadProducts(); });
qs("sortFilter").addEventListener("change", (event) => { state.sort = event.target.value; state.page = 1; loadProducts(); });
qs("prevPage").addEventListener("click", () => { state.page = Math.max(1, state.page - 1); loadProducts(); });
qs("nextPage").addEventListener("click", () => { state.page = Math.min(state.totalPages, state.page + 1); loadProducts(); });
qs("refreshBtn").addEventListener("click", refreshAll);
qs("addProductBtn").addEventListener("click", () => openForm());
qs("closeDialog").addEventListener("click", () => qs("productDialog").close());
qs("closeForm").addEventListener("click", () => qs("formDialog").close());
qs("productForm").addEventListener("submit", saveProduct);
qs("themeToggle").addEventListener("click", () => document.body.classList.toggle("dark"));
qs("closeDelete").addEventListener("click", () => qs("deleteDialog").close());
qs("cancelDelete").addEventListener("click", () => qs("deleteDialog").close());
qs("confirmDelete").addEventListener("click", confirmDelete);

productGrid.addEventListener("click", (event) => {
  const button = event.target.closest("button[data-action]");
  if (!button) return;
  const id = Number(button.dataset.id);
  const product = state.products.find((item) => Number(item.id) === id);
  if (!product && button.dataset.action !== "details") return;
  if (button.dataset.action === "details") showDetails(id);
  if (button.dataset.action === "edit") openEditForm(id);
  if (button.dataset.action === "delete") openDelete(product);
});

refreshAll();
