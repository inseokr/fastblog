# Camera Roll → Blog Onboarding Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Insert an animated onboarding page between SplashView and ProblemStatementView that shows 12 photos falling chaotically, then transforms into the real Bloggo blog UI which scrolls up to reveal a tagline and Continue button.

**Architecture:** Single new SwiftUI view `CameraRollToBlogView` drives all 7 animation phases via one `async` function using `Task.sleep` sequencing (never `DispatchQueue.main.asyncAfter`). The view is wired into `OnboardingFlowView` by adding a `.cameraRollToBlog` step. A blog mock sub-view renders hardcoded Bali trip data using real app colors/fonts to faithfully represent the actual blog UI.

**Tech Stack:** SwiftUI, `@State`, `withAnimation`, `Task { }` async sequencing, `LinearGradient`, `ScrollView(.horizontal)`

---

## File map

| Action | File | What changes |
|--------|------|-------------|
| **Create** | `fastblog/Views/Onboarding/CameraRollToBlogView.swift` | New animated onboarding view |
| **Modify** | `fastblog/Views/Onboarding/OnboardingFlowView.swift` | Add step + wire navigation |
| **Modify** | `fastblog.xcodeproj/project.pbxproj` | Register new file (3 sections) |

New pbxproj IDs (next available after `BB0003E3`):
- `BB0003E4` — PBXFileReference
- `BB0003E5` — PBXBuildFile

---

## Task 1: Create `CameraRollToBlogView.swift`

**Files:**
- Create: `fastblog/Views/Onboarding/CameraRollToBlogView.swift`

- [ ] **Step 1: Create the file with the full implementation**

Create `fastblog/Views/Onboarding/CameraRollToBlogView.swift` with this exact content:

```swift
import SwiftUI

// MARK: - Data model for each falling photo tile

private struct FallingPhotoData {
    let width: CGFloat
    let height: CGFloat
    let xOffset: CGFloat   // distance from leading edge of screen
    let landY: CGFloat     // final top-offset after falling
    let rotation: Double   // degrees
    let colors: [Color]
    let filename: String
}

// MARK: - Main view

struct CameraRollToBlogView: View {
    var onContinue: () -> Void

    // MARK: Phase 1 — camera roll label
    @State private var showCameraLabel = false

    // MARK: Phase 2 — falling photos (12 tiles)
    @State private var photoOpacities: [Double] = Array(repeating: 0, count: 12)
    @State private var photoOffsets: [CGFloat]  = Array(repeating: -220, count: 12)

    // MARK: Phase 3 — dissolve
    @State private var dissolvePhotos = false

    // MARK: Phase 4 — flash
    @State private var showFlash = false

    // MARK: Phase 5 — blog UI + staggered reveal
    @State private var showBlogUI      = false
    @State private var showCoverTitle  = false
    @State private var showCoverMeta   = false
    @State private var showShareBtn    = false
    @State private var showMap         = false
    @State private var showDayHeader   = false
    @State private var showStop1       = false
    @State private var showStop2       = false
    @State private var showDayPills    = false

    // MARK: Phase 6 — blog scrolls up
    @State private var blogOffset: CGFloat = 0

    // MARK: Phase 7 — tagline + continue
    @State private var showTagline  = false
    @State private var showContinue = false

    // MARK: - Hardcoded photo tile data

    private let fallingPhotos: [FallingPhotoData] = [
        .init(width: 88,  height: 88,  xOffset: 18,  landY: 318, rotation: -11, colors: [Color(red:0.88,green:0.44,blue:0.25), Color(red:0.69,green:0.25,blue:0.13)], filename: "IMG_3847"),
        .init(width: 72,  height: 95,  xOffset: 192, landY: 283, rotation:  15, colors: [Color(red:0.25,green:0.44,blue:0.88), Color(red:0.13,green:0.25,blue:0.63)], filename: "IMG_0291"),
        .init(width: 60,  height: 60,  xOffset: 118, landY: 350, rotation:  -4, colors: [Color(red:0.25,green:0.63,blue:0.38), Color(red:0.13,green:0.44,blue:0.25)], filename: "IMG_5512"),
        .init(width: 98,  height: 70,  xOffset: 162, landY: 228, rotation:  19, colors: [Color(red:0.56,green:0.25,blue:0.69), Color(red:0.38,green:0.06,blue:0.56)], filename: "IMG_7734"),
        .init(width: 55,  height: 75,  xOffset: 6,   landY: 386, rotation: -17, colors: [Color(red:0.88,green:0.25,blue:0.38), Color(red:0.63,green:0.06,blue:0.25)], filename: "IMG_1192"),
        .init(width: 78,  height: 78,  xOffset: 66,  landY: 258, rotation:   6, colors: [Color(red:0.81,green:0.63,blue:0.25), Color(red:0.56,green:0.38,blue:0.06)], filename: "IMG_4405"),
        .init(width: 65,  height: 90,  xOffset: 226, landY: 328, rotation: -10, colors: [Color(red:0.25,green:0.75,blue:0.63), Color(red:0.06,green:0.50,blue:0.38)], filename: "IMG_8823"),
        .init(width: 108, height: 74,  xOffset: 84,  landY: 198, rotation: -14, colors: [Color(red:0.38,green:0.50,blue:0.81), Color(red:0.19,green:0.31,blue:0.63)], filename: "IMG_2267"),
        .init(width: 58,  height: 58,  xOffset: 150, landY: 415, rotation:   8, colors: [Color(red:0.88,green:0.50,blue:0.19), Color(red:0.63,green:0.25,blue:0.06)], filename: "IMG_6098"),
        .init(width: 75,  height: 85,  xOffset: 36,  landY: 365, rotation:  12, colors: [Color(red:0.19,green:0.56,blue:0.75), Color(red:0.06,green:0.31,blue:0.50)], filename: "IMG_3311"),
        .init(width: 66,  height: 100, xOffset: 108, landY: 276, rotation:  -7, colors: [Color(red:0.63,green:0.31,blue:0.63), Color(red:0.38,green:0.06,blue:0.38)], filename: "IMG_9940"),
        .init(width: 54,  height: 64,  xOffset: 204, landY: 445, rotation:  22, colors: [Color(red:0.38,green:0.63,blue:0.31), Color(red:0.19,green:0.38,blue:0.19)], filename: "IMG_0774"),
    ]

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [
                    OnboardingConstants.Colors.backgroundGradientTop,
                    OnboardingConstants.Colors.backgroundGradientBottom
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Phase 1: camera roll label
            cameraRollLabel

            // Phase 2–3: falling + dissolving photo tiles
            fallingPhotosLayer

            // Phase 4: white flash
            Color.white
                .ignoresSafeArea()
                .opacity(showFlash ? 0.22 : 0)
                .allowsHitTesting(false)

            // Phase 5–6: blog mock (slides upward)
            if showBlogUI {
                blogMockView
                    .offset(y: blogOffset)
                    .transition(.opacity)
            }

            // Phase 7: tagline overlay + continue button
            if showTagline {
                taglineOverlay
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .task { await startAnimation() }
    }

    // MARK: - Phase 1: Camera roll label

    private var cameraRollLabel: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 36, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
            Text("Your Camera Roll")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
                .tracking(0.5)
        }
        .opacity(showCameraLabel ? 1 : 0)
        .scaleEffect(showCameraLabel ? 1 : 0.9)
    }

    // MARK: - Phase 2–3: Falling photos

    private var fallingPhotosLayer: some View {
        GeometryReader { _ in
            ForEach(fallingPhotos.indices, id: \.self) { i in
                let p = fallingPhotos[i]
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: p.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: p.width, height: p.height)
                    .overlay(alignment: .bottomLeading) {
                        Text(p.filename)
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .padding(5)
                    }
                    .rotationEffect(.degrees(p.rotation))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.45), radius: 8, y: 4)
                    .position(x: p.xOffset + p.width / 2, y: photoOffsets[i] + p.height / 2)
                    .opacity(photoOpacities[i])
                    .blur(radius: dissolvePhotos ? 4 : 0)
                    .scaleEffect(dissolvePhotos ? 0.8 : 1)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Phase 5: Blog mock

    private var blogMockView: some View {
        VStack(spacing: 0) {
            coverHeroMock
            blogScrollContent
        }
        .background(Color.black)
        .ignoresSafeArea(edges: .bottom)
    }

    // Cover photo hero — matches CoverPageView + RecapBlogPageView view mode
    private var coverHeroMock: some View {
        ZStack {
            // Simulated travel cover photo
            LinearGradient(
                colors: [
                    Color(red: 0.48, green: 0.25, blue: 0.13),
                    Color(red: 0.17, green: 0.25, blue: 0.38),
                    Color(red: 0.06, green: 0.11, blue: 0.19)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Scrims — matches coverPhotoHero exactly
            Color.black.opacity(0.38)
            LinearGradient(
                colors: [.black.opacity(0.62), .black.opacity(0.12), .black.opacity(0.45)],
                startPoint: .bottom,
                endPoint: .top
            )

            // Centered title block — matches view mode VStack(spacing: 14)
            VStack(spacing: 10) {
                Text("Bali 2024")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.6), radius: 6, y: 2)
                    .opacity(showCoverTitle ? 1 : 0)
                    .offset(y: showCoverTitle ? 0 : 10)

                VStack(spacing: 4) {
                    Text("Jun 12 – Jun 17, 2024")
                        .font(.callout)
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                    Text("14 moments")
                        .font(.callout)
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                }
                .opacity(showCoverMeta ? 1 : 0)
                .offset(y: showCoverMeta ? 0 : 8)

                // "Share Your Blog" capsule — matches RecapBlogPageView button
                HStack(spacing: 6) {
                    Image(systemName: "book.pages")
                        .font(.system(size: 14, weight: .medium))
                    Text("Share Your Blog")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.15).background(.ultraThinMaterial))
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                .opacity(showShareBtn ? 1 : 0)
                .offset(y: showShareBtn ? 0 : 8)
            }
            .padding(.horizontal, 24)
        }
        .frame(height: 220)
    }

    // Scroll content: map + day header + 2 stop rows + day pill bar
    private var blogScrollContent: some View {
        VStack(spacing: 0) {
            // Map card
            mapCardMock
                .opacity(showMap ? 1 : 0)
                .offset(y: showMap ? 0 : 10)

            // Day header — matches daySection() date row
            HStack(spacing: 8) {
                Text("Jun 12")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                Text("☀️ 84° / 71°F")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 6)
            .opacity(showDayHeader ? 1 : 0)
            .offset(y: showDayHeader ? 0 : 8)

            // Place stop rows
            placeStopRow(
                number: 1,
                badgeColor: .green,
                name: "Tegallalang Rice Terraces",
                subtitle: "Ubud, Bali  ·  2:14 PM",
                categorySymbol: "leaf.fill",
                categoryLabel: "Nature",
                categoryColor: .green,
                photoColors: [
                    [Color(red:0.88,green:0.44,blue:0.25), Color(red:0.56,green:0.19,blue:0.13)],
                    [Color(red:0.81,green:0.56,blue:0.19), Color(red:0.50,green:0.31,blue:0.06)],
                    [Color(red:0.25,green:0.63,blue:0.38), Color(red:0.13,green:0.38,blue:0.25)]
                ],
                photoTimes: ["2:14 PM", "2:21 PM", "2:35 PM"],
                overflow: "+7"
            )
            .opacity(showStop1 ? 1 : 0)
            .offset(y: showStop1 ? 0 : 10)

            placeStopRow(
                number: 2,
                badgeColor: .blue,
                name: "Tirta Empul Temple",
                subtitle: "Tampaksiring  ·  4:50 PM",
                categorySymbol: "building.columns.fill",
                categoryLabel: "Landmark",
                categoryColor: .blue,
                photoColors: [
                    [Color(red:0.25,green:0.44,blue:0.88), Color(red:0.13,green:0.25,blue:0.63)],
                    [Color(red:0.38,green:0.50,blue:0.81), Color(red:0.19,green:0.31,blue:0.63)]
                ],
                photoTimes: ["4:50 PM", "5:02 PM"],
                overflow: "+4"
            )
            .opacity(showStop2 ? 1 : 0)
            .offset(y: showStop2 ? 0 : 10)

            Spacer(minLength: 0)

            // Day pill bar — matches dayPill() bottom strip
            dayPillBar
                .opacity(showDayPills ? 1 : 0)
        }
        .background(Color.black)
    }

    // Inline map placeholder — matches mapCard() appearance
    private var mapCardMock: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
                )
            // Fake map grid
            Canvas { context, size in
                let gridColor = Color.white.opacity(0.06)
                for x in stride(from: CGFloat(0), through: size.width, by: 24) {
                    context.stroke(Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) }, with: .color(gridColor), lineWidth: 1)
                }
                for y in stride(from: CGFloat(0), through: size.height, by: 24) {
                    context.stroke(Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) }, with: .color(gridColor), lineWidth: 1)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            // Three location pins
            Circle().fill(Color.green).frame(width: 10, height: 10)
                .position(x: 90, y: 28)
            Circle().fill(Color.blue).frame(width: 10, height: 10)
                .position(x: 170, y: 52)
            Circle().fill(Color.orange).frame(width: 10, height: 10)
                .position(x: 130, y: 68)

            // Expand icon — matches mapCard expand button
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.black.opacity(0.55))
                .clipShape(Circle())
                .padding(10)
        }
        .frame(height: 90)
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    // Single place stop row — matches PlaceStopRowView layout
    @ViewBuilder
    private func placeStopRow(
        number: Int,
        badgeColor: Color,
        name: String,
        subtitle: String,
        categorySymbol: String,
        categoryLabel: String,
        categoryColor: Color,
        photoColors: [[Color]],
        photoTimes: [String],
        overflow: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Numbered badge — matches stopBadge in PlaceStopRowView
            ZStack {
                Circle().fill(badgeColor)
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 28, height: 28)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                // Place name — 15pt bold, matches PlaceStopRowView
                Text(name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)

                // Subtitle (location + time)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.45))

                // Category chip — matches PlaceCategoryChip
                HStack(spacing: 4) {
                    Image(systemName: categorySymbol)
                        .font(.caption2)
                    Text(categoryLabel)
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundStyle(categoryColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(categoryColor.opacity(0.18)))
                .padding(.top, 2)

                // Photo strip — 80% of screen width per photo, horizontal scroll
                photoStrip(colors: photoColors, times: photoTimes, overflow: overflow)
            }
        }
        .padding(12)
        .background(Color(white: 0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    // Horizontal photo strip — matches photoStripThumbnailSize (UIScreen width * 0.8)
    private func photoStrip(colors: [[Color]], times: [String], overflow: String) -> some View {
        let thumbWidth = UIScreen.main.bounds.width * 0.68 // 0.68 accounts for stop-row insets
        let thumbHeight: CGFloat = 180

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(colors.indices, id: \.self) { i in
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(LinearGradient(
                                colors: colors[i],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: thumbWidth, height: thumbHeight)

                        // Timestamp badge — matches photoTimestampBadge()
                        if i < times.count {
                            Text(times[i])
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.black.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                                .padding(8)
                        }
                    }
                }

                // Overflow chip
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 60, height: thumbHeight)
                    .overlay(
                        Text(overflow)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.45))
                    )
            }
        }
        .padding(.top, 4)
    }

    // Day pill bar — matches dayPill() bottom strip
    private var dayPillBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(["Day 1", "Day 2", "Day 3", "Day 4", "Day 5"], id: \.self) { label in
                    Text(label)
                        .font(.subheadline)
                        .fontWeight(label == "Day 1" ? .semibold : .regular)
                        .foregroundColor(label == "Day 1" ? .white : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(label == "Day 1" ? Color.blue : Color(white: 0.2))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 50)
        .background(Color.black)
        .overlay(alignment: .top) {
            Color.white.opacity(0.08).frame(height: 0.5)
        }
    }

    // MARK: - Phase 7: Tagline overlay + Continue button

    private var taglineOverlay: some View {
        ZStack {
            Color.black.opacity(0.72)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 14) {
                    // Star glyph
                    Text("✦")
                        .font(.system(size: 30))
                        .foregroundColor(.white.opacity(0.7))
                        .scaleEffect(showTagline ? 1 : 0.5)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.1), value: showTagline)

                    // "Introducing Bloggo" label
                    Text("INTRODUCING BLOGGO")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.45))
                        .tracking(2)
                        .opacity(showTagline ? 1 : 0)
                        .offset(y: showTagline ? 0 : 8)
                        .animation(.easeOut(duration: 0.45).delay(0.2), value: showTagline)

                    // Main headline
                    Group {
                        Text("Your camera roll,\norganized into\na ")
                            .foregroundColor(.white)
                        + Text("Blog.")
                            .foregroundColor(Color(red: 200/255, green: 235/255, blue: 1.0))
                    }
                    .font(.system(size: 24, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
                    .opacity(showTagline ? 1 : 0)
                    .offset(y: showTagline ? 0 : 10)
                    .animation(.easeOut(duration: 0.5).delay(0.35), value: showTagline)

                    // Subtitle
                    Text("Automatically sorted by day,\nplace & moment.")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .opacity(showTagline ? 1 : 0)
                        .offset(y: showTagline ? 0 : 8)
                        .animation(.easeOut(duration: 0.45).delay(0.5), value: showTagline)
                }
                .padding(.horizontal, 28)

                Spacer()

                // Continue button — matches ProblemStatementView button style
                Button(action: onContinue) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(OnboardingConstants.Colors.doneButtonBlue)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
                .opacity(showContinue ? 1 : 0)
                .offset(y: showContinue ? 0 : 12)
                .animation(.spring(response: 0.4, dampingFraction: 0.75).delay(0), value: showContinue)
            }
        }
    }

    // MARK: - Animation sequence

    @MainActor
    private func startAnimation() async {
        // Phase 1: camera roll label
        try? await Task.sleep(for: .milliseconds(300))
        withAnimation(.easeOut(duration: 0.4)) { showCameraLabel = true }

        // Phase 2: 12 photos fall, staggered 100 ms apart
        try? await Task.sleep(for: .milliseconds(500))
        for i in 0..<fallingPhotos.count {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(100))
            withAnimation(.easeIn(duration: 0.6)) {
                photoOpacities[i] = 1
                photoOffsets[i] = fallingPhotos[i].landY
            }
        }

        // Phase 3: dissolve all photos + fade label
        try? await Task.sleep(for: .milliseconds(600))
        withAnimation(.easeOut(duration: 0.3)) { showCameraLabel = false }
        withAnimation(.easeIn(duration: 0.5)) { dissolvePhotos = true }

        // Phase 4: white flash
        try? await Task.sleep(for: .milliseconds(400))
        withAnimation(.easeOut(duration: 0.18)) { showFlash = true }
        try? await Task.sleep(for: .milliseconds(180))
        withAnimation(.easeOut(duration: 0.28)) { showFlash = false }

        // Phase 5: blog UI builds in — staggered reveals
        try? await Task.sleep(for: .milliseconds(100))
        withAnimation(.easeOut(duration: 0.4)) { showBlogUI = true }
        try? await Task.sleep(for: .milliseconds(300))
        withAnimation(.easeOut(duration: 0.45)) { showCoverTitle = true }
        try? await Task.sleep(for: .milliseconds(200))
        withAnimation(.easeOut(duration: 0.4)) { showCoverMeta = true }
        try? await Task.sleep(for: .milliseconds(150))
        withAnimation(.easeOut(duration: 0.4)) { showShareBtn = true }
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.easeOut(duration: 0.4)) { showMap = true }
        try? await Task.sleep(for: .milliseconds(200))
        withAnimation(.easeOut(duration: 0.35)) { showDayHeader = true }
        try? await Task.sleep(for: .milliseconds(200))
        withAnimation(.easeOut(duration: 0.38)) { showStop1 = true }
        try? await Task.sleep(for: .milliseconds(200))
        withAnimation(.easeOut(duration: 0.38)) { showStop2 = true }
        try? await Task.sleep(for: .milliseconds(200))
        withAnimation(.easeOut(duration: 0.4)) { showDayPills = true }

        // Phase 6: wait 1.5 s, then slide entire blog view upward
        try? await Task.sleep(for: .milliseconds(1500))
        withAnimation(.easeInOut(duration: 1.4)) { blogOffset = -220 }

        // Phase 7: tagline overlay fades in after scroll starts settling
        try? await Task.sleep(for: .milliseconds(1600))
        showTagline = true

        // Continue button slides in 0.8 s later
        try? await Task.sleep(for: .milliseconds(800))
        showContinue = true
    }
}
```

- [ ] **Step 2: Verify the file is saved and well-formed**

```bash
wc -l /Users/justinseo/Desktop/Bloggo/fastblog/fastblog/Views/Onboarding/CameraRollToBlogView.swift
```
Expected: a line count above 200 (no truncation).

---

## Task 2: Register the file in `project.pbxproj`

**Files:**
- Modify: `fastblog.xcodeproj/project.pbxproj`

The pbxproj needs three additions. Make each edit separately so you can verify each one.

- [ ] **Step 1: Add the PBXBuildFile entry**

Find this line (around line 217):
```
		BB000309 /* TripDistanceFromHomeOnboardingView.swift in Sources */ = {isa = PBXBuildFile; fileRef = BB000308 /* TripDistanceFromHomeOnboardingView.swift */; };
```

Add immediately after it:
```
		BB0003E5 /* CameraRollToBlogView.swift in Sources */ = {isa = PBXBuildFile; fileRef = BB0003E4 /* CameraRollToBlogView.swift */; };
```

- [ ] **Step 2: Add the PBXFileReference entry**

Find this line (around line 472):
```
		BB000308 /* TripDistanceFromHomeOnboardingView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = TripDistanceFromHomeOnboardingView.swift; sourceTree = "<group>"; };
```

Add immediately after it:
```
		BB0003E4 /* CameraRollToBlogView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CameraRollToBlogView.swift; sourceTree = "<group>"; };
```

- [ ] **Step 3: Add to the Onboarding PBXGroup**

Find this section (around line 768):
```
			BB00017D /* SplashView.swift */,
```

Add immediately after it:
```
			BB0003E4 /* CameraRollToBlogView.swift */,
```

- [ ] **Step 4: Add to PBXSourcesBuildPhase**

Find (around line 1069):
```
			BB00017E /* SplashView.swift in Sources */,
```

Add immediately after it:
```
			BB0003E5 /* CameraRollToBlogView.swift in Sources */,
```

- [ ] **Step 5: Verify pbxproj has all four occurrences**

```bash
grep -c "CameraRollToBlogView" /Users/justinseo/Desktop/Bloggo/fastblog/fastblog.xcodeproj/project.pbxproj
```
Expected output: `4`

---

## Task 3: Wire into `OnboardingFlowView`

**Files:**
- Modify: `fastblog/Views/Onboarding/OnboardingFlowView.swift`

- [ ] **Step 1: Add the new step to the enum**

Find:
```swift
enum OnboardingStep {
    case splash
    case problemStatement
```

Replace with:
```swift
enum OnboardingStep {
    case splash
    case cameraRollToBlog
    case problemStatement
```

- [ ] **Step 2: Change SplashView's callback to go to the new step**

Find:
```swift
            if step == .splash {
                SplashView {
                    step = .problemStatement
                }
```

Replace with:
```swift
            if step == .splash {
                SplashView {
                    step = .cameraRollToBlog
                }
```

- [ ] **Step 3: Insert the new branch between splash and problemStatement**

Find:
```swift
            } else if step == .problemStatement {
```

Add the new branch immediately before it:
```swift
            } else if step == .cameraRollToBlog {
                CameraRollToBlogView {
                    step = .problemStatement
                }
            } else if step == .problemStatement {
```

- [ ] **Step 4: Verify OnboardingFlowView compiles cleanly — build the project**

```bash
xcodebuild -project /Users/justinseo/Desktop/Bloggo/fastblog/fastblog.xcodeproj -scheme Bloggo -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

If there are errors, fix them before proceeding.

---

## Task 4: Verify end-to-end on simulator

- [ ] **Step 1: Reset onboarding state so the flow runs from the beginning**

In the simulator: **Device → Erase All Content and Settings**, or run the app and in Xcode console execute:
```
UserDefaults.standard.removeObject(forKey: "blogify.hasCompletedOnboarding")
```

Alternatively, in `OnboardingFlowView.swift` temporarily force `@State private var step: OnboardingStep = .cameraRollToBlog` to jump straight to the new page, then revert after testing.

- [ ] **Step 2: Walk through the full animation sequence**

Launch the app on the simulator and verify each phase:

| Phase | What to observe |
|-------|----------------|
| 1 | SF Symbol camera icon + "Your Camera Roll" text fades in |
| 2 | 12 photo tiles fall one by one from the top with rotations |
| 3 | All photos dissolve (blur + fade + scale down) |
| 4 | Brief white flash |
| 5 | Blog UI fades in — cover gradient → title "Bali 2024" → dates → "Share Your Blog" button → map → "Jun 12" day header → Tegallalang stop → Tirta Empul stop → day pills |
| 6 | After 1.5 s, entire blog slides upward ~220 pt |
| 7 | Tagline overlay appears: "✦" → "INTRODUCING BLOGGO" → "Your camera roll, organized into a Blog." → subtitle |
| 8 | "Continue" button slides in at bottom |

- [ ] **Step 3: Tap Continue and verify navigation**

Tapping Continue must land on `NeighborhoodExplainerView` ("Set Your Home Area").
The rest of the onboarding flow (neighborhood → photo permission → trip distance) must be unaffected.

- [ ] **Step 4: Commit**

```bash
cd /Users/justinseo/Desktop/Bloggo/fastblog && git add fastblog/Views/Onboarding/CameraRollToBlogView.swift fastblog/Views/Onboarding/OnboardingFlowView.swift fastblog.xcodeproj/project.pbxproj && git commit -m "$(cat <<'EOF'
feat: add camera roll to blog animated onboarding page

Inserts CameraRollToBlogView between SplashView and ProblemStatementView.
7-phase animation shows photos falling chaotically then transforming into
the real Bloggo blog UI, ending with a tagline and Continue button.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```
