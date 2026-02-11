//
//  TermsOfServiceView.swift
//  Capper
//

import SwiftUI

/// Dedicated Terms of Service page for BlogGo. Shown from Settings.
struct TermsOfServiceView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Group {
                    sectionTitle("Agreement to Terms")
                    bodyText("By downloading, installing, or using the BlogGo app (\"the App\"), you agree to be bound by these Terms of Service (\"Terms\"). If you do not agree to these Terms, do not use the App.")
                }

                Group {
                    sectionTitle("Description of the Service")
                    bodyText("BlogGo is a mobile application that helps you discover trips from your photo library (e.g., over the last 90 days), select photos, and create recap blogs. Features include trip scanning, neighborhood-based filtering, draft saving, and editing recap blog content. The service is provided for personal, non-commercial use.")
                }

                Group {
                    sectionTitle("Eligibility")
                    bodyText("You must be at least 13 years of age (or the minimum age required in your jurisdiction) to use the App. By using the App, you represent that you meet this requirement and have the authority to accept these Terms.")
                }

                Group {
                    sectionTitle("Your Content and Conduct")
                    bodyText("You retain ownership of the photos and content you use within the App. By using the App, you represent that you have the right to use such content and that it does not infringe or violate any third party’s rights or any applicable law. You agree not to use the App to create, store, or share content that is illegal, harmful, offensive, or that violates others’ privacy or intellectual property rights.")
                }

                Group {
                    sectionTitle("Privacy")
                    bodyText("Your use of the App is also governed by our Privacy Policy. By using the App, you consent to the collection and use of information as described in the Privacy Policy.")
                }

                Group {
                    sectionTitle("Disclaimer of Warranties")
                    bodyText("The App is provided \"as is\" and \"as available\" without warranties of any kind, either express or implied. We do not warrant that the App will be uninterrupted, error-free, or free of harmful components. Use of the App is at your sole risk.")
                }

                Group {
                    sectionTitle("Limitation of Liability")
                    bodyText("To the maximum extent permitted by law, BlogGo and its providers shall not be liable for any indirect, incidental, special, consequential, or punitive damages, or any loss of data, revenue, or profits, arising from your use of or inability to use the App. Our total liability shall not exceed the amount you paid to use the App in the past twelve months, if any.")
                }

                Group {
                    sectionTitle("Changes to the App or Terms")
                    bodyText("We may modify, suspend, or discontinue the App or any part of it at any time. We may also update these Terms. We will use reasonable means to notify you of material changes (e.g., in-app notice or updated Terms in Settings). Continued use of the App after changes constitutes acceptance of the revised Terms.")
                }

                Group {
                    sectionTitle("Termination")
                    bodyText("You may stop using the App at any time. We may suspend or terminate your access to the App if we believe you have violated these Terms or for other operational or legal reasons.")
                }

                Group {
                    sectionTitle("General")
                    bodyText("These Terms constitute the entire agreement between you and BlogGo regarding the App. If any part of these Terms is held unenforceable, the remaining provisions will remain in effect. Our failure to enforce any right or provision does not waive that right or provision.")
                }

                Group {
                    sectionTitle("Contact")
                    bodyText("For questions about these Terms of Service, please contact us through the support or feedback option in the app or the contact details provided in the App Store listing.")
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
}

#Preview {
    NavigationStack {
        TermsOfServiceView()
    }
}
