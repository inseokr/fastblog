//
//  MemoryRecallViewModel.swift
//  Capper
//

import SwiftUI
import Combine

@MainActor
final class MemoryRecallViewModel: ObservableObject {
    @Published var currentRecall: RecallTrigger?
    @Published var isLoading = false
    
    @AppStorage("capper.memoryRecall.lastComputedDate") private var lastComputedDate: Double = 0
    
    private let service = MemoryRecallService.shared
    
    func onAppear() {
        checkAndGenerateRecall()
    }
    
    private func checkAndGenerateRecall() {
        let now = Date()
        let lastDate = Date(timeIntervalSince1970: lastComputedDate)
        
        // If not processed today yet
        if !Calendar.current.isDate(now, inSameDayAs: lastDate) {
            refreshRecall()
        } else {
            // Potentially load from a cache if we want persistence across app launches within the same day.
            // For now, we'll just re-generate if currentRecall is nil (e.g. app restart on same day).
            if currentRecall == nil {
                refreshRecall()
            }
        }
    }
    
    func refreshRecall() {
        isLoading = true
        Task {
            let recall = await service.generateDailyRecall()
            self.currentRecall = recall
            self.lastComputedDate = Date().timeIntervalSince1970
            self.isLoading = false
        }
    }
}
