// app/Sources/KickbackBar/HistoryVM.swift
import SwiftUI
import KickbackKit

@MainActor final class HistoryVM: ObservableObject {
  @Published private(set) var model: HistoryModel?
  @Published private(set) var loading = true

  func load() {
    loading = true
    Task.detached(priority: .utility) {
      let h = ModelClient.history()
      await MainActor.run { self.model = h; self.loading = false }
    }
  }
}
