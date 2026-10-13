// The Compare page: every comparison is in the HTML already; this only shows one at a time.
(() => {
  "use strict";

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
  const animate = typeof window.gsap !== "undefined" && !matchMedia("(prefers-reduced-motion: reduce)").matches;

  const views = new Map($$("[data-view]").map((el) => [el.dataset.view, el]));
  const buttons = $$("[data-app]");
  if (!views.size || !buttons.length) return;

  function select(key, push = true) {
    if (!views.has(key)) key = "commandtab";
    buttons.forEach((button) => {
      const on = button.dataset.app === key;
      button.setAttribute("aria-pressed", String(on));
      button.setAttribute("aria-selected", String(on));
    });
    views.forEach((el, name) => { el.hidden = name !== key; });
    const shown = views.get(key);
    if (animate) gsap.fromTo(shown, { opacity: 0, y: 8 }, { opacity: 1, y: 0, duration: 0.3, ease: "power2.out" });
    if (push) history.replaceState(null, "", `#${key}`);
  }

  buttons.forEach((button) => button.addEventListener("click", () => select(button.dataset.app)));
  select(location.hash.slice(1) || "commandtab", false);
})();
