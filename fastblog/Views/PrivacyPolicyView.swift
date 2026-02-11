//
//  PrivacyPolicyView.swift
//  Capper
//

import SwiftUI

/// Dedicated Privacy Policy page for BlogGo. Shown from Settings.
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Group {
                    sectionTitle("Introduction")
                    bodyText("BlogGo (\"we,\" \"our,\" or \"the app\") is committed to protecting your privacy. This Privacy Policy explains how we handle information when you use the BlogGo app on your device.")
                }

                Group {
                    sectionTitle("Information We Access")
                    bodyText("To provide trip detection and recap blog features, BlogGo may access:")
                    bullet("Photos and metadata: We access your photo library to scan for trips (e.g., from the last 90 days), read creation dates and locations, and use selected photos to build your recap blogs.")
                    bullet("Location: If you set a neighborhood in Settings, we use your device location (or a location you choose on the map) to define an area. Photos taken near this area may be excluded from trip results so everyday photos are not counted as trips.")
                }

                Group {
                    sectionTitle("How We Use This Information")
                    bodyText("We use the information only to:")
                    bullet("Segment your photos into trips based on dates and location gaps.")
                    bullet("Let you select which photos to include in a recap blog.")
                    bullet("Apply your neighborhood preference to filter out local photos from trip scanning.")
                    bodyText("All processing is done on your device. We do not upload your photos, location, or personal data to our servers.")
                }

                Group {
                    sectionTitle("Data Storage")
                    bodyText("Your recap blogs, draft selections, neighborhood setting, and related preferences are stored locally on your device (e.g., in app storage). We do not retain copies of this data on external servers.")
                }

                Group {
                    sectionTitle("Data Sharing")
                    bodyText("We do not sell, rent, or share your photos, location, or other personal information with third parties for marketing or advertising purposes. If you use system features such as sharing a blog or exporting content, that action is handled by your device’s OS and any services you choose (e.g., Messages, Mail).")
                }

                Group {
                    sectionTitle("Your Choices")
                    bodyText("You can revoke photo or location access at any time in your device Settings. Revoking access may limit or disable trip scanning and neighborhood-based filtering. You can clear or change your neighborhood in BlogGo Settings.")
                }

                Group {
                    sectionTitle("Changes to This Policy")
                    bodyText("We may update this Privacy Policy from time to time. We will post the updated policy in the app (e.g., in Settings). Continued use of BlogGo after changes constitutes acceptance of the revised policy.")
                }

                Group {
                    sectionTitle("Contact")
                    bodyText("If you have questions about this Privacy Policy or BlogGo’s practices, please contact us through the support or feedback option in the app or the contact details provided in the App Store listing.")
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
