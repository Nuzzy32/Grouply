import Foundation
import Observation

@MainActor @Observable final class DemoStore {
  var users: [GLUser] = []
  var groups: [GLGroup] = []
  var projects: [GLProject] = []
  var tasks: [GLTask] = []
  var messages: [GLMessage] = []
  var invites: [GLInvite] = []
  var reports: [GLReport] = []
  var currentUserID: String?
  private var blocks: [String: [String]] = [:]
  var readMessageIDs: [String: Set<String>] = [:]
  var isBusy = false
  var isRestoringSession = false
  var backendError: String?
  /// Transient toast shown at the top of the app (prototype `flash`).
  var toast: (text: String, kind: GLToastKind)?
  @ObservationIgnored private var toastTask: Task<Void, Never>?
  @ObservationIgnored private var backend: SupabaseBackend?
  @ObservationIgnored private var realtimeTask: Task<Void, Never>?
  @ObservationIgnored private var realtimeRefreshTask: Task<Void, Never>?
  @ObservationIgnored private var realtimeRefreshPending = false
  @ObservationIgnored private var backendIsActive = true
  @ObservationIgnored private var realtimeGeneration = 0
  var realtimeConnected = false
  @ObservationIgnored private let backendFactory: (BackendConfiguration) -> SupabaseBackend
  var isCloudMode: Bool { backend != nil }
  var backendConfigured: Bool { BackendConfiguration.bundled != nil }
  var now: Date { Date() }
  var blockedUserIDs: [String] { blocks[currentUserID ?? ""] ?? [] }
  var currentUser: GLUser? { currentUserID.flatMap(user) }
  var myGroups: [GLGroup] { groups.filter { $0.memberIDs.contains(currentUserID ?? "") } }
  var memberTasks: [GLTask] {
    tasks.filter {
      $0.assigneeID == currentUserID
        && project($0.projectID).map { isMember(groupID: $0.groupID) } == true
    }
  }
  init(backendFactory: ((BackendConfiguration) -> SupabaseBackend)? = nil) {
    self.backendFactory = backendFactory ?? { SupabaseBackend(configuration: $0) }
  }
  func user(_ id: String) -> GLUser? { users.first { $0.id == id } }
  func group(_ id: String) -> GLGroup? { groups.first { $0.id == id } }
  func project(_ id: String) -> GLProject? { projects.first { $0.id == id } }
  func task(_ id: String) -> GLTask? { tasks.first { $0.id == id } }
  func isCoordinator(groupID: String) -> Bool {
    group(groupID)?.coordinatorID == currentUserID && isMember(groupID: groupID)
  }
  func isMember(groupID: String) -> Bool {
    group(groupID)?.memberIDs.contains(currentUserID ?? "") == true
  }
  func tasks(in projectID: String) -> [GLTask] { tasks.filter { $0.projectID == projectID } }
  func projects(in groupID: String) -> [GLProject] { projects.filter { $0.groupID == groupID } }
  func messages(groupID: String, taskID: String? = nil) -> [GLMessage] {
    messages.filter {
      $0.groupID == groupID && $0.taskID == taskID
        && ($0.delivery == .sent || $0.senderID == currentUserID)
    }.sorted {
      $0.createdAt < $1.createdAt
    }
  }
  func unreadCount(groupID: String) -> Int {
    guard let actor = currentUserID, isMember(groupID: groupID) else { return 0 }
    let seen = readMessageIDs[actor + ":" + groupID] ?? []
    return messages.filter {
      $0.groupID == groupID && $0.taskID == nil && $0.senderID != actor
        && $0.delivery == .sent && !seen.contains($0.id)
    }.count
  }
  func markChatRead(groupID: String) {
    guard let actor = currentUserID, isMember(groupID: groupID) else { return }
    let sentIDs = messages.filter {
      $0.groupID == groupID && $0.taskID == nil && $0.delivery == .sent
        && !(readMessageIDs[actor + ":" + groupID] ?? []).contains($0.id)
    }.map(\.id)
    guard !sentIDs.isEmpty, isCloudMode else { return }
    Task { await self.markReadOnBackend(groupID: groupID, messageIDs: sentIDs) }
  }
  func markRead(groupID: String) { markChatRead(groupID: groupID) }
  func progress(projectID: String) -> Double {
    let values = tasks(in: projectID)
    return values.isEmpty
      ? 0 : Double(values.filter { $0.status == .done }.count) / Double(values.count)
  }
}

extension DemoStore {
  func setBackendActive(_ active: Bool) {
    backendIsActive = active
    stopRealtime()
    if active { startRealtime() }
  }

  private func startRealtime() {
    guard backendIsActive, realtimeTask == nil, let client = backend else { return }
    let generation = realtimeGeneration
    realtimeTask = Task { [weak self] in
      await client.realtime(onConnection: { [weak self] connected in
        guard let self, self.backend === client, self.realtimeGeneration == generation else { return }
        self.realtimeConnected = connected
        if !client.hasSession { self.clearExpiredBackend() }
      }, onChange: { [weak self] in
        guard let self, self.backend === client, self.realtimeGeneration == generation else { return }
        self.queueRealtimeRefresh()
      })
    }
  }

  private func stopRealtime() {
    realtimeGeneration += 1
    realtimeTask?.cancel()
    realtimeTask = nil
    realtimeRefreshTask?.cancel()
    realtimeRefreshTask = nil
    realtimeRefreshPending = false
    realtimeConnected = false
  }

  func queueRealtimeRefresh() {
    guard let client = backend else { return }
    realtimeRefreshPending = true
    guard realtimeRefreshTask == nil else { return }
    let generation = realtimeGeneration
    realtimeRefreshTask = Task { [weak self] in
      guard let self else { return }
      defer { if self.realtimeGeneration == generation { self.realtimeRefreshTask = nil } }
      var retrySeconds = 1
      while self.realtimeRefreshPending, !Task.isCancelled, self.realtimeGeneration == generation, self.backend === client {
        do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
        if self.isBusy { continue }
        self.realtimeRefreshPending = false
        if await self.refreshFromBackend() {
          retrySeconds = 1
        } else if !Task.isCancelled, self.realtimeGeneration == generation, self.backend === client {
          self.realtimeRefreshPending = true
          do { try await Task.sleep(for: .seconds(retrySeconds)) } catch { return }
          retrySeconds = min(retrySeconds * 2, 30)
        }
      }
    }
  }

  func connectBackend(email: String, password: String) async throws {
    guard !isBusy else { throw DemoError(message: "Tunggu proses sebelumnya selesai.") }
    guard let config = BackendConfiguration.bundled else { throw DemoError(message: "Konfigurasi Supabase belum tersedia. Ikuti docs/BACKEND_SETUP.md.") }
    isBusy = true
    defer { isBusy = false }
    let client = backendFactory(config)
    try await client.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
    let snapshot = try await client.snapshot()
    backend = client
    applyBackend(snapshot)
    startRealtime()
  }

  func connectApple(idToken: String, nonce: String, fullName: String?) async throws {
    guard !isBusy else { throw DemoError(message: "Tunggu proses sebelumnya selesai.") }
    guard let config = BackendConfiguration.bundled else { throw DemoError(message: "Konfigurasi Supabase belum tersedia.") }
    isBusy = true
    defer { isBusy = false }
    let client = backendFactory(config)
    try await client.signInWithApple(idToken: idToken, nonce: nonce)
    if let fullName, !fullName.isEmpty {
      _ = try await client.mutate(action: "updateProfile", payload: ["name": .string(fullName)])
    }
    let snapshot = try await client.snapshot()
    backend = client
    applyBackend(snapshot)
    startRealtime()
  }

  func restoreBackendSession() async {
    guard !isBusy, !isCloudMode, !ProcessInfo.processInfo.arguments.contains("--uitesting"),
      let config = BackendConfiguration.bundled else { return }
    isRestoringSession = true
    isBusy = true
    defer { isRestoringSession = false; isBusy = false }
    do {
      let client = backendFactory(config)
      if try await client.restoreSession() {
        let snapshot = try await client.snapshot()
        backend = client
        applyBackend(snapshot)
        startRealtime()
      }
    } catch { backendError = "Sesi server belum dapat dipulihkan: \(error.localizedDescription)" }
  }

  func signOut() async throws {
    guard !isBusy else { throw DemoError(message: "Tunggu proses sebelumnya selesai.") }
    guard let client = backend else { clearExpiredBackend(); return }
    clearExpiredBackend()
    backendError = nil
    try await client.signOut()
  }

  @discardableResult func refreshFromBackend() async -> Bool {
    guard let client = backend, !isBusy else { return false }
    isBusy = true
    defer { isBusy = false }
    do {
      let snapshot = try await client.snapshot()
      guard backend === client, !Task.isCancelled else { return false }
      guard client.hasSession else { clearExpiredBackend(); return false }
      applyBackend(snapshot)
      return true
    }
    catch {
      guard backend === client, !Task.isCancelled else { return false }
      backendError = "Gagal memuat data server: \(error.localizedDescription)"
      if !client.hasSession { clearExpiredBackend() }
      return false
    }
  }

  func mutateBackend(_ action: String, _ payload: [String: JSONValue]) async throws -> MutationResult {
    guard let client = backend else { throw DemoError(message: "Masuk ke akun terlebih dahulu.") }
    guard !isBusy else { throw DemoError(message: "Tunggu proses sebelumnya selesai.") }
    isBusy = true
    defer { isBusy = false }
    do {
      let result = try await client.mutate(action: action, payload: payload)
      guard backend === client, client.hasSession, !Task.isCancelled else { throw CancellationError() }
      do {
        let snapshot = try await client.snapshot()
        guard backend === client, client.hasSession, !Task.isCancelled else { throw CancellationError() }
        applyBackend(snapshot)
      }
      catch {
        guard backend === client, !Task.isCancelled else { throw CancellationError() }
        backendError = "Perubahan tersimpan di server, tetapi tampilan belum diperbarui. Tarik untuk memuat ulang. \(error.localizedDescription)"
        if !client.hasSession { clearExpiredBackend() }
      }
      return result
    } catch {
      if backend === client, !client.hasSession { clearExpiredBackend() }
      throw error
    }
  }

  func markReadOnBackend(groupID: String, messageIDs: [String]) async {
    guard let client = backend else { return }
    do {
      _ = try await client.mutate(action: "markChatRead", payload: ["groupID": .string(groupID), "messageIDs": .array(messageIDs.map(JSONValue.string))])
      guard backend === client, let actor = currentUserID else { return }
      readMessageIDs[actor + ":" + groupID, default: []].formUnion(messageIDs)
    }
    catch {
      if backend === client { backendError = "Penanda baca belum tersimpan di server: \(error.localizedDescription)" }
    }
  }

  func deleteBackendAccount() async throws {
    guard let client = backend else { throw DemoError(message: "Masuk ke akun terlebih dahulu.") }
    guard !isBusy else { throw DemoError(message: "Tunggu proses sebelumnya selesai.") }
    isBusy = true
    stopRealtime()
    defer { isBusy = false }
    do {
      try await client.deleteAccount()
      guard backend === client else { return }
      clearExpiredBackend()
      backendError = nil
    } catch {
      guard backend === client else { throw error }
      if !client.hasSession {
        clearExpiredBackend()
        backendError = "Sesi lokal dihentikan: \(error.localizedDescription)"
      } else {
        startRealtime()
      }
      throw error
    }
  }

  @discardableResult func sendMessage(groupID: String, taskID: String? = nil, text: String, clientID: String = UUID().uuidString) async throws -> String {
    do {
      let result = try await mutateBackend("sendMessage", ["groupID": .string(groupID), "taskID": taskID.map(JSONValue.string) ?? .null, "text": .string(text), "clientID": .string(clientID)])
      return result.id ?? clientID
    } catch let error as URLError {
      if let actor = currentUserID {
        messages.removeAll { $0.id == clientID }
        messages.append(GLMessage(id: clientID, groupID: groupID, taskID: taskID, senderID: actor, text: text, createdAt: Date(), delivery: .failed))
      }
      backendError = "Pesan belum terkonfirmasi server: \(error.localizedDescription)"
      return clientID
    }
  }

  func retryMessage(_ id: String) async throws {
    guard let old = messages.first(where: { $0.id == id && $0.senderID == currentUserID && $0.delivery == .failed }) else { return }
    _ = try await sendMessage(groupID: old.groupID, taskID: old.taskID, text: old.text, clientID: old.id)
  }

  private func applyBackend(_ snapshot: BackendSnapshot) {
    let drafts = messages.filter { $0.senderID == snapshot.currentUserID && $0.delivery == .failed }
    let visibleCodes = Dictionary(uniqueKeysWithValues: invites.filter { !$0.code.isEmpty }.map { ($0.id, $0.code) })
    users = snapshot.users
    groups = snapshot.groups
    projects = snapshot.projects
    tasks = snapshot.tasks
    messages = snapshot.messages
    messages += drafts.filter { draft in !messages.contains { $0.id == draft.id } && snapshot.groups.contains { $0.id == draft.groupID } }
    invites = snapshot.invites.map { row in
      var invite = row
      if snapshot.groups.contains(where: { $0.id == row.groupID && $0.coordinatorID == snapshot.currentUserID }) {
        invite.code = visibleCodes[row.id] ?? row.code
      }
      return invite
    }
    reports = snapshot.reports
    currentUserID = snapshot.currentUserID
    blocks = [snapshot.currentUserID: snapshot.blockedUserIDs]
    readMessageIDs = Dictionary(uniqueKeysWithValues: snapshot.groups.map { (snapshot.currentUserID + ":" + $0.id, Set(snapshot.readMessageIDs)) })
    backendError = nil
  }

  private func clearExpiredBackend() {
    stopRealtime()
    backend = nil
    users = []; groups = []; projects = []; tasks = []; messages = []; invites = []; reports = []
    currentUserID = nil
    blocks = [:]; readMessageIDs = [:]
  }
}

extension DemoStore {
  /// "Kamu" for the signed-in user, like the prototype's `nm()`.
  func displayName(_ id: String) -> String {
    if id.isEmpty { return "Pengguna terhapus" }
    return id == currentUserID ? "Kamu" : user(id)?.name ?? "Anggota"
  }
  /// Task-thread events (submit/review/assign…) for a project's tasks, newest first.
  /// Demo stores them as kind "system", the server as kind "activity"; both carry the task ID.
  func projectActivity(_ projectID: String) -> [GLMessage] {
    let ids = Set(tasks(in: projectID).map(\.id))
    return messages.filter { $0.kind != "text" && $0.taskID.map(ids.contains) == true }
      .sorted { $0.createdAt > $1.createdAt }
  }
  /// Hours since the active submission was sent, while a task waits in review.
  func reviewWaitHours(_ task: GLTask) -> Int? {
    guard task.status == .inReview, let sent = task.submissions.last?.createdAt else { return nil }
    return Int(now.timeIntervalSince(sent) / 3600)
  }
}

extension DemoStore {
  func flash(_ text: String, _ kind: GLToastKind = .ok) {
    toast = (text, kind)
    toastTask?.cancel()
    toastTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(2.6))
      guard !Task.isCancelled else { return }
      self?.toast = nil
    }
  }
}
