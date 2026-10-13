# GlideTab website

A static site: plain HTML, CSS and JavaScript with no build step. Animations use GSAP from cdnjs.

| File | What it is |
| --- | --- |
| `index.html` | The landing page, with the interactive switcher demo |
| `features.html` | Each feature with a working example, plus a grid of the rest |
| `compare-data.js` | The comparison data and the written comparisons. Edit this, not the pages below |
| `compare.html`, `compare/*.html`, `compare.js` | The Compare hub and one page per app, written by `tools/build.mjs` |
| `tools/build.mjs` | Writes the Compare pages, the sitemap, the version number and the structured data |
| `llms.txt`, `robots.txt`, `sitemap.xml` | For search engines and AI crawlers |
| `windows.html` | The demo windows (browser, code editor, Messages and so on), shared by every page |
| `privacy.html`, `404.html` | Privacy notes and the not-found page |
| `styles.css`, `demo.css` | Page styles, and the demo desktop's windows |
| `site.js`, `app.js` | Shared page behavior, and the switcher demos |
| `icons.svg` | Every icon, as one sprite |

## Preview locally

```bash
python3 -m http.server 8787 --directory site
```

Then open http://localhost:8787.

## Deploy on Cloudflare Pages

1. In the Cloudflare dashboard, create a Pages project and connect this GitHub repository.
2. Use these build settings:

   | Setting | Value |
   | --- | --- |
   | Framework preset | None |
   | Build command | (leave empty) |
   | Build output directory | `/` |
   | Root directory | `site` |

3. Under Settings, Builds, add `site/*` to the build watch paths, so app-only commits don't redeploy the site.
4. Add `glidetab.com` under Custom domains (and `www.glidetab.com`, redirecting to it).

`_headers` sets the security headers and caching. Pages serves `features.html` at `/features` (and so on) and uses `404.html` for missing pages. The plain Python server above doesn't do that, so open `/features.html` when previewing locally.

## Updating

- The download buttons point to `releases/latest/download/GlideTab.zip`, so they always fetch the newest release. The release asset must keep that file name.
- The version number in the page updates itself from the GitHub API once the repository is public. Until then it shows the number written in `index.html`.
- After changing a CSS or JavaScript file, bump the `?v=` number where it's linked, so browsers fetch the new file.
- The demo windows are HTML templates in `windows.html`. The desktop and every switcher thumbnail are drawn from them, so a change to a window shows up everywhere.
- Comparison data and text live in `compare-data.js`. After editing it, or after bumping the version in `Resources/Info.plist`, run `node site/tools/build.mjs` from the repository root and commit what it writes: `compare.html`, `compare/*.html`, `sitemap.xml`, and the version numbers and structured data in `index.html` and `features.html`.
- Each page's `<head>` carries a title and description written for search, Open Graph and Twitter tags, and JSON-LD structured data (SoftwareApplication, FAQPage and breadcrumbs). Keep titles under about 60 characters and descriptions under about 160.

## Images

- `images/wallpaper.jpg`, the demo desktop's wallpaper, is a photo from [Unsplash](https://unsplash.com/photos/1506905925346-21bda4d32df4), used under the [Unsplash License](https://unsplash.com/license) (free to use, no attribution required).
- Everything else, including the app icons in the demo, is drawn for this site.
