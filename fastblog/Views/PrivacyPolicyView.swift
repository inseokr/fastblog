//
//  PrivacyPolicyView.swift
//  Capper
//

import SwiftUI

/// Dedicated Privacy Policy page for Bloggo. Shown from Settings.
struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    /// Gradient + Close row + vertical paddings (excluding safe area). Used so the last lines can scroll above the CTA while content may draw under it.
    private static let closeFooterFixedHeight: CGFloat = 32 + 4 + 16 + 22 + 16 + 16

    var body: some View {
        GeometryReader { geometry in
            let bottomScrollPadding = Self.closeFooterFixedHeight + geometry.safeAreaInsets.bottom
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Spacer(minLength: 0)
                        Image("SplashIcon")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 68, height: 68)
                            .clipShape(RoundedRectangle(appChromeBaseRadius: 16))
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 2)

                    Text("Privacy Policy")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)

                    Text("Last Updated: June 5, 2026")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 4)

                Group {
                    sectionTitle("1. Information We Collect")
                    bodyText("We collect information you provide directly to us, such as when you create an account or contact support. This includes your username, name where applicable, and email address.")
                    bodyText("We also collect limited technical and usage data to improve the app and diagnose issues. For example, the app may send product analytics events to our servers (including an anonymous identifier stored on your device, app version, timezone, and contextual fields such as feature or screen names that do not include the text of your blogs or your photo library). Crash or diagnostic data may be included depending on your device settings. This category of data is not a full copy of your blog text or photo library.")
                }

                Group {
                    sectionTitle("2. Your Blog Content Stays on Your Device")
                    bodyText("Your blogs, drafts, and the photos you include in them are stored and processed on your device. In-app camera captures—including optional short Reel clips and Vibe audio—are also stored locally with your blog. Bloggo does not upload your blog content, Reel clips, or your photo library to our servers for editing, server-side backup, sync, hosting, or publishing.")
                    bodyText("We do not store or sync your blog files on our systems; only the account and technical data described elsewhere in this policy are processed on our servers.")
                    bodyText("Your blog files stay with you locally unless you export them yourself (for example, PDF, zip, or video using the app's export tools). If you create an account, we store the information needed to sign you in and operate your account on our systems, such as username and email—that is separate from your blog drafts and media, which remain on your device.")
                    bullet("Blog generation uses AI that runs entirely on your device. Your photos are not sent to external AI services for that processing.")
                }

                Group {
                    sectionTitle("3. Photos, Reels & Location Metadata")
                    bodyText("Photos you add are read from your device's photo library and stay under your control on your device.")
                    bodyText("When you use the in-app camera, Bloggo can save a still photo together with an optional short Reel clip and Vibe audio. Those files are kept in your blog's local storage on your device; they are not uploaded to our servers.")
                    bullet("EXIF metadata (such as GPS coordinates embedded in photo files) may be read on your device to help build your blog. You can limit or disable related behavior in your app and system settings where applicable.")
                }

                Group {
                    sectionTitle("4. Sharing and Personal Backup")
                    bodyText("Sharing is something you start from the app; we do not put your blog on a public website. Typical options include:")
                    bullet("PDF / storybook export: Generated on-device. Sharing via Mail, AirDrop, or other apps inherits those vendors' privacy terms.")
                    bullet("Video export: Rendered locally; you choose whether to save to Photos or hand off via the share sheet.")
                    bullet("Carousel Studio–style tooling: Helps build image sets or canvases for TikTok, Facebook, Messages, etc. Once you invoke an external app's share APIs, those apps' notices apply—not this policy alone.")
                    bullet("ZIP (or comparable archive): Packaged backups you can save yourself (for example via the Files app or another destination you choose).")
                    bullet("QR code (“Share with Bloggo”): Encodes a handshake so recipients open Bloggo locally. Keep the QR out of unintended hands the same way you would a link.")
                }

                Group {
                    sectionTitle("5. How We Use Your Information")
                    bodyText("We use the information we collect to:")
                    bullet("Provide, maintain, and improve the Bloggo app.")
                    bullet("Authenticate your account and keep it secure.")
                    bullet("Send important notices, updates, and support communications.")
                    bullet("Respond to your questions and support requests.")
                    bullet("Detect and prevent fraudulent or unauthorized activity.")
                }

                Group {
                    sectionTitle("6. Information Sharing")
                    bodyText("We do not sell, trade, or rent your personal information to third parties. We may share limited account information with trusted service providers who assist in operating our service (such as authentication infrastructure), provided they are bound by confidentiality obligations and use the information only as we direct.")
                    bodyText("We may disclose information if required by law or if we believe disclosure is necessary to protect our rights or the safety of our users.")
                }

                Group {
                    sectionTitle("7. Registered Accounts")
                    bodyText("Bloggo requires an account to use the app. Account creation requires a valid email address.")
                    bodyText("Age and accounts. Bloggo is listed on the Apple App Store with a 4+ age rating. Creating a Bloggo account requires you to provide personal information (such as an email address) that we process on our systems. You must be at least 13 years old to create an account, or the minimum age required in your jurisdiction to consent to the collection of your personal information online, whichever is higher. If you do not meet this requirement, you must not use the app.")
                    bullet("By creating an account, you represent that you meet the age requirement above.")
                    bullet("Only one account may be created per email address.")
                    bodyText("An account does not move your blog content to our servers; drafts and photos stay on your device as described in Section 2, while we store the account details needed to sign you in.")
                }

                Group {
                    sectionTitle("8. Data Retention")
                    bodyText("Your blogs and drafts live on your device. Deleting the app removes that local data unless you have exported copies (PDF, zip, etc.) elsewhere yourself.")
                    bodyText("Information tied to your account (such as your name and email) is kept on our systems while your account is active. When you are signed in, you can delete your account at any time from the Bloggo app: open Settings, then tap Delete Account and confirm. We then process deletion of your account from our systems; this typically completes within 30 days, subject to legal or security retention needs. You can also email bloggo@linkedspaces.com if you need help with your account or data.")
                }

                Group {
                    sectionTitle("9. Data Security")
                    bodyText("We implement security measures consistent with industry practice. Data sent between the app and our servers for account sign-in and related services is encrypted in transit (HTTPS/TLS). Your blog content itself is not stored on our servers under this policy. No method of storage or transmission is perfectly secure; we encourage you to use a strong, unique password for your Bloggo account and to keep your device and Apple ID secure.")
                }

                Group {
                    sectionTitle("10. Your Rights")
                    bodyText("Depending on your location, you may have the right to access, correct, export, or delete personal data we hold about you. To delete your Bloggo account, use Delete Account in Settings while signed in. For other requests about account data, contact us at bloggo@linkedspaces.com. You can manage, export, or delete blog content stored on your device directly in the app at any time.")
                }

                Group {
                    sectionTitle("11. Changes to This Policy")
                    bodyText("We may update this privacy policy from time to time. We will notify you of any material changes by posting the new policy within the app and, where appropriate, by sending a notification to your registered email address.")
                }

                Group {
                    sectionTitle("12. Contact Us")
                    bodyText("If you have questions or concerns about this privacy policy, please contact us at bloggo@linkedspaces.com.")
                }

                    Spacer(minLength: 40)
                    }
                    .padding(20)
                    .padding(.bottom, bottomScrollPadding)
                }
                .scrollClipDisabled()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                closeFooter
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var closeFooter: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    Color(uiColor: .systemBackground).opacity(0),
                    Color(uiColor: .systemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 32)
            .allowsHitTesting(false)

            Button {
                dismiss()
            } label: {
                Text("Close")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
            .fontWeight(.semibold)
    }

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
