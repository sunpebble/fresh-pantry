import Foundation
import Testing
@testable import FreshPantry

struct ModelContainerMigrationTests {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "migtest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func copiesStoreTripletToTarget() throws {
        let fm = FileManager.default
        let legacyDir = tempDir(), targetDir = tempDir()
        let legacy = legacyDir.appending(path: "default.store")
        let target = targetDir.appending(path: "FreshPantry.store")
        for suffix in ["", "-shm", "-wal"] {
            try "data\(suffix)".write(to: URL(fileURLWithPath: legacy.path + suffix), atomically: true, encoding: .utf8)
        }

        ModelContainerFactory.migrateStore(from: legacy, to: target, fileManager: fm)

        for suffix in ["", "-shm", "-wal"] {
            let dst = URL(fileURLWithPath: target.path + suffix)
            #expect(fm.fileExists(atPath: dst.path))
            #expect((try? String(contentsOf: dst, encoding: .utf8)) == "data\(suffix)")
        }
    }

    @Test func noOpWhenTargetAlreadyExists() throws {
        let fm = FileManager.default
        let legacyDir = tempDir(), targetDir = tempDir()
        let legacy = legacyDir.appending(path: "default.store")
        let target = targetDir.appending(path: "FreshPantry.store")
        try "OLD".write(to: legacy, atomically: true, encoding: .utf8)
        try "EXISTING".write(to: target, atomically: true, encoding: .utf8)

        ModelContainerFactory.migrateStore(from: legacy, to: target, fileManager: fm)

        // 目标已存在 → 绝不覆盖。
        #expect((try? String(contentsOf: target, encoding: .utf8)) == "EXISTING")
    }

    @Test func noOpWhenLegacyMissing() throws {
        let fm = FileManager.default
        let legacyDir = tempDir(), targetDir = tempDir()
        let legacy = legacyDir.appending(path: "default.store") // 不创建
        let target = targetDir.appending(path: "FreshPantry.store")

        ModelContainerFactory.migrateStore(from: legacy, to: target, fileManager: fm)

        #expect(!fm.fileExists(atPath: target.path))
    }
}
