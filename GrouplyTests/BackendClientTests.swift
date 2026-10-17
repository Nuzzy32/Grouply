import XCTest

@testable import Grouply

private final class MemoryTokenStore: BackendTokenStore {
  var data: Data?
  var failsClear = false
  func load() throws -> Data? { data }
  func save(_ data: Data) throws { self.data = data }
  func clear() throws {
    if failsClear { throw BackendError(status: -34018, message: "Secure cleanup failed") }
    data = nil
  }
}
private final class BackendURLProtocol: URLProtocol {
  static var handler: ((URLRequest) throws -> (Int, String))?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      let (status, body) = try Self.handler!(request)
      let response = HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil,
        headerFields: ["Content-Type": "application/json"])!
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Data(body.utf8))
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}
private func requestBody(_ request: URLRequest) -> Data {
  if let data = request.httpBody { return data }
  guard let stream = request.httpBodyStream else { return Data() }
  stream.open()
  defer { stream.close() }
  var data = Data()
  var buffer = [UInt8](repeating: 0, count: 1024)
  while stream.hasBytesAvailable {
    let count = stream.read(&buffer, maxLength: buffer.count)
    if count <= 0 { break }
    data.append(contentsOf: buffer.prefix(count))
  }
  return data
}
final class BackendClientTests: XCTestCase {
  @MainActor func testAccountDeletionClearsStateWithoutFetchingDeletedSnapshot() async throws {
    for cleanupFails in [false, true] {
      let tokens = MemoryTokenStore()
      let backend = client(store: tokens)
      let store = DemoStore(backendFactory: { _ in backend })
      store.setBackendActive(false)
      var deletionCount = 0
      var snapshotCount = 0
      BackendURLProtocol.handler = { request in
        switch request.url!.lastPathComponent {
        case "token":
          return (200, #"{"access_token":"token","refresh_token":"refresh","expires_in":3600,"user":{"id":"actor"}}"#)
        case "grouply_snapshot":
          snapshotCount += 1
          return (200, #"{"users":[],"groups":[],"projects":[],"tasks":[],"messages":[],"invites":[],"reports":[],"currentUserID":"actor","blockedUserIDs":[],"readMessageIDs":[]}"#)
        case "grouply_mutate":
          let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
          XCTAssertEqual(body["action"] as? String, "deleteAccount")
          deletionCount += 1
          return (200, #"{"deleted":true}"#)
        default:
          XCTFail("Deletion must not request logout or another endpoint")
          return (500, "{}")
        }
      }
      try await store.connectBackend(email: "actor@example.org", password: "unused")
      tokens.failsClear = cleanupFails
      do {
        try await store.deleteAccount()
        XCTAssertFalse(cleanupFails)
      } catch {
        XCTAssertTrue(cleanupFails)
        XCTAssertTrue(error.localizedDescription.contains("Akun server telah dihapus"))
      }
      XCTAssertEqual(deletionCount, 1)
      XCTAssertEqual(snapshotCount, 1)
      XCTAssertFalse(store.isCloudMode)
      XCTAssertFalse(backend.hasSession)
      XCTAssertNil(store.currentUserID)
      XCTAssertFalse(store.realtimeConnected)
      XCTAssertTrue(store.reports.isEmpty)
      if !cleanupFails { XCTAssertNil(tokens.data) }
    }
  }

  @MainActor func testAccountDeletionDenialKeepsExistingSession() async throws {
    let tokens = MemoryTokenStore()
    let backend = client(store: tokens)
    BackendURLProtocol.handler = { request in
      if request.url!.lastPathComponent == "token" {
        return (200, #"{"access_token":"token","refresh_token":"refresh","expires_in":3600,"user":{"id":"actor"}}"#)
      }
      return (400, #"{"message":"active_assignment"}"#)
    }
    try await backend.signIn(email: "actor@example.org", password: "unused")
    do { try await backend.deleteAccount(); XCTFail("Must reject active assignments") }
    catch let error as BackendError { XCTAssertEqual(error.message, "active_assignment") }
    XCTAssertTrue(backend.hasSession)
    XCTAssertNotNil(tokens.data)
  }

  @MainActor func testAccountDeletionNeedsExplicitServerConfirmation() async throws {
    let tokens = MemoryTokenStore()
    let backend = client(store: tokens)
    BackendURLProtocol.handler = { request in
      if request.url!.lastPathComponent == "token" {
        return (200, #"{"access_token":"token","refresh_token":"refresh","expires_in":3600,"user":{"id":"actor"}}"#)
      }
      return (200, "{}")
    }
    try await backend.signIn(email: "actor@example.org", password: "unused")
    do { try await backend.deleteAccount(); XCTFail("Requires deletion acknowledgement") }
    catch let error as BackendError { XCTAssertTrue(error.message.contains("belum mengonfirmasi")) }
    XCTAssertTrue(backend.hasSession)
    XCTAssertNotNil(tokens.data)
  }

  @MainActor func testDeletedIdentityAndLegacyReportDecode() throws {
    let store = DemoStore()
    XCTAssertEqual(store.displayName(""), "Pengguna terhapus")
    let data = Data(#"{"id":"r","messageID":"m","reporterID":"u","reason":"spam","createdAt":"2026-10-17T00:00:00Z"}"#.utf8)
    let report = try SupabaseBackend.decoder().decode(GLReport.self, from: data)
    XCTAssertNil(report.status)
    XCTAssertEqual(report.statusLabel, "Menunggu peninjauan")
  }
  @MainActor func testRealtimeURLAndSubscriptionsDoNotExposeTokensOrDeleteEvents() throws {
    let config = BackendConfiguration(url: URL(string: "http://127.0.0.1:55321")!, publishableKey: "sb_publishable_test")
    let url = SupabaseBackend.realtimeURL(config)
    XCTAssertEqual(url.scheme, "ws")
    XCTAssertEqual(url.port, 55321)
    XCTAssertEqual(url.path, "/realtime/v1/websocket")
    XCTAssertFalse(url.absoluteString.contains("access_token"))
    let subscriptions = try JSONSerialization.jsonObject(with: JSONEncoder().encode(SupabaseBackend.realtimeSubscriptions(userID: "actor"))) as! [[String: String]]
    XCTAssertEqual(subscriptions.count, 4)
    XCTAssertFalse(subscriptions.contains { ["DELETE", "*"].contains($0["event"] ?? "") })
    XCTAssertEqual(subscriptions.filter { $0["table"] != "chat_messages" }.map { $0["filter"] }, Array(repeating: "user_id=eq.actor", count: 3))
    let secure = BackendConfiguration(url: URL(string: "https://example.supabase.co")!, publishableKey: "sb_publishable_test")
    XCTAssertEqual(SupabaseBackend.realtimeURL(secure).scheme, "wss")
  }

  func testRealtimeFramesDistinguishAcknowledgementsErrorsAndChanges() throws {
    for status in ["error", "timeout"] {
      let frame = try JSONDecoder().decode(RealtimeFrame.self, from: Data("{\"event\":\"system\",\"payload\":{\"status\":\"\(status)\"}}".utf8))
      XCTAssertTrue(frame.isError)
      XCTAssertFalse(frame.isOK)
    }
    let joined = try JSONDecoder().decode(RealtimeFrame.self, from: Data(#"{"event":"phx_reply","ref":"join","payload":{"status":"ok"}}"#.utf8))
    XCTAssertTrue(joined.isOK)
    XCTAssertEqual(joined.ref, "join")
    XCTAssertFalse(joined.subscriptionReady)
    let ready = try JSONDecoder().decode(RealtimeFrame.self, from: Data(#"{"event":"system","payload":{"status":"ok","extension":"postgres_changes"}}"#.utf8))
    XCTAssertTrue(ready.subscriptionReady)
    let changed = try JSONDecoder().decode(RealtimeFrame.self, from: Data(#"{"event":"postgres_changes","payload":{"data":{"table":"chat_messages","record":{"id":"message"}}}}"#.utf8))
    XCTAssertFalse(changed.isOK)
    XCTAssertFalse(changed.isError)
  }
  @MainActor func testOldUnauthorizedResponseCannotDeleteNewSession() async throws {
    let sharedStore = MemoryTokenStore()
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [HeldUnauthorizedProtocol.self]
    let session = URLSession(configuration: config)
    let configuration = BackendConfiguration(
      url: URL(string: "https://example.supabase.co")!, publishableKey: "sb_publishable_test")
    let old = SupabaseBackend(
      configuration: configuration, session: session, tokenStore: sharedStore)
    try await old.signIn(email: "old@example.org", password: "unused")
    let held = expectation(description: "Old request is pending")
    HeldUnauthorizedProtocol.onHold = { held.fulfill() }
    let request = Task { try await old.mutate(action: "markChatRead", payload: [:]) }
    await fulfillment(of: [held], timeout: 5)
    try await old.signOut()
    let next = SupabaseBackend(
      configuration: configuration, session: session, tokenStore: sharedStore)
    try await next.signIn(email: "new@example.org", password: "unused")
    let saved = sharedStore.data
    HeldUnauthorizedProtocol.pending?.respond(status: 401, body: "{\"message\":\"unauthorized\"}")
    do {
      _ = try await request.value
      XCTFail("Old request should fail")
    } catch {}
    XCTAssertEqual(sharedStore.data, saved)
    XCTAssertTrue(next.hasSession)
    HeldUnauthorizedProtocol.pending = nil
    HeldUnauthorizedProtocol.onHold = nil
  }
  @MainActor private func client(store: MemoryTokenStore) -> SupabaseBackend {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [BackendURLProtocol.self]
    return SupabaseBackend(
      configuration: BackendConfiguration(
        url: URL(string: "https://example.supabase.co")!, publishableKey: "sb_publishable_test"),
      session: URLSession(configuration: config), tokenStore: store)
  }

  @MainActor private func waitForBackendIdle(_ store: DemoStore) async throws {
    for _ in 0..<200 {
      if !store.isBusy { return }
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Backend operation did not finish")
  }

  @MainActor func testMutationSnapshotCannotRestoreExpiredAccountOrOverwriteExpiryError() async throws {
    let snapshot = #"{"users":[],"groups":[],"projects":[],"tasks":[],"messages":[],"invites":[],"reports":[],"currentUserID":"expired-account","blockedUserIDs":[],"readMessageIDs":[]}"#
    for status in [200, 500] {
      let tokens = MemoryTokenStore()
      let configuration = URLSessionConfiguration.ephemeral
      configuration.protocolClasses = [HeldUnauthorizedProtocol.self]
      let session = URLSession(configuration: configuration)
      defer { session.invalidateAndCancel() }
      let store = DemoStore(backendFactory: {
        SupabaseBackend(configuration: $0, session: session, tokenStore: tokens)
      })
      store.setBackendActive(false)
      let held = expectation(description: "Mutation snapshot is pending (\(status))")
      var snapshotCount = 0
      var pending: HeldUnauthorizedProtocol?
      HeldUnauthorizedProtocol.handler = { request in
        switch request.request.url!.lastPathComponent {
        case "token":
          request.respond(status: 200, body: #"{"access_token":"token","refresh_token":"refresh","expires_in":3600,"user":{"id":"expired-account"}}"#)
        case "grouply_mutate":
          request.respond(status: 200, body: #"{"id":"saved"}"#)
        default:
          snapshotCount += 1
          if snapshotCount == 2 {
            pending = request
            held.fulfill()
          } else if snapshotCount == 1 {
            request.respond(status: 200, body: snapshot)
          } else {
            request.respond(status: 401, body: #"{"message":"JWT expired"}"#)
          }
        }
      }
      defer { HeldUnauthorizedProtocol.handler = nil }
      try await store.connectBackend(email: "member@example.org", password: "unused")
      let mutation = Task { try await store.mutateBackend("updateProfile", [:]) }
      await fulfillment(of: [held], timeout: 5)
      let response = try XCTUnwrap(pending)
      store.isBusy = false
      let refreshed = await store.refreshFromBackend()
      XCTAssertFalse(refreshed)
      XCTAssertFalse(store.isCloudMode)
      XCTAssertNil(store.currentUserID)
      XCTAssertNil(tokens.data)
      let expiryError = store.backendError
      response.respond(status: status, body: status == 200 ? snapshot : #"{"message":"old snapshot failed"}"#)
      do {
        _ = try await mutation.value
        XCTFail("Expired mutation must not finish successfully")
      } catch is CancellationError {
      } catch {
        XCTFail("Expected cancellation, got \(error)")
      }
      XCTAssertFalse(store.isCloudMode)
      XCTAssertNil(store.currentUserID)
      XCTAssertEqual(store.backendError, expiryError)
    }
  }

  @MainActor func testQueuedRealtimeRefreshRetriesFailuresWithoutAnotherEvent() async throws {
    let tokens = MemoryTokenStore()
    let backend = client(store: tokens)
    let store = DemoStore(backendFactory: { _ in backend })
    store.setBackendActive(false)
    defer { store.setBackendActive(false) }
    let recovered = expectation(description: "Catchup retries until the snapshot succeeds")
    var snapshotCount = 0
    BackendURLProtocol.handler = { request in
      if request.url!.lastPathComponent == "token" {
        return (200, #"{"access_token":"token","refresh_token":"refresh","expires_in":3600,"user":{"id":"initial-account"}}"#)
      }
      snapshotCount += 1
      if snapshotCount == 2 { throw URLError(.notConnectedToInternet) }
      if snapshotCount == 3 { return (503, #"{"message":"temporarily unavailable"}"#) }
      let actor = snapshotCount == 1 ? "initial-account" : "caught-up-account"
      if snapshotCount == 4 { recovered.fulfill() }
      return (200, "{\"users\":[],\"groups\":[],\"projects\":[],\"tasks\":[],\"messages\":[],\"invites\":[],\"reports\":[],\"currentUserID\":\"\(actor)\",\"blockedUserIDs\":[],\"readMessageIDs\":[]}")
    }
    try await store.connectBackend(email: "member@example.org", password: "unused")
    store.queueRealtimeRefresh()
    await fulfillment(of: [recovered], timeout: 8)
    try await waitForBackendIdle(store)
    XCTAssertEqual(snapshotCount, 4)
    XCTAssertEqual(store.currentUserID, "caught-up-account")
    XCTAssertNil(store.backendError)
    XCTAssertTrue(store.isCloudMode)
    XCTAssertTrue(backend.hasSession)
  }

  @MainActor func testCancelledMutationSnapshotDoesNotPublishRefreshError() async throws {
    let tokens = MemoryTokenStore()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [HeldUnauthorizedProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let store = DemoStore(backendFactory: {
      SupabaseBackend(configuration: $0, session: session, tokenStore: tokens)
    })
    store.setBackendActive(false)
    let held = expectation(description: "Snapshot is pending before cancellation")
    var snapshotCount = 0
    HeldUnauthorizedProtocol.handler = { request in
      switch request.request.url!.lastPathComponent {
      case "token":
        request.respond(status: 200, body: #"{"access_token":"token","refresh_token":"refresh","expires_in":3600,"user":{"id":"current-account"}}"#)
      case "grouply_mutate":
        request.respond(status: 200, body: #"{"id":"saved"}"#)
      default:
        snapshotCount += 1
        if snapshotCount == 1 {
          request.respond(status: 200, body: #"{"users":[],"groups":[],"projects":[],"tasks":[],"messages":[],"invites":[],"reports":[],"currentUserID":"current-account","blockedUserIDs":[],"readMessageIDs":[]}"#)
        } else {
          held.fulfill()
        }
      }
    }
    defer { HeldUnauthorizedProtocol.handler = nil }
    try await store.connectBackend(email: "member@example.org", password: "unused")
    let mutation = Task { try await store.mutateBackend("updateProfile", [:]) }
    await fulfillment(of: [held], timeout: 5)
    mutation.cancel()
    do {
      _ = try await mutation.value
      XCTFail("Cancelled mutation must not finish successfully")
    } catch is CancellationError {
    } catch {
      XCTFail("Expected cancellation, got \(error)")
    }
    XCTAssertEqual(store.currentUserID, "current-account")
    XCTAssertNil(store.backendError)
    XCTAssertTrue(store.isCloudMode)
    XCTAssertFalse(store.isBusy)
  }

  override func tearDown() {
    BackendURLProtocol.handler = nil
    super.tearDown()
  }

  @MainActor func testExpiredSessionRefreshesAndPersistsRotatedTokenBeforeRPC() async throws {
    let store = MemoryTokenStore()
    let backend = client(store: store)
    var refreshCount = 0
    BackendURLProtocol.handler = { request in
      if request.url!.path.hasSuffix("/token") {
        let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
        if request.url!.query!.contains("refresh_token") {
          refreshCount += 1
          XCTAssertEqual(body["refresh_token"] as? String, "refresh-old")
          return (
            200,
            "{\"access_token\":\"new\",\"refresh_token\":\"refresh-new\",\"expires_in\":3600,\"user\":{\"id\":\"u1\"}}"
          )
        }
        return (
          200,
          "{\"access_token\":\"old\",\"refresh_token\":\"refresh-old\",\"expires_in\":0,\"user\":{\"id\":\"u1\"}}"
        )
      }
      XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer new")
      return (200, "{\"id\":\"g1\"}")
    }
    try await backend.signIn(email: "member@example.org", password: "password")
    let result = try await backend.mutate(action: "createGroup", payload: [:])
    XCTAssertEqual(result.id, "g1")
    XCTAssertEqual(refreshCount, 1)
    XCTAssertTrue(String(data: store.data!, encoding: .utf8)!.contains("refresh-new"))
  }
  @MainActor func testUnauthorizedRPCPreservesErrorAndClearsSession() async throws {
    let store = MemoryTokenStore()
    let backend = client(store: store)
    BackendURLProtocol.handler = { request in
      if request.url!.path.hasSuffix("/token") {
        return (
          200,
          "{\"access_token\":\"valid\",\"refresh_token\":\"refresh\",\"expires_in\":3600,\"user\":{\"id\":\"u1\"}}"
        )
      }
      return (401, "{\"message\":\"JWT expired\"}")
    }
    try await backend.signIn(email: "member@example.org", password: "password")
    do {
      _ = try await backend.snapshot()
      XCTFail("Expected 401")
    } catch let error as BackendError {
      XCTAssertEqual(error.message, "JWT expired")
      XCTAssertEqual(error.localizedDescription, "Sesi berakhir. Silakan masuk kembali.")
    }
    XCTAssertFalse(backend.hasSession)
    XCTAssertNil(store.data)
  }
  @MainActor func testLogoutClearsCredentialsWhenServerFails() async throws {
    let store = MemoryTokenStore()
    let backend = client(store: store)
    BackendURLProtocol.handler = { request in
      if request.url!.path.hasSuffix("/token") {
        return (
          200,
          "{\"access_token\":\"valid\",\"refresh_token\":\"refresh\",\"expires_in\":3600,\"user\":{\"id\":\"u1\"}}"
        )
      }
      throw URLError(.notConnectedToInternet)
    }
    try await backend.signIn(email: "member@example.org", password: "password")
    do {
      try await backend.signOut()
      XCTFail("Expected transport failure")
    } catch {}
    XCTAssertFalse(backend.hasSession)
    XCTAssertNil(store.data)
  }
  @MainActor func testLogoutStillRevokesServerWhenKeychainDeletionFails() async throws {
    let store = MemoryTokenStore()
    let backend = client(store: store)
    var revoked = false
    BackendURLProtocol.handler = { request in
      if request.url!.path.hasSuffix("/token") {
        return (
          200,
          "{\"access_token\":\"valid\",\"refresh_token\":\"refresh\",\"expires_in\":3600,\"user\":{\"id\":\"u1\"}}"
        )
      }
      revoked = request.url!.path.hasSuffix("/logout")
      return (204, "")
    }
    try await backend.signIn(email: "member@example.org", password: "password")
    store.failsClear = true
    do {
      try await backend.signOut()
      XCTFail("Expected secure cleanup failure")
    } catch let error as BackendError { XCTAssertEqual(error.status, -34018) }
    XCTAssertTrue(revoked)
    XCTAssertFalse(backend.hasSession)
  }

  func testServerErrorsHaveReadableIndonesianDescriptionsWithoutLosingCodes() {
    let stale = BackendError(status: 400, message: "stale_version")
    XCTAssertEqual(stale.message, "stale_version")
    XCTAssertEqual(
      stale.localizedDescription, "Data tugas sudah berubah. Muat ulang, lalu coba lagi.")
    XCTAssertEqual(
      BackendError(status: 400, message: "Invalid login credentials").localizedDescription,
      "Email atau kata sandi tidak sesuai.")
    XCTAssertEqual(
      BackendError(status: 400, message: "invite_expired").localizedDescription,
      "Undangan sudah kedaluwarsa. Minta kode baru dari koordinator.")
    XCTAssertEqual(
      BackendError(status: 500, message: "Unknown server message").localizedDescription,
      "Unknown server message")
  }

  @MainActor func testISO8601DatesAndConfigurationTrustBoundary() throws {
    struct Dates: Decodable {
      let first: Date
      let second: Date
    }
    let data = Data(
      "{\"first\":\"2026-10-16T01:02:03.123456+00:00\",\"second\":\"2026-10-16T01:02:03Z\"}".utf8)
    let dates = try SupabaseBackend.decoder().decode(Dates.self, from: data)
    XCTAssertEqual(dates.first.timeIntervalSince(dates.second), 0.123, accuracy: 0.002)
    XCTAssertFalse(
      BackendConfiguration(
        url: URL(string: "http://example.org")!, publishableKey: "sb_publishable_test"
      ).isValid)
    XCTAssertFalse(
      BackendConfiguration(
        url: URL(string: "https://example.org")!, publishableKey: "sb_secret_forbidden"
      ).isValid)
    let role = Data("{\"role\":\"service_role\"}".utf8).base64EncodedString()
    XCTAssertFalse(
      BackendConfiguration(
        url: URL(string: "https://example.org")!, publishableKey: "e30.\(role).sig"
      ).isValid)
    XCTAssertTrue(
      BackendConfiguration(
        url: URL(string: "http://127.0.0.1:54321")!, publishableKey: "sb_publishable_test"
      ).isValid)
    let nonce = try AppleSignInNonce()
    XCTAssertEqual(nonce.raw.count, 64)
    XCTAssertEqual(nonce.hashed.count, 64)
    XCTAssertNotEqual(nonce.raw, nonce.hashed)
  }

  @MainActor func testUnconfirmedSendKeepsPrivateFailedDraftAcrossSnapshots() async throws {
    let backend = client(store: MemoryTokenStore())
    let store = DemoStore(backendFactory: { _ in backend })
    store.setBackendActive(false)
    var offline = true
    BackendURLProtocol.handler = { request in
      switch request.url!.lastPathComponent {
      case "token":
        return (200, #"{"access_token":"token","refresh_token":"refresh","expires_in":3600,"user":{"id":"actor"}}"#)
      case "grouply_snapshot":
        return (200, ##"{"users":[],"groups":[{"id":"g1","name":"Grup","description":"","course":"","memberIDs":["actor","other"],"coordinatorID":"actor","tint":"#D8EAF4","icon":"person.3"}],"projects":[],"tasks":[],"messages":[],"invites":[],"reports":[],"currentUserID":"actor","blockedUserIDs":[],"readMessageIDs":[]}"##)
      default:
        if offline { throw URLError(.notConnectedToInternet) }
        return (200, #"{"id":"draft"}"#)
      }
    }
    try await store.connectBackend(email: "actor@example.org", password: "unused")
    let id = try await store.sendMessage(groupID: "g1", text: "Draft", clientID: "draft")
    XCTAssertEqual(id, "draft")
    XCTAssertEqual(store.messages(groupID: "g1").first { $0.id == id }?.delivery, .failed)
    XCTAssertNotNil(store.backendError)
    offline = false
    await store.refreshFromBackend()
    XCTAssertEqual(store.messages.filter { $0.id == id }.map(\.delivery), [.failed])
    store.currentUserID = "other"
    XCTAssertFalse(store.messages(groupID: "g1").contains { $0.id == id })
    XCTAssertEqual(store.unreadCount(groupID: "g1"), 0)
  }
}

private final class HeldUnauthorizedProtocol: URLProtocol {
  static var handler: ((HeldUnauthorizedProtocol) -> Void)?
  static var pending: HeldUnauthorizedProtocol?
  static var onHold: (() -> Void)?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    if let handler = Self.handler {
      handler(self)
      return
    }
    if request.url!.path.contains("/rpc/") {
      Self.pending = self
      Self.onHold?()
    } else if request.url!.path.hasSuffix("/logout") {
      respond(status: 204, body: "")
    } else {
      respond(
        status: 200,
        body:
          "{\"access_token\":\"token\",\"refresh_token\":\"refresh\",\"expires_in\":3600,\"user\":{\"id\":\"u1\"}}"
      )
    }
  }
  func respond(status: Int, body: String) {
    client?.urlProtocol(
      self,
      didReceive: HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
      cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
