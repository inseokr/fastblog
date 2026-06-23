//
//  MemoryRecallModal.swift
//  fastblog
//

import SwiftUI
import Photos

struct MemoryRecallModal: View {
    let recall: RecallTrigger
    let onCreateBlog: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection
                        
                        LazyVGrid(columns: columns, spacing: 2) {
                            if recall.everydayCaptureIds.isEmpty {
                                ForEach(recall.assets, id: \.localIdentifier) { asset in
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.1))
                                        .aspectRatio(1, contentMode: .fill)
                                        .overlay(
                                            AssetPhotoView(assetIdentifier: asset.localIdentifier, cornerRadius: 0, targetSize: CGSize(width: 400, height: 400))
                                        )
                                        .clipped()
                                }
                            } else {
                                ForEach(recall.everydayCaptureIds, id: \.self) { captureId in
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.1))
                                        .aspectRatio(1, contentMode: .fill)
                                        .overlay {
                                            if let image = AppCapturePhotoService.shared.loadThumbnail(captureId: captureId, maxPixelSize: 400) {
                                                Image(uiImage: image)
                                                    .resizable()
                                                    .scaledToFill()
                                            }
                                        }
                                        .clipped()
                                }
                            }
                        }
                        
                        // Bottom padding for CTA
                        Color.clear.frame(height: 140)
                    }
                }
                .ignoresSafeArea(edges: .bottom)
                
                ctaSection
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if recall.type == .onThisDay {
                Text("1 Year Ago")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .appChromeCornerRadius(4)
            }
            
            Text(recall.title)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.white)
            
            Text(recall.subtitle)
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }
    
    private var ctaSection: some View {
        VStack {
            Spacer()
            Button(action: onCreateBlog) {
                Text(recall.everydayCaptureIds.isEmpty ? "Create Blog From This Memory" : "Open My Places")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .appChromeCornerRadius(14)
                    .shadow(radius: 5)
            }
            .padding(20)
            .background(
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )
        }
    }
}
