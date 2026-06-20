import Foundation

/// Generic provenance-tracked field wrapper for AI/user-edited drafts.
/// Value-equal over value+source.
struct DraftField<T: Equatable>: Equatable {
    var value: T
    var source: DraftSource

    init(value: T, source: DraftSource) {
        self.value = value
        self.source = source
    }

    static func ai(_ value: T) -> DraftField<T> {
        DraftField(value: value, source: .ai)
    }

    static func user(_ value: T) -> DraftField<T> {
        DraftField(value: value, source: .user)
    }

    /// Returns a new field with the edited value, tagged `.user`.
    func editedTo(_ next: T) -> DraftField<T> {
        DraftField(value: next, source: .user)
    }
}
