// The Compare page: one app at a time, side by side with GlideTab, or every app in one chart.
(() => {
  "use strict";

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
  const animate = typeof window.gsap !== "undefined" && !matchMedia("(prefers-reduced-motion: reduce)").matches;

  const ROWS = [
    ["windows", "Switches between windows"],
    ["hold", "Hold a key, tap to move"],
    ["previews", "Live previews"],
    ["search", "Search by typing"],
    ["tabs", "Browser tabs"],
    ["source", "Open source"],
  ];

  // true = yes, false = no or undocumented, a string = a short note.
  const APPS = {
    glidetab: { name: "GlideTab", price: "Free", look: "grid", windows: true, hold: true, previews: true, search: "Always on", tabs: true, source: "MIT" },
    commandtab: { name: "⌘Tab", price: "Built into macOS", look: "icons", windows: "Apps only", hold: true, previews: false, search: false, tabs: false, source: false,
      pick: "you'd rather not install anything and keep one window per app." },
    missioncontrol: { name: "Mission Control", price: "Built into macOS", look: "spread", windows: true, hold: "Mouse first", previews: "Full size", search: false, tabs: false, source: false,
      pick: "you like seeing every window laid out at once." },
    alttab: { name: "AltTab", price: "Free, Pro $9.99", look: "grid", windows: true, hold: true, previews: true, search: "Pro only", tabs: false, source: "GPL-3.0",
      pick: "you're on macOS 12 or 13, or want sorting, animations and single-key actions." },
    witch: { name: "Witch", price: "$14", look: "list", windows: true, hold: true, previews: true, search: true, tabs: true, source: false,
      pick: "your Mac runs an older macOS, or you want deep control over the list." },
    contexts: { name: "Contexts", price: "$9.99", look: "sidebar", windows: true, hold: true, previews: false, search: true, tabs: false, source: false,
      pick: "you want a sidebar of windows that's always there." },
    hyperswitch: { name: "HyperSwitch", price: "Free, beta", look: "grid", windows: true, hold: true, previews: true, search: false, tabs: false, source: false,
      pick: "your Mac runs a macOS older than 14." },
    raycast: { name: "Raycast", price: "Free, Pro from $8/mo", look: "launcher", windows: true, hold: "Opens a launcher", previews: false, search: true, tabs: false, source: false,
      pick: "you already use Raycast and a searchable list is enough." },
  };

  const mark = (value) => {
    if (value === true) return '<span class="yes"><svg aria-hidden="true"><use href="/icons.svg#i-check"/></svg><span class="visually-hidden">Yes</span></span>';
    if (value === false) return '<span class="no"><svg aria-hidden="true"><use href="/icons.svg#i-dash"/></svg><span class="visually-hidden">No</span></span>';
    return `<span class="note">${value}</span>`;
  };

  // Small drawings of how each kind of switcher looks. Generic shapes, not anyone's actual interface.
  const LOOKS = {
    grid: '<div class="look grid"><div class="lp"><i></i><i class="sel"></i><i></i><i></i><i></i><i></i></div></div>',
    icons: '<div class="look icons"><div class="lp"><b></b><b class="sel"></b><b></b><b></b><b></b></div></div>',
    spread: '<div class="look spread"><span class="spaces"><i></i><i class="on"></i><i></i></span><i class="w a"></i><i class="w b"></i><i class="w c"></i><i class="w d"></i></div>',
    list: '<div class="look list"><div class="lp"><u></u><u class="sel"></u><u></u><u></u></div></div>',
    sidebar: '<div class="look sidebar"><div class="side"><u></u><u class="sel"></u><u></u><u></u><u></u></div></div>',
    launcher: '<div class="look launcher"><div class="lp"><span class="bar"></span><u class="sel"></u><u></u><u></u></div></div>',
  };

  const duel = $("#duel");
  const buttons = $$("[data-app]");

  function showDuel(key) {
    const them = APPS[key];
    const ours = APPS.glidetab;
    const rows = ROWS.map(([field, label]) => `<tr><th scope="row">${label}</th><td class="ours">${mark(ours[field])}</td><td>${mark(them[field])}</td></tr>`).join("");
    duel.innerHTML = `
      <div class="duel-card">
        <table>
          <thead>
            <tr>
              <th scope="col"><span class="visually-hidden">Feature</span></th>
              <th scope="col" class="ours">${LOOKS[ours.look]}<b>${ours.name}</b><small>${ours.price}</small></th>
              <th scope="col">${LOOKS[them.look]}<b>${them.name}</b><small>${them.price}</small></th>
            </tr>
          </thead>
          <tbody>${rows}</tbody>
        </table>
        <p class="verdict">Pick ${them.name} if ${them.pick}</p>
      </div>`;
  }

  function showAll() {
    const keys = Object.keys(APPS);
    const head = keys.map((key) => `<th scope="col"${key === "glidetab" ? ' class="ours"' : ""}><b>${APPS[key].name}</b><small>${APPS[key].price}</small></th>`).join("");
    const rows = ROWS.map(([field, label]) => `<tr><th scope="row">${label}</th>${keys.map((key) => `<td${key === "glidetab" ? ' class="ours"' : ""}>${mark(APPS[key][field])}</td>`).join("")}</tr>`).join("");
    duel.innerHTML = `<div class="matrix"><div class="scroll"><table><thead><tr><th scope="col"><span class="visually-hidden">Feature</span></th>${head}</tr></thead><tbody>${rows}</tbody></table></div></div>`;
  }

  function select(key, push = true) {
    if (!APPS[key] && key !== "all") key = "commandtab";
    buttons.forEach((button) => {
      const on = button.dataset.app === key;
      button.setAttribute("aria-pressed", String(on));
      button.setAttribute("aria-selected", String(on));
    });
    if (key === "all") showAll();
    else showDuel(key);
    if (animate) gsap.fromTo(duel.firstElementChild, { opacity: 0, y: 8 }, { opacity: 1, y: 0, duration: 0.3, ease: "power2.out" });
    if (push) history.replaceState(null, "", `#${key}`);
  }

  buttons.forEach((button) => button.addEventListener("click", () => select(button.dataset.app)));
  select(location.hash.slice(1) || "commandtab", false);
})();
