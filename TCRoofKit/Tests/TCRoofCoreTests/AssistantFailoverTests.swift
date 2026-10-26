import XCTest
@testable import TCRoofCore

/// The backup provider: asked when the main one fails in a way another provider may not.
final class AssistantFailoverTests: XCTestCase {
    typealias F = Assistant.OpenAI.Failure

    private actor Stub: Assistant.Transport {
        let fail: Error?
        let name: String
        private(set) var calls = 0
        init(_ name: String, fail: Error? = nil) { self.name = name; self.fail = fail }
        func complete(_ request: Assistant.Request) async throws -> Assistant.Reply {
            calls += 1
            if let fail { throw fail }
            return Assistant.Reply(message: .init(role: .assistant, content: name), servedBy: name)
        }
    }

    private let q = Assistant.Request(messages: [.user("q")], tools: [])

    func testTheMainAnswersWhenItCan() async throws {
        let main = Stub("Claude"), backup = Stub("Qwen")
        let r = try await Assistant.Failover(primary: main, backup: backup).complete(q)
        XCTAssertEqual(r.servedBy, "Claude")
        let backupCalls = await backup.calls
        XCTAssertEqual(backupCalls, 0)
    }

    func testTheBackupAnswersWhenTheMainFails() async throws {
        for failure in [F.badKey, .busy, .freeQuotaUsed, .server(500, "x"), .badReply, .noKey] {
            let r = try await Assistant.Failover(primary: Stub("Claude", fail: failure), backup: Stub("Qwen")).complete(q)
            XCTAssertEqual(r.message.content, "Qwen", "\(failure)")
            XCTAssertEqual(r.servedBy, "Qwen | สำรอง")
        }
        // a network error too
        let r = try await Assistant.Failover(primary: Stub("Claude", fail: URLError(.timedOut)), backup: Stub("Qwen")).complete(q)
        XCTAssertEqual(r.message.content, "Qwen")
    }

    func testTheDaysLimitAndCancellingAreNotPassedOn() async {
        let backup = Stub("Qwen")
        for failure in [F.limit(50) as Error, CancellationError()] {
            do {
                _ = try await Assistant.Failover(primary: Stub("Claude", fail: failure), backup: backup).complete(q)
                XCTFail("should throw")
            } catch {}
        }
        let calls = await backup.calls
        XCTAssertEqual(calls, 0)
    }

    func testWithoutABackupTheFailureStands() async {
        do {
            _ = try await Assistant.Failover(primary: Stub("Claude", fail: F.badKey), backup: nil).complete(q)
            XCTFail("should throw")
        } catch { XCTAssertEqual(error as? F, .badKey) }
        // and when the backup fails too, its failure is the one shown
        do {
            _ = try await Assistant.Failover(primary: Stub("Claude", fail: F.badKey), backup: Stub("Qwen", fail: F.busy)).complete(q)
            XCTFail("should throw")
        } catch { XCTAssertEqual(error as? F, .busy) }
    }

    @MainActor
    func testTheSessionShowsWhoAnswered() async throws {
        let s = Assistant.Session(transport: Assistant.Failover(primary: Stub("Claude", fail: F.busy), backup: Stub("Qwen")), jobs: { [] })
        _ = try await s.send("q")
        XCTAssertEqual(s.servedBy, "Qwen | สำรอง")
    }

    func testRoutesAndUses() {
        XCTAssertEqual(Assistant.Route(provider: .anthropic, model: "claude-haiku-5-5").label, "Claude (Anthropic) | claude-haiku-5-5")
        XCTAssertEqual(Assistant.Use.allCases, [.chat, .digest])
    }
}
