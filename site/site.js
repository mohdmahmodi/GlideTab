// Shared page chrome: the menu bar clock and app menu, light and dark, and the release number.
(() => {
  "use strict";

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];

  // Menu bar clock.
  const clock = $("#clock");
  const miniClock = $("#mini-clock");
  if (clock || miniClock) {
    const long = new Intl.DateTimeFormat(undefined, { weekday: "short", day: "numeric", month: "short", hour: "numeric", minute: "2-digit" });
    const short = new Intl.DateTimeFormat(undefined, { hour: "numeric", minute: "2-digit" });
    const tick = () => {
      const now = new Date();
      if (clock) clock.textContent = long.format(now).replace(/,/g, "");
      if (miniClock) miniClock.textContent = short.format(now);
    };
    tick();
    setInterval(tick, 15000);
  }

  // App menu.
  const menu = $("#app-menu");
  if (menu) {
    const button = $("button", menu);
    const setOpen = (open) => {
      menu.classList.toggle("open", open);
      button.setAttribute("aria-expanded", String(open));
    };
    button.addEventListener("click", (event) => {
      event.stopPropagation();
      setOpen(!menu.classList.contains("open"));
    });
    document.addEventListener("click", () => setOpen(false));
    document.addEventListener("keydown", (event) => event.key === "Escape" && setOpen(false));
  }

  // Light and dark: follows the system unless the visitor picks one.
  const root = document.documentElement;
  const systemDark = matchMedia("(prefers-color-scheme: dark)");
  const applyTheme = (theme) => {
    if (theme) root.dataset.theme = theme;
    else delete root.dataset.theme;
  };
  try { applyTheme(localStorage.getItem("theme")); } catch {}
  const toggle = $("#theme-toggle");
  if (toggle) {
    toggle.addEventListener("click", () => {
      const current = root.dataset.theme || (systemDark.matches ? "dark" : "light");
      const next = current === "dark" ? "light" : "dark";
      applyTheme(next === (systemDark.matches ? "dark" : "light") ? null : next);
      try {
        if (root.dataset.theme) localStorage.setItem("theme", root.dataset.theme);
        else localStorage.removeItem("theme");
      } catch {}
    });
  }

  // Yes and no marks in comparison tables.
  $$("td[data-yes]").forEach((td) => {
    td.innerHTML = '<svg aria-hidden="true"><use href="/icons.svg#i-check"/></svg><span class="visually-hidden">Yes</span>';
  });
  $$("td[data-no]").forEach((td) => {
    td.innerHTML = '<svg aria-hidden="true" style="opacity:.4"><use href="/icons.svg#i-dash"/></svg><span class="visually-hidden">No</span>';
  });

  // Inner pages: highlight the section in view in the pill navigation.
  const pills = $$(".pill-nav a");
  if (pills.length) {
    const byId = new Map(pills.map((link) => [link.getAttribute("href").slice(1), link]));
    pills[0].classList.add("current");
    const observer = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        pills.forEach((link) => link.classList.remove("current"));
        const link = byId.get(entry.target.id);
        if (!link) continue;
        link.classList.add("current");
        link.parentElement.scrollTo({ left: link.offsetLeft - 20, behavior: "smooth" });
      }
    }, { rootMargin: "-25% 0px -65% 0px" });
    byId.forEach((_, id) => {
      const section = document.getElementById(id);
      if (section) observer.observe(section);
    });
  }

  // The latest release number, once the repository is public.
  const versions = $$("[data-version]");
  if (versions.length) {
    fetch("https://api.github.com/repos/mohdmahmodi/glidetab/releases/latest", { headers: { Accept: "application/vnd.github+json" } })
      .then((response) => (response.ok ? response.json() : null))
      .then((release) => {
        const version = release && String(release.tag_name || "").replace(/^v/i, "");
        if (/^\d+(\.\d+)*$/.test(version)) versions.forEach((el) => (el.textContent = version));
      })
      .catch(() => {});
  }
})();
