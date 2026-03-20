# PDF Stop Card Redesign Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve per-stop PDF cards with better typography, a fixed text width, and two user-selectable layout modes (Normal and Story).

**Architecture:** Add `PDFLayoutMode` to the data model, add a UI toggle in the options sheet, then refactor `drawPlaceStopCard` into two clean layout functions (`drawNormalStopCard`, `drawStoryStopCard`) with three shared helpers (`drawStopHeader`, `drawPhotoGrid`, `drawSeparator`). No new files — all changes are in the two existing files.

**Tech Stack:** Swift, UIKit, CoreGraphics PDF renderer (`UIGraphicsPDFRenderer`), SwiftUI (options sheet)

---

## File Map

| File | Change |
|------|--------|
| `fastblog/Services/PDFExportService.swift` | Add `PDFLayoutMode` enum; update `PDFExportOptions`; refactor `drawPlaceStopCard` into router + two layout functions + three helpers |
| `fastblog/Views/PDFExportOptionsSheet.swift` | Add Layout Style section between Font Style and Photo Style |

> **Note:** This is UIKit CoreGraphics drawing code — there is no automated unit test framework in place and visual rendering cannot be unit tested. Each task is verified by building the project (`xcodebuild`) and, for layout tasks, by exporting a PDF on device/simulator and visually inspecting it.

---

## Build Command

Use this to verify each task compiles cleanly:

```bash
xcodebuild -project /Users/justinseo/Desktop/Bloggo/fastblog/fastblog.xcodeproj \
  -scheme fastblog -destination 'platform=iOS Simulator,name=iPhone 16' \
  build 2>&1 | tail -5
```

Expected output ends with: `** BUILD SUCCEEDED **`

---

## Task 1: Add `PDFLayoutMode` and update `PDFExportOptions`

**Files:**
- Modify: `fastblog/Services/PDFExportService.swift` (lines 62–77, after `PDFPhotoShapeOptions`)

- [ ] **Step 1: Add `PDFLayoutMode` enum after `PhotoShape` and before `PDFPhotoShapeOptions`**

  In `PDFExportService.swift`, find the line `/// Per-position photo shapes for the 2-column PDF grid.` and insert above it:

  ```swift
  enum PDFLayoutMode: String, CaseIterable, Codable {
      case normal = "Normal"
      case story  = "Story"

      var label: String { rawValue }
      var subtitle: String {
          switch self {
          case .normal: return "Caption above photos"
          case .story:  return "Photos first, caption below"
          }
      }
  }
  ```

- [ ] **Step 2: Add `layoutMode` field to `PDFExportOptions`**

  Find:
  ```swift
  struct PDFExportOptions: Codable, Equatable {
      var blogColor:        BlogColor           = .white
      var fontTheme:        FontTheme          = .classic
      var photoShapeOptions: PDFPhotoShapeOptions = PDFPhotoShapeOptions()
  }
  ```

  Replace with:
  ```swift
  struct PDFExportOptions: Codable, Equatable {
      var blogColor:         BlogColor            = .white
      var fontTheme:         FontTheme            = .classic
      var photoShapeOptions: PDFPhotoShapeOptions = PDFPhotoShapeOptions()
      var layoutMode:        PDFLayoutMode        = .normal
  }
  ```

- [ ] **Step 3: Build to verify**

  Run the build command above. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

  ```bash
  git add fastblog/Services/PDFExportService.swift
  git commit -m "feat: add PDFLayoutMode enum and layoutMode field to PDFExportOptions"
  ```

---

## Task 2: Add Layout Style section to `PDFExportOptionsSheet`

**Files:**
- Modify: `fastblog/Views/PDFExportOptionsSheet.swift`

The sheet currently renders: `blogColorSection`, `fontThemeSection`, `photoShapeSection`, `exportButton`. We insert a new `layoutStyleSection` between `fontThemeSection` and `photoShapeSection`.

- [ ] **Step 1: Add `layoutStyleSection` computed property**

  In `PDFExportOptionsSheet.swift`, add after the `fontThemeSection` property (around line 102, before `// MARK: - Photo Shape Section`):

  ```swift
  // MARK: - Layout Style Section

  private var layoutStyleSection: some View {
      VStack(alignment: .leading, spacing: 12) {
          sectionHeader("Layout Style", icon: "rectangle.split.2x1")

          VStack(spacing: 0) {
              ForEach(PDFLayoutMode.allCases, id: \.self) { mode in
                  optionRow(
                      title: mode.label,
                      subtitle: mode.subtitle,
                      isSelected: pending.layoutMode == mode
                  ) {
                      pending.layoutMode = mode
                  }
                  if mode != PDFLayoutMode.allCases.last {
                      Divider().padding(.leading, 52)
                  }
              }
          }
          .background(Color(uiColor: .secondarySystemGroupedBackground))
          .cornerRadius(12)
      }
  }
  ```

- [ ] **Step 2: Insert `layoutStyleSection` into `body`**

  Find in `body`:
  ```swift
  fontThemeSection
  photoShapeSection
  ```

  Replace with:
  ```swift
  fontThemeSection
  layoutStyleSection
  photoShapeSection
  ```

- [ ] **Step 3: Build to verify**

  Run the build command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

  ```bash
  git add fastblog/Views/PDFExportOptionsSheet.swift
  git commit -m "feat: add Layout Style section to PDF options sheet"
  ```

---

## Task 3: Extract shared helpers

**Files:**
- Modify: `fastblog/Services/PDFExportService.swift`

Extract three new private static functions from the existing `drawPlaceStopCard`. At this stage **do not change any drawing behavior** — just extract and wire up so the existing PDF output is identical. The existing `drawPlaceStopCard` will call these helpers temporarily until Task 6.

### 3a: `drawStopHeader`

Draws badge + title (with link icon) + subtitle/location. This is the block from `pen.skip(cardPadding)` through `pen.y += subSize.height` in the current function (approx lines 417–503).

- [ ] **Step 1: Add `drawStopHeader` as a new private static func**

  Add after `drawPlaceStopCard`'s closing brace, before `// MARK: - Photo Drawing`:

  ```swift
  // MARK: - Shared: Stop Header

  /// Draws badge + title (with Google search link) + location subtitle.
  /// Advances pen.y to the bottom of the location line.
  private static func drawStopHeader(
      pen: inout Pen,
      stop: PlaceStop,
      number: Int,
      badgeColor: UIColor,
      options: PDFExportOptions,
      primaryText: UIColor,
      secondaryText: UIColor
  ) {
      let badgeSize: CGFloat = 32
      let cardLeft = pen.margin + cardPadding
      let titleW = cardInteriorW - badgeSize - 10

      let titleFont = Self.font(for: options.fontTheme, size: 17, weight: .semibold)
      let subFont   = Self.font(for: options.fontTheme, size: 12)

      // ── Badge ──
      pen.drawBadge(number: number, color: badgeColor, size: badgeSize)

      // ── Title with link icon ──
      var titleAttrs: [NSAttributedString.Key: Any] = [
          .font: titleFont,
          .foregroundColor: primaryText
      ]

      var urlToOpen: URL?
      if let query = stop.placeTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
         let url = URL(string: "https://www.google.com/search?q=\(query)") {
          urlToOpen = url
      }

      let attrTitle = NSMutableAttributedString(string: stop.placeTitle, attributes: titleAttrs)

      // Reuse the same link icon base64 that was in drawPlaceStopCard
      let linkIconBase64 = "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"
      var customIcon: UIImage? = nil
      if let data = Data(base64Encoded: linkIconBase64) {
          customIcon = UIImage(data: data)
      }

      if let linkIcon = customIcon {
          let attachment = NSTextAttachment()
          attachment.image = linkIcon
          let iconSize: CGFloat = 13
          let yOffset = (titleFont.capHeight - iconSize) / 2
          attachment.bounds = CGRect(x: 0, y: yOffset, width: iconSize, height: iconSize)
          let noUnderlineAttrs: [NSAttributedString.Key: Any] = [.underlineStyle: 0]
          let spaceStr = NSAttributedString(string: " ", attributes: noUnderlineAttrs)
          let iconStr = NSMutableAttributedString(attachment: attachment)
          iconStr.addAttributes(noUnderlineAttrs, range: NSRange(location: 0, length: iconStr.length))
          attrTitle.append(spaceStr)
          attrTitle.append(iconStr)
      }

      let titleRectBounds = attrTitle.boundingRect(
          with: CGSize(width: titleW, height: .greatestFiniteMagnitude),
          options: [.usesLineFragmentOrigin], context: nil
      )
      let drawRect = CGRect(
          x: cardLeft + badgeSize + 10,
          y: pen.y + (badgeSize - titleRectBounds.height) / 2,
          width: titleW, height: titleRectBounds.height
      )
      attrTitle.draw(with: drawRect, options: [.usesLineFragmentOrigin], context: nil)

      if let url = urlToOpen {
          let pdfRect = CGRect(x: drawRect.minX, y: pen.pageH - drawRect.maxY,
                               width: drawRect.width, height: drawRect.height)
          pen.ctx.setURL(url, for: pdfRect)
      }

      pen.y += max(badgeSize, titleRectBounds.height)

      // ── Location subtitle ──
      let hasSubtitle = !(stop.placeSubtitle ?? "").isEmpty
      if hasSubtitle, let subtitle = stop.placeSubtitle {
          pen.skip(2)
          let subAttrs: [NSAttributedString.Key: Any] = [
              .font: subFont,
              .foregroundColor: secondaryText
          ]
          let subSize = subtitle.boundingRect(
              with: CGSize(width: titleW, height: .greatestFiniteMagnitude),
              options: [.usesLineFragmentOrigin],
              attributes: subAttrs, context: nil
          )
          subtitle.draw(
              with: CGRect(x: cardLeft + badgeSize + 10, y: pen.y,
                           width: titleW, height: subSize.height),
              options: [.usesLineFragmentOrigin],
              attributes: subAttrs, context: nil
          )
          pen.y += subSize.height
      }
  }
  ```

### 3b: `drawSeparator`

- [ ] **Step 2: Add `SeparatorStyle` enum and `drawSeparator` helper**

  Add after `drawStopHeader`, before `// MARK: - Photo Drawing`:

  ```swift
  // MARK: - Shared: Separator

  private enum SeparatorStyle {
      case thin   // 0.5pt line only
      case story  // lines flanking centered "STORY" label
  }

  /// Draws a separator and advances pen.y by 17pt (8 top + 1 line + 8 bottom).
  private static func drawSeparator(
      pen: inout Pen,
      style: SeparatorStyle,
      color: UIColor,
      cardLeft: CGFloat
  ) {
      let lineY = pen.y + 8
      guard let gc = UIGraphicsGetCurrentContext() else { pen.y += 17; return }

      switch style {
      case .thin:
          gc.saveGState()
          gc.setStrokeColor(color.cgColor)
          gc.setLineWidth(0.5)
          gc.move(to: CGPoint(x: cardLeft, y: lineY))
          gc.addLine(to: CGPoint(x: cardLeft + cardInteriorW, y: lineY))
          gc.strokePath()
          gc.restoreGState()

      case .story:
          let label = "STORY"
          let labelFont = UIFont.systemFont(ofSize: 9, weight: .medium)
          let labelAttrs: [NSAttributedString.Key: Any] = [
              .font: labelFont,
              .foregroundColor: color
          ]
          let labelSize = label.size(withAttributes: labelAttrs)
          let labelX = cardLeft + (cardInteriorW - labelSize.width) / 2
          label.draw(at: CGPoint(x: labelX, y: lineY - labelSize.height / 2), withAttributes: labelAttrs)

          let lineEndX = labelX - 8
          let lineStartX2 = labelX + labelSize.width + 8

          gc.saveGState()
          gc.setStrokeColor(color.cgColor)
          gc.setLineWidth(0.5)
          gc.move(to: CGPoint(x: cardLeft, y: lineY))
          gc.addLine(to: CGPoint(x: lineEndX, y: lineY))
          gc.move(to: CGPoint(x: lineStartX2, y: lineY))
          gc.addLine(to: CGPoint(x: cardLeft + cardInteriorW, y: lineY))
          gc.strokePath()
          gc.restoreGState()
      }

      pen.y += 17
  }
  ```

### 3c: `drawPhotoGrid`

- [ ] **Step 3: Add `drawPhotoGrid` helper**

  Add after `drawSeparator`, before `// MARK: - Photo Drawing`:

  ```swift
  // MARK: - Shared: Photo Grid

  /// Draws the 2-column photo grid with per-photo captions.
  /// - indent: offset from cardLeft. Per spec, photos are always full-width — pass 0 in both Normal and Story modes.
  /// - cardLeft: pen.margin + cardPadding
  private static func drawPhotoGrid(
      pen: inout Pen,
      photos: [(RecapPhoto, UIImage)],
      indent: CGFloat,
      cardLeft: CGFloat,
      options: PDFExportOptions,
      secondaryText: UIColor,
      cardBgColor: UIColor
  ) {
      guard !photos.isEmpty else { return }
      let captionFont = Self.font(for: options.fontTheme, size: 11)
      let colW = photoSize
      let colH = photoSize
      let gridLeft = cardLeft + indent

      let pageBeforePhotos = pen.pageNumber
      pen.skip(8)
      if pen.pageNumber != pageBeforePhotos {
          let rowCount = (photos.count + 1) / 2
          let estRemaining = CGFloat(rowCount) * (photoSize + 45) + cardPadding + 8
          let contH = min(estRemaining, pen.maxY - pen.y)
          if let gc = UIGraphicsGetCurrentContext(), contH > 0 {
              gc.saveGState()
              gc.setFillColor(cardBgColor.cgColor)
              gc.fill(CGRect(x: pen.margin, y: pen.y, width: contentW, height: contH))
              gc.restoreGState()
          }
      }

      for row in stride(from: 0, to: photos.count, by: 2) {
          let pageBeforeEnsure = pen.pageNumber
          pen.ensureRoom(colH + 40)
          if pen.pageNumber != pageBeforeEnsure {
              let rowsLeft = (photos.count - row + 1) / 2
              let estRemaining = CGFloat(rowsLeft) * (colH + 45) + cardPadding + 8
              let contH = min(estRemaining, pen.maxY - pen.y)
              if let gc = UIGraphicsGetCurrentContext(), contH > 0 {
                  gc.saveGState()
                  gc.setFillColor(cardBgColor.cgColor)
                  gc.fill(CGRect(x: pen.margin, y: pen.y, width: contentW, height: contH))
                  gc.restoreGState()
              }
          }

          let (leftPhoto, leftImg) = photos[row]
          let hasPair = row + 1 < photos.count
          let leftShape = hasPair ? options.photoShapeOptions.leftShape : options.photoShapeOptions.singleShape
          let leftRect = CGRect(x: gridLeft, y: pen.y, width: colW, height: colH)
          drawPhoto(leftImg, in: leftRect, shape: leftShape)

          if hasPair {
              let (_, rightImg) = photos[row + 1]
              let rightRect = CGRect(x: gridLeft + colW + photoGap, y: pen.y, width: colW, height: colH)
              drawPhoto(rightImg, in: rightRect, shape: options.photoShapeOptions.rightShape)
          }
          pen.y += colH

          // Per-photo captions
          var captionH: CGFloat = 0
          if let cap = leftPhoto.caption, !cap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              pen.skip(3)
              let capAttrs: [NSAttributedString.Key: Any] = [.font: captionFont, .foregroundColor: secondaryText]
              let capSize = cap.boundingRect(
                  with: CGSize(width: colW, height: 28),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                  attributes: capAttrs, context: nil
              )
              let h = min(capSize.height, 28)
              cap.draw(with: CGRect(x: gridLeft, y: pen.y, width: colW, height: h),
                       options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                       attributes: capAttrs, context: nil)
              captionH = max(captionH, h + 3)
          }
          if hasPair {
              let (rightPhoto, _) = photos[row + 1]
              if let cap = rightPhoto.caption, !cap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                  let capAttrs: [NSAttributedString.Key: Any] = [.font: captionFont, .foregroundColor: secondaryText]
                  let capSize = cap.boundingRect(
                      with: CGSize(width: colW, height: 28),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                      attributes: capAttrs, context: nil
                  )
                  let h = min(capSize.height, 28)
                  cap.draw(with: CGRect(x: gridLeft + colW + photoGap, y: pen.y, width: colW, height: h),
                           options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                           attributes: capAttrs, context: nil)
                  captionH = max(captionH, h + 3)
              }
          }
          pen.y += captionH
          pen.skip(10)
      }
  }
  ```

- [ ] **Step 4: Build to verify**

  Run the build command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

  ```bash
  git add fastblog/Services/PDFExportService.swift
  git commit -m "refactor: extract drawStopHeader, drawSeparator, drawPhotoGrid helpers"
  ```

---

## Task 4: Implement `drawNormalStopCard`

**Files:**
- Modify: `fastblog/Services/PDFExportService.swift`

Normal mode: header (badge + title + location) → caption (indented, max-width 466pt) → thin separator (if caption exists) → photo grid (full width).

- [ ] **Step 1: Add `drawNormalStopCard` after the helpers, before `// MARK: - Photo Drawing`**

  ```swift
  // MARK: - Normal Stop Card

  private static func drawNormalStopCard(
      pen: inout Pen,
      stop: PlaceStop,
      number: Int,
      badgeColor: UIColor,
      photos: [(RecapPhoto, UIImage)],
      options: PDFExportOptions,
      cardBgColor: UIColor,
      primaryText: UIColor,
      secondaryText: UIColor,
      separatorColor: UIColor
  ) {
      let badgeSize: CGFloat = 32
      let cardLeft = pen.margin + cardPadding
      let textIndent: CGFloat = badgeSize + 10  // 42pt
      let captionMaxW = cardInteriorW - textIndent  // 466pt

      let titleFont    = Self.font(for: options.fontTheme, size: 17, weight: .semibold)
      let subFont      = Self.font(for: options.fontTheme, size: 12)
      let captionFont  = Self.font(for: options.fontTheme, size: 14)

      let hasCaption = !(stop.overallStory ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      let hasSubtitle = !(stop.placeSubtitle ?? "").isEmpty

      // ── Pre-compute card height for background ──
      let estTitleH = max(badgeSize, estimateTextHeight(stop.placeTitle, font: titleFont, width: cardInteriorW - textIndent))
      var estContentH = estTitleH
      if hasSubtitle, let sub = stop.placeSubtitle {
          estContentH += 2 + estimateTextHeight(sub, font: subFont, width: cardInteriorW - textIndent)
      }
      if hasCaption, let caption = stop.overallStory {
          estContentH += 8 + estimateTextHeight(caption, font: captionFont, width: captionMaxW)
          estContentH += 17  // separator
      } else {
          estContentH += 8  // gap before photos
      }
      if !photos.isEmpty {
          let rowCount = (photos.count + 1) / 2
          estContentH += CGFloat(rowCount) * (photoSize + 10) + 8
      }
      let totalCardH = cardPadding + estContentH + cardPadding

      // Cohesion: keep header + separator + first photo row together
      let captionHForCohesion = hasCaption
          ? min(estimateTextHeight(stop.overallStory ?? "", font: captionFont, width: captionMaxW), 68)
          : 0
      let subHForCohesion = hasSubtitle
          ? 2 + estimateTextHeight(stop.placeSubtitle ?? "", font: subFont, width: cardInteriorW - textIndent)
          : 0
      let headerH = estTitleH + subHForCohesion + (hasCaption ? 8 + captionHForCohesion : 8)
      let separatorH: CGFloat = hasCaption ? 17 : 0
      let firstPhotoH: CGFloat = photos.isEmpty ? 0 : photoSize
      let cohesionH = cardPadding + headerH + separatorH + firstPhotoH + cardPadding
      pen.ensureRoom(min(cohesionH, (pen.pageH - pen.margin * 2) * 0.6))

      // ── Card background ──
      let bgH = min(totalCardH, pen.maxY - pen.y)
      if let gc = UIGraphicsGetCurrentContext() {
          gc.saveGState()
          let bgRect = CGRect(x: pen.margin, y: pen.y, width: contentW, height: bgH)
          gc.setFillColor(cardBgColor.cgColor)
          UIBezierPath(roundedRect: bgRect, cornerRadius: cardRadius).addClip()
          gc.fill(bgRect)
          gc.restoreGState()
      }
      pen.skip(cardPadding)

      // ── Header (badge + title + location) ──
      drawStopHeader(pen: &pen, stop: stop, number: number, badgeColor: badgeColor,
                     options: options, primaryText: primaryText, secondaryText: secondaryText)

      // ── Caption ──
      if hasCaption, let caption = stop.overallStory {
          pen.skip(8)
          let captionAttrs: [NSAttributedString.Key: Any] = [
              .font: captionFont,
              .foregroundColor: secondaryText
          ]
          let captionSize = caption.boundingRect(
              with: CGSize(width: captionMaxW, height: .greatestFiniteMagnitude),
              options: [.usesLineFragmentOrigin],
              attributes: captionAttrs, context: nil
          )
          caption.draw(
              with: CGRect(x: cardLeft + textIndent, y: pen.y,
                           width: captionMaxW, height: captionSize.height),
              options: [.usesLineFragmentOrigin],
              attributes: captionAttrs, context: nil
          )
          pen.y += captionSize.height

          // Thin separator between caption and photos
          drawSeparator(pen: &pen, style: .thin, color: separatorColor, cardLeft: cardLeft)
      } else {
          pen.skip(8)
      }

      // ── Photo grid (full width, indent = 0) ──
      drawPhotoGrid(pen: &pen, photos: photos, indent: 0, cardLeft: cardLeft,
                    options: options, secondaryText: secondaryText, cardBgColor: cardBgColor)

      pen.skip(cardPadding)
  }
  ```

- [ ] **Step 2: Build to verify**

  Run the build command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

  ```bash
  git add fastblog/Services/PDFExportService.swift
  git commit -m "feat: implement drawNormalStopCard"
  ```

---

## Task 5: Implement `drawStoryStopCard`

**Files:**
- Modify: `fastblog/Services/PDFExportService.swift`

Story mode: header → photos (full width) → per-photo captions → `── STORY ──` divider → caption block. Fallbacks: zero photos → render like Normal; no caption → skip divider and caption.

- [ ] **Step 1: Add `drawStoryStopCard` after `drawNormalStopCard`**

  ```swift
  // MARK: - Story Stop Card

  private static func drawStoryStopCard(
      pen: inout Pen,
      stop: PlaceStop,
      number: Int,
      badgeColor: UIColor,
      photos: [(RecapPhoto, UIImage)],
      options: PDFExportOptions,
      cardBgColor: UIColor,
      primaryText: UIColor,
      secondaryText: UIColor,
      separatorColor: UIColor
  ) {
      let badgeSize: CGFloat = 32
      let cardLeft = pen.margin + cardPadding

      let titleFont   = Self.font(for: options.fontTheme, size: 17, weight: .semibold)
      let subFont     = Self.font(for: options.fontTheme, size: 12)
      let captionFont = Self.font(for: options.fontTheme, size: 14)

      let hasPhotos  = !photos.isEmpty
      let hasCaption = !(stop.overallStory ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      let hasSubtitle = !(stop.placeSubtitle ?? "").isEmpty

      // ── Pre-compute card height for background ──
      let estTitleH = max(badgeSize, estimateTextHeight(stop.placeTitle, font: titleFont, width: cardInteriorW - badgeSize - 10))
      var estContentH = estTitleH
      if hasSubtitle, let sub = stop.placeSubtitle {
          estContentH += 2 + estimateTextHeight(sub, font: subFont, width: cardInteriorW - badgeSize - 10)
      }
      if hasPhotos {
          let rowCount = (photos.count + 1) / 2
          estContentH += 8 + CGFloat(rowCount) * (photoSize + 10)
          if hasCaption, let caption = stop.overallStory {
              estContentH += 17  // STORY separator
              estContentH += estimateTextHeight(caption, font: captionFont, width: cardInteriorW)
          }
      } else if hasCaption, let caption = stop.overallStory {
          // No photos: fall through to Normal-style caption
          estContentH += 8 + estimateTextHeight(caption, font: captionFont, width: cardInteriorW - badgeSize - 10)
      }
      let totalCardH = cardPadding + estContentH + cardPadding

      // Cohesion: header + first photo row (or caption if no photos)
      let subHForCohesion = hasSubtitle
          ? 2 + estimateTextHeight(stop.placeSubtitle ?? "", font: subFont, width: cardInteriorW - badgeSize - 10)
          : 0
      let headerH = estTitleH + subHForCohesion
      let firstRowH: CGFloat = hasPhotos ? (photoSize + 10) : 0
      let cohesionH = cardPadding + headerH + 8 + firstRowH + cardPadding
      pen.ensureRoom(min(cohesionH, (pen.pageH - pen.margin * 2) * 0.6))

      // ── Card background ──
      let bgH = min(totalCardH, pen.maxY - pen.y)
      if let gc = UIGraphicsGetCurrentContext() {
          gc.saveGState()
          let bgRect = CGRect(x: pen.margin, y: pen.y, width: contentW, height: bgH)
          gc.setFillColor(cardBgColor.cgColor)
          UIBezierPath(roundedRect: bgRect, cornerRadius: cardRadius).addClip()
          gc.fill(bgRect)
          gc.restoreGState()
      }
      pen.skip(cardPadding)

      // ── Header ──
      drawStopHeader(pen: &pen, stop: stop, number: number, badgeColor: badgeColor,
                     options: options, primaryText: primaryText, secondaryText: secondaryText)

      if hasPhotos {
          // ── Photos (full width) ──
          drawPhotoGrid(pen: &pen, photos: photos, indent: 0, cardLeft: cardLeft,
                        options: options, secondaryText: secondaryText, cardBgColor: cardBgColor)

          // ── STORY divider + caption (only if caption exists) ──
          if hasCaption, let caption = stop.overallStory {
              drawSeparator(pen: &pen, style: .story, color: separatorColor, cardLeft: cardLeft)

              let captionAttrs: [NSAttributedString.Key: Any] = [
                  .font: captionFont,
                  .foregroundColor: secondaryText
              ]
              let captionSize = caption.boundingRect(
                  with: CGSize(width: cardInteriorW, height: .greatestFiniteMagnitude),
                  options: [.usesLineFragmentOrigin],
                  attributes: captionAttrs, context: nil
              )
              pen.ensureRoom(captionSize.height)
              caption.draw(
                  with: CGRect(x: cardLeft, y: pen.y,
                               width: cardInteriorW, height: captionSize.height),
                  options: [.usesLineFragmentOrigin],
                  attributes: captionAttrs, context: nil
              )
              pen.y += captionSize.height
          }
      } else if hasCaption, let caption = stop.overallStory {
          // No photos: render caption like Normal mode (indented)
          let textIndent: CGFloat = badgeSize + 10
          let captionMaxW = cardInteriorW - textIndent
          pen.skip(8)
          let captionAttrs: [NSAttributedString.Key: Any] = [
              .font: captionFont,
              .foregroundColor: secondaryText
          ]
          let captionSize = caption.boundingRect(
              with: CGSize(width: captionMaxW, height: .greatestFiniteMagnitude),
              options: [.usesLineFragmentOrigin],
              attributes: captionAttrs, context: nil
          )
          caption.draw(
              with: CGRect(x: cardLeft + textIndent, y: pen.y,
                           width: captionMaxW, height: captionSize.height),
              options: [.usesLineFragmentOrigin],
              attributes: captionAttrs, context: nil
          )
          pen.y += captionSize.height
      }

      pen.skip(cardPadding)
  }
  ```

- [ ] **Step 2: Build to verify**

  Run the build command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

  ```bash
  git add fastblog/Services/PDFExportService.swift
  git commit -m "feat: implement drawStoryStopCard"
  ```

---

## Task 6: Wire up the router and remove the old `drawPlaceStopCard` body

**Files:**
- Modify: `fastblog/Services/PDFExportService.swift`

Replace the entire body of `drawPlaceStopCard` with a router that calls the two new functions. Delete all the old inline drawing code (approx 300 lines, lines 334–643).

- [ ] **Step 1: Replace `drawPlaceStopCard` body with the router**

  Find the entire `private static func drawPlaceStopCard(` function and replace its body (everything between the opening `{` and closing `}`) with:

  ```swift
  private static func drawPlaceStopCard(
      pen: inout Pen,
      stop: PlaceStop,
      number: Int,
      badgeColor: UIColor,
      photos: [UUID: UIImage],
      options: PDFExportOptions,
      cardBgColor: UIColor,
      primaryText: UIColor,
      secondaryText: UIColor,
      separatorColor: UIColor
  ) {
      let includedPhotos = stop.photos.filter(\.isIncluded)
      let photosWithImages = includedPhotos.compactMap { p -> (RecapPhoto, UIImage)? in
          guard let img = photos[p.id] else { return nil }
          return (p, img)
      }

      switch options.layoutMode {
      case .normal:
          drawNormalStopCard(pen: &pen, stop: stop, number: number, badgeColor: badgeColor,
                             photos: photosWithImages, options: options, cardBgColor: cardBgColor,
                             primaryText: primaryText, secondaryText: secondaryText,
                             separatorColor: separatorColor)
      case .story:
          drawStoryStopCard(pen: &pen, stop: stop, number: number, badgeColor: badgeColor,
                            photos: photosWithImages, options: options, cardBgColor: cardBgColor,
                            primaryText: primaryText, secondaryText: secondaryText,
                            separatorColor: separatorColor)
      }
  }
  ```

- [ ] **Step 2: Build to verify**

  Run the build command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Also update the badge size constant in `Pen.drawBadge`**

  In the `Pen` struct, `drawBadge` currently calls `pen.drawBadge(number: number, color: badgeColor, size: badgeSize)` and the badge size was 28. The new `badgeSize` is 32pt, set inside each draw function — this is already handled since `drawNormalStopCard` and `drawStoryStopCard` pass `badgeSize = 32` to `drawStopHeader`. No change needed to `Pen.drawBadge` itself. Confirm by reading the `drawBadge` function — it accepts the size as a parameter and doesn't hardcode anything.

- [ ] **Step 4: Final build**

  Run the build command. Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

  ```bash
  git add fastblog/Services/PDFExportService.swift
  git commit -m "refactor: wire up drawPlaceStopCard router, remove old inline body"
  ```

---

## Task 7: Visual Verification

- [ ] **Step 1: Run the app on simulator, open an existing trip blog**
- [ ] **Step 2: Tap Export → PDF Options**
  - Confirm the **Layout Style** section appears between Font Style and Photo Style
  - Confirm Normal and Story rows are present and selectable
- [ ] **Step 3: Export with Normal mode**
  - Open the PDF and visually verify:
    - Badge is 32pt circular
    - Title is larger/bolder than location text
    - Caption appears above photos, indented, no full-width stretch
    - Thin separator line between caption and photos
    - Photo grid is full width (not indented)
- [ ] **Step 4: Export with Story mode**
  - Open the PDF and visually verify:
    - Photos appear directly below header
    - `── STORY ──` divider appears after photos
    - Caption appears below divider at full card width
- [ ] **Step 5: Final commit**

  ```bash
  git add fastblog/Services/PDFExportService.swift fastblog/Views/PDFExportOptionsSheet.swift
  git commit -m "feat: PDF stop card redesign — Normal/Story modes, typography hierarchy"
  ```
