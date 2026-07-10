//
//  TravelDNAView.swift
//  Bloggo — Travel DNA screen (renders TravelDNAEngine output), styled like the concept mockup.
//
//  Feed it captions (from the ③/④ paths). It classifies → aggregates → shows persona bars.
//

import SwiftUI

struct TravelDNAView: View {
    /// Captions for the user's photos (the descriptions produced by the caption paths).
    let captions: [String]
    /// Use Foundation Models for classification (falls back to keywords automatically).
    var useLLM: Bool = true

    @State private var dna: TravelDNA?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if isLoading {
                        ProgressView("Analyzing your photos…").padding(.top, 40)
                    } else if let dna {
                        hero(dna)
                        ForEach(dna.personas.prefix(6)) { p in personaRow(p) }
                        Text("From \(dna.total) photos · analyzed on-device")
                            .font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Travel DNA")
        }
        .task { await build() }
    }

    private func hero(_ dna: TravelDNA) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("You are a").font(.subheadline).foregroundStyle(.white.opacity(0.85))
            Text("\(dna.personas.first?.emoji ?? "🧭") \(dna.headline)")
                .font(.title2).bold().foregroundStyle(.white)
            Text(dna.summary).font(.footnote).foregroundStyle(.white.opacity(0.9))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            LinearGradient(colors: [Color(red: 0.48, green: 0.36, blue: 1.0),
                                    Color(red: 1.0, green: 0.37, blue: 0.62)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private func personaRow(_ p: Persona) -> some View {
        HStack(spacing: 12) {
            Text(p.emoji).font(.system(size: 26))
                .frame(width: 46, height: 46)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(p.title).font(.headline)
                    Spacer()
                    Text("\(Int(p.percent))%").font(.subheadline).foregroundStyle(.secondary)
                }
                if !p.topSubcategories.isEmpty {
                    Text(p.topSubcategories.joined(separator: ", "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                ProgressView(value: p.percent, total: 100).tint(.accentColor)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func build() async {
        isLoading = true
        var result = await TravelDNAEngine.buildDNA(captions: captions, useLLM: useLLM)
        result.summary = await TravelDNAEngine.lifestyleSummary(result)   // upgrade to LLM blurb if available
        dna = result
        isLoading = false
    }
}

#Preview("Travel DNA — Vancouver sample") {
    // Sample captions (from the ③/④ experiment). In the app, pass the real captions.
    TravelDNAView(captions: [
        "Two lattes with intricate latte art on a wooden table at a cozy café in Victory Square.",
        "A grilled meat platter with a poached egg on a pink ceramic dish at a downtown izakaya.",
        "A round plate of sushi with shrimp and fish, a teapot and chopsticks, at a sushi bar.",
        "The busy entrance to the Capilano Suspension Bridge, people under a wooden canopy.",
        "A person dispensing orange gelato into a cup at a café near Capilano.",
        "A serene afternoon at Capilano where towering pines frame a calm river under a blue sky.",
        "A woman in a gray jacket gently holds a falcon at the Raptor Experience.",
        "Families relax in red Adirondack chairs at an outdoor café in North Vancouver."
    ], useLLM: false)   // set true on-device with Apple Intelligence for better tagging
}
