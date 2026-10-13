// Writes the Compare pages from compare-data.js, keeps the version number and the
// structured data in sync with Resources/Info.plist, and rebuilds sitemap.xml.
//
//   node site/tools/build.mjs
//
// Run it after editing compare-data.js or bumping the version, then commit the output.
import { createRequire } from "node:module";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const site = join(here, "..");
const repo = join(site, "..");
const require = createRequire(import.meta.url);
const { APPS, duelCard, matrix } = require(join(site, "compare-data.js"));

const ORIGIN = "https://glidetab.com";
const ASSET_V = 21;
const TODAY = new Date().toISOString().slice(0, 10);
const VERSION = readFileSync(join(repo, "Resources/Info.plist"), "utf8")
  .match(/CFBundleShortVersionString<\/key>\s*<string>([^<]+)</)[1];

const escape = (s) => s.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");
const ld = (data) => `<script type="application/ld+json">${JSON.stringify(data)}</script>`;

const APP_LD = {
  "@type": "SoftwareApplication",
  "@id": `${ORIGIN}/#app`,
  name: "GlideTab",
  alternateName: "GlideTab for Mac",
  url: ORIGIN,
  applicationCategory: "UtilitiesApplication",
  operatingSystem: "macOS 14 or later",
  softwareVersion: VERSION,
  isAccessibleForFree: true,
  offers: { "@type": "Offer", price: 0, priceCurrency: "USD" },
  license: "https://opensource.org/license/mit",
  downloadUrl: "https://github.com/mohdmahmodi/glidetab/releases/latest/download/GlideTab.zip",
  releaseNotes: "https://github.com/mohdmahmodi/glidetab/releases",
  sameAs: ["https://github.com/mohdmahmodi/glidetab"],
  screenshot: `${ORIGIN}/images/og.png`,
  fileSize: "5MB",
  author: { "@type": "Person", name: "Mohd Mahmodi", url: "https://mohdmahmodi.com", sameAs: ["https://x.com/mohdmahmodi", "https://github.com/mohdmahmodi"] },
  description: "A free, open source window switcher for macOS. Hold Option and press Tab to see every open window with a live preview, type to find one, and let go to switch. Shows browser tabs too.",
  featureList: [
    "Every window, including other Spaces, other displays, minimized windows and hidden apps",
    "Type to search window titles, app names and browser tabs",
    "Thumbnails, app icons or list styles",
    "Up to nine shortcuts, trackpad swipe, or take over Command-Tab",
    "Close, minimize or full screen a window from the switcher",
    "No account, no tracking, nothing leaves the Mac",
  ],
};

function head({ title, description, path, stylesheets = ["styles.css"], jsonLd = [], noindex = false }) {
  const url = ORIGIN + path;
  return `<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escape(title)}</title>
  <meta name="description" content="${escape(description)}">
  <meta name="robots" content="${noindex ? "noindex, follow" : "index, follow, max-image-preview:large, max-snippet:-1"}">
  <link rel="canonical" href="${url}">
  <meta name="theme-color" content="#ececee" media="(prefers-color-scheme: light)">
  <meta name="theme-color" content="#161618" media="(prefers-color-scheme: dark)">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="GlideTab">
  <meta property="og:locale" content="en_US">
  <meta property="og:title" content="${escape(title)}">
  <meta property="og:description" content="${escape(description)}">
  <meta property="og:url" content="${url}">
  <meta property="og:image" content="${ORIGIN}/images/og.png">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta property="og:image:alt" content="The GlideTab switcher showing open Mac windows with live previews">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${escape(title)}">
  <meta name="twitter:description" content="${escape(description)}">
  <meta name="twitter:image" content="${ORIGIN}/images/og.png">
  <meta name="twitter:creator" content="@mohdmahmodi">
  <link rel="icon" href="/favicon.png" type="image/png">
  <link rel="apple-touch-icon" href="/apple-touch-icon.png">
${stylesheets.map((s) => `  <link rel="stylesheet" href="/${s}?v=${ASSET_V}">`).join("\n")}
${jsonLd.map((d) => "  " + ld({ "@context": "https://schema.org", ...d })).join("\n")}
</head>`;
}

const breadcrumbs = (items) => ({
  "@type": "BreadcrumbList",
  itemListElement: items.map(([name, path], i) => ({ "@type": "ListItem", position: i + 1, name, item: ORIGIN + path })),
});

function header(current) {
  const link = (href, label) => `<a href="${href}"${href === current ? ' aria-current="page"' : ""}>${label}</a>`;
  return `<header class="menubar">
  <div class="app-menu" id="app-menu">
    <button class="app-name" aria-haspopup="true" aria-expanded="false"><img src="/images/icon.png" alt=""> GlideTab</button>
    <div class="menu" role="menu">
      <a href="/" role="menuitem">Home</a>
      <a href="https://github.com/mohdmahmodi/glidetab" role="menuitem">View Source on GitHub</a>
      <a href="https://github.com/mohdmahmodi/glidetab/releases" role="menuitem">Release Notes</a>
      <hr>
      <a href="/privacy" role="menuitem">Privacy</a>
    </div>
  </div>
  <nav class="nav" aria-label="Pages">
    ${link("/features", "Features")}
    ${link("/compare", "Compare")}
    <a href="/#faq">Questions</a>
    <a href="https://github.com/mohdmahmodi/glidetab">GitHub</a>
  </nav>
  <div class="spacer"></div>
  <div class="status">
    <button class="icon" id="theme-toggle" aria-label="Switch between light and dark"><svg><use href="/icons.svg#i-appearance"/></svg></button>
    <span class="icon" aria-hidden="true"><svg><use href="/icons.svg#i-wifi"/></svg></span>
    <span class="icon" aria-hidden="true"><svg><use href="/icons.svg#i-battery"/></svg></span>
    <span class="clock" id="clock" aria-hidden="true"></span>
  </div>
  <a class="download" href="https://github.com/mohdmahmodi/glidetab/releases/latest/download/GlideTab.zip">Download</a>
</header>`;
}

const FOOTER = `<footer>
  <div class="wrap">
    <span>© 2026 Mohd Mahmodi. GlideTab is released under the MIT License.</span>
    <nav aria-label="Footer">
      <a href="/">Home</a>
      <a href="/features">Features</a>
      <a href="/compare">Compare</a>
      <a href="/privacy">Privacy</a>
      <a href="https://github.com/mohdmahmodi/glidetab">GitHub</a>
      <a href="https://x.com/mohdmahmodi">X</a>
      <a href="https://mohdmahmodi.com">mohdmahmodi.com</a>
    </nav>
  </div>
</footer>`;

const scripts = (extra = []) => [
  '<script src="https://cdnjs.cloudflare.com/ajax/libs/gsap/3.12.5/gsap.min.js" integrity="sha384-g4NTh/Iv5PPU4xPyhEWqPcwtNXOvdaDI8LLnyYfyNZOjKJeYQyjzQ9X5275eBjpt" crossorigin="anonymous" defer></script>',
  `<script src="/site.js?v=${ASSET_V}" defer></script>`,
  ...extra.map((s) => `<script src="/${s}?v=${ASSET_V}" defer></script>`),
].join("\n");

const download = (secondaryHref, secondaryLabel) => `  <div class="dialog-wrap">
    <div class="dialog" role="group" aria-labelledby="dl-title">
      <img src="/images/icon.png" alt="" width="88" height="88">
      <h2 id="dl-title">Try GlideTab</h2>
      <p>Version <span data-version>${VERSION}</span> for macOS 14 or later.<br>Free, about 5 MB.</p>
      <div class="buttons">
        <a class="button secondary" href="${secondaryHref}">${secondaryLabel}</a>
        <a class="button primary" href="https://github.com/mohdmahmodi/glidetab/releases/latest/download/GlideTab.zip">Download</a>
      </div>
    </div>
  </div>`;

const FOOTNOTE = `<p class="footnote center">As of October 2026, from each developer's website. A dash means the feature isn't offered or isn't documented. Prices in US dollars. Spotted a mistake? <a href="https://github.com/mohdmahmodi/glidetab/issues">Open an issue</a>.</p>`;

const competitors = Object.entries(APPS).filter(([key]) => key !== "glidetab");

// The hub: one picker, every comparison in the page, one shown at a time.
function hub() {
  const views = competitors
    .map(([key, app], i) => `      <div data-view="${key}"${i ? " hidden" : ""}>
${duelCard(key)}
        <p class="center more-link"><a href="/compare/${app.slug}">More about GlideTab vs ${app.name}</a></p>
      </div>`)
    .join("\n");
  const body = `<main class="wrap">
  <div class="page-head center">
    <h1>Compare Mac window switchers</h1>
    <p>GlideTab next to the switchers built into macOS and the apps people use instead of them. Pick one to see how it stacks up.</p>
  </div>

  <div class="picker-row">
    <div class="segmented picker" role="tablist" aria-label="Compare with">
${competitors.map(([key, app]) => `      <button role="tab" data-app="${key}">${app.name}</button>`).join("\n")}
      <button role="tab" data-app="all">All apps</button>
    </div>
  </div>

  <section class="duel" id="duel" aria-live="polite">
${views}
      <div data-view="all" hidden>
${matrix()}
      </div>
  </section>

  ${FOOTNOTE}

  <section class="compare-copy">
    <h2>What to look for in a window switcher</h2>
    <p>The switcher built into every Mac, ⌘Tab, moves between apps, not windows. If you keep several windows of the same app open, it can't take you to a specific one. Every app on this page fixes that in its own way: a grid of previews, a list, a sidebar, or a search field.</p>
    <p>The things that separate them are whether you can see what each window looks like before you pick it, whether you can type a name instead of tapping through the list, whether browser tabs count as windows, which versions of macOS they run on, and what they cost. GlideTab is free and open source, shows live previews, searches as you type, and includes browser tabs. It needs macOS 14 or later.</p>
    <p>Each comparison has its own page: ${competitors.map(([, app]) => `<a href="/compare/${app.slug}">GlideTab vs ${app.name}</a>`).join(", ")}.</p>
  </section>

${download("/features", "All Features")}
</main>`;
  const title = "Compare Mac window switchers: GlideTab vs AltTab, Witch, Contexts";
  const description = "GlideTab next to ⌘Tab, Mission Control, AltTab, Witch, Contexts, HyperSwitch and Raycast: live previews, search, browser tabs, price and source code.";
  return page({
    path: "/compare", title, description, body, current: "/compare", extraScripts: ["compare.js"],
    jsonLd: [
      breadcrumbs([["GlideTab", "/"], ["Compare", "/compare"]]),
      { "@type": "WebPage", "@id": `${ORIGIN}/compare`, name: title, description, about: { "@id": `${ORIGIN}/#app` }, isPartOf: { "@type": "WebSite", url: ORIGIN, name: "GlideTab" } },
    ],
  });
}

// One competitor, with its own text.
function duelPage(key, app) {
  const others = competitors.filter(([k]) => k !== key);
  const body = `<main class="wrap">
  <div class="page-head center">
    <h1>${app.heading}</h1>
    <p>${app.tagline}</p>
  </div>

  <section class="duel">
${duelCard(key)}
  </section>

  ${FOOTNOTE}

  <section class="compare-copy">
    <h2>How they differ</h2>
${app.intro.map((p) => `    <p>${p}</p>`).join("\n")}
    <h2>Pick ${app.name} if</h2>
    <p>${app.pick.charAt(0).toUpperCase() + app.pick.slice(1)}${app.site ? ` <a href="${app.site}" rel="nofollow">${app.name}'s website</a> has the details.` : ""}</p>
    <h2>Pick GlideTab if</h2>
    <p>You want every window with a live preview, you'd like to type a name instead of tabbing through the list, you want browser tabs in the same place, and you'd rather not pay. It needs macOS 14 or later. <a href="/features">See every feature</a>, or <a href="https://github.com/mohdmahmodi/glidetab">read the source</a>.</p>
    <h2>Other comparisons</h2>
    <p>${others.map(([, o]) => `<a href="/compare/${o.slug}">GlideTab vs ${o.name}</a>`).join(" · ")} · <a href="/compare#all">All apps in one chart</a></p>
  </section>

${download("/compare", "All Comparisons")}
</main>`;
  const path = `/compare/${app.slug}`;
  return page({
    path, title: app.title, description: app.description, body, current: "/compare",
    jsonLd: [
      breadcrumbs([["GlideTab", "/"], ["Compare", "/compare"], [`GlideTab vs ${app.name}`, path]]),
      {
        "@type": "WebPage", "@id": ORIGIN + path, name: app.title, description: app.description,
        about: { "@id": `${ORIGIN}/#app` },
        mentions: { "@type": "SoftwareApplication", name: app.name, operatingSystem: "macOS", applicationCategory: "UtilitiesApplication", ...(app.site ? { url: app.site } : {}) },
        isPartOf: { "@type": "WebSite", url: ORIGIN, name: "GlideTab" },
      },
    ],
  });
}

function page({ path, title, description, body, current, jsonLd, extraScripts = [] }) {
  return `<!doctype html>
<html lang="en">
${head({ title, description, path, jsonLd })}
<body>

${header(current)}

${body}

${FOOTER}

${scripts(extraScripts)}
</body>
</html>
`;
}

// Compare pages.
writeFileSync(join(site, "compare.html"), hub());
mkdirSync(join(site, "compare"), { recursive: true });
for (const [key, app] of competitors) writeFileSync(join(site, "compare", `${app.slug}.html`), duelPage(key, app));

// Version number and structured data on the hand-written pages.
for (const name of ["index.html", "features.html"]) {
  const file = join(site, name);
  let html = readFileSync(file, "utf8");
  html = html.replace(/<span data-version>[^<]*<\/span>/g, `<span data-version>${VERSION}</span>`);
  if (name === "index.html") {
    const faqs = [...html.matchAll(/<summary>(?:<svg>.*?<\/svg>)?(.*?)<\/summary>\s*<div class="answer">(.*?)<\/div>/gs)]
      .map(([, q, a]) => ({ "@type": "Question", name: q.trim(), acceptedAnswer: { "@type": "Answer", text: a.replace(/<[^>]+>/g, "").trim() } }));
    const blocks = [
      APP_LD,
      { "@type": "WebSite", url: ORIGIN, name: "GlideTab", publisher: { "@type": "Person", name: "Mohd Mahmodi", url: "https://mohdmahmodi.com" } },
      { "@type": "FAQPage", mainEntity: faqs },
    ].map((d) => "  " + ld({ "@context": "https://schema.org", ...d })).join("\n");
    html = html.replace(/  <!-- ld:start -->[\s\S]*?<!-- ld:end -->/, `  <!-- ld:start -->\n${blocks}\n  <!-- ld:end -->`);
  }
  writeFileSync(file, html);
}

// Sitemap.
const urls = ["/", "/features", "/compare", ...competitors.map(([, app]) => `/compare/${app.slug}`), "/privacy"];
writeFileSync(join(site, "sitemap.xml"), `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls.map((u) => `  <url><loc>${ORIGIN}${u}</loc><lastmod>${TODAY}</lastmod></url>`).join("\n")}
</urlset>
`);

console.log(`wrote compare.html, ${competitors.length} comparison pages and sitemap.xml for version ${VERSION}`);
