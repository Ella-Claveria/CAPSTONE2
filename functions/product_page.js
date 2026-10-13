/**
 * The public product page behind a shared link
 * (https://agritrade-bef87.web.app/product/<id>), without Firebase — what
 * may be shown, and the HTML. Kept separate so it can be unit tested (see
 * test/product_page.test.js); public_product.js does the reading.
 *
 * Two rules run through all of it:
 *
 *   1. Nothing leaves here that is not picked out by name. The product
 *      and farmer documents are never passed through — publicProductView
 *      copies the few public fields one by one, so a private field added
 *      to either document later cannot leak by accident.
 *   2. A listing that should not be seen says nothing about itself. A
 *      suspended listing, or one from a farmer who is not approved or is
 *      suspended or banned, is indistinguishable from one that never
 *      existed; an archived one only says it is unavailable.
 */

const SITE = "https://agritrade-bef87.web.app";
const APP_PACKAGE = "com.example.agritrade";

// The official place to get the app (a Play Store listing, or another
// link the team has approved for the public). Empty until there is one:
// the page then says the app is not publicly available yet instead of
// sending anyone to a made-up or temporary address.
const APP_DOWNLOAD_URL = "";

const PRODUCT_ID = /^[A-Za-z0-9_-]{1,64}$/;

function isProductId(id) {
  return typeof id === "string" && PRODUCT_ID.test(id);
}

function text(value, max = 200) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function number(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function httpsUrl(value) {
  const url = text(value, 2000);
  return /^https:\/\/[^\s"'<>]+$/.test(url) ? url : "";
}

/**
 * What the page may show for a product, or why it shows nothing.
 *
 * `product` and `farmer` are the Firestore documents' data (or null);
 * `reviews` is the product's review documents' data.
 *
 *   { state: "not_found" }                    no such listing, or hidden
 *   { state: "unavailable" }                  archived
 *   { state: "active", outOfStock, ... }      the listing
 */
function publicProductView({ id, product, farmer, reviews = [] }) {
  if (!product || !farmer) return { state: "not_found" };
  if (product.isSuspended === true) return { state: "not_found" };
  if (farmer.role !== "farmer" || farmer.approvalStatus !== "approved") return { state: "not_found" };
  if (farmer.accountStatus === "suspended" || farmer.accountStatus === "banned") return { state: "not_found" };
  if (product.isArchived === true) return { state: "unavailable" };

  const quantity = number(product.quantity) ?? 0;
  const unit = text(product.unit, 30) || "unit";
  const images = (Array.isArray(product.imageUrls) ? product.imageUrls : [product.imageUrl])
    .map(httpsUrl)
    .filter(Boolean)
    .slice(0, 8);
  if (images.length === 0 && httpsUrl(product.imageUrl)) images.push(httpsUrl(product.imageUrl));

  const wholesalePrice = product.wholesaleEnabled === true ? number(product.wholesalePrice) : null;
  const reviewCount = Math.max(0, Math.floor(number(product.reviewCount) ?? 0));

  return {
    state: "active",
    id,
    name: text(product.name, 120) || "Product",
    category: text(product.category, 60),
    description: text(product.description, 2000),
    images,
    unit,
    retailPrice: number(product.retailPrice) ?? number(product.price) ?? 0,
    wholesale:
      wholesalePrice === null
        ? null
        : { price: wholesalePrice, minimumQuantity: number(product.wholesaleMinimumQuantity) },
    quantity,
    outOfStock: quantity <= 0,
    delivery: product.deliveryAvailable === true && product.pickupOnly !== true,
    // Pick-up is always possible; where exactly is agreed in the app.
    pickup: true,
    farmer: {
      // The display name and the general area only — never the phone
      // number, address, coordinates, email or anything from verification.
      name: text(farmer.name, 80) || text(farmer.fullName, 80) || "AgriTrade+ Farmer",
      area: [text(farmer.barangay, 60), text(farmer.municipality, 60), text(farmer.province, 60)]
        .filter(Boolean)
        .join(", "),
    },
    rating: reviewCount > 0 ? number(product.rating) : null,
    reviewCount,
    // The rating and what was written, nothing about who wrote it.
    reviews: reviews
      .map((review) => ({
        rating: Math.min(5, Math.max(1, Math.round(number(review.rating) ?? 0))),
        comment: text(review.comment, 400),
        when: review.createdAt && typeof review.createdAt.toDate === "function" ? review.createdAt.toDate() : null,
      }))
      .filter((review) => review.comment)
      .sort((a, b) => (b.when ? b.when.getTime() : 0) - (a.when ? a.when.getTime() : 0))
      .slice(0, 5),
  };
}

// ---------------------------------------------------------------
// HTML
// ---------------------------------------------------------------

function esc(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function peso(amount) {
  return `₱${Number(amount).toLocaleString("en-PH", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
}

function amount(value) {
  return Number(value).toLocaleString("en-PH", { maximumFractionDigits: 2 });
}

function stars(rating) {
  const full = Math.round(rating);
  return "★".repeat(full) + "☆".repeat(5 - full);
}

const STYLE = `
:root{--green:#2E7D32;--dark:#0E3210;--pale:#DCEDC8;--bg:#F7FAF7;--line:#E3EAE3;--text:#1F2A20;--muted:#667066}
*{box-sizing:border-box}
body{margin:0;font-family:Montserrat,system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;background:var(--bg);color:var(--text);-webkit-text-size-adjust:100%}
header{display:flex;align-items:center;gap:10px;padding:12px 16px;background:#fff;border-bottom:1px solid var(--line)}
header img{width:32px;height:32px;border-radius:8px}
header b{font-size:17px;color:var(--dark)}
main{max-width:720px;margin:0 auto;padding:0 0 112px}
.gallery{display:flex;overflow-x:auto;scroll-snap-type:x mandatory;background:#fff;-webkit-overflow-scrolling:touch}
.gallery img{flex:0 0 100%;width:100%;aspect-ratio:4/3;object-fit:cover;scroll-snap-align:center}
.noimg{aspect-ratio:4/3;display:flex;align-items:center;justify-content:center;background:var(--pale);color:var(--green);font-weight:600}
.count{font-size:11.5px;color:var(--muted);text-align:center;padding:6px 0 0}
section{background:#fff;border:1px solid var(--line);border-radius:16px;margin:12px 16px 0;padding:16px}
h1{font-size:21px;line-height:1.25;margin:0 0 6px;color:var(--dark)}
h2{font-size:11px;letter-spacing:.06em;text-transform:uppercase;color:var(--muted);margin:0 0 10px}
.price{font-size:22px;font-weight:700;color:var(--green)}
.price small{font-size:13px;font-weight:500;color:var(--muted)}
.row{display:flex;justify-content:space-between;gap:12px;padding:5px 0;font-size:13.5px}
.row span:first-child{color:var(--muted)}
.row span:last-child{font-weight:600;text-align:right}
.badge{display:inline-block;font-size:11.5px;font-weight:700;border-radius:999px;padding:3px 10px;background:var(--pale);color:var(--dark)}
.badge.out{background:#FDECEC;color:#C62828}
p{font-size:14px;line-height:1.55;margin:0;white-space:pre-line;overflow-wrap:anywhere}
.stars,.row span.stars{color:#F9A825;letter-spacing:1px}
.review{padding:10px 0;border-top:1px solid var(--line)}
.review:first-of-type{border-top:0;padding-top:0}
.review small{color:var(--muted);font-size:11.5px}
.bar{position:fixed;left:0;right:0;bottom:0;background:#fff;border-top:1px solid var(--line);padding:12px 16px calc(12px + env(safe-area-inset-bottom))}
.bar div{max-width:688px;margin:0 auto}
button,.btn{font:inherit;font-size:15px;font-weight:700;border-radius:26px;height:50px;width:100%;border:0;cursor:pointer;display:flex;align-items:center;justify-content:center;text-decoration:none}
.primary{background:var(--dark);color:#fff}
.primary[disabled]{background:#DDD;color:#8F8F8F;cursor:default}
.secondary{background:#fff;color:var(--dark);border:1.5px solid var(--dark)}
.note{font-size:12px;color:var(--muted);text-align:center;margin:8px 0 0}
dialog{border:0;border-radius:22px;padding:24px 20px 18px;width:min(92vw,380px);font-family:inherit;color:var(--text)}
dialog::backdrop{background:rgba(0,0,0,.45)}
dialog h3{font-size:18px;margin:0 0 8px;color:var(--dark);text-align:center}
dialog p{text-align:center;color:var(--muted);margin:0 0 18px}
dialog .btn,dialog button{margin-top:10px}
.link{background:none;height:auto;color:var(--green);font-size:13px;font-weight:600;margin-top:14px;text-decoration:underline}
.empty{text-align:center;padding:72px 24px}
.empty h1{font-size:20px}
.empty p{color:var(--muted)}
`.trim();

function shell({ title, description, image, url, nonce, body, script = "" }) {
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<meta name="description" content="${esc(description)}">
<meta property="og:type" content="product">
<meta property="og:site_name" content="AgriTrade+">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(description)}">
<meta property="og:url" content="${esc(url)}">
${image ? `<meta property="og:image" content="${esc(image)}">\n<meta name="twitter:card" content="summary_large_image">` : `<meta name="twitter:card" content="summary">`}
<meta name="referrer" content="strict-origin">
<link rel="icon" href="/agritrade_favicon.png">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Montserrat:wght@400;500;600;700&display=swap" rel="stylesheet">
<style nonce="${nonce}">${STYLE}</style>
</head>
<body>
<header><img src="/icons/Icon-192.png" alt=""><b>AgriTrade+</b></header>
${body}
${script ? `<script nonce="${nonce}">${script}</script>` : ""}
</body>
</html>`;
}

function messagePage({ heading, message, url, nonce }) {
  return shell({
    title: `${heading} · AgriTrade+`,
    description: message,
    image: "",
    url,
    nonce,
    body: `<main><div class="empty"><h1>${esc(heading)}</h1><p>${esc(message)}</p></div></main>`,
  });
}

// Runs in the visitor's browser: the Order Now dialog. No data is fetched
// and nothing is sent anywhere.
const SCRIPT = `
(function(){
  var d=document.getElementById('app-dialog');
  function open(){ if(d.showModal){d.showModal();}else{d.setAttribute('open','');} }
  function close(){ if(d.close){d.close();}else{d.removeAttribute('open');} }
  var order=document.getElementById('order');
  if(order&&!order.disabled){order.addEventListener('click',open);}
  document.getElementById('later').addEventListener('click',close);
  d.addEventListener('click',function(e){ if(e.target===d){close();} });
  var soon=document.getElementById('download-soon');
  if(soon){soon.addEventListener('click',function(){
    document.getElementById('dialog-message').textContent=
      'The AgriTrade+ app is not available for public download yet. Please check back soon.';
    soon.disabled=true;
  });}
})();
`.trim();

/**
 * The full HTML for `view` (from publicProductView). `nonce` is the
 * per-response value the Content-Security-Policy header allows.
 */
function renderProductPage(view, { id, nonce, downloadUrl = APP_DOWNLOAD_URL } = {}) {
  const url = `${SITE}/product/${isProductId(id) ? id : ""}`;

  if (view.state === "unavailable") {
    return messagePage({
      heading: "This product is currently unavailable.",
      message: "The farmer is not offering this listing right now.",
      url,
      nonce,
    });
  }
  if (view.state !== "active") {
    return messagePage({
      heading: "Product Not Found",
      message: "This listing is no longer available.",
      url,
      nonce,
    });
  }

  const v = view;
  const priceLine = `${peso(v.retailPrice)}/${v.unit}`;
  const summary = [
    priceLine,
    v.outOfStock ? "Out of Stock" : `${amount(v.quantity)} ${v.unit} available`,
    v.farmer.area,
  ]
    .filter(Boolean)
    .join(" · ");

  const gallery = v.images.length
    ? `<div class="gallery">${v.images
        .map((src, i) => `<img src="${esc(src)}" alt="${esc(v.name)} photo ${i + 1}" ${i ? 'loading="lazy"' : ""}>`)
        .join("")}</div>${v.images.length > 1 ? `<div class="count">${v.images.length} photos — swipe to see more</div>` : ""}`
    : `<div class="noimg">No photo</div>`;

  const wholesale = v.wholesale
    ? `<div class="row"><span>Wholesale price</span><span>${esc(peso(v.wholesale.price))}/${esc(v.unit)}</span></div>` +
      (v.wholesale.minimumQuantity
        ? `<div class="row"><span>Minimum wholesale order</span><span>${esc(amount(v.wholesale.minimumQuantity))} ${esc(v.unit)}</span></div>`
        : "")
    : "";

  const fulfilment = v.delivery ? "Delivery and pick-up" : "Pick-up only";

  const reviews =
    v.reviewCount > 0 && v.rating !== null
      ? `<section><h2>Reviews</h2>
<div class="row"><span><span class="stars">${stars(v.rating)}</span> ${esc(v.rating.toFixed(1))} out of 5</span><span>${v.reviewCount} review${v.reviewCount === 1 ? "" : "s"}</span></div>
${v.reviews
  .map(
    (r) =>
      `<div class="review"><div class="stars">${stars(r.rating)}</div><p>${esc(r.comment)}</p><small>Verified buyer${
        r.when ? ` · ${esc(r.when.toLocaleDateString("en-PH", { year: "numeric", month: "short", day: "numeric", timeZone: "Asia/Manila" }))}` : ""
      }</small></div>`
  )
  .join("")}</section>`
      : "";

  const openInApp =
    `intent://product/${esc(v.id)}#Intent;scheme=agritrade;package=${APP_PACKAGE};` +
    `S.browser_fallback_url=${encodeURIComponent(url)};end`;

  const download = httpsUrl(downloadUrl)
    ? `<a class="btn primary" id="download" href="${esc(downloadUrl)}" rel="noopener">Download App</a>`
    : `<button class="primary" id="download-soon" type="button">Download App</button>`;

  const body = `<main>
${gallery}
<section>
<h1>${esc(v.name)}</h1>
<div class="price">${esc(peso(v.retailPrice))}<small>/${esc(v.unit)}</small></div>
<div style="margin-top:10px"><span class="badge${v.outOfStock ? " out" : ""}">${
    v.outOfStock ? "Out of Stock" : `${esc(amount(v.quantity))} ${esc(v.unit)} available`
  }</span></div>
</section>
<section><h2>Pricing</h2>
<div class="row"><span>Retail price</span><span>${esc(priceLine)}</span></div>
${wholesale}
<div class="row"><span>Order options</span><span>${fulfilment}</span></div>
</section>
${v.description ? `<section><h2>Description</h2><p>${esc(v.description)}</p></section>` : ""}
<section><h2>Farmer</h2>
<div class="row"><span>Sold by</span><span>${esc(v.farmer.name)}</span></div>
${v.farmer.area ? `<div class="row"><span>Location</span><span>${esc(v.farmer.area)}</span></div>` : ""}
</section>
${reviews}
</main>
<div class="bar"><div>
<button class="primary" id="order" type="button"${v.outOfStock ? " disabled" : ""}>${v.outOfStock ? "Out of Stock" : "Order Now"}</button>
<div class="note">Ordering is done in the AgriTrade+ mobile app.</div>
</div></div>
<dialog id="app-dialog" aria-labelledby="dialog-title">
<h3 id="dialog-title">Download the App to Order</h3>
<p id="dialog-message">You can view product details here, but ordering is available only through the AgriTrade+ app.</p>
${download}
<button class="secondary" id="later" type="button">Maybe Later</button>
<a class="btn link" href="${openInApp}">I already have the app — open it</a>
</dialog>`;

  return shell({
    title: `${v.name} · AgriTrade+`,
    description: summary,
    image: v.images[0] || "",
    url,
    nonce,
    body,
    script: SCRIPT,
  });
}

module.exports = { APP_DOWNLOAD_URL, isProductId, publicProductView, renderProductPage, esc };
