//
//  TermsOfServiceView.swift
//  Capper
//

import SwiftUI

/// Dedicated Terms of Service page for Bloggo. Shown from Settings.
struct TermsOfServiceView: View {
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

                    Text("Terms of Service")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)

                    Text("Last Updated: April 7, 2026")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, 4)

                Group {
                    sectionTitle("1. Acceptance of Terms")
                    bodyText("The Bloggo mobile application and the features and services available through it (the \"App,\" and our \"Services\") are provided to you by LinkedSpaces LLC (\"LinkedSpaces,\" \"we,\" \"us\") subject to these Terms of Service, including the policies described in our Privacy Policy (together, the \"Terms\"). By downloading, accessing, or using the App, whether as a guest or with a registered account, you agree to follow and be bound by the Terms. We may update the Terms from time to time. The current Terms are available within the App. We and our third party service providers may change features, services, related to the App without notice. Bloggo is a travel journaling app; your blog content and photos are stored locally on your device and are not uploaded to our servers as part of normal app operation, except as described in our Privacy Policy (for example, account information you provide and limited technical or usage data). Certain parts of the Terms may be clarified by additional notices we show in the App. The App is not intended for children under 13 years of age. If you are under 13, do not create an account; you may use limited guest features only as described in these Terms. If you do not agree with the Terms, do not use the App.")
                    bodyText("BY CONTINUING TO USE THE APP, YOU INDICATE YOUR AGREEMENT TO THE TERMS AND ANY REVISIONS WE POST.")
                    bodyText("We may modify or discontinue the App or any part of it, temporarily or permanently, with or without notice. You agree that we are not liable to you or to any third party for any modification, suspension, or discontinuance of the App or any portion of it.")
                }

                Group {
                    sectionTitle("2. Description of Service")
                    bodyText("Bloggo is a travel journaling app that helps you create, edit, and share beautifully formatted blog posts from your travel experiences. Our service includes:")
                    bullet("Blog generation with AI on your device: automatically create blog posts from your travel photos.")
                    bullet("Blog drafts: save and manage multiple blog drafts locally on your device.")
                    bullet("PDF export: export any blog as a polished PDF to share however you choose.")
                    bullet("QR code sharing: generate a QR code for any blog to share it in person with another Bloggo user.")
                }

                Group {
                    sectionTitle("3. Guest Users and Registered Accounts")
                    bodyText("Bloggo can be used with or without a registered account:")
                    bullet("Guest Users: Guests may create and export one (1) blog. Guest data is stored locally on the device and is not associated with any account.")
                    bullet("Registered Users: Creating a Bloggo account allows you to save and manage unlimited blog drafts and export as many blogs as you like. Registered accounts require a valid email address.")
                    bodyText("Account creation takes only a moment. Registered users enjoy the full Bloggo experience with no content restrictions.")
                }

                Group {
                    sectionTitle("4. User Accounts")
                    bodyText("If you create an account, you are responsible for maintaining the confidentiality of your account credentials and for all activities that occur under your account. Please notify us immediately of any unauthorized use.")
                    bullet("You must be at least 13 years old to create a Bloggo account.")
                    bullet("If you are under 13, you may use Bloggo only as a guest (without creating an account).")
                    bullet("Only one account may be created per email address.")
                    bullet("You must provide accurate and complete information during registration.")
                    bullet("You are responsible for all content created or exported from your account.")
                }

                Group {
                    sectionTitle("5. Sharing Features")
                    bodyText("Bloggo supports two sharing methods, both of which are entirely initiated by you:")
                    bullet("PDF Export: You may export any blog as a PDF and share it through any channel available on your device. Once the PDF leaves your device, it is subject to the terms of whatever platform you use to transmit it.")
                    bullet("QR Code Sharing: You may generate a QR code for a blog to share it in person with another Bloggo user. QR code sharing is intended for direct, local sharing and does not publish your blog to the internet or create a public link.")
                    bodyText("Bloggo does not publish your blogs to a public website or make them accessible via a web URL. You remain in full control of your content and how it is shared.")
                }

                Group {
                    sectionTitle("6. Content Policy")
                    bodyText("You retain full ownership of the content you create in Bloggo. Your blogs and photos are stored locally on your device and are never uploaded to our servers as part of normal app operation.")
                    bodyText("Regardless of how content is shared or exported, you agree not to create or distribute content that:")
                    bullet("Is illegal, harmful, or violates the rights of others.")
                    bullet("Contains spam, malware, or deliberately deceptive information.")
                    bullet("Infringes on intellectual property or privacy rights.")
                    bullet("Harasses, threatens, or intimidates any individual.")
                    bullet("Contains adult content or material inappropriate for general audiences.")
                    bullet("Includes photos or identifying information of individuals without their consent, particularly minors.")
                }

                Group {
                    sectionTitle("7. Intellectual Property")
                    bodyText("Bloggo and its original content, features, and functionality are owned by LinkedSpaces LLC and are protected by applicable copyright, trademark, and other intellectual property laws. You may not reproduce, modify, or distribute any part of the Bloggo app or its interface without our express written permission.")
                }

                Group {
                    sectionTitle("8. Termination")
                    bodyText("We may terminate or suspend your account at our sole discretion, without prior notice, for conduct that we believe violates these Terms or is harmful to other users, us, or third parties. Because your blog content is stored locally on your device, termination of your account does not affect locally saved content on your device.")
                }

                Group {
                    sectionTitle("9. Disclaimer of Warranties")
                    bodyText("Bloggo is provided \"as is\" and \"as available\" without warranties of any kind, express or implied. We do not warrant that the service will be uninterrupted, free of errors, or free from bugs or other issues. We are not responsible for any loss of locally stored content resulting from device failure, operating system changes, or deletion that you initiate.")
                }

                Group {
                    sectionTitle("10. Limitation of Liability")
                    bodyText("To the maximum extent permitted by applicable law, LinkedSpaces LLC, the Bloggo app, and our affiliates shall not be liable for any indirect, incidental, special, consequential, or punitive damages arising from your use of or inability to use the service, including any loss of locally stored content or exported files.")
                }

                Group {
                    sectionTitle("11. Governing Law")
                    bodyText("These Terms shall be governed by the laws of the State of California, without regard to its conflict of law provisions.")
                }

                Group {
                    sectionTitle("12. Contact")
                    bodyText("For questions about these Terms of Service, please contact us at bloggo@linkedspaces.com.")
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
        TermsOfServiceView()
    }
}
