// Comparison data, shared by the Compare page's script and by tools/build.mjs, which writes the
// per-app pages. Edit it here and run `node site/tools/build.mjs` from the repository root.
(function (root, factory) {
  if (typeof module !== "undefined" && module.exports) module.exports = factory();
  else root.COMPARE = factory();
})(typeof self !== "undefined" ? self : this, function () {
  "use strict";

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
    glidetab: {
      name: "GlideTab", price: "Free", look: "grid",
      windows: true, hold: true, previews: true, search: "Always on", tabs: true, source: "MIT",
    },
    commandtab: {
      name: "⌘Tab", price: "Built into macOS", look: "icons",
      windows: "Apps only", hold: true, previews: false, search: false, tabs: false, source: false,
      pick: "you'd rather not install anything and keep one window per app.",
      slug: "command-tab", site: "https://support.apple.com/guide/mac-help/switch-between-apps-mchlp2458/mac",
      title: "GlideTab vs ⌘Tab: switching windows instead of apps on a Mac",
      description: "The built-in ⌘Tab switcher on macOS only switches between apps. GlideTab shows every window with a live preview and lets you type to find one. Free and open source.",
      heading: "GlideTab vs the built-in ⌘Tab",
      tagline: "The switcher every Mac ships with, next to one that sees windows.",
      intro: [
        "⌘Tab is the switcher built into macOS. It shows one icon per running app, so if you have three browser windows or two documents open, it treats them as one entry and takes you to whichever was in front last. It has no previews and no search, and it can't bring a minimized window back.",
        "GlideTab works the same way with your hands: hold a key, tap Tab, let go. The difference is what it shows. Every window gets its own spot with a live picture of it, including windows on other Spaces and displays, minimized windows and hidden apps. Start typing and the list narrows to matching window titles, app names and browser tabs.",
        "You can keep ⌘Tab as it is and give GlideTab its own keys, or let GlideTab take over ⌘Tab. The built-in switcher comes back the moment you quit GlideTab.",
      ],
    },
    missioncontrol: {
      name: "Mission Control", price: "Built into macOS", look: "spread",
      windows: true, hold: "Mouse first", previews: "Full size", search: false, tabs: false, source: false,
      pick: "you like seeing every window laid out at once.",
      slug: "mission-control", site: "https://support.apple.com/guide/mac-help/mission-control-mh35798/mac",
      title: "GlideTab vs Mission Control: finding a window on a Mac",
      description: "Mission Control spreads every window across the screen. GlideTab shows them in a grid you move through from the keyboard, with search. Free and open source.",
      heading: "GlideTab vs Mission Control",
      tagline: "Both show every window. One is built for the keyboard.",
      intro: [
        "Mission Control is the macOS feature that spreads every open window across the screen, in full size, so you can click the one you want. It's built in, it's free, and it shows windows at a scale no switcher panel can match.",
        "It's also built around the mouse. You open it with a gesture or a key, then move the pointer to a window and click. There's no way to type a name, and windows on other Spaces are off to the side as separate desktops rather than in the same view.",
        "GlideTab is the keyboard version of the same idea: every window in one grid, with a preview, in the order you last used them. Hold Option, tap Tab to move, let go to switch, or type part of a title to jump straight to it. Many people keep both and use Mission Control when they want to see everything at once.",
      ],
    },
    alttab: {
      name: "AltTab", price: "Free, Pro $9.99", look: "grid",
      windows: true, hold: true, previews: true, search: "Pro only", tabs: false, source: "GPL-3.0",
      pick: "you're on macOS 12 or 13, or want sorting, animations and single-key actions.",
      slug: "alttab", site: "https://alt-tab-macos.netlify.app",
      title: "GlideTab vs AltTab: free Mac window switchers compared",
      description: "AltTab and GlideTab both bring a Windows-style switcher to macOS, free and open source. The differences: search, browser tabs, and which macOS versions they run on.",
      heading: "GlideTab vs AltTab",
      tagline: "Two free, open source window switchers for the Mac.",
      intro: [
        "AltTab is the best-known window switcher for macOS. It's free, open source under the GPL, and has been around for years, with a large set of options for sorting, animations, single-key actions and appearance. A paid Pro upgrade adds search and a few more features. It runs on older versions of macOS than GlideTab does.",
        "GlideTab started from the same idea, a switcher that shows windows rather than apps, and focused on two things AltTab doesn't do in its free version. You can type while the switcher is open to find a window by its title or app name, and your browser tabs show up in that search, from every window and every profile, so you can jump to a tab without first finding its window.",
        "It's also smaller in scope. There are fewer settings, no plug-ins, and the app is about 5 MB with no third-party code. If you want a lot of knobs, AltTab has more of them. If you want to type a name and be there, that's what GlideTab is for.",
      ],
    },
    witch: {
      name: "Witch", price: "$14", look: "list",
      windows: true, hold: true, previews: true, search: true, tabs: true, source: false,
      pick: "your Mac runs an older macOS, or you want deep control over the list.",
      slug: "witch", site: "https://manytricks.com/witch/",
      title: "GlideTab vs Witch: Mac window switchers compared",
      description: "Witch is a paid window switcher for macOS with search and browser tabs. GlideTab does both for free, with live previews in a grid. Here's how they compare.",
      heading: "GlideTab vs Witch",
      tagline: "The closest match on features, with one big difference in price.",
      intro: [
        "Witch, from Many Tricks, is the longest-running window switcher on the Mac. It shows windows in a list, with previews, and it has the two features that set GlideTab apart from most other switchers: you can type to search, and browser tabs can appear in the list. It costs $14 and supports older versions of macOS.",
        "GlideTab offers the same core set for free: windows across all Spaces and displays, live previews, search by typing, and browser tabs from Safari, Chrome, Brave, Edge, Vivaldi, Firefox and Zen. The default look is a grid of previews rather than a list, though a list style is one click away in Settings.",
        "Witch has more ways to tune the list and more years of edge cases handled. GlideTab is newer, open source, and needs macOS 14 or later. If you're on a Mac that can run it, the honest comparison is that you get the same job done without paying.",
      ],
    },
    contexts: {
      name: "Contexts", price: "$9.99", look: "sidebar",
      windows: true, hold: true, previews: false, search: true, tabs: false, source: false,
      pick: "you want a sidebar of windows that's always there.",
      slug: "contexts", site: "https://contexts.co",
      title: "GlideTab vs Contexts: Mac window switcher comparison",
      description: "Contexts puts a window list in a sidebar with search. GlideTab shows live previews in a grid, adds browser tabs, and is free and open source.",
      heading: "GlideTab vs Contexts",
      tagline: "A sidebar you can always see, or a grid you summon.",
      intro: [
        "Contexts takes a different approach from most switchers. Its main feature is a sidebar that stays on the edge of the screen listing every window, so you can click any of them at any time. It also has a ⌘Tab-style panel and a search you reach with a shortcut, and it costs $9.99.",
        "GlideTab doesn't have a permanent sidebar. It appears when you hold Option and press Tab, shows every window with a live preview, and disappears when you let go. Typing while it's open searches window titles, app names and browser tabs.",
        "If you like having the list on screen all the time, Contexts is built for that. If you'd rather keep the screen clear and call the switcher up with a key, GlideTab is the free option that also shows what each window looks like.",
      ],
    },
    hyperswitch: {
      name: "HyperSwitch", price: "Free, beta", look: "grid",
      windows: true, hold: true, previews: true, search: false, tabs: false, source: false,
      pick: "your Mac runs a macOS older than 14.",
      slug: "hyperswitch", site: "https://bahoom.com/hyperswitch",
      title: "GlideTab vs HyperSwitch: free Mac window switchers",
      description: "HyperSwitch is a free, long-running beta window switcher for macOS. GlideTab adds search and browser tabs and is open source. Compared side by side.",
      heading: "GlideTab vs HyperSwitch",
      tagline: "Two free switchers, from different eras.",
      intro: [
        "HyperSwitch has been a free beta for many years. It adds window switching to macOS with previews, in a panel that looks a lot like the Windows one, and it still works on versions of macOS that newer apps have dropped.",
        "GlideTab covers the same ground and adds search by typing and browser tabs in the results. It's open source, signed and notarized, updates itself, and needs macOS 14 or later.",
        "If your Mac can't run macOS 14, HyperSwitch is one of the few free options left. If it can, GlideTab is the more current choice, with source code you can read and a release you can check.",
      ],
    },
    raycast: {
      name: "Raycast", price: "Free, Pro from $8/mo", look: "launcher",
      windows: true, hold: "Opens a launcher", previews: false, search: true, tabs: false, source: false,
      pick: "you already use Raycast and a searchable list is enough.",
      slug: "raycast", site: "https://www.raycast.com",
      title: "GlideTab vs Raycast for switching windows on a Mac",
      description: "Raycast can list and switch windows from its launcher. GlideTab is a dedicated switcher: hold Option, tap Tab, see every window with a preview. Free and open source.",
      heading: "GlideTab vs Raycast",
      tagline: "A launcher that can switch windows, and a switcher that only does that.",
      intro: [
        "Raycast is a launcher. You open it with a shortcut, type, and it runs commands, opens apps, does math and much more. One of its commands lists your open windows so you can search and switch to one. It's free for that, with a paid plan for cloud features.",
        "GlideTab does one thing. Hold Option and press Tab to see every window with a live preview, in the order you last used them, and tap Tab to move between them without typing anything. You can type to search too, and browser tabs appear in the results.",
        "Plenty of people use both: Raycast to open things, GlideTab to move between the windows they already have open. If the window list inside Raycast is all you need, you can skip the extra app.",
      ],
    },
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

  const mark = (value) => {
    if (value === true) return '<span class="yes"><svg aria-hidden="true"><use href="/icons.svg#i-check"/></svg><span class="visually-hidden">Yes</span></span>';
    if (value === false) return '<span class="no"><svg aria-hidden="true"><use href="/icons.svg#i-dash"/></svg><span class="visually-hidden">No</span></span>';
    return `<span class="note">${value}</span>`;
  };

  // GlideTab next to one app.
  function duelCard(key) {
    const them = APPS[key];
    const ours = APPS.glidetab;
    const rows = ROWS.map(([field, label]) => `<tr><th scope="row">${label}</th><td class="ours">${mark(ours[field])}</td><td>${mark(them[field])}</td></tr>`).join("");
    return `<div class="duel-card">
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

  // Every app in one chart.
  function matrix() {
    const keys = Object.keys(APPS);
    const head = keys.map((key) => `<th scope="col"${key === "glidetab" ? ' class="ours"' : ""}><b>${APPS[key].name}</b><small>${APPS[key].price}</small></th>`).join("");
    const rows = ROWS.map(([field, label]) => `<tr><th scope="row">${label}</th>${keys.map((key) => `<td${key === "glidetab" ? ' class="ours"' : ""}>${mark(APPS[key][field])}</td>`).join("")}</tr>`).join("");
    return `<div class="matrix"><div class="scroll"><table><thead><tr><th scope="col"><span class="visually-hidden">Feature</span></th>${head}</tr></thead><tbody>${rows}</tbody></table></div></div>`;
  }

  return { ROWS, APPS, LOOKS, duelCard, matrix };
});
