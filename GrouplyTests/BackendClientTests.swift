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
}

private final class HeldUnauthorizedProtocol: URLProtocol {
  static var pending: HeldUnauthorizedProtocol?
  static var onHold: (() -> Void)?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
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
