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
                        title: "没有同步失败项",
                        message: "所有待同步内容已恢复正常。"
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
                            Text("同步失败的项目")
                        } footer: {
                            Text("这些写入多次同步失败，已暂时停止重试。可重试一次，或清除失败记录（会丢弃这些未同步的更改）。")
                        }

                        Section {
                            Button {
                                onRetry()
                                dismiss()
                            } label: {
                                Label("立即重试", systemImage: "arrow.clockwise")
                            }
                            .listRowBackground(Color.fkSurfaceContainerLowest)

                            Button(role: .destructive) {
                                showClearConfirm = true
                            } label: {
                                Label("清除失败记录", systemImage: "trash")
                            }
                            .listRowBackground(Color.fkSurfaceContainerLowest)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.fkSurface)
            .navigationTitle("同步失败")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .confirmationDialog(
                "清除失败记录？",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("清除", role: .destructive) {
                    onClear()
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将丢弃 \(items.count) 个项目的未同步更改，此操作不可撤销。")
            }
        }
        .tint(.fkPrimary)
    }
}
