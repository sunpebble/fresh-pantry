import Foundation
import SwiftData
import Testing
@testable import FreshPantry

/// Device-local cook-tally store (#7): increment-on-cook + snapshot load.
struct CookHistoryRepositoryTests {
    private func makeRepo() throws -> CookHistoryRepository {
        let container = try ModelContainerFactory.makeInMemory()
        return CookHistoryRepository(modelContainer: container)
    }

    @Test func recordCookInsertsThenIncrements() async throws {
        let repo = try makeRepo()
        try await repo.recordCook(recipeId: "r1", now: Date(timeIntervalSince1970: 100))
        try await repo.recordCook(recipeId: "r1", now: Date(timeIntervalSince1970: 200))
        let all = try await repo.loadAll()
        #expect(all["r1"]?.cookCount == 2)
        #expect(all["r1"]?.lastCookedAt == Date(timeIntervalSince1970: 200))
    }

    @Test func separateRecipesTrackedIndependently() async throws {
        let repo = try makeRepo()
        try await repo.recordCook(recipeId: "a")
        try await repo.recordCook(recipeId: "b")
        try await repo.recordCook(recipeId: "b")
        let all = try await repo.loadAll()
        #expect(all["a"]?.cookCount == 1)
        #expect(all["b"]?.cookCount == 2)
    }

    @Test func blankIdIsNoOp() async throws {
        let repo = try makeRepo()
        try await repo.recordCook(recipeId: "   ")
        #expect(try await repo.loadAll().isEmpty)
    }
}
