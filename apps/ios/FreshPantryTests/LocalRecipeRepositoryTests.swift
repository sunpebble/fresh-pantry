import Foundation
import Testing
@testable import FreshPantry

/// Tests for the JSON payload loader: production ships no recipe JSON, while
/// injected payloads still decode lossily for tests/previews.
struct LocalRecipeRepositoryTests {
    // MARK: Default production seam

    @Test func defaultRepositoryHasNoBundledRecipes() async throws {
        let repo = LocalRecipeRepository()
        let recipes = await repo.loadAll()
        #expect(recipes.isEmpty)
    }

    @Test func loadIsCachedAcrossCalls() async throws {
        let repo = LocalRecipeRepository()
        let first = await repo.loadAll()
        let second = await repo.loadAll()
        #expect(first.count == second.count)
    }

    // MARK: Per-entry resilience

    @Test func malformedEntryIsSkippedRestPreserved() {
        // A valid recipe, a non-object entry, and a second valid recipe.
        let json = """
        [
          {"id":"a","name":"番茄炒蛋","category":"家常","difficulty":1,"cookingMinutes":15,
           "description":"","ingredients":[],"steps":[]},
          12345,
          {"id":"b","name":"青椒肉丝","category":"川菜","difficulty":2,"cookingMinutes":20,
           "description":"","ingredients":[],"steps":[]}
        ]
        """
        let recipes = LocalRecipeRepository.decode(data: Data(json.utf8))
        #expect(recipes.map(\.id) == ["a", "b"]) // bad middle entry skipped
    }

    @Test func nonArrayPayloadYieldsEmpty() {
        let recipes = LocalRecipeRepository.decode(data: Data(#"{"not":"an array"}"#.utf8))
        #expect(recipes.isEmpty)
    }

    @Test func injectedPayloadOverridesBundle() async {
        let json = #"[{"id":"x","name":"注入","category":"家常","difficulty":1,"cookingMinutes":10,"description":"","ingredients":[],"steps":[]}]"#
        let repo = LocalRecipeRepository(payload: Data(json.utf8))
        let recipes = await repo.loadAll()
        #expect(recipes.map(\.id) == ["x"])
    }
}
