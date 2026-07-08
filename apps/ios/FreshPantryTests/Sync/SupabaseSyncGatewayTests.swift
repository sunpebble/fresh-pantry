import Foundation
import Supabase
import Testing
@testable import FreshPantry

/// Wire-level tests for `SupabaseSyncGateway.pushVersionedRow`, driven by a
/// stubbed `URLProtocol` on a real `SupabaseClient` (no live network) so the
/// asserted behavior is the ACTUAL PostgREST request sequence.
///
/// The pinned contract: a first write (`baseVersion <= 0`) uses
/// `upsert(ignoreDuplicates: true)`, and a conflict (ON CONFLICT DO NOTHING →
/// empty representation) must NOT be silently acknowledged — it falls through
/// to the contended-write resolution, whose version-gated UPDATE revives a
/// remote tombstone (deterministic-id set-membership rows: favorite_recipes /
/// dietary_preferences). Regression test for the silent-lost-write defect.
@Suite(.serialized)
struct SupabaseSyncGatewayTests {
    // MARK: Stub plumbing

    struct RecordedRequest: Sendable {
        let method: String
        let url: String
        let headers: [String: String]
        let body: Data
    }

    /// Scripted response queue + request recorder. `URLProtocol` is instantiated
    /// by the loading system, so state is process-wide statics behind a lock;
    /// the suite is `.serialized` and each test resets the script.
    final class StubURLProtocol: URLProtocol {
        private static let lock = NSLock()
        nonisolated(unsafe) private static var responses: [(status: Int, body: String)] = []
        nonisolated(unsafe) private static var recorded: [RecordedRequest] = []

        static func reset(script: [(status: Int, body: String)]) {
            lock.lock()
            defer { lock.unlock() }
            responses = script
            recorded = []
        }

        static var requests: [RecordedRequest] {
            lock.lock()
            defer { lock.unlock() }
            return recorded
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.lock.lock()
            Self.recorded.append(
                RecordedRequest(
                    method: request.httpMethod ?? "",
                    url: request.url?.absoluteString ?? "",
                    headers: request.allHTTPHeaderFields ?? [:],
                    body: Self.drainBody(request)
                )
            )
            let next = Self.responses.isEmpty ? nil : Self.responses.removeFirst()
            Self.lock.unlock()

            guard let next else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: next.status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(next.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}

        /// URLSession delivers the body as a stream, not `httpBody`.
        private static func drainBody(_ request: URLRequest) -> Data {
            if let body = request.httpBody { return body }
            guard let stream = request.httpBodyStream else { return Data() }
            stream.open()
            defer { stream.close() }
            var data = Data()
            let size = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: size)
                guard read > 0 else { break }
                data.append(buffer, count: read)
            }
            return data
        }
    }

    /// In-memory session store so tests never touch the keychain.
    final class InMemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: Data] = [:]
        func store(key: String, value: Data) throws { lock.lock(); values[key] = value; lock.unlock() }
        func retrieve(key: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return values[key] }
        func remove(key: String) throws { lock.lock(); values[key] = nil; lock.unlock() }
    }

    private func makeStubClient() -> SupabaseClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return SupabaseClient(
            supabaseURL: URL(string: "https://stub.supabase.co")!,
            supabaseKey: "stub-key",
            options: SupabaseClientOptions(
                auth: .init(storage: InMemoryAuthStorage()),
                global: .init(session: URLSession(configuration: config))
            )
        )
    }

    private func makeGateway() -> SupabaseSyncGateway {
        SupabaseSyncGateway(client: makeStubClient())
    }

    private func makeRepository() -> RemotePantryRepository {
        RemotePantryRepository(client: makeStubClient())
    }

    // MARK: Fixtures

    private let hid = "11111111-1111-1111-1111-111111111111"
    private let favId = "22222222-2222-2222-2222-222222222222"

    /// The patch `SyncWriter` enqueues for a favorite: the full domain map,
    /// `deletedAt` encoded ALWAYS (null when active).
    private var favoritePatch: [String: JSONValue] {
        [
            "id": .string(favId),
            "recipeID": .string("recipe-1"),
            "remoteVersion": .int(0),
            "clientUpdatedAt": .string("2026-07-08T00:00:00.000Z"),
            "deletedAt": .null,
        ]
    }

    private func createOp(baseVersion: Int? = nil, operation: SyncOperationType = .create) -> SyncOperation {
        SyncOperation(
            id: "op-1",
            householdId: hid,
            entityType: .favoriteRecipe,
            entityId: favId,
            operation: operation,
            patch: favoritePatch,
            baseVersion: baseVersion,
            clientId: "client-a",
            createdAt: JSONDate.parse("2026-07-08T00:00:00.000Z")!
        )
    }

    /// A remote tombstone row at `version` — member B un-favorited recipe-1.
    private func tombstoneRow(version: Int) -> String {
        """
        [{"id":"\(favId)","household_id":"\(hid)","payload":{"id":"\(favId)","recipeID":"recipe-1","remoteVersion":\(version),"clientUpdatedAt":"2026-07-01T00:00:00.000Z","deletedAt":"2026-07-01T00:00:00.000Z"},"version":\(version),"client_id":"client-b","client_updated_at":"2026-07-01T00:00:00.000Z","deleted_at":"2026-07-01T00:00:00.000Z","created_at":"2026-06-01T00:00:00.000Z","updated_at":"2026-07-01T00:00:00.000Z"}]
        """
    }

    private func insertedRow(version: Int) -> String {
        """
        [{"id":"\(favId)","household_id":"\(hid)","payload":{"id":"\(favId)","recipeID":"recipe-1","remoteVersion":\(version)},"version":\(version),"client_id":"client-a","deleted_at":null,"created_at":"2026-07-08T00:00:00.000Z","updated_at":"2026-07-08T00:00:00.000Z"}]
        """
    }

    private func bodyJSON(_ request: RecordedRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
    }

    // MARK: Create-conflict (the silent-lost-write defect)

    @Test func createConflictFallsThroughToVersionedUpdateRevivingTombstone() async throws {
        // Upsert hits an existing tombstone → DO NOTHING (empty representation);
        // the gateway must then select the live row and revive it with a
        // version-gated UPDATE instead of silently acknowledging the op.
        StubURLProtocol.reset(script: [
            (201, "[]"),               // upsert(ignoreDuplicates) → conflict, no row written
            (200, tombstoneRow(version: 4)),
            (200, insertedRow(version: 5)),
        ])

        let acked = try await makeGateway().pushOperations([createOp()])

        #expect(acked == ["op-1"])
        let requests = StubURLProtocol.requests
        try #require(requests.count == 3)

        #expect(requests[0].method == "POST")
        #expect(requests[0].headers["Prefer"]?.contains("resolution=ignore-duplicates") == true)
        // Conflict detection reads the response body — minimal-return would
        // make every clean create decode-fail.
        #expect(requests[0].headers["Prefer"]?.contains("return=representation") == true)

        #expect(requests[1].method == "GET")
        #expect(requests[1].url.contains("household_id=eq.\(hid)"))
        #expect(requests[1].url.contains("id=eq.\(favId)"))

        #expect(requests[2].method == "PATCH")
        #expect(requests[2].url.contains("version=eq.4"))
        let body = bodyJSON(requests[2])
        #expect(body["version"] as? Int == 5)
        #expect(body["deleted_at"] is NSNull)   // the revive
        #expect(body["client_id"] as? String == "client-a")
        let payload = body["payload"] as? [String: Any]
        #expect(payload?["deletedAt"] is NSNull)
        #expect(payload?["recipeID"] as? String == "recipe-1")
    }

    @Test func cleanCreateInsertsWithoutFollowUpRequests() async throws {
        StubURLProtocol.reset(script: [
            (201, insertedRow(version: 1)),
        ])

        let acked = try await makeGateway().pushOperations([createOp()])

        #expect(acked == ["op-1"])
        let requests = StubURLProtocol.requests
        try #require(requests.count == 1)
        #expect(requests[0].method == "POST")
        #expect(bodyJSON(requests[0])["version"] as? Int == 1)
    }

    // MARK: Contended-update recreate race

    @Test func contendedRecreateConflictRetriesInsteadOfSilentlyAcking() async throws {
        // Update path: the gated UPDATE misses (version moved), the row is gone
        // on re-fetch, the recreate upsert ALSO conflicts (row reappeared —
        // e.g. as a tombstone). The gateway must loop again and resolve against
        // the live row, not return as if written.
        StubURLProtocol.reset(script: [
            (200, "[]"),               // conditional UPDATE version=eq.3 → 0 rows
            (200, "[]"),               // re-fetch → row gone
            (201, "[]"),               // recreate upsert → conflict (reappeared)
            (200, tombstoneRow(version: 7)),
            (200, insertedRow(version: 8)),
        ])

        let acked = try await makeGateway().pushOperations([createOp(baseVersion: 3, operation: .update)])

        #expect(acked == ["op-1"])
        let requests = StubURLProtocol.requests
        try #require(requests.count == 5)
        #expect(requests[0].method == "PATCH")
        #expect(requests[0].url.contains("version=eq.3"))
        #expect(requests[2].method == "POST")
        #expect(requests[2].headers["Prefer"]?.contains("return=representation") == true)
        #expect(requests[4].method == "PATCH")
        #expect(requests[4].url.contains("version=eq.7"))
        #expect(bodyJSON(requests[4])["version"] as? Int == 8)
        #expect(bodyJSON(requests[4])["deleted_at"] is NSNull)
    }

    // MARK: Secondary-unique-index dedupe (inventory) must stay a silent skip

    @Test func secondaryIndexConflictIsTheDocumentedDedupeSkip() async throws {
        // A bare ON CONFLICT DO NOTHING also swallows collisions on SECONDARY
        // unique indexes (inventory_items_household_name_added_uniq), where the
        // winning row has a DIFFERENT id. That skip is load-bearing dedupe
        // (see migration 20260601035956): no row ever carries the op's id, so
        // the gateway must ack, not dead-letter, after confirming the id is
        // absent.
        StubURLProtocol.reset(script: [
            (201, "[]"),  // upsert → conflict on the dedupe index
            (200, "[]"),  // select by op id → no such row
            (201, "[]"),  // recreate upsert → same dedupe conflict
            (200, "[]"),  // select by op id → still absent → documented skip
        ])

        let acked = try await makeGateway().pushOperations([createOp()])

        #expect(acked == ["op-1"])
        #expect(StubURLProtocol.requests.count == 4)
    }

    @Test func nonUuidCreateConflictAcksWithoutResolution() async throws {
        // A non-UUID entity id is never sent as the id column (applyLocalId
        // drops it), so its conflict can only be the dedupe index — resolving
        // by id would feed a non-uuid into a uuid filter (Postgres 22P02).
        StubURLProtocol.reset(script: [
            (201, "[]"),  // insert (no id column) → dedupe-index conflict
        ])
        let op = SyncOperation(
            id: "op-2",
            householdId: hid,
            entityType: .inventoryItem,
            entityId: "ing_1",
            operation: .create,
            patch: ["id": .string("ing_1"), "name": .string("Milk")],
            baseVersion: nil,
            clientId: "client-a",
            createdAt: JSONDate.parse("2026-07-08T00:00:00.000Z")!
        )

        let acked = try await makeGateway().pushOperations([op])

        #expect(acked == ["op-2"])
        #expect(StubURLProtocol.requests.count == 1)
    }

    // MARK: Bulk upsert must report which rows actually landed

    @Test func bulkUpsertReturnsOnlyInsertedIds() async throws {
        // Two local-only favorites; the representation contains only the first
        // — the second was ON CONFLICT DO NOTHING'd (e.g. a remote tombstone
        // holds its deterministic id). `upsertRows` must surface exactly the
        // inserted ids so `uploadLocalOnly` stops v1-marking the collided row.
        let otherId = "44444444-4444-4444-4444-444444444444"
        StubURLProtocol.reset(script: [
            (201, insertedRow(version: 1)),  // representation: favId only
        ])
        let rows: [[String: JSONValue]] = [
            ["id": .string(favId), "recipeID": .string("recipe-1"), "remoteVersion": .int(0), "deletedAt": .null],
            ["id": .string(otherId), "recipeID": .string("recipe-2"), "remoteVersion": .int(0), "deletedAt": .null],
        ]

        let inserted = try await makeRepository().upsertFavoriteRecipes(hid, rows)

        #expect(inserted == [favId])
        let requests = StubURLProtocol.requests
        try #require(requests.count == 1)
        #expect(requests[0].method == "POST")
        #expect(requests[0].headers["Prefer"]?.contains("resolution=ignore-duplicates") == true)
        // The id set is decoded from the representation the request already
        // asks for — the wire contract (Flutter parity) must not change.
        #expect(requests[0].headers["Prefer"]?.contains("return=representation") == true)
    }

    // MARK: Collided upload rows resolve through resolveUploadCollisions

    private func resolveCollision(script: [(Int, String)]) async -> Set<String> {
        StubURLProtocol.reset(script: script)
        return await makeGateway().resolveUploadCollisions(
            entityType: .favoriteRecipe,
            householdId: hid,
            rows: [favoritePatch],
            clientId: "client-a"
        )
    }

    @Test func uploadCollisionRevivesTombstoneWithGatedClientWinsUpdate() async throws {
        // The bulk upsert already collided; resolution selects the row, finds a
        // tombstone, and revives it with the version-gated client-wins UPDATE
        // (the full pull filters tombstones — nothing else can deliver it).
        let resolved = await resolveCollision(script: [
            (200, tombstoneRow(version: 4)),  // select → tombstone
            (200, insertedRow(version: 5)),   // gated PATCH → revived
        ])

        #expect(resolved == [favId])
        let requests = StubURLProtocol.requests
        try #require(requests.count == 2)
        #expect(requests[0].method == "GET")
        #expect(requests[0].url.contains("household_id=eq.\(hid)"))
        #expect(requests[0].url.contains("id=eq.\(favId)"))
        #expect(requests[1].method == "PATCH")
        #expect(requests[1].url.contains("version=eq.4"))
        let body = bodyJSON(requests[1])
        #expect(body["version"] as? Int == 5)
        #expect(body["deleted_at"] is NSNull)  // the revive
        #expect(body["client_id"] as? String == "client-a")
        let payload = body["payload"] as? [String: Any]
        #expect(payload?["recipeID"] as? String == "recipe-1")
    }

    @Test func uploadCollisionLeavesLiveRowUntouched() async throws {
        // A LIVE row must never be written: remote is authoritative (the pull
        // adopts it) and a concurrent outbox push may have just landed a NEWER
        // write here — overwriting it with the upload snapshot would silently
        // roll the user's edit back. The row is still confirmed (bump v1
        // upstream = the missed-version-bump self-heal).
        let resolved = await resolveCollision(script: [
            (200, insertedRow(version: 3)),  // select → live row (deleted_at null)
        ])

        #expect(resolved == [favId])
        #expect(StubURLProtocol.requests.count == 1)  // select only, no write
    }

    @Test func uploadCollisionAcksAbsentRowAsDedupeSkip() async throws {
        // No remote row carries the id: the conflict was a secondary unique
        // index (inventory's dedupe) — the documented silent skip. Confirm so
        // the v1 bump lets the next merge drop the local duplicate.
        let resolved = await resolveCollision(script: [
            (200, "[]"),  // select → absent
        ])

        #expect(resolved == [favId])
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test func uploadCollisionLeavesHotRowUnresolvedAfterRetryBudget() async throws {
        // Every gated revive misses (version keeps moving): the row must NOT
        // be reported resolved — a v1 mark without a live remote row is the
        // original silent-loss defect. It stays rv0 and retries next run.
        let resolved = await resolveCollision(script: [
            (200, tombstoneRow(version: 4)), (200, "[]"),  // retry 1: gate miss
            (200, tombstoneRow(version: 5)), (200, "[]"),  // retry 2
            (200, tombstoneRow(version: 6)), (200, "[]"),  // retry 3
        ])

        #expect(resolved.isEmpty)
        #expect(StubURLProtocol.requests.count == 6)
    }

    // MARK: Unresolvable conflict must NOT ack (pins the error propagation)

    @Test func unresolvableCreateConflictLeavesOpUnacked() async throws {
        // Every gated UPDATE misses (hot row): the retry budget exhausts and
        // the op must stay in the outbox — swallowing the resolution error
        // would resurrect the silent-lost-write bug.
        StubURLProtocol.reset(script: [
            (201, "[]"),                      // upsert → conflict
            (200, tombstoneRow(version: 4)),  // retry 1: select
            (200, "[]"),                      //          gated PATCH misses
            (200, tombstoneRow(version: 5)),  // retry 2
            (200, "[]"),
            (200, tombstoneRow(version: 6)),  // retry 3
            (200, "[]"),
        ])

        let acked = try await makeGateway().pushOperations([createOp()])

        #expect(acked.isEmpty)
        #expect(StubURLProtocol.requests.count == 7)
    }
}
