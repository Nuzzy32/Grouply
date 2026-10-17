import XCTest

@testable import Grouply

private struct LocalBackendAccounts: Decodable {
  struct Account: Decodable {
    let email: String
    let password: String
  }
  let url: URL
  let publishableKey: String
  let accounts: [String: Account]
  static func load() throws -> Self {
    guard let path = ProcessInfo.processInfo.environment["GROUPLY_LOCAL_ACCOUNTS_PATH"],
      path.hasPrefix("/"),
      FileManager.default.fileExists(atPath: path)
    else { throw XCTSkip("Local backend accounts file is unavailable.") }
    let value = try JSONDecoder().decode(
      Self.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
    guard ["localhost", "127.0.0.1", "::1"].contains(value.url.host ?? "") else {
      throw XCTSkip("Integration tests only run against a local backend.")
    }
    return value
  }
  func account(_ name: String) throws -> Account {
    guard let account = accounts[name] else { throw XCTSkip("Missing local test account.") }
    return account
  }
}
private final class IntegrationTokenStore: BackendTokenStore {
  var data: Data?
  func load() throws -> Data? { data }
  func save(_ data: Data) throws { self.data = data }
  func clear() throws { data = nil }
}

final class BackendIntegrationTests: XCTestCase {
  @MainActor func testSignedSimulatorKeychainRoundTrip() async throws {
    let config = try LocalBackendAccounts.load()
    let configuration = BackendConfiguration(url: config.url, publishableKey: config.publishableKey)
    let tokens = KeychainBackendTokenStore(account: "GrouplyIntegration-\(UUID().uuidString)")
    defer { try? tokens.clear() }
    let client = SupabaseBackend(configuration: configuration, tokenStore: tokens)
    let account = try config.account("raka")
    try await client.signIn(email: account.email, password: account.password)
    XCTAssertNotNil(try tokens.load())
    let restored = SupabaseBackend(configuration: configuration, tokenStore: tokens)
    let hasSession = try await restored.restoreSession()
    XCTAssertTrue(hasSession)
    _ = try await restored.snapshot()
    try await restored.signOut()
    XCTAssertNil(try tokens.load())
  }
  @MainActor func testNativeClientsCollaborateAndRestoreAgainstLocalSupabase() async throws {
    let config = try LocalBackendAccounts.load()
    let configuration = BackendConfiguration(url: config.url, publishableKey: config.publishableKey)
    let alexTokens = IntegrationTokenStore()
    let alex = SupabaseBackend(configuration: configuration, tokenStore: alexTokens)
    let raka = SupabaseBackend(configuration: configuration, tokenStore: IntegrationTokenStore())
    let nadia = SupabaseBackend(configuration: configuration, tokenStore: IntegrationTokenStore())
    for (name, client) in [("alex", alex), ("raka", raka), ("nadia", nadia)] {
      let account = try config.account(name)
      try await client.signIn(email: account.email, password: account.password)
    }
    let rakaID = try await raka.snapshot().currentUserID
    let nadiaID = try await nadia.snapshot().currentUserID
    let groupResult = try await alex.mutate(
      action: "createGroup",
      payload: [
        "name": .string("Native Integration \(UUID().uuidString.prefix(8))"),
        "description": .string("Native client integration verification"),
        "course": .string("Pengujian"),
      ])
    let groupID = try XCTUnwrap(groupResult.id)
    // Raka has not joined yet; a valid JWT must not grant cross-group access.
    let outsiderSnapshot = try await raka.snapshot()
    XCTAssertFalse(outsiderSnapshot.groups.contains { $0.id == groupID })
    do {
      _ = try await raka.mutate(
        action: "createProject",
        payload: [
          "groupID": .string(groupID), "title": .string("Forbidden"), "description": .string(""),
          "dueAt": .date(Date().addingTimeInterval(86400)),
        ])
      XCTFail("Cross-group mutation must be rejected")
    } catch is BackendError {}
    for member in [raka, nadia] {
      let inviteResult = try await alex.mutate(
        action: "generateInvite", payload: ["groupID": .string(groupID)])
      let invite = try XCTUnwrap(inviteResult.invite)
      _ = try await member.mutate(action: "joinGroup", payload: ["code": .string(invite.code)])
    }
    let due = Date().addingTimeInterval(86400 * 3)
    let projectResult = try await alex.mutate(
      action: "createProject",
      payload: [
        "groupID": .string(groupID), "title": .string("Alur Kolaborasi Native"),
        "description": .string(""), "dueAt": .date(due),
      ])
    let projectID = try XCTUnwrap(projectResult.id)
    let taskResult = try await alex.mutate(
      action: "createTask",
      payload: [
        "projectID": .string(projectID), "title": .string("Implementasi skema"),
        "description": .string(""), "assigneeID": .string(rakaID), "reviewerID": .string(nadiaID),
        "dueAt": .date(due),
      ])
    let taskID = try XCTUnwrap(taskResult.id)
    var snapshot = try await raka.snapshot()
    var task = try XCTUnwrap(snapshot.tasks.first { $0.id == taskID })
    _ = try await raka.mutate(
      action: "startTask", payload: ["id": .string(taskID), "expectedVersion": .int(task.version)])
    snapshot = try await raka.snapshot()
    task = try XCTUnwrap(snapshot.tasks.first { $0.id == taskID })
    _ = try await raka.mutate(
      action: "submitWork",
      payload: [
        "taskID": .string(taskID), "note": .string("Skema selesai dan siap ditinjau."),
        "links": .array([.string("https://example.org/schema")]),
        "expectedVersion": .int(task.version),
      ])
    snapshot = try await nadia.snapshot()
    task = try XCTUnwrap(snapshot.tasks.first { $0.id == taskID })
    XCTAssertEqual(task.status, .inReview)
    do {
      _ = try await nadia.mutate(
        action: "review",
        payload: [
          "taskID": .string(taskID), "approve": .bool(true), "feedback": .string(""),
          "expectedVersion": .int(task.version - 1),
        ])
      XCTFail("Stale review must be rejected")
    } catch let error as BackendError { XCTAssertTrue(error.message.contains("stale_version")) }
    _ = try await nadia.mutate(
      action: "review",
      payload: [
        "taskID": .string(taskID), "approve": .bool(true), "feedback": .string("Sudah sesuai"),
        "expectedVersion": .int(task.version),
      ])
    let restored = SupabaseBackend(configuration: configuration, tokenStore: alexTokens)
    let didRestore = try await restored.restoreSession()
    XCTAssertTrue(didRestore)
    let completed = try await restored.snapshot()
    let completedTask = try XCTUnwrap(completed.tasks.first { $0.id == taskID })
    XCTAssertEqual(completedTask.status, .done)
    XCTAssertEqual(completedTask.submissions.last?.decision, "approved")
    XCTAssertEqual(completedTask.submissions.last?.reviewerID, nadiaID)
    XCTAssertEqual(completed.groups.first { $0.id == groupID }?.memberIDs.count, 3)
    try await restored.signOut()
    XCTAssertNil(alexTokens.data)
    XCTAssertFalse(restored.hasSession)
    try await raka.signOut()
    try await nadia.signOut()
  }

  @MainActor func testNativeStoreLoadsServerStateAcrossInstances() async throws {
    let config = try LocalBackendAccounts.load()
    guard let bundled = BackendConfiguration.bundled, bundled.url == config.url else {
      throw XCTSkip("App bundle must be configured for the local backend to test its store bridge.")
    }
    let account = try config.account("alex")
    let first = DemoStore(
      persist: false,
      backendFactory: { SupabaseBackend(configuration: $0, tokenStore: IntegrationTokenStore()) })
    try await first.connectBackend(email: account.email, password: account.password)
    XCTAssertTrue(first.isCloudMode)
    let groupID = try await first.createGroup(
      name: "Store Integration \(UUID().uuidString.prefix(8))", description: "", course: "Pengujian"
    )
    let invitation = try await first.generateInvite(groupID: groupID)
    XCTAssertFalse(invitation.code.isEmpty)
    XCTAssertEqual(first.invites.first { $0.id == invitation.id }?.code, invitation.code)
    await first.refreshFromBackend()
    XCTAssertEqual(first.invites.first { $0.id == invitation.id }?.code, invitation.code)
    XCTAssertNil(first.groupsJoinError(code: "opaque-token-not-present-in-snapshot"))
    let second = DemoStore(
      persist: false,
      backendFactory: { SupabaseBackend(configuration: $0, tokenStore: IntegrationTokenStore()) })
    try await second.connectBackend(email: account.email, password: account.password)
    XCTAssertTrue(second.groups.contains { $0.id == groupID })
    XCTAssertEqual(first.currentUserID, second.currentUserID)
    first.reports.append(
      GLReport(
        messageID: "server-only-id", reporterID: first.currentUserID!, reason: "server-only-report",
        createdAt: Date()))
    try await first.signOut()
    XCTAssertTrue(first.reports.isEmpty)
    first.signIn(as: "u1")
    XCTAssertTrue(first.reports.isEmpty)
    try await second.signOut()
  }
}
