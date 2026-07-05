import SwiftUI

/// Detail sheet for quarantined sync failures — lists the held-back entities and
/// offers retry or destructive clear. Presented when the user taps the
/// 「N 条同步失败」 banner.
struct SyncFailureSheet: View {
    let items: [DeadLetterDisplayItem]
    let onRetry: () -> Void
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    FkEmptyState(
                        systemImage: "checkmark.circle",
                        title: String(localized: "sync.failure.empty.title"),
                        message: String(localized: "sync.failure.empty.message")
                    )
                } else {
                    List {
                        Section {
                            ForEach(items) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.fkBodyMedium)
                                        .foregroundStyle(Color.fkOnSurface)
                                    Text(item.typeLabel)
                                        .font(.fkLabelSmall)
                                        .foregroundStyle(Color.fkOnSurfaceVariant)
                                }
                                .listRowBackground(Color.fkSurfaceContainerLowest)
                            }
                        } header: {
                            Text("sync.failure.header")
                        } footer: {
                            Text("sync.failure.footer")
                        }

                        Section {
                            Button {
                                onRetry()
                                dismiss()
                            } label: {
                                Label(String(localized: "sync.action.retryNow"), systemImage: "arrow.clockwise")
                            }
                            .listRowBackground(Color.fkSurfaceContainerLowest)

                            Button(role: .destructive) {
                                showClearConfirm = true
                            } label: {
                                Label(String(localized: "sync.action.clearFailures"), systemImage: "trash")
                            }
                            .listRowBackground(Color.fkSurfaceContainerLowest)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.fkSurface)
            .navigationTitle("sync.failure.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("sync.action.done") { dismiss() }
                }
            }
            .confirmationDialog(
                "sync.failure.clearConfirm.title",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("sync.action.clear", role: .destructive) {
                    onClear()
                    dismiss()
                }
                Button("household.action.cancel", role: .cancel) {}
            } message: {
                Text(String(localized: "sync.failure.clearConfirm.message \(items.count)"))
            }
        }
        .tint(.fkPrimary)
    }
}
