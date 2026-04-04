//
//  TermsOfServiceView.swift
//  Capper
//

import SwiftUI

/// Dedicated Terms of Service page for Bloggo. Shown from Settings.
struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Group {
                    sectionTitle("1. Acceptance of Terms")
                    bodyText("By using Bloggo — whether as a guest or by creating an account — you agree to these Terms of Service and our Privacy Policy. If you do not agree, please do not use our service.")
                }

                Group {
                    sectionTitle("2. Description of Service")
                    bodyText("Bloggo is a travel journaling app that helps you create, edit, and share beautifully formatted blog posts from your travel experiences. Our service includes:")
                    bullet("AI-assisted blog generation: automatically create blog posts from your travel photos using on-device AI.")
                    bullet("Blog drafts: save and manage multiple blog drafts locally on your device.")
                    bullet("PDF export: export any blog as a polished PDF to share however you choose.")
                    bullet("QR code sharing: generate a QR code for any blog to share it in person with another Bloggo user.")
                    bodyText("We reserve the right to modify, suspend, or discontinue any aspect of the service at any time.")
                }

                Group {
                    sectionTitle("3. Guest Users and Registered Accounts")
                    bodyText("Bloggo can be used with or without a registered account:")
                    bullet("Guest Users: Guests may create and export one (1) blog. Guest data is stored locally on the device and is not associated with any account.")
                    bullet("Registered Users (free): Creating a free Bloggo account allows you to save and manage unlimited blog drafts and export as many blogs as you like. Registered accounts require a valid email address.")
                    bodyText("Account creation is free and takes only a moment. Registered users enjoy the full Bloggo experience with no content restrictions.")
                }

                Group {
                    sectionTitle("4. User Accounts")
                    bodyText("If you create an account, you are responsible for maintaining the confidentiality of your account credentials and for all activities that occur under your account. Please notify us immediately of any unauthorized use.")
                    bullet("You must be at least 13 years old to create an account.")
                    bullet("You may not create more than one account per person.")
                    bullet("You must provide accurate and complete information during registration.")
                    bullet("You are responsible for all content created or exported from your account.")
                }

                Group {
                    sectionTitle("5. Sharing Features")
                    bodyText("Bloggo supports two sharing methods, both of which are entirely user-initiated:")
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
                    bodyText("Bloggo and its original content, features, and functionality are owned by Bloggo and are protected by applicable copyright, trademark, and other intellectual property laws. You may not reproduce, modify, or distribute any part of the Bloggo app or its interface without our express written permission.")
                }

                Group {
                    sectionTitle("8. Termination")
                    bodyText("We may terminate or suspend your account at our sole discretion, without prior notice, for conduct that we believe violates these Terms or is harmful to other users, us, or third parties. Because your blog content is stored locally on your device, termination of your account does not affect locally saved content on your device.")
                }

                Group {
                    sectionTitle("9. Disclaimer of Warranties")
                    bodyText("Bloggo is provided \"as is\" and \"as available\" without warranties of any kind, express or implied. We do not warrant that the service will be uninterrupted, error-free, or free from bugs or other issues. We are not responsible for any loss of locally stored content resulting from device failure, operating system changes, or user-initiated deletion.")
                }

                Group {
                    sectionTitle("10. Limitation of Liability")
                    bodyText("To the maximum extent permitted by applicable law, Bloggo and its affiliates shall not be liable for any indirect, incidental, special, consequential, or punitive damages arising from your use of or inability to use the service, including any loss of locally stored content or exported files.")
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
        }
        .navigationTitle("Terms of Service")
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
