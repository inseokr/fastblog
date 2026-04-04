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
                    bodyText("We collect information you provide directly to us, such as when you create an account or contact support. This includes your name and email address.")
                    bodyText("We may also collect limited usage data to help us diagnose technical issues and improve the app experience, such as crash reports and general usage patterns. This data does not include your blog content or photos.")
                }

                Group {
                    sectionTitle("2. Photos & Blog Content")
                    bodyText("Bloggo is designed with your privacy in mind. Your photos and blog content are processed and stored locally on your device. Specifically:")
                    bullet("Photos you use in your blogs are accessed from your device's photo library and are never uploaded to external servers.")
                    bullet("AI-assisted blog generation is performed on-device or through on-device models; your photos are not sent to third-party services for this purpose.")
                    bullet("EXIF metadata (such as GPS location embedded in photo files) may be read locally to enrich your blog with location context. You can disable this in your app settings.")
                    bullet("Your blog content remains on your device unless you choose to export or share it using the available sharing features described below.")
                }

                Group {
                    sectionTitle("3. Sharing Your Blogs")
                    bodyText("Bloggo provides two ways to share your blogs with others:")
                    bullet("PDF Export: You may export any blog as a PDF file, which you can then share through any method available on your device (such as AirDrop, Messages, or email). Once exported, the PDF is subject to the privacy practices of whichever platform you use to send it.")
                    bullet("QR Code Sharing: You may generate a QR code for a blog to share it in person with another Bloggo user. This is intended for direct, local sharing between individuals and does not publish your blog to the internet or make it accessible via a public link.")
                    bodyText("Bloggo does not publish your blogs to the web or make them accessible via a public URL. All sharing is user-initiated and user-controlled.")
                }

                Group {
                    sectionTitle("4. How We Use Your Information")
                    bodyText("We use the information we collect to:")
                    bullet("Provide, maintain, and improve the Bloggo app.")
                    bullet("Authenticate your account and keep it secure.")
                    bullet("Send important notices, updates, and support communications.")
                    bullet("Respond to your questions and support requests.")
                    bullet("Detect and prevent fraudulent or unauthorized activity.")
                }

                Group {
                    sectionTitle("5. Information Sharing")
                    bodyText("We do not sell, trade, or rent your personal information to third parties. We may share limited account information with trusted service providers who assist in operating our service (such as authentication infrastructure), provided they are bound by confidentiality obligations and use the information only as we direct.")
                    bodyText("We may disclose information if required by law or if we believe disclosure is necessary to protect our rights or the safety of our users.")
                }

                Group {
                    sectionTitle("6. Guest and Registered User Access")
                    bodyText("Bloggo offers two tiers of access:")
                    bullet("Guest Users (no account): Guests may create and export one (1) blog. To save additional blogs or export more than one, guests are encouraged to create a free account.")
                    bullet("Registered Users (free account): Users with a free Bloggo account can create and save as many blog drafts as they like and export as many blogs as they like. Account creation is free and requires only an email address.")
                    bodyText("Creating an account does not change what data is stored or how your content is handled — all blog content continues to be stored locally on your device.")
                }

                Group {
                    sectionTitle("7. Data Retention")
                    bodyText("Because your blog content is stored locally on your device, you are in full control of your data. Deleting the app removes all locally stored blogs and drafts. For account-related information (such as your name and email), you may request deletion at any time by contacting our support team. Account data is removed from our systems within 30 days of a deletion request.")
                }

                Group {
                    sectionTitle("8. Data Security")
                    bodyText("We implement industry-standard security measures to protect your account information, including encrypted transmission (HTTPS/TLS) for any data communicated with our servers. Your blog content never leaves your device through our systems, which significantly limits exposure. We encourage you to use a strong, unique password for your Bloggo account and to keep your device secure.")
                }

                Group {
                    sectionTitle("9. Your Rights")
                    bodyText("Depending on your location, you may have the right to access, correct, export, or delete your personal account data. To exercise these rights, please contact us at bloggo@linkedspaces.com. Because blog content is stored locally on your device, you can manage, export, or delete it directly from within the app at any time.")
                }

                Group {
                    sectionTitle("10. Changes to This Policy")
                    bodyText("We may update this privacy policy from time to time. We will notify you of any material changes by posting the new policy within the app and, where appropriate, by sending a notification to your registered email address.")
                }

                Group {
                    sectionTitle("11. Contact Us")
                    bodyText("If you have questions or concerns about this privacy policy, please contact us at bloggo@linkedspaces.com.")
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
