# Security

GlideTab needs Accessibility, Screen Recording and Automation access, so please report security issues privately.

## Reporting a vulnerability

Don't open a public issue. Use GitHub's private vulnerability reporting (Security tab → Report a vulnerability) and include steps to reproduce. You'll get a reply within a few days.

## Supported versions

Only the latest release gets security fixes.

## Data handling

- Window titles, browser tab titles and addresses, and thumbnails are read only to show them in the switcher. They stay in memory and are never written to disk or sent anywhere.
- The only network request is the optional update check to the GitHub Releases API.
- An update is installed only if it's signed by the same developer as the running app, notarized if the running copy is, and newer than it.
