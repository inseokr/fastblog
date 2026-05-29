# Import Bloggo Design Kit into Figma

**Short answer:** I cannot log into your Figma or create a native `.fig` file from here. You *can* get **colors and spacing variables in one click** from the JSON in this repo. **Full screens and components** need a second step (HTML import or ~30–60 min manual assembly using those variables).

---

## What is near-flawless vs what is not

| Asset | Method | Fidelity |
|-------|--------|----------|
| **Color + number variables** | [TokensBrücke](https://www.figma.com/community/plugin/1254538877056388290) → Import JSON | **~95%** — names, hex, spacing match repo |
| **Typography styles** | Manual in Figma (or Tokens Studio) | Figma Variables don’t support font composites natively |
| **Components** (BottomNav, cards) | Build once using variables | **100%** after first build |
| **Full screens** | [html.to.design](https://www.figma.com/community/plugin/1159127764991605925) from HTML | **~70–80%** — always review layers |
| **Entire kit in one paste** | ❌ Not possible | No clipboard format for full kits |

---

## Path A — Variables (do this first, ~2 minutes)

### 1. Create an empty Figma file

`Bloggo Design Kit` → add pages from [figma-build-guide.md](./figma-build-guide.md).

### 2. Install plugin

**TokensBrücke** (Figma Community): [tokens-bruecke/figma-plugin](https://www.figma.com/community/plugin/1254538877056388290)

### 3. Import JSON

1. Run **TokensBrücke** in your file.
2. Click **Import JSON**.
3. Select: `docs/design-kit/tokens/bloggo.tokens.json`
4. Confirm — you should see two collections:
   - **color** — `background/app`, `action/primary`, scrims, etc.
   - **layout** — `nav/bar-content-height` (62), `space/screen-horizontal` (20), radii, etc.

### 4. Verify

On **Foundations** page, create rectangles and bind fills to `color/background/app`, `color/action/primary`, etc. If hex matches the guide, tokens are live.

### Alternative: Tokens Studio for Figma

1. Install **Tokens Studio**.
2. **Styles & Variables → Import** → load the same JSON (may need to map groups manually).
3. **Sync to Figma Variables** from the plugin.

Use one plugin as source of truth — not both on the same file without a process.

---

## Path B — Visual screens (optional, ~10 min + cleanup)

### 1. Open the HTML reference

In a browser, open:

`docs/design-kit/html/design-kit-v1.html`

(local file: double-click or drag into Chrome)

### 2. Import to Figma

1. Install **html.to.design** (Figma Community).
2. In the plugin, paste the page URL or use **Import local HTML** if supported; otherwise host the file briefly (e.g. `python3 -m http.server` in `docs/design-kit/html/`).
3. Select frames: **Foundations**, **Camera**, **My Blogs**, **My Places**.
4. After import:
   - Replace hardcoded fills with **variables** from Path A.
   - Rename layers (plugin names are messy).
   - Resize frame to **393 × 852** if needed.

### 3. Publish

Turn repeated pieces (bottom nav, Tap to Blog banner) into **components** bound to variables.

---

## Path C — Enterprise / API (optional)

TokensBrücke CLI can push variables with a Figma **Enterprise** API token and file key. Not required for most teams — Path A is enough.

---

## What we maintain in the repo

| File | Role |
|------|------|
| `tokens/bloggo.tokens.json` | Single import source for Figma Variables |
| `html/design-kit-v1.html` | Visual reference + html.to.design input |
| `figma-build-guide.md` | Pages, components, governance after import |

When colors change in code, update **JSON first** → re-import or sync in Figma → update `.ai/skills/ui/colors/palette.md`.

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Import creates wrong types | In TokensBrücke, use standard `type`/`value` (this JSON already does) |
| Slash names become nested groups | Expected: `background/app` in Figma matches token path |
| HTML import colors wrong | Re-bind fills to imported variables |
| Typography missing | Add **Text styles** manually on Foundations (SF Pro, sizes in guide) |

---

## Checklist after import

- [ ] Variables: `color` + `layout` collections present
- [ ] Foundations swatches use variables, not raw hex
- [ ] Bottom nav height = `layout/nav/bar-content-height` (62)
- [ ] Three screens on **Screens** page (from HTML or manual)
- [ ] Components published as library
- [ ] File URL added to [README.md](./README.md)
