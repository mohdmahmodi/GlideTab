// The landing page demos: a working switcher on a small desktop, and a few looping examples.
(async () => {
  "use strict";

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
  const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const hasGsap = typeof window.gsap !== "undefined";
  const hasFlip = hasGsap && typeof window.Flip !== "undefined";
  const animate = hasGsap && !reduceMotion;
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

  if (hasFlip) gsap.registerPlugin(Flip);

  // MARK: Demo data

  const WINDOWS = {
    browser: { app: "Browser", title: "Four days in Lisbon", icon: "app-browser", w: 760, h: 500, x: 320, y: 76 },
    messages: { app: "Messages", title: "Ana Ribeiro", icon: "app-messages", w: 540, h: 340, x: 640, y: 330 },
    design: { app: "Design", title: "Lisbon App", icon: "app-design", w: 660, h: 420, x: 160, y: 230, cls: "design" },
    code: { app: "Code", title: "Switcher.swift", icon: "app-code", w: 700, h: 460, x: 36, y: 44, cls: "code" },
    photos: { app: "Photos", title: "Library", icon: "app-photos", w: 500, h: 300, x: 40, y: 380 },
    calendar: { app: "Calendar", title: "October 2026", icon: "app-calendar", w: 450, h: 320, x: 720, y: 40 },
    mail: { app: "Mail", title: "Inbox", icon: "app-mail", w: 640, h: 380, x: 300, y: 110, badge: "space" },
    music: { app: "Music", title: "Recently Added", icon: "app-music", w: 560, h: 350, x: 360, y: 150, badge: "minimized" },
  };

  const BADGES = {
    minimized: ["i-minimized", "Minimized"],
    space: ["i-space", "Space 2"],
    hidden: ["i-hidden", "Hidden"],
  };

  const icon = (id, cls = "app-icon") => `<svg class="${cls}" aria-hidden="true"><use href="/icons.svg#${id}"/></svg>`;

  function buildWindow(id, extraClass = "") {
    const def = WINDOWS[id];
    const el = document.createElement("div");
    el.className = `window ${def.cls || ""} ${extraClass}`.trim();
    el.style.width = `${def.w}px`;
    el.style.height = `${def.h}px`;
    el.append($(`#win-${id}`).content.cloneNode(true));
    return el;
  }

  const escapeHTML = (text) => text.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
  const words = (query) => query.toLowerCase().split(/\s+/).filter(Boolean);

  function matches(query, text) {
    const haystack = text.toLowerCase();
    return words(query).every((word) => haystack.includes(word));
  }

  function highlight(text, query) {
    const lower = text.toLowerCase();
    const marked = new Array(text.length).fill(false);
    for (const word of words(query)) {
      for (let i = lower.indexOf(word); i !== -1; i = lower.indexOf(word, i + 1)) {
        for (let j = i; j < i + word.length; j++) marked[j] = true;
      }
    }
    let html = "";
    for (let i = 0; i < text.length; i++) {
      if (marked[i] && !marked[i - 1]) html += "<mark>";
      html += escapeHTML(text[i]);
      if (marked[i] && !marked[i + 1]) html += "</mark>";
    }
    return html;
  }

  // MARK: Switcher panel, drawn the way the app draws it

  class Panel {
    constructor(el, { thumb = { w: 194, h: 128 }, typeable = false } = {}) {
      this.el = el;
      this.thumb = thumb;
      this.items = [];
      this.cells = new Map();
      this.selected = 0;
      this.query = "";
      this.excluded = new Set();
      this.ringPlaced = false;
      el.innerHTML = `
        <div class="search"><svg aria-hidden="true"><use href="/icons.svg#i-search"/></svg><span class="field"><span class="text"></span><span class="caret"></span><span class="placeholder">Search windows and tabs</span></span><span class="count"></span></div>
        <div class="cells"></div>`;
      this.search = $(".search", el);
      this.text = $(".text", el);
      this.placeholder = $(".placeholder", el);
      this.count = $(".count", el);
      this.grid = $(".cells", el);
      this.ring = document.createElement("div");
      this.ring.className = "ring";
      if (typeable) this.makeTypeable();
    }

    // A real (invisible) text field over the search bar, so visitors can type into the demo.
    makeTypeable() {
      const input = document.createElement("input");
      input.className = "type";
      input.setAttribute("aria-label", "Search the windows in this example");
      input.autocomplete = "off";
      input.spellcheck = false;
      this.search.append(input);
      this.input = input;
      input.addEventListener("input", () => {
        flipRender(this, { query: input.value, selected: 0, focused: true });
        this.onType?.();
      });
      input.addEventListener("focus", () => {
        this.search.classList.add("focused");
        this.onType?.();
      });
      input.addEventListener("blur", () => this.search.classList.toggle("focused", Boolean(this.query)));
      input.addEventListener("keydown", (event) => {
        const count = this.visible().length;
        const step = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1, Tab: event.shiftKey ? -1 : 1 }[event.key];
        if (step && count) {
          event.preventDefault();
          this.render({ selected: (this.selected + step + count) % count, focused: true });
        } else if (event.key === "Escape") {
          input.value = "";
          flipRender(this, { query: "", selected: 0, focused: true });
        } else if (event.key === "Enter" && animate) {
          gsap.fromTo(this.ring, { scale: 0.96 }, { scale: 1, duration: 0.3, ease: "back.out(3)" });
        }
        this.onType?.();
      });
    }

    get isTyping() {
      return Boolean(this.input && (document.activeElement === this.input || this.input.value));
    }

    setItems(items) {
      this.items = items;
      this.grid.replaceChildren(this.ring);
      this.ringPlaced = false;
      for (const item of items) {
        let cell = this.cells.get(item.key);
        if (!cell) {
          cell = this.makeCell(item);
          this.cells.set(item.key, cell);
        }
        this.updateBadge(cell, item);
        this.grid.append(cell);
      }
    }

    makeCell(item) {
      const cell = document.createElement("div");
      cell.className = "cell";
      cell.innerHTML = `
        <div class="head">${icon(item.icon)}<span class="title"></span></div>
        <div class="thumb">${icon(item.icon, "big-icon")}</div>
        <div class="sub"></div>`;
      if (item.window) {
        const def = WINDOWS[item.window];
        const shrink = buildWindow(item.window, "shrink");
        const scale = Math.min(this.thumb.w / def.w, this.thumb.h / def.h);
        shrink.style.transform = `translate(-50%, -50%) scale(${scale})`;
        $(".thumb", cell).prepend(shrink);
      }
      cell.addEventListener("click", () => this.onPick?.(item.key));
      cell.addEventListener("mouseenter", () => this.onHover?.(item.key));
      return cell;
    }

    updateBadge(cell, item) {
      cell.querySelectorAll(".badge").forEach((badge) => badge.remove());
      cell.classList.toggle("dim", item.badge === "minimized" || item.badge === "hidden");
      const sub = $(".sub", cell);
      sub.textContent = "";
      if (item.tab) sub.insertAdjacentHTML("beforeend", '<svg aria-hidden="true"><use href="/icons.svg#i-globe"/></svg>');
      if (item.sub) sub.append(item.sub);
      if (BADGES[item.badge]) {
        const [symbol, label] = BADGES[item.badge];
        const html = `<span class="badge"><svg aria-hidden="true"><use href="/icons.svg#${symbol}"/></svg>${label}</span>`;
        $(".thumb", cell).insertAdjacentHTML("beforeend", html);
        sub.insertAdjacentHTML("beforeend", html);
      }
    }

    visible() {
      return this.items.filter((item) => !this.excluded.has(item.key) && (!this.query || matches(this.query, `${item.title} ${item.app} ${item.sub || ""}`)));
    }

    render({ selected = this.selected, query = this.query, focused = false } = {}) {
      this.query = query;
      const visible = this.visible();
      this.selected = Math.max(0, Math.min(selected, visible.length - 1));
      const shown = new Set(visible);
      for (const item of this.items) {
        const cell = this.cells.get(item.key);
        cell.hidden = !shown.has(item);
        $(".title", cell).innerHTML = highlight(item.title, query);
        cell.classList.toggle("selected", visible[this.selected] === item);
      }
      this.text.textContent = query;
      this.placeholder.hidden = Boolean(query);
      this.count.textContent = query ? `${visible.length} of ${this.items.length}` : "";
      this.search.classList.toggle("focused", focused || Boolean(query));
      this.placeRing();
      return visible;
    }

    // The selection outline glides from one window to the next.
    placeRing(glide = true) {
      const cell = $(".cell.selected", this.grid);
      if (!cell) {
        this.ring.style.opacity = "0";
        return;
      }
      const box = { x: cell.offsetLeft, y: cell.offsetTop, width: cell.offsetWidth, height: cell.offsetHeight };
      if (animate && glide && this.ringPlaced) {
        gsap.to(this.ring, { ...box, opacity: 1, duration: 0.18, ease: "power3.out", overwrite: true });
      } else if (hasGsap) {
        gsap.set(this.ring, { ...box, opacity: 1 });
      } else {
        Object.assign(this.ring.style, { transform: `translate(${box.x}px, ${box.y}px)`, width: `${box.width}px`, height: `${box.height}px`, opacity: "1" });
      }
      this.ringPlaced = true;
    }

    selectedItem() {
      return this.visible()[this.selected];
    }

    indexOf(key) {
      return this.visible().findIndex((item) => item.key === key);
    }
  }

  // Filtering with a short layout animation. Only cells that stay visible move; the rest fade.
  function flipRender(panel, options) {
    if (!hasFlip || reduceMotion) return panel.render(options);
    const before = new Set([...panel.cells.values()].filter((cell) => !cell.hidden));
    const state = Flip.getState([panel.el, ...panel.cells.values()]);
    panel.render(options);
    const after = [...panel.cells.values()].filter((cell) => !cell.hidden);
    const staying = after.filter((cell) => before.has(cell));
    const entering = after.filter((cell) => !before.has(cell));
    Flip.from(state, { targets: [panel.el, ...staying], duration: 0.34, ease: "power3.out", nested: true });
    if (entering.length) gsap.fromTo(entering, { opacity: 0, y: 6 }, { opacity: 1, y: 0, duration: 0.3, delay: 0.06, ease: "power2.out" });
  }

  // MARK: Fit fixed-size stages to their container

  function fitStages() {
    for (const fit of $$("[data-stage]")) {
      const stage = fit.firstElementChild;
      const width = Number(fit.dataset.width || 1200);
      const height = Number(fit.dataset.height || 720);
      const scale = fit.clientWidth / width;
      stage.style.transform = `scale(${scale})`;
      fit.style.height = `${height * scale}px`;
    }
  }
  fitStages();
  new ResizeObserver(fitStages).observe(document.body);

  // Runs a demo only while it's on screen.
  function whileVisible(el, start, threshold = 0.35) {
    let token = 0;
    new IntersectionObserver(([entry]) => {
      token++;
      if (entry.isIntersecting) {
        const mine = token;
        start(() => token === mine);
      }
    }, { threshold }).observe(el);
  }

  // The demo windows live in one shared file, so every page draws the same apps.
  if (!document.getElementById("win-browser")) {
    const holder = document.createElement("div");
    holder.hidden = true;
    try {
      holder.innerHTML = await fetch("/windows.html").then((response) => response.text());
    } catch {
      return; // without the windows there's nothing to demo; the rest of the page still works
    }
    document.body.append(holder);
  }

  // MARK: Hero demo

  if ($("#hero-panel")) {

  const hero = {
    order: ["browser", "messages", "design", "code", "photos", "calendar", "mail", "music"],
    elements: new Map(),
    open: false,
    pinned: false,
    optionDown: false,
    inView: true,
    userUntil: 0,
    paused: reduceMotion,
    loopToken: 0,
    tapTimer: null,
  };

  const desktop = $("#desktop");
  const heroPanel = new Panel($("#hero-panel"));
  const coachText = $("#coach-text");
  const held = { option: false, tab: false };

  function press(name, down) {
    held[name] = down;
    $$(`[data-key="${name}"]`).forEach((key) => key.classList.toggle("down", down));
  }

  // The notification on the demo desktop walks the visitor through it, one step at a time.
  const touch = matchMedia("(hover: none)").matches;
  const COACH = {
    idle: touch ? "Try it: tap the Tab key below the screen." : 'Try it: hold <kbd data-key="option">⌥ Option</kbd>, then press <kbd data-key="tab">Tab</kbd>.',
    option: 'Keep holding Option and press <kbd data-key="tab">Tab</kbd>.',
    open: 'Tap <kbd data-key="tab">Tab</kbd> to move. Let go of <kbd data-key="option">⌥ Option</kbd> to switch.',
    typing: "Searching. Press Return to switch, or Esc to clear.",
    done: "That's it. Your Mac works the same way with GlideTab.",
  };
  if (touch && coachText) coachText.innerHTML = COACH.idle;
  let coachState = "idle";
  function coach(state) {
    if (!coachText || state === coachState) return;
    coachState = state;
    const swap = () => {
      coachText.innerHTML = COACH[state];
      press("option", held.option);
      press("tab", held.tab);
    };
    if (animate) gsap.to(coachText, { opacity: 0, duration: 0.1, onComplete: () => { swap(); gsap.to(coachText, { opacity: 1, duration: 0.18 }); } });
    else swap();
    clearTimeout(coach.timer);
    if (state === "done") coach.timer = setTimeout(() => coach("idle"), 4500);
  }

  // The Dock, with a dot under every app that has windows.
  $("#dock").innerHTML = ["browser", "messages", "mail", "code", "design", "photos", "calendar", "music"]
    .map((id) => `<span class="slot running">${icon(WINDOWS[id].icon)}</span>`)
    .join("") + '<span class="divider"></span><span class="slot">' + icon("app-files") + "</span>";

  function placeWindows(animateIn = false) {
    hero.order.forEach((id, index) => {
      const def = WINDOWS[id];
      if (def.badge) return; // minimized, or on another Space
      let el = hero.elements.get(id);
      if (!el) {
        el = buildWindow(id, "desk-window");
        el.style.left = `${def.x}px`;
        el.style.top = `${def.y}px`;
        el.addEventListener("pointerdown", () => !hero.open && focusWindow(id));
        desktop.append(el);
        hero.elements.set(id, el);
      }
      el.style.zIndex = String(30 - index);
      el.classList.toggle("key-window", index === 0);
      el.classList.toggle("inactive", index !== 0);
    });
    $("#front-app").textContent = WINDOWS[hero.order[0]].app;
    if (animateIn && animate) {
      const els = hero.order.map((id) => hero.elements.get(id)).filter(Boolean).reverse();
      gsap.from(els, { opacity: 0, y: 24, scale: 0.97, duration: 0.7, ease: "power3.out", stagger: 0.08, delay: 0.1 });
    }
  }

  const heroItems = () => hero.order.map((id) => ({ key: id, window: id, ...WINDOWS[id] }));

  function openSwitcher() {
    if (hero.open) return;
    hero.open = true;
    hero.pinned = false;
    heroPanel.setItems(heroItems());
    heroPanel.el.style.setProperty("--cols", "4");
    heroPanel.el.style.visibility = "visible";
    heroPanel.render({ selected: 1, query: "" });
    if (animate) gsap.fromTo(heroPanel.el, { opacity: 0, scale: 0.985 }, { opacity: 1, scale: 1, duration: 0.14, ease: "power2.out" });
  }

  function move(step) {
    if (!hero.open) return;
    const count = heroPanel.visible().length;
    if (count) heroPanel.render({ selected: (heroPanel.selected + step + count) % count });
  }

  function cancel() {
    hero.open = false;
    hero.pinned = false;
    heroPanel.query = "";
    heroPanel.el.style.visibility = "hidden";
  }

  function commit() {
    if (!hero.open) return;
    const item = heroPanel.selectedItem();
    cancel();
    if (item) focusWindow(item.key);
  }

  function focusWindow(id) {
    const def = WINDOWS[id];
    const kind = def.badge;
    delete def.badge; // it's on this Space and unminimized now
    hero.order = [id, ...hero.order.filter((other) => other !== id)];
    placeWindows();
    const el = hero.elements.get(id);
    if (kind && animate) {
      if (kind === "minimized") gsap.from(el, { y: 300, scale: 0.15, opacity: 0, duration: 0.5, ease: "power3.out", transformOrigin: "50% 100%" });
      else gsap.from(el, { x: 460, opacity: 0, duration: 0.5, ease: "power3.out" });
    }
  }

  function typeInSearch(character) {
    if (!hero.open) return;
    hero.pinned = true;
    heroPanel.render({ selected: 0, query: heroPanel.query + character });
    if (isUser()) coach("typing");
  }

  const isUser = () => Date.now() < hero.userUntil;

  function takeOver() {
    hero.userUntil = Date.now() + 9000;
    hero.loopToken++;
  }

  heroPanel.onPick = (key) => {
    takeOver();
    heroPanel.render({ selected: heroPanel.indexOf(key) });
    commit();
    coach("done");
  };
  heroPanel.onHover = (key) => {
    if (Date.now() < hero.userUntil) heroPanel.render({ selected: heroPanel.indexOf(key) });
  };

  // Real keys: Option and Tab work on the page while the demo is on screen.
  document.addEventListener("keydown", (event) => {
    if (!hero.inView) return;
    if (event.key === "Alt") {
      hero.optionDown = true;
      takeOver();
      if (hero.open) cancel();
      press("option", true);
      coach("option");
      return;
    }
    if (event.key === "Tab" && event.altKey) {
      event.preventDefault();
      takeOver();
      press("tab", true);
      if (!hero.open) openSwitcher();
      else move(event.shiftKey ? -1 : 1);
      coach("open");
      return;
    }
    if (!hero.open) return;
    const actions = {
      Escape: () => (heroPanel.query ? heroPanel.render({ query: "", selected: 0 }) : cancel()),
      Enter: () => { commit(); coach("done"); },
      ArrowRight: () => move(1),
      ArrowLeft: () => move(-1),
      ArrowDown: () => move(4),
      ArrowUp: () => move(-4),
      Backspace: () => heroPanel.render({ query: heroPanel.query.slice(0, -1), selected: 0 }),
    };
    if (actions[event.key]) {
      event.preventDefault();
      takeOver();
      actions[event.key]();
      return;
    }
    // Option changes the character a key types, so read the physical key instead.
    const code = event.code;
    const character = code.startsWith("Key") ? code.slice(3).toLowerCase() : code.startsWith("Digit") ? code.slice(5) : code === "Space" ? " " : null;
    if (character && !event.metaKey && !event.ctrlKey) {
      event.preventDefault();
      takeOver();
      typeInSearch(character);
    }
  });

  document.addEventListener("keyup", (event) => {
    if (event.key === "Tab") press("tab", false);
    if (event.key === "Alt") {
      hero.optionDown = false;
      press("option", false);
      if (hero.open && !hero.pinned) {
        commit();
        coach("done");
      } else if (!hero.open && coachState === "option") {
        coach("idle");
      }
    }
  });

  window.addEventListener("blur", () => {
    hero.optionDown = false;
    press("option", false);
    press("tab", false);
    if (hero.open) cancel();
  });

  // Touch screens: tap the on-screen Tab key; it switches when you stop tapping.
  $("#tap-tab").addEventListener("click", () => {
    takeOver();
    press("tab", true);
    setTimeout(() => press("tab", false), 120);
    if (!hero.open) openSwitcher();
    else move(1);
    clearTimeout(hero.tapTimer);
    hero.tapTimer = setTimeout(() => {
      if (hero.open && !hero.pinned) commit();
    }, 1200);
  });

  const pauseButton = $("#demo-pause");
  const showPaused = () => {
    pauseButton.setAttribute("aria-pressed", String(hero.paused));
    pauseButton.querySelector("span").textContent = hero.paused ? "Play demo" : "Pause demo";
    pauseButton.querySelector("use").setAttribute("href", hero.paused ? "/icons.svg#i-play" : "/icons.svg#i-pause");
  };
  pauseButton.addEventListener("click", () => {
    hero.paused = !hero.paused;
    hero.loopToken++;
    if (!hero.paused) hero.userUntil = 0;
    showPaused();
  });
  showPaused();

  // The demo plays itself until you take over.
  async function autoplay() {
    const scripts = [{ taps: 1 }, { taps: 3 }, { taps: 1 }, { search: "inbox" }, { taps: 2 }, { taps: 6 }, { taps: 1 }];
    let round = 0;
    for (;;) {
      await sleep(600);
      if (hero.paused || !hero.inView || Date.now() < hero.userUntil || hero.open || hero.optionDown) continue;
      const token = ++hero.loopToken;
      const alive = () => token === hero.loopToken;
      const script = scripts[round++ % scripts.length];

      await sleep(900);
      if (!alive()) continue;
      press("option", true);
      await sleep(280);
      if (!alive()) { press("option", false); continue; }
      press("tab", true);
      openSwitcher();
      await sleep(140);
      press("tab", false);

      if (script.search) {
        await sleep(700);
        for (const character of script.search) {
          if (!alive()) break;
          typeInSearch(character);
          await sleep(130);
        }
        press("option", false);
        await sleep(1000);
      } else {
        for (let i = 1; i < script.taps && alive(); i++) {
          await sleep(540);
          if (!alive()) break;
          press("tab", true);
          move(1);
          await sleep(130);
          press("tab", false);
        }
        await sleep(750);
      }
      press("option", false);
      if (alive()) commit();
      await sleep(1800);
    }
  }

  placeWindows(true);
  new IntersectionObserver(([entry]) => {
    hero.inView = entry.intersectionRatio > 0.25;
    if (!hero.inView && hero.open) cancel();
  }, { threshold: [0, 0.25, 0.5] }).observe($("#hero-screen"));
  autoplay();
  }

  // MARK: Styles, morphing between thumbnails, app icons and list

  for (const el of $$('[data-demo="styles"]')) {
    const panel = new Panel(el, { typeable: true });
    const order = ["browser", "code", "messages", "design", "calendar", "photos", "mail"];
    panel.setItems(order.map((id) => ({ key: id, window: id, ...WINDOWS[id], badge: undefined, sub: WINDOWS[id].app })));
    panel.render({ selected: 1 });
    const buttons = $$("[data-style-choice]", el.closest("section"));
    let current = "thumbnails";
    let userUntil = 0;

    const choose = (style) => {
      if (style === current) return;
      current = style;
      buttons.forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.styleChoice === style)));
      const apply = () => {
        panel.el.dataset.style = style;
        panel.el.style.setProperty("--cols", style === "icons" ? "7" : "4");
      };
      if (!animate) {
        apply();
        panel.placeRing(false);
        return;
      }
      // Fade the windows out, resize the panel to its new shape, and fade the new layout in.
      const el = panel.el;
      const from = { width: el.offsetWidth, height: el.offsetHeight };
      gsap.killTweensOf([el, panel.grid, panel.ring]);
      gsap.to(panel.ring, { opacity: 0, duration: 0.1 });
      gsap.to(panel.grid, {
        opacity: 0,
        duration: 0.14,
        ease: "power1.out",
        onComplete: () => {
          apply();
          gsap.set(el, { clearProps: "width,height" });
          const to = { width: el.offsetWidth, height: el.offsetHeight };
          panel.placeRing(false);
          gsap.fromTo(panel.ring, { opacity: 0 }, { opacity: 1, duration: 0.25, delay: 0.4 });
          gsap.fromTo(el, from, { ...to, duration: 0.46, ease: "power3.inOut", clearProps: "width,height" });
          gsap.to(panel.grid, { opacity: 1, duration: 0.01, delay: 0.16 });
          const cells = [...panel.cells.values()];
          gsap.fromTo(cells, { opacity: 0, y: 10, scale: 0.98 }, { opacity: 1, y: 0, scale: 1, duration: 0.42, ease: "power3.out", stagger: 0.03, delay: 0.18, clearProps: "transform,opacity" });
        },
      });
    };

    buttons.forEach((b) => b.addEventListener("click", () => {
      userUntil = Date.now() + 20000;
      choose(b.dataset.styleChoice);
    }));
    panel.onHover = (key) => panel.render({ selected: panel.indexOf(key) });

    // Shows each style in turn until someone picks one.
    if (!reduceMotion) whileVisible(panel.el, async (alive) => {
      const styles = ["thumbnails", "icons", "list"];
      while (alive()) {
        await sleep(3400);
        if (!alive() || Date.now() < userUntil || panel.el.matches(":hover") || panel.isTyping) continue;
        choose(styles[(styles.indexOf(current) + 1) % styles.length]);
      }
    }, 0.5);
  }

  // MARK: Every window, with badges

  for (const el of $$('[data-demo="badges"]')) {
    const panel = new Panel(el, { thumb: { w: 204, h: 128 } });
    const badges = { mail: "space", music: "minimized", photos: "hidden" };
    panel.setItems(["browser", "mail", "code", "music", "photos", "messages"].map((id) => ({ key: id, window: id, ...WINDOWS[id], badge: badges[id] })));
    panel.render({ selected: 1 });
    panel.onHover = (key) => panel.render({ selected: panel.indexOf(key) });
    whileVisible(panel.el, async (alive) => {
      while (alive()) {
        await sleep(1500);
        if (!alive() || panel.el.matches(":hover")) continue;
        panel.render({ selected: (panel.selected + 1) % panel.items.length });
      }
    });
  }

  // MARK: Find windows and tabs

  for (const el of $$('[data-demo="find"]')) {
    const panel = new Panel(el, { typeable: true });
    panel.setItems([
      { key: "f1", title: "Four days in Lisbon", app: "Browser", sub: "Browser", icon: "app-browser" },
      { key: "f2", title: "Lisbon trip", app: "Messages", sub: "Messages", icon: "app-messages" },
      { key: "f3", title: "Flights to Lisbon", app: "Browser", sub: "Personal · flights.example", icon: "app-globe", tab: true },
      { key: "f4", title: "Q3 planning", app: "Browser", sub: "Work · docs.google.com", icon: "app-globe", tab: true },
      { key: "f5", title: "Inbox", app: "Mail", sub: "Mail", icon: "app-mail" },
      { key: "f6", title: "Pull requests", app: "Browser", sub: "Work · github.com", icon: "app-orbit", tab: true },
      { key: "f7", title: "Switcher.swift", app: "Code", sub: "Code", icon: "app-code" },
    ]);
    panel.render({ selected: 0 });
    whileVisible(panel.el, async (alive) => {
      const queries = ["lisbon", "docs", "pull"];
      let round = 0;
      const playing = () => alive() && !panel.isTyping;
      while (alive()) {
        await sleep(1000);
        if (!playing()) continue;
        const query = queries[round++ % queries.length];
        for (let i = 1; i <= query.length && playing(); i++) {
          flipRender(panel, { query: query.slice(0, i), selected: 0, focused: true });
          await sleep(160);
        }
        await sleep(1300);
        if (playing() && panel.visible().length > 1) {
          panel.render({ selected: 1 });
          await sleep(900);
        }
        await sleep(600);
        if (playing()) flipRender(panel, { query: "", selected: 0 });
      }
    });
  }

  // MARK: Trackpad swipe

  for (const demo of $$('[data-demo="trackpad"]')) {
    const strip = $(".strip", demo);
    strip.innerHTML = ["app-browser", "app-messages", "app-code", "app-design", "app-photos"].map((id) => icon(id)).join("");
    const cells = [...strip.children];
    const select = (index) => cells.forEach((cell, i) => cell.classList.toggle("selected", i === index));
    select(0);
    if (animate) {
      const fingers = $(".fingers", demo);
      const timeline = gsap.timeline({ repeat: -1, repeatDelay: 0.8, paused: true });
      timeline
        .set(fingers, { x: -90, opacity: 0, scale: 1.15 })
        .call(() => select(0))
        .to(fingers, { opacity: 0.85, scale: 1, duration: 0.25 })
        .to(fingers, { x: 90, duration: 1.6, ease: "none" })
        .call(() => select(1), null, 0.6)
        .call(() => select(2), null, 1.0)
        .call(() => select(3), null, 1.4)
        .to(fingers, { opacity: 0, scale: 1.15, duration: 0.25 })
        .to(cells[3], { scale: 1.1, duration: 0.15, yoyo: true, repeat: 1 });
      new IntersectionObserver(([entry]) => (entry.isIntersecting ? timeline.play() : timeline.pause()), { threshold: 0.3 }).observe(strip);
    }
  }

  // MARK: Window buttons on hover

  for (const el of $$('[data-demo="buttons"]')) {
    const panel = new Panel(el, { thumb: { w: 204, h: 128 } });
    const all = ["browser", "code", "messages", "photos", "design", "calendar"].map((id) => ({ key: id, window: id, ...WINDOWS[id], badge: undefined }));
    panel.setItems(all);
    panel.render({ selected: 0 });
    for (const cell of panel.cells.values()) {
      $(".thumb", cell).insertAdjacentHTML("beforeend", '<span class="hover-lights" aria-hidden="true"><i></i><i></i><i></i></span>');
    }
    whileVisible(el, async (alive) => {
      let round = 0;
      while (alive()) {
        await sleep(900);
        const visible = panel.visible();
        const target = visible[(round++ % (visible.length - 1)) + 1];
        if (!target || !alive()) continue;
        panel.render({ selected: visible.indexOf(target) });
        const cell = panel.cells.get(target.key);
        cell.classList.add("hovered");
        await sleep(1100);
        if (!alive()) { cell.classList.remove("hovered"); break; }
        cell.classList.add("pressing");
        await sleep(260);
        cell.classList.remove("hovered", "pressing");
        if (animate) await gsap.to(cell, { opacity: 0, scale: 0.9, duration: 0.22, ease: "power2.in" });
        else await sleep(0);
        panel.excluded.add(target.key);
        flipRender(panel, { selected: 0 });
        if (hasGsap) gsap.set(cell, { clearProps: "opacity,transform" });
        await sleep(1500);
        if (panel.visible().length <= 3) {
          panel.excluded.clear();
          flipRender(panel, { selected: 0 });
          await sleep(900);
        }
      }
    });
  }

  // MARK: Building from source, typed out in Terminal

  const terminal = $("#terminal");
  if (terminal) {
    const lines = [
      { type: "git clone https://github.com/mohdmahmodi/glidetab.git" },
      { out: "Cloning into 'glidetab'... done." },
      { type: "cd glidetab && ./build.sh install" },
      { out: "Built build/GlideTab.app (universal)" },
      { out: '<span class="ok">✓</span> Installed and launched /Applications/GlideTab.app' },
    ];
    const prompt = '<span class="prompt">~ %</span> ';
    let played = false;
    const play = async () => {
      if (played) return;
      played = true;
      let html = "";
      for (const line of lines) {
        if (line.type) {
          for (let i = 1; i <= line.type.length; i++) {
            terminal.innerHTML = `${html}${prompt}${escapeHTML(line.type.slice(0, i))}<span class="cursor"></span>`;
            await sleep(reduceMotion ? 0 : 26);
          }
          html += `${prompt}${escapeHTML(line.type)}\n`;
          await sleep(reduceMotion ? 0 : 380);
        } else {
          html += `${line.out}\n`;
          terminal.innerHTML = `${html}<span class="cursor"></span>`;
          await sleep(reduceMotion ? 0 : 320);
        }
      }
      terminal.innerHTML = `${html}${prompt}<span class="cursor"></span>`;
    };
    new IntersectionObserver(([entry]) => entry.isIntersecting && play(), { threshold: 0.6 }).observe(terminal);
  }
})();
