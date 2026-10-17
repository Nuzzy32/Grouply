import CryptoKit
import Foundation
import Security

struct BackendConfiguration {
  let url: URL
  let publishableKey: String

  var isValid: Bool {
    let local = ["localhost", "127.0.0.1", "::1"].contains(url.host ?? "")
    guard url.host != nil, url.user == nil, url.password == nil,
      url.query == nil, url.fragment == nil,
      url.scheme == "https" || (url.scheme == "http" && local),
      !publishableKey.isEmpty, !publishableKey.contains("$("),
      !publishableKey.hasPrefix("sb_secret_")
    else { return false }
    if publishableKey.hasPrefix("sb_publishable_") { return true }
    let segments = publishableKey.split(separator: ".")
    guard segments.count == 3 else { return false }
    var payload = String(segments[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(
      of: "_", with: "/")
    payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
    guard let data = Data(base64Encoded: payload),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return false }
    return json["role"] as? String == "anon"
  }

  static var bundled: BackendConfiguration? {
    guard let rawURL = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
      let url = URL(string: rawURL),
      let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_PUBLISHABLE_KEY") as? String
    else { return nil }
    let configuration = BackendConfiguration(url: url, publishableKey: key)
    return configuration.isValid ? configuration : nil
  }
}

enum JSONValue: Codable {
  case string(String)
  case bool(Bool)
  case int(Int)
  case double(Double)
  case array([JSONValue])
  case object([String: JSONValue])
  case null
  static func date(_ date: Date) -> Self { .string(ISO8601DateFormatter().string(from: date)) }
  init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() {
      self = .null
    } else if let v = try? c.decode(Bool.self) {
      self = .bool(v)
    } else if let v = try? c.decode(Int.self) {
      self = .int(v)
    } else if let v = try? c.decode(Double.self) {
      self = .double(v)
    } else if let v = try? c.decode(String.self) {
      self = .string(v)
    } else if let v = try? c.decode([JSONValue].self) {
      self = .array(v)
    } else {
      self = .object(try c.decode([String: JSONValue].self))
    }
  }
  func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .string(let v): try c.encode(v)
    case .bool(let v): try c.encode(v)
    case .int(let v): try c.encode(v)
    case .double(let v): try c.encode(v)
    case .array(let v): try c.encode(v)
    case .object(let v): try c.encode(v)
    case .null: try c.encodeNil()
    }
  }
}

struct BackendSnapshot: Codable {
  var users: [GLUser]
  var groups: [GLGroup]
  var projects: [GLProject]
  var tasks: [GLTask]
  var messages: [GLMessage]
  var invites: [GLInvite]
  var reports: [GLReport]
  var currentUserID: String
  var blockedUserIDs: [String]
  var readMessageIDs: [String]
}
struct MutationResult: Decodable {
  var id: String?
  var invite: GLInvite?
}

struct BackendError: LocalizedError {
  let status: Int
  let message: String
  var errorDescription: String? {
    switch message.lowercased() {
    case "unauthorized", "jwt expired", "invalid refresh token: refresh token not found",
      "refresh_token_not_found", "refresh_token_already_used":
      return "Sesi berakhir. Silakan masuk kembali."
    case "invalid login credentials", "invalid_credentials":
      return "Email atau kata sandi tidak sesuai."
    case "email not confirmed", "email_not_confirmed":
      return "Konfirmasi email sebelum masuk."
    case "forbidden": return "Kamu tidak memiliki akses untuk tindakan ini."
    case "stale_version": return "Data tugas sudah berubah. Muat ulang, lalu coba lagi."
    case "project_read_only":
      return "Proyek selesai atau diarsipkan. Buka kembali sebelum mengubah tugas."
    case "already_reviewed":
      return "Tugas sedang direview atau sudah selesai dan belum dapat diubah."
    case "active_assignment":
      return "Anggota masih memiliki tugas aktif. Alihkan tugasnya terlebih dahulu."
    case "coordinator_transfer_required":
      return "Alihkan peran koordinator sebelum meninggalkan grup."
    case "group_full": return "Grup sudah mencapai batas delapan anggota."
    case "invite_expired": return "Undangan sudah kedaluwarsa. Minta kode baru dari koordinator."
    case "invite_full": return "Undangan sudah mencapai batas penggunaan. Minta kode baru."
    case "invalid_input": return "Data belum sesuai. Periksa isian dan coba lagi."
    case "rate_limited", "over_request_rate_limit", "too many requests":
      return "Terlalu banyak permintaan. Tunggu sebentar, lalu coba lagi."
    case "account_deletion_unavailable":
      return "Penghapusan akun server belum tersedia di aplikasi ini."
    default: return message
    }
  }
}

// Persist refresh credentials only in device-local Keychain, never UserDefaults.
protocol BackendTokenStore {
  func load() throws -> Data?
  func save(_ data: Data) throws
  func clear() throws
}
struct KeychainBackendTokenStore: BackendTokenStore {
  let account: String
  private var signedOutKey: String { "id.grouply.auth.signedOut." + account }
  private var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "id.grouply.auth", kSecAttrAccount as String: account,
    ]
  }
  func load() throws -> Data? {
    guard !UserDefaults.standard.bool(forKey: signedOutKey) else { return nil }
    var attributes = query
    attributes[kSecReturnData as String] = true
    attributes[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(attributes as CFDictionary, &result)
    // Without the Keychain entitlement (unsigned simulator build) nothing can have been saved.
    if status == errSecItemNotFound || status == errSecMissingEntitlement { return nil }
    guard status == errSecSuccess else { throw failure(status) }
    return result as? Data
  }
  func save(_ data: Data) throws {
    let changes = [kSecValueData as String: data]
    var status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
    if status == errSecItemNotFound {
      var attributes = query
      attributes[kSecValueData as String] = data
      attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      status = SecItemAdd(attributes as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw failure(status) }
    UserDefaults.standard.removeObject(forKey: signedOutKey)
  }
  func clear() throws {
    // A failed Keychain deletion must not restore a session the user signed out of.
    UserDefaults.standard.set(true, forKey: signedOutKey)
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
  }
  private func failure(_ status: OSStatus) -> BackendError {
    BackendError(status: Int(status), message: "Penyimpanan sesi aman tidak tersedia (\(status)).")
  }
}

struct AppleSignInNonce {
  let raw: String
  var hashed: String {
    SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
  }
  init() throws {
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      throw BackendError(status: 0, message: "Gagal membuat nonce Apple yang aman. Coba lagi.")
    }
    raw = bytes.map { String(format: "%02x", $0) }.joined()
  }
}

struct RealtimeFrame: Decodable {
  let event: String
  let ref: String?
  let payload: [String: JSONValue]
  var isOK: Bool {
    if case .string("ok") = payload["status"] { return true }
    return false
  }
  var isError: Bool {
    if case .string("error") = payload["status"] { return true }
    if case .string("timeout") = payload["status"] { return true }
    return false
  }
  var subscriptionReady: Bool {
    guard event == "system", isOK, case .string("postgres_changes") = payload["extension"] else { return false }
    return true
  }
}

@MainActor final class SupabaseBackend {
  private final class RealtimeState {
    var subscribed = false
    var heartbeatPending = false
  }
  private struct AuthSession: Codable {
    struct User: Codable { let id: String }
    let access_token: String
    let refresh_token: String
    var expires_at: TimeInterval?
    let expires_in: TimeInterval?
    let user: User
    var needsRefresh: Bool { (expires_at ?? 0) <= Date().timeIntervalSince1970 + 60 }
  }
  private let configuration: BackendConfiguration
  private let session: URLSession
  private let tokenStore: any BackendTokenStore
  private var auth: AuthSession?
  private var refreshTask: Task<Void, Error>?
  private var generation = 0
  var hasSession: Bool { auth != nil }

  func realtime(
    onConnection: @escaping @MainActor (Bool) -> Void,
    onChange: @escaping @MainActor () -> Void
  ) async {
    var retrySeconds = 1
    while !Task.isCancelled, hasSession {
      do {
        try await ensureFreshSession()
        guard configuration.isValid, let token = auth?.access_token, let userID = auth?.user.id else { return }
        let socket = session.webSocketTask(with: Self.realtimeURL(configuration))
        socket.resume()
        defer { socket.cancel(with: .goingAway, reason: nil) }
        try await withTaskCancellationHandler {
          try await sendRealtime(socket, event: "phx_join", payload: [
            "access_token": .string(token),
            "config": .object([
              "broadcast": .object(["ack": .bool(false), "self": .bool(false)]),
              "presence": .object(["enabled": .bool(false)]),
              "postgres_changes": .array(Self.realtimeSubscriptions(userID: userID))
            ])
          ], reference: "join")
          let state = RealtimeState()
          let heartbeat = Task { @MainActor in
            do {
              while !Task.isCancelled {
                try await Task.sleep(for: .seconds(20))
                guard state.subscribed, !state.heartbeatPending else {
                  socket.cancel(with: .goingAway, reason: nil)
                  return
                }
                try await self.ensureFreshSession()
                guard let freshToken = self.auth?.access_token else { return }
                try await self.sendRealtime(socket, event: "access_token", payload: ["access_token": .string(freshToken)])
                state.heartbeatPending = true
                try await self.sendRealtime(socket, event: "heartbeat", topic: "phoenix", reference: "heartbeat")
              }
            } catch {
              socket.cancel(with: .goingAway, reason: nil)
            }
          }
          defer { heartbeat.cancel() }
          while !Task.isCancelled {
            let message = try await socket.receive()
            let data: Data
            switch message {
            case .data(let value): data = value
            case .string(let value): data = Data(value.utf8)
            @unknown default: continue
            }
            let frame = try JSONDecoder().decode(RealtimeFrame.self, from: data)
            if frame.event == "phx_error" || frame.event == "phx_close" || frame.isError {
              throw BackendError(status: 0, message: "Koneksi realtime terputus.")
            }
            if frame.event == "phx_reply", frame.ref == "heartbeat" { state.heartbeatPending = false }
            if frame.subscriptionReady {
              state.subscribed = true
              retrySeconds = 1
              onConnection(true)
              onChange()
            } else if frame.event == "postgres_changes" { onChange() }
          }
        } onCancel: {
          socket.cancel(with: .goingAway, reason: nil)
        }
      } catch {}
      onConnection(false)
      if Task.isCancelled || !hasSession { return }
      do { try await Task.sleep(for: .seconds(retrySeconds)) } catch { return }
      retrySeconds = min(retrySeconds * 2, 30)
    }
    onConnection(false)
  }

  static func realtimeSubscriptions(userID: String) -> [JSONValue] {
    [("chat_messages", "INSERT"), ("chat_reads", "INSERT"), ("user_sync_state", "INSERT"), ("user_sync_state", "UPDATE")].map { table, event in
      var change: [String: JSONValue] = ["event": .string(event), "schema": .string("public"), "table": .string(table)]
      if table != "chat_messages" { change["filter"] = .string("user_id=eq.\(userID)") }
      return .object(change)
    }
  }

  static func realtimeURL(_ configuration: BackendConfiguration) -> URL {
    var components = URLComponents(url: configuration.url.appendingPathComponent("realtime/v1/websocket"), resolvingAgainstBaseURL: false)!
    components.scheme = components.scheme == "https" ? "wss" : "ws"
    components.queryItems = [URLQueryItem(name: "apikey", value: configuration.publishableKey), URLQueryItem(name: "vsn", value: "1.0.0")]
    return components.url!
  }

  private func sendRealtime(
    _ socket: URLSessionWebSocketTask, event: String, payload: [String: JSONValue] = [:],
    topic: String = "realtime:grouply", reference: String = UUID().uuidString
  ) async throws {
    let frame: [String: JSONValue] = ["topic": .string(topic), "event": .string(event), "payload": .object(payload), "ref": .string(reference)]
    let data = try Self.encoder().encode(frame)
    try await socket.send(.string(String(decoding: data, as: UTF8.self)))
  }

  init(
    configuration: BackendConfiguration, session: URLSession = .shared,
    tokenStore: (any BackendTokenStore)? = nil
  ) {
    self.configuration = configuration
    self.session = session
    self.tokenStore =
      tokenStore ?? KeychainBackendTokenStore(account: configuration.url.absoluteString)
  }

  static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let c = try decoder.singleValueContainer()
      let raw = try c.decode(String.self)
      let fractional = ISO8601DateFormatter()
      fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) {
        return date
      }
      throw DecodingError.dataCorruptedError(in: c, debugDescription: "Tanggal server tidak valid.")
    }
    return decoder
  }
  static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }

  func signIn(email: String, password: String) async throws {
    try await authenticate(
      grant: "password", body: ["email": .string(email), "password": .string(password)])
  }
  func signInWithApple(idToken: String, nonce: String) async throws {
    try await authenticate(
      grant: "id_token",
      body: ["provider": .string("apple"), "id_token": .string(idToken), "nonce": .string(nonce)])
  }
  func restoreSession() async throws -> Bool {
    guard let data = try tokenStore.load() else { return false }
    do { auth = try Self.decoder().decode(AuthSession.self, from: data) } catch {
      try clearSession()
      throw error
    }
    try await ensureFreshSession()
    return hasSession
  }
  func signOut() async throws {
    let accessToken = auth?.access_token
    var cleanupError: Error?
    do { try clearSession() } catch { cleanupError = error }
    if let accessToken {
      do {
        _ = try await request(
          path: "auth/v1/logout", query: [URLQueryItem(name: "scope", value: "local")],
          token: accessToken)
      } catch {
        if cleanupError == nil { throw error }
      }
    }
    if let cleanupError { throw cleanupError }
  }
  func snapshot() async throws -> BackendSnapshot {
    let data = try await authenticatedRequest(path: "rest/v1/rpc/grouply_snapshot", body: [:])
    return try Self.decoder().decode(BackendSnapshot.self, from: data)
  }
  func mutate(action: String, payload: [String: JSONValue]) async throws -> MutationResult {
    let data = try await authenticatedRequest(
      path: "rest/v1/rpc/grouply_mutate",
      body: ["action": .string(action), "payload": .object(payload)])
    return try Self.decoder().decode(MutationResult.self, from: data)
  }
  private func authenticate(grant: String, body: [String: JSONValue]) async throws {
    let startGeneration = generation
    let data = try await request(
      path: "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: grant)], body: body)
    var next = try Self.decoder().decode(AuthSession.self, from: data)
    next.expires_at = next.expires_at ?? Date().timeIntervalSince1970 + (next.expires_in ?? 0)
    guard startGeneration == generation else { throw CancellationError() }
    try tokenStore.save(Self.encoder().encode(next))
    auth = next
  }
  private func ensureFreshSession() async throws {
    if let refreshTask { return try await refreshTask.value }
    guard let auth else { throw BackendError(status: 401, message: "Silakan masuk kembali.") }
    guard auth.needsRefresh else { return }
    let refreshGeneration = generation
    let task = Task { @MainActor in
      do {
        try await self.authenticate(
          grant: "refresh_token", body: ["refresh_token": .string(auth.refresh_token)])
      } catch {
        if self.generation == refreshGeneration, let error = error as? BackendError,
          [400, 401, 403].contains(error.status)
        {
          try self.clearSession()
        }
        throw error
      }
    }
    refreshTask = task
    defer { refreshTask = nil }
    try await task.value
  }
  private func authenticatedRequest(path: String, body: [String: JSONValue]) async throws -> Data {
    try await ensureFreshSession()
    let requestGeneration = generation
    guard let token = auth?.access_token else {
      throw BackendError(status: 401, message: "Silakan masuk kembali.")
    }
    do { return try await request(path: path, body: body, token: token) } catch {
      if generation == requestGeneration, let error = error as? BackendError, error.status == 401 {
        try clearSession()
      }
      throw error
    }
  }
  private func clearSession() throws {
    generation += 1
    refreshTask?.cancel()
    auth = nil
    try tokenStore.clear()
  }
  private func request(
    path: String, query: [URLQueryItem] = [], body: [String: JSONValue]? = nil, token: String? = nil
  ) async throws -> Data {
    guard configuration.isValid else {
      throw BackendError(
        status: 0,
        message: "Konfigurasi Supabase tidak valid; gunakan URL aman dan publishable key.")
    }
    var components = URLComponents(
      url: configuration.url.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
    if !query.isEmpty { components.queryItems = query }
    var request = URLRequest(url: components.url!)
    request.httpMethod = "POST"
    request.timeoutInterval = 30
    request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    if let body { request.httpBody = try Self.encoder().encode(body) }
    let (data, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse else {
      throw BackendError(status: 0, message: "Respons server tidak valid.")
    }
    guard (200..<300).contains(response.statusCode) else {
      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
      let message =
        json?["message"] as? String ?? json?["msg"] as? String ?? json?["error_description"]
        as? String ?? json?["error"] as? String
      throw BackendError(
        status: response.statusCode,
        message: message ?? "Permintaan server gagal (\(response.statusCode)).")
    }
    return data
  }
}
