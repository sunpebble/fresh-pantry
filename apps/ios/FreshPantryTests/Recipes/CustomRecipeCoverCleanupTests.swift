import CoreGraphics
import Foundation
import ImageIO
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import FreshPantry

/// Tests for the custom-recipe cover cleanup loop: deleting a recipe must also
/// delete its locally-stored `file://` cover (nothing references it anymore),
/// while a failed/non-matching remove leaves files alone. Exercises the real
/// covers directory (like `RecipeCoverStoreTests`); every test cleans up.
@MainActor
struct CustomRecipeCoverCleanupTests {
    // MARK: Fixture

    private func makeStore() throws -> CustomRecipeStore {
        let container = try ModelContainerFactory.makeInMemory()
        return CustomRecipeStore(
            repository: CustomRecipeRepository(modelContainer: container),
            householdID: "home"
        )
    }

    /// Encodes a small solid-color PNG so `RecipeCoverStore.save` has a real
    /// image to persist (mirrors the `RecipeCoverStoreTests` fixture).
    private func makeImageData() -> Data {
        let size = 64
        let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.9, green: 0.5, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let cgImage = context.makeImage()!

        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        )!
        CGImageDestinationAddImage(destination, cgImage, nil)
        _ = CGImageDestinationFinalize(destination)
        return output as Data
    }

    private func recipe(id: String, imageUrl: String?) -> Recipe {
        Recipe(
            id: id,
            name: "带封面的菜",
            category: "家常",
            difficulty: 2,
            cookingMinutes: 15,
            description: "",
            ingredients: [RecipeIngredient(name: "番茄", quantity: 2, unit: "个")],
            steps: ["切块"],
            imageUrl: imageUrl
        )
    }

    private func cleanup(_ urlString: String) {
        if let url = URL(string: urlString), url.isFileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: remove → deletes the local cover file

    @Test func removeDeletesLocalCoverFile() async throws {
        let store = try makeStore()
        let recipeId = "cover-del-\(UUID().uuidString.lowercased())"
        let coverUrl = try await RecipeCoverStore.save(makeImageData(), recipeId: recipeId)
        defer { cleanup(coverUrl) }
        let target = recipe(id: recipeId, imageUrl: coverUrl)
        _ = await store.add(target)

        let ok = await store.remove(target.id)

        #expect(ok)
        let path = try #require(URL(string: coverUrl)).path
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    // MARK: remove with a remote cover → still succeeds, nothing to delete

    @Test func removeWithRemoteCoverSucceeds() async throws {
        let store = try makeStore()
        let target = recipe(
            id: "remote-\(UUID().uuidString.lowercased())",
            imageUrl: "https://example.com/cover.jpg"
        )
        _ = await store.add(target)

        #expect(await store.remove(target.id))
        #expect(store.recipes.isEmpty)
    }

    // MARK: a non-matching remove leaves the cover file alone

    @Test func failedRemoveKeepsCoverFile() async throws {
        let store = try makeStore()
        let recipeId = "cover-keep-\(UUID().uuidString.lowercased())"
        let coverUrl = try await RecipeCoverStore.save(makeImageData(), recipeId: recipeId)
        defer { cleanup(coverUrl) }
        _ = await store.add(recipe(id: recipeId, imageUrl: coverUrl))

        let ok = await store.remove("ghost-id")

        #expect(!ok)
        let path = try #require(URL(string: coverUrl)).path
        #expect(FileManager.default.fileExists(atPath: path))
    }
}
