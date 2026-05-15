import SwiftUI
import UIKit

// MARK: - Data model for each falling photo tile

private struct FallingPhotoData {
    let width: CGFloat
    let height: CGFloat
    let xFraction: CGFloat    // left-edge as fraction of screen width (0–1)
    let landYFraction: CGFloat // landing Y as fraction of screen height (0–1)
    let rotation: Double       // degrees
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
    @State private var photoOffsets: [CGFloat]  = Array(repeating: -240, count: 12)

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

    @State private var showPrivacyPolicy = false
    @State private var showTermsOfService = false

    // MARK: - Hardcoded photo tile data (xFraction: left edge / screenWidth, shifted right for visual balance)

    private let fallingPhotos: [FallingPhotoData] = [
        .init(width: 140, height: 140, xFraction: 0.10, landYFraction: 0.42, rotation: -11, colors: [Color(red:0.88,green:0.44,blue:0.25), Color(red:0.69,green:0.25,blue:0.13)], filename: "IMG_3847"),
        .init(width: 115, height: 150, xFraction: 0.54, landYFraction: 0.37, rotation:  15, colors: [Color(red:0.25,green:0.44,blue:0.88), Color(red:0.13,green:0.25,blue:0.63)], filename: "IMG_0291"),
        .init(width: 95,  height: 95,  xFraction: 0.34, landYFraction: 0.47, rotation:  -4, colors: [Color(red:0.25,green:0.63,blue:0.38), Color(red:0.13,green:0.44,blue:0.25)], filename: "IMG_5512"),
        .init(width: 150, height: 110, xFraction: 0.55, landYFraction: 0.30, rotation:  19, colors: [Color(red:0.56,green:0.25,blue:0.69), Color(red:0.38,green:0.06,blue:0.56)], filename: "IMG_7734"),
        .init(width: 105, height: 125, xFraction: 0.08, landYFraction: 0.52, rotation: -17, colors: [Color(red:0.88,green:0.25,blue:0.38), Color(red:0.63,green:0.06,blue:0.25)], filename: "IMG_1192"),
        .init(width: 120, height: 120, xFraction: 0.22, landYFraction: 0.34, rotation:   6, colors: [Color(red:0.81,green:0.63,blue:0.25), Color(red:0.56,green:0.38,blue:0.06)], filename: "IMG_4405"),
        .init(width: 100, height: 135, xFraction: 0.58, landYFraction: 0.44, rotation: -10, colors: [Color(red:0.25,green:0.75,blue:0.63), Color(red:0.06,green:0.50,blue:0.38)], filename: "IMG_8823"),
        .init(width: 165, height: 120, xFraction: 0.20, landYFraction: 0.26, rotation: -14, colors: [Color(red:0.38,green:0.50,blue:0.81), Color(red:0.19,green:0.31,blue:0.63)], filename: "IMG_2267"),
        .init(width: 92,  height: 92,  xFraction: 0.42, landYFraction: 0.57, rotation:   8, colors: [Color(red:0.88,green:0.50,blue:0.19), Color(red:0.63,green:0.25,blue:0.06)], filename: "IMG_6098"),
        .init(width: 115, height: 130, xFraction: 0.12, landYFraction: 0.49, rotation:  12, colors: [Color(red:0.19,green:0.56,blue:0.75), Color(red:0.06,green:0.31,blue:0.50)], filename: "IMG_3311"),
        .init(width: 105, height: 155, xFraction: 0.32, landYFraction: 0.36, rotation:  -7, colors: [Color(red:0.63,green:0.31,blue:0.63), Color(red:0.38,green:0.06,blue:0.38)], filename: "IMG_9940"),
        .init(width: 88,  height: 100, xFraction: 0.56, landYFraction: 0.62, rotation:  22, colors: [Color(red:0.38,green:0.63,blue:0.31), Color(red:0.19,green:0.38,blue:0.19)], filename: "IMG_0774"),
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

            // Phase 5–6: blog mock pinned to screen top via clear full-screen anchor
            if showBlogUI {
                Color.clear
                    .ignoresSafeArea()
                    .overlay(alignment: .top) { blogMockView }
                    .offset(y: blogOffset)
                    .transition(.opacity)
            }

            // Day pills: fixed at screen bottom, independent of blog scroll offset
            if showDayPills {
                VStack(spacing: 0) {
                    Spacer()
                    dayPillBar
                }
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
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyView()
        }
        .sheet(isPresented: $showTermsOfService) {
            TermsOfServiceView()
        }
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
        GeometryReader { geo in
            ForEach(fallingPhotos.indices, id: \.self) { i in
                let p = fallingPhotos[i]
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: p.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: p.width, height: p.height)
                    .overlay(alignment: .bottomLeading) {
                        Text(p.filename)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.4))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .padding(6)
                    }
                    .rotationEffect(.degrees(p.rotation))
                    .shadow(color: .black.opacity(0.5), radius: 10, y: 5)
                    .position(
                        x: p.xFraction * geo.size.width + p.width / 2,
                        y: photoOffsets[i] + p.height / 2
                    )
                    .opacity(photoOpacities[i])
                    .blur(radius: dissolvePhotos ? 4 : 0)
                    .scaleEffect(dissolvePhotos ? 0.8 : 1)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Phase 5: Blog mock (no day pills — they're fixed in body ZStack)

    private var blogMockView: some View {
        VStack(spacing: 0) {
            coverHeroMock
            blogScrollContent
        }
        .background(Color.black)
    }

    // Cover photo hero — matches CoverPageView + RecapBlogPageView view mode
    private var coverHeroMock: some View {
        ZStack {
            // Vivid tropical gradient — clearly reads as a travel photo
            LinearGradient(
                colors: [
                    Color(red: 0.85, green: 0.48, blue: 0.22),
                    Color(red: 0.55, green: 0.35, blue: 0.60),
                    Color(red: 0.10, green: 0.28, blue: 0.55)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Light bottom scrim only — keeps text readable without hiding the gradient
            LinearGradient(
                colors: [.black.opacity(0.55), .black.opacity(0.05)],
                startPoint: .bottom,
                endPoint: .center
            )

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
        .frame(height: 300)
    }

    // Scroll content: map + day header + 2 stop rows (day pills are fixed in body ZStack)
    private var blogScrollContent: some View {
        VStack(spacing: 0) {
            mapCardMock
                .opacity(showMap ? 1 : 0)
                .offset(y: showMap ? 0 : 10)

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

            // Extra bottom space so stop rows aren't hidden behind fixed day pill bar
            Color.clear.frame(height: 58)
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

            Circle().fill(Color.green).frame(width: 10, height: 10)
                .position(x: 90, y: 28)
            Circle().fill(Color.blue).frame(width: 10, height: 10)
                .position(x: 170, y: 52)
            Circle().fill(Color.orange).frame(width: 10, height: 10)
                .position(x: 130, y: 68)

            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.black.opacity(0.55))
                .clipShape(Circle())
                .padding(10)
        }
        .frame(height: 140)
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
            ZStack {
                Circle().fill(badgeColor)
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 28, height: 28)
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.45))

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

    // Horizontal photo strip — square thumbnails at 0.8× screen width, matching PlaceStopRowView exactly
    private func photoStrip(colors: [[Color]], times: [String], overflow: String) -> some View {
        let thumbSize = UIScreen.main.bounds.width * 0.8 // square, matches photoStripThumbnailSize

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
                            .frame(width: thumbSize, height: thumbSize)

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

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 60, height: thumbSize)
                    .overlay(
                        Text(overflow)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white.opacity(0.45))
                    )
            }
        }
        .padding(.top, 4)
    }

    // Day pill bar — fixed at screen bottom via body ZStack
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
            // Full-screen frosted dark background
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.72))
                .ignoresSafeArea()

            // Tagline — centered in safe-area bounds (ZStack default)
            VStack(spacing: 14) {
                Text("✦")
                    .font(.system(size: 36))
                    .foregroundColor(.white.opacity(0.7))
                    .scaleEffect(showTagline ? 1 : 0.5)
                    .animation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.1), value: showTagline)

                Text("INTRODUCING BLOGGO")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white.opacity(0.45))
                    .tracking(2)
                    .opacity(showTagline ? 1 : 0)
                    .offset(y: showTagline ? 0 : 8)
                    .animation(.easeOut(duration: 0.45).delay(0.2), value: showTagline)

                Group {
                    Text("Your camera roll,\norganized into\na ")
                        .foregroundColor(.white)
                    + Text("Blog.")
                        .foregroundColor(Color(red: 200/255, green: 235/255, blue: 1.0))
                }
                .font(.system(size: 30, weight: .bold))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
                .opacity(showTagline ? 1 : 0)
                .offset(y: showTagline ? 0 : 10)
                .animation(.easeOut(duration: 0.5).delay(0.35), value: showTagline)

                Text("Automatically sorted by day,\nplace & moment.")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .opacity(showTagline ? 1 : 0)
                    .offset(y: showTagline ? 0 : 8)
                    .animation(.easeOut(duration: 0.45).delay(0.5), value: showTagline)
            }
            .padding(.horizontal, 28)

            // Continue button — pinned to bottom via its own VStack
            VStack(spacing: 0) {
                Spacer()
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
                .padding(.bottom, 12)
                .opacity(showContinue ? 1 : 0)
                .offset(y: showContinue ? 0 : 12)
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: showContinue)

                VStack(spacing: 4) {
                    Text("By continuing, you agree to Bloggo's")
                        .foregroundColor(.white.opacity(0.35))

                    HStack(spacing: 4) {
                        Button("Privacy Policy") {
                            showPrivacyPolicy = true
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white.opacity(0.5))

                        Text("and")
                            .foregroundColor(.white.opacity(0.35))

                        Button("Terms of Service") {
                            showTermsOfService = true
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white.opacity(0.5))
                    }
                }
                .font(.caption)
                .padding(.bottom, 36)
                .opacity(showContinue ? 1 : 0)
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: showContinue)
            }
        }
    }

    // MARK: - Animation sequence

    @MainActor
    private func startAnimation() async {
        let screenHeight = UIScreen.main.bounds.height

        // Phase 1: camera roll label
        try? await Task.sleep(for: .milliseconds(300))
        withAnimation(.easeOut(duration: 0.4)) { showCameraLabel = true }

        // Phase 2: 12 photos fall, staggered 100 ms apart
        try? await Task.sleep(for: .milliseconds(500))
        for i in 0..<fallingPhotos.count {
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .milliseconds(100))
            let landY = fallingPhotos[i].landYFraction * screenHeight
            withAnimation(.easeIn(duration: 0.6)) {
                photoOpacities[i] = 1
                photoOffsets[i] = landY
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

        // Phase 6: wait 1 s, then slide entire blog view upward
        try? await Task.sleep(for: .milliseconds(1000))
        withAnimation(.easeInOut(duration: 1.4)) { blogOffset = -220 }

        // Phase 7: tagline overlay fades in after scroll starts settling
        try? await Task.sleep(for: .milliseconds(1600))
        withAnimation(.easeIn(duration: 0.4)) { showTagline = true }

        // Continue button slides in 0.8 s later
        try? await Task.sleep(for: .milliseconds(800))
        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { showContinue = true }
    }
}
