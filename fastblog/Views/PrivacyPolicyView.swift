//
//  PrivacyPolicyView.swift
//  Capper
//

import SwiftUI

/// Dedicated Privacy Policy page for Bloggo. Shown from Settings.
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Group {
                    sectionTitle("1. Information We Collect")
                    bodyText("We collect information you provide directly to us, such as when you create an account, publish a blog post, or contact support. This includes your name, email address, and any content you create on our platform.")
                    bodyText("We also collect usage data automatically, including your IP address, browser type, pages visited, and time spent on the platform. This helps us improve Bloggo and diagnose technical issues.")
                }

                Group {
                    sectionTitle("2. Photos & Cloud-Uploaded Content")
                    bodyText("Bloggo allows you to upload photos and blog content from the iOS app or web editor to our cloud servers. Regarding this content:")
                    bullet("Photos you upload are stored securely on our cloud infrastructure and are used solely to display your blog posts and generate AI-assisted travel blogs on your behalf.")
                    bullet("Photos are not shared with third parties for advertising, training data sets, or any purpose other than operating and improving the Bloggo service.")
                    bullet("AI blog generation may process your photos using on-device or cloud-based AI models to identify scenes and generate descriptive text; this processing is done solely to create your blog content.")
                    bullet("EXIF metadata (such as GPS location embedded in photo files) may be read by our service to enrich your blog with location data if you choose to enable this feature; you can disable location enrichment in your app settings.")
                    bullet("You may delete your uploaded photos and blogs at any time from within the app or web editor; deletions are processed within 30 days from our backup systems.")
                }

                Group {
                    sectionTitle("3. Web Blog Editor Usage")
                    bodyText("When you use the Bloggo web editor at bloggo.linkedspaces.com, we collect:")
                    bullet("Session data: authentication tokens to verify your identity and keep you securely signed in.")
                    bullet("Edit history: changes you make to blog posts are logged temporarily to support auto-save and conflict resolution across devices.")
                    bullet("Browser and device information: browser type, operating system, and screen resolution to ensure the editor renders correctly for you.")
                    bodyText("Content you write or edit in the web editor is saved to your cloud account and is subject to the same privacy protections as all other user content described in this policy.")
                }

                Group {
                    sectionTitle("4. How We Use Your Information")
                    bodyText("We use your information to:")
                    bullet("Provide, maintain, and improve our services.")
                    bullet("Store and sync your blogs and photos across the iOS app and web platform.")
                    bullet("Generate AI-powered blog posts from your uploaded travel photos.")
                    bullet("Process transactions and send related information.")
                    bullet("Send technical notices and support messages.")
                    bullet("Respond to your comments and questions.")
                    bullet("Monitor and analyze usage patterns to improve the platform.")
                    bullet("Detect and prevent fraudulent or illegal activity.")
                }

                Group {
                    sectionTitle("5. Information Sharing")
                    bodyText("We do not sell, trade, or rent your personal information or uploaded content to third parties. We may share your information with trusted service providers who assist us in operating our platform (such as cloud hosting providers), provided they agree to keep this information confidential and use it only for the purposes we specify.")
                    bodyText("We may disclose your information if required by law or if we believe disclosure is necessary to protect our rights or the safety of others.")
                }

                Group {
                    sectionTitle("6. Data Retention")
                    bodyText("We retain your personal information and cloud-stored content for as long as your account is active or as needed to provide services. You may request deletion of your account and all associated data, including uploaded photos and blog posts, at any time by contacting our support team. Data is removed from active systems promptly and from backups within 30 days.")
                }

                Group {
                    sectionTitle("7. Data Security")
                    bodyText("We implement industry-standard security measures to protect your personal information and uploaded content, including encrypted transmission (HTTPS/TLS) and encrypted storage for sensitive account data. However, no method of transmission over the internet is 100% secure, and we cannot guarantee absolute security. We encourage you to use a strong, unique password for your Bloggo account.")
                }

                Group {
                    sectionTitle("8. Your Rights")
                    bodyText("Depending on your location, you may have the right to access, correct, export, or delete your personal data and uploaded content. You may also have the right to object to or restrict certain processing of your data. To exercise these rights, please contact us at bloggo@linkedspaces.com.")
                }

                Group {
                    sectionTitle("9. Changes to This Policy")
                    bodyText("We may update this privacy policy from time to time. We will notify you of any material changes by posting the new policy on this page, and, where appropriate, sending a notification via email or within the app.")
                }

                Group {
                    sectionTitle("10. Contact Us")
                    bodyText("If you have questions about this privacy policy, please contact us at bloggo@linkedspaces.com.")
                }

                Spacer(minLength: 40)
            }
            .padding(20)
        }
        .navigationTitle("Privacy Policy")
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
