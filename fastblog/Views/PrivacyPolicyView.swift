//
//  PrivacyPolicyView.swift
//  Capper
//

import SwiftUI

/// Dedicated Privacy Policy page for Bloggo. Shown from Settings.
struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    private let scrollBottomInset: CGFloat = 120

    var body: some View {
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

                    Text("Last Updated: April 8, 2026")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 4)

                Group {
                    sectionTitle("1. Information We Collect")
                    bodyText("We collect information you provide directly to us, such as when you create an account or contact support. This includes your username, name where applicable, and email address.")
                    bodyText("We also collect limited technical and usage data to improve the app and diagnose issues. For example, the app may send product analytics events to our servers (including an anonymous identifier stored on your device, app version, timezone, and non-content contextual fields such as feature or screen names). Crash or diagnostic data may be included depending on your device settings. This category of data is not a full copy of your blog text or photo library.")
                }

                Group {
                    sectionTitle("2. Your Blog Content Stays on Your Device")
                    bodyText("Your blogs, drafts, and the photos you include in them are stored and processed on your device. Bloggo does not upload your blog content or your photos to our servers for backup, sync, hosting, or publishing.")
                    bodyText("Whether you use Bloggo as a guest or with an account, your blog material stays on your device unless you export it yourself (for example, as a PDF or zip file). If you create an account, we store the information needed to sign you in and operate your account—such as username and email—on our systems. That account information is separate from your blog files, which remain on your device.")
                    bullet("Blog generation that uses on-device AI runs on your device. Your photos are not sent to external AI services for that processing.")
                }

                Group {
                    sectionTitle("3. Photos & Location Metadata")
                    bodyText("Photos you add are read from your device's photo library and stay under your control on your device.")
                    bullet("EXIF metadata (such as GPS coordinates embedded in photo files) may be read on your device to help build your blog. You can limit or disable related behavior in your app and system settings where applicable.")
                }

                Group {
                    sectionTitle("4. Sharing and Personal Backup")
                    bodyText("Sharing in Bloggo is something you start from the app; we do not put your blog on a public website. Typical options include:")
                    bullet("PDF: The app can create a PDF on your device. You can save or download it and share it manually using Mail, AirDrop, Files, or any other app you choose. Those services have their own privacy practices.")
                    bullet("QR code: You can use a QR code to hand off a blog to another Bloggo user in person (for example, so they can open it in Bloggo on their device), or for your own convenience. That flow is designed for direct, user-initiated sharing—not for us to host or publish your blog online.")
                    bullet("Zip export: You can export your blog as a zip file (or similar archive) for your own backup or to move it between your devices. Those files stay under your control unless you choose to send them somewhere else.")
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
                    sectionTitle("7. Guest and Registered User Access")
                    bodyText("Bloggo offers two tiers of access:")
                    bullet("Guest users (no account): Guests may create and export a limited number of blogs, as shown in the app. To save additional blogs or use features that require an account, you can create one.")
                    bullet("Registered users: Users with a Bloggo account can save and export blogs according to the limits shown in the app. Account creation requires a valid email address.")
                    bullet("You must be at least 13 years old to create an account. If you are under 13, you may use Bloggo only as a guest.")
                    bullet("Only one account may be created per email address.")
                    bodyText("An account does not move your blog content to our servers; it is still stored on your device as described in Section 2, while we store the account details needed to sign you in.")
                }

                Group {
                    sectionTitle("8. Data Retention")
                    bodyText("Your blogs and drafts live on your device. Deleting the app removes that local data unless you have exported copies (PDF, zip, etc.) elsewhere yourself.")
                    bodyText("Information tied to your account (such as your name and email) is kept on our systems while your account is active. When you are signed in, you can delete your account at any time from the Bloggo app: open Settings, then tap Delete Account and confirm. We then process deletion of your account from our systems; this typically completes within 30 days, subject to legal or security retention needs. You can also email bloggo@linkedspaces.com if you need help with your account or data.")
                }

                Group {
                    sectionTitle("9. Data Security")
                    bodyText("We implement security measures consistent with industry practice. Data sent between the app and our servers for account sign-in and related services is encrypted in transit (HTTPS/TLS). Your blog content itself is not uploaded to our servers under this policy. No method of storage or transmission is perfectly secure; we encourage you to use a strong, unique password for your Bloggo account and to keep your device and Apple ID secure.")
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
            .padding(.bottom, scrollBottomInset)
            }

            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.clear, Color(uiColor: .systemBackground).opacity(0.9)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 42)
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
                        .shadow(color: Color.blue.opacity(0.3), radius: 10, y: 4)
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
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
