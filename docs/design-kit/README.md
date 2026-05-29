# Bloggo Visual Design Kit

**Hub:** [Figma — Bloggo Design Kit](https://www.figma.com/) *(paste team file URL after creation)*

Single visual source of truth for product design, engineering, clients, marketing, and QA. Markdown in this folder describes the kit; **pixels live in Figma**.

## Who opens what

| Role | Figma access | Start on page |
|------|----------------|---------------|
| Product / UX | Can edit | `Components`, `Screens` |
| Engineering | Can view + Dev Mode | `Components`, `Resources` |
| Client / PM | Can view (comment) | `Start here`, `Screens` |
| Marketing | Can view | `Brand`, `Resources` |
| QA | Can view | `Screens`, `Patterns` |

## Repo mirrors (secondary — export from Figma)

- **PDF:** `exports/Bloggo-Design-Kit-{version}.pdf` — Brand + Screens only (for email/Slack)
- **Implementation tokens:** `.ai/skills/ui/` — must match Figma variable names

## Quick import (no manual hex entry)

1. **Variables (~2 min):** [import-to-figma.md](./import-to-figma.md) → TokensBrücke → `tokens/bloggo.tokens.json`
2. **Screens (~10 min):** Open `html/design-kit-v1.html` → **html.to.design** plugin → re-bind fills to variables

## Documents

| File | Purpose |
|------|---------|
| [import-to-figma.md](./import-to-figma.md) | **Start here** — what imports flawlessly vs manual |
| [tokens/bloggo.tokens.json](./tokens/bloggo.tokens.json) | Paste into Figma via TokensBrücke |
| [html/design-kit-v1.html](./html/design-kit-v1.html) | Visual screens for html.to.design |
| [figma-build-guide.md](./figma-build-guide.md) | Page-by-page build instructions, variables, components, publishing |

## Versioning

Update the **Resources → Changelog** frame in Figma and bump `CHANGELOG.md` here when UI ships (e.g. camera home, bottom nav).
