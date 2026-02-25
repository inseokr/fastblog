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
                    bodyText("By creating an account or using Bloggo, you agree to these Terms of Service and our Privacy Policy. If you do not agree, please do not use our service.")
                }

                Group {
                    sectionTitle("2. Description of Service")
                    bodyText("Bloggo is a travel blogging platform that allows users to create, edit, publish, and share blog posts from both the Bloggo iOS mobile app and the Bloggo web platform. Our service includes:")
                    bullet("AI-powered blog generation: automatically create blog posts from your travel photos using on-device or cloud-based AI")
                    bullet("Cloud upload and sync: upload and store your locally created blogs to the cloud so they are accessible from any device")
                    bullet("Web blog editor: edit, format, and publish your blog posts directly from a web browser at bloggo.linkedspaces.com")
                    bullet("Public sharing: share your published blogs via a unique public link")
                    bodyText("We reserve the right to modify, suspend, or discontinue any aspect of the service at any time.")
                }

                Group {
                    sectionTitle("3. User Accounts")
                    bodyText("You are responsible for maintaining the confidentiality of your account credentials and for all activities that occur under your account. You must notify us immediately of any unauthorized use of your account.")
                    bullet("You must be at least 13 years old to use Bloggo")
                    bullet("You may not create more than one account per person")
                    bullet("You must provide accurate and complete information")
                    bullet("You are responsible for all content posted from your account")
                }

                Group {
                    sectionTitle("4. Cloud Storage & Uploads")
                    bodyText("Bloggo offers the ability to upload locally created blogs and their associated photos to our cloud infrastructure. By using the cloud upload feature, you acknowledge and agree that:")
                    bullet("Uploaded content (including blog text and photos) will be stored on Bloggo's servers and may be accessible from any device where you are signed in")
                    bullet("You are solely responsible for ensuring you have the right to upload any photos or content you submit")
                    bullet("We may compress or optimize photos during the upload process to ensure optimal performance")
                    bullet("Bloggo is not responsible for data loss due to user-initiated deletion, account termination for Terms violations, or unforeseen technical failures, though we take reasonable precautions to protect your data")
                }

                Group {
                    sectionTitle("5. Web Blog Editor")
                    bodyText("The Bloggo web platform provides a full-featured blog editor accessible at bloggo.linkedspaces.com. By using the web editor, you agree that:")
                    bullet("Edits made in the web editor are saved to your cloud blog and will be reflected across all platforms where your blog is published")
                    bullet("You are responsible for all content you create or modify using the web editor")
                    bullet("The web editor is provided as-is and may be updated or modified at any time; we will make reasonable efforts to preserve your content during such updates")
                    bullet("Auto-save functionality may be available; however, you should manually save your work regularly to avoid data loss in the event of a connectivity interruption")
                }

                Group {
                    sectionTitle("6. Content Policy")
                    bodyText("You retain ownership of the content you create on Bloggo. By posting content or uploading it to the cloud, you grant us a non-exclusive, worldwide license to store, display, distribute, and promote your content on our platform.")
                    bodyText("You agree not to post or upload content that:")
                    bullet("Is illegal, harmful, or violates others' rights")
                    bullet("Contains spam, malware, or deceptive information")
                    bullet("Infringes on intellectual property or privacy rights")
                    bullet("Harasses, threatens, or intimidates others")
                    bullet("Contains adult content without proper age-gating")
                    bullet("Includes photos of individuals without their consent, especially minors")
                }

                Group {
                    sectionTitle("7. Intellectual Property")
                    bodyText("Bloggo and its original content, features, and functionality are owned by Bloggo and are protected by international copyright, trademark, and other intellectual property laws.")
                }

                Group {
                    sectionTitle("9. Termination")
                    bodyText("We may terminate or suspend your account at our sole discretion, without notice, for conduct that we believe violates these Terms or is harmful to other users, us, or third parties. Upon termination, your cloud-stored content may be deleted after a reasonable grace period.")
                }

                Group {
                    sectionTitle("10. Disclaimer of Warranties")
                    bodyText("Bloggo is provided \"as is\" without warranties of any kind. We do not warrant that the service will be uninterrupted, error-free, or free of viruses or other harmful components. Cloud storage availability is subject to our infrastructure uptime and is not guaranteed to be 100% available at all times.")
                }

                Group {
                    sectionTitle("11. Limitation of Liability")
                    bodyText("To the maximum extent permitted by law, Bloggo shall not be liable for any indirect, incidental, special, consequential, or punitive damages resulting from your use of or inability to use the service, including any loss of cloud-stored data.")
                }

                Group {
                    sectionTitle("12. Governing Law")
                    bodyText("These Terms shall be governed by the laws of the State of California, without regard to its conflict of law provisions.")
                }

                Group {
                    sectionTitle("13. Contact")
                    bodyText("For questions about these Terms, contact us at bloggo@linkedspaces.com.")
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
