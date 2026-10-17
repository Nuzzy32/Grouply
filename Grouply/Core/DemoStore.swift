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
  var simulatedOffline = false
  var simulateSendFailure = false
  var advanceDemoTime = false { didSet { save() } }
  var persistenceError: String?
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
  private var storageWritable = true
  private let persist: Bool
  private let storageURL: URL
  var now: Date { Date().addingTimeInterval(advanceDemoTime ? 8 * 86400 : 0) }
  var blockedUserIDs: [String] { blocks[currentUserID ?? ""] ?? [] }
  var currentUser: GLUser? { currentUserID.flatMap(user) }
  var myGroups: [GLGroup] { groups.filter { $0.memberIDs.contains(currentUserID ?? "") } }
  var memberTasks: [GLTask] {
    tasks.filter {
      $0.assigneeID == currentUserID
        && project($0.projectID).map { isMember(groupID: $0.groupID) } == true
    }
  }
  init(persist: Bool = true, storageURL: URL? = nil, backendFactory: ((BackendConfiguration) -> SupabaseBackend)? = nil) {
    self.backendFactory = backendFactory ?? { SupabaseBackend(configuration: $0) }
    self.persist = persist
    self.storageURL =
      storageURL
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Grouply/demo-v1.json")
    if persist, FileManager.default.fileExists(atPath: self.storageURL.path) {
      do {
        apply(try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: self.storageURL)))
        return
      } catch {
        let backup = self.storageURL.deletingPathExtension().appendingPathExtension(
          "unreadable-\(UUID().uuidString).json")
        do {
          try FileManager.default.moveItem(at: self.storageURL, to: backup)
          persistenceError =
            "Data demo tidak terbaca. Salinan disimpan di \(backup.lastPathComponent)."
        } catch {
          storageWritable = false
          persistenceError =
            "Data demo tidak terbaca; penyimpanan dihentikan agar salinan lama tetap aman."
        }
      }
    }
    loadSeed()
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
    guard !sentIDs.isEmpty else { return }
    if isCloudMode {
      Task { await self.markReadOnBackend(groupID: groupID, messageIDs: sentIDs) }
      return
    }
    readMessageIDs[actor + ":" + groupID, default: []].formUnion(sentIDs)
    save()
  }
  func markRead(groupID: String) { markChatRead(groupID: groupID) }
  func progress(projectID: String) -> Double {
    let values = tasks(in: projectID)
    return values.isEmpty
      ? 0 : Double(values.filter { $0.status == .done }.count) / Double(values.count)
  }
  func signIn(as id: String) {
    guard !isCloudMode, !isBusy else { return }
    guard let selected = user(id), !selected.email.isEmpty else { return }
    currentUserID = id
    save()
  }
  func switchPersona(_ id: String) { signIn(as: id) }
  func localSignOut() {
    currentUserID = nil
    save()
  }
  func reset() {
    guard !isCloudMode, !isBusy else { return }
    blocks = [:]
    readMessageIDs = [:]
    loadSeed()
    advanceDemoTime = false
    simulatedOffline = false
    simulateSendFailure = false
    reports = []
    save()
  }
  private func fail(_ text: String) throws -> Never { throw DemoError(message: text) }
  private func me() throws -> String {
    guard !simulatedOffline else {
      try fail("Mode offline demo aktif. Nonaktifkan untuk menyimpan perubahan.")
    }
    guard let id = currentUserID, user(id) != nil else {
      try fail("Masuk ke sesi demo terlebih dahulu.")
    }
    return id
  }
  private func member(_ id: String) throws -> GLGroup {
    _ = try me()
    guard let g = group(id), isMember(groupID: id) else { try fail("Kamu bukan anggota grup ini.") }
    return g
  }
  private func coordinator(_ id: String) throws -> GLGroup {
    let g = try member(id)
    guard isCoordinator(groupID: id) else { try fail("Aksi ini khusus koordinator.") }
    return g
  }
  private func active(_ id: String) throws -> GLProject {
    guard let p = project(id) else { try fail("Proyek tidak ditemukan.") }
    _ = try member(p.groupID)
    guard p.status == .active else {
      try fail("Proyek selesai atau diarsipkan hanya dapat dibaca.")
    }
    return p
  }
  private func checkedTask(_ id: String, version: Int? = nil) throws -> GLTask {
    guard let t = task(id) else { try fail("Tugas tidak ditemukan.") }
    _ = try active(t.projectID)
    if let version, t.version != version {
      try fail("Tugas telah berubah. Tutup editor dan coba lagi.")
    }
    return t
  }
  private func editable(_ t: GLTask) throws {
    guard t.status != .inReview && t.status != .done else {
      try fail("Tugas terkunci selama review atau setelah selesai.")
    }
  }
  private func text(_ value: String, max: Int, required: Bool = true) throws -> String {
    let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !required || !value.isEmpty, value.count <= max else {
      try fail("Isi wajib diisi dan maksimal \(max) karakter.")
    }
    return value
  }
  private func validDate(_ date: Date) throws {
    guard date.timeIntervalSinceReferenceDate.isFinite else { try fail("Tanggal tidak valid.") }
  }
  private func assignment(_ g: GLGroup, _ assignee: String, _ reviewer: String) throws {
    guard assignee != reviewer, g.memberIDs.contains(assignee), g.memberIDs.contains(reviewer)
    else { try fail("Pelaksana dan reviewer harus anggota grup yang berbeda.") }
  }
  private func put(_ t: GLTask) {
    if let i = tasks.firstIndex(where: { $0.id == t.id }) {
      var t = t
      t.version += 1
      tasks[i] = t
    }
    save()
  }
  /// `verb` is the group-chat activity line after the actor's name ("mengirim hasil"),
  /// `system` the task-thread line ("mengirim revisi 1"). Mirrors the prototype's A()/S().
  private func activity(_ t: GLTask, _ verb: String?, system: String) {
    guard let p = project(t.projectID) else { return }
    if let verb {
      messages.append(
        GLMessage(
          groupID: p.groupID, taskID: nil, senderID: currentUserID ?? "",
          text: verb, createdAt: now, kind: "activity", targetTaskID: t.id))
    }
    messages.append(
      GLMessage(
        groupID: p.groupID, taskID: t.id, senderID: currentUserID ?? "", text: system,
        createdAt: now, kind: "system", targetTaskID: t.id))
    save()
  }
  @discardableResult func localCreateGroup(name: String, description: String, course: String) throws
    -> String
  {
    let id = UUID().uuidString
    let actor = try me()
    let name = try text(name, max: 80)
    let description = try text(description, max: 1000, required: false)
    let course = try text(course, max: 120, required: false)
    let tints = ["#D8EAF4", "#F9E9BE", "#F6CED1", "#C9F2D6", "#DED2FF"]
    groups.append(
      GLGroup(
        id: id, name: name, description: description,
        course: course.isEmpty ? "Mata kuliah belum diisi" : course, memberIDs: [actor],
        coordinatorID: actor, tint: tints[groups.count % tints.count], icon: "person.3"))
    save()
    return id
  }
  func localUpdateGroup(id: String, name: String, description: String, course: String) throws {
    _ = try coordinator(id)
    let name = try text(name, max: 80)
    let description = try text(description, max: 1000, required: false)
    let course = try text(course, max: 120, required: false)
    let i = groups.firstIndex { $0.id == id }!
    groups[i].name = name
    groups[i].description = description
    groups[i].course = course
    save()
  }
  @discardableResult func localCreateProject(
    groupID: String, title: String, description: String, dueAt: Date
  ) throws -> String {
    try validDate(dueAt)
    _ = try coordinator(groupID)
    let title = try text(title, max: 120)
    let description = try text(description, max: 2000, required: false)
    let id = UUID().uuidString
    projects.append(
      GLProject(
        id: id, groupID: groupID, title: title, description: description, dueAt: dueAt,
        status: .active))
    save()
    return id
  }
  func localUpdateProject(id: String, title: String, description: String, dueAt: Date) throws {
    try validDate(dueAt)
    let p = try active(id)
    _ = try coordinator(p.groupID)
    let title = try text(title, max: 120)
    let description = try text(description, max: 2000, required: false)
    let i = projects.firstIndex { $0.id == id }!
    projects[i].title = title
    projects[i].description = description
    projects[i].dueAt = dueAt
    save()
  }
  private func setProject(_ id: String, _ status: ProjectStatus) throws {
    guard let i = projects.firstIndex(where: { $0.id == id }) else {
      try fail("Proyek tidak ditemukan.")
    }
    _ = try coordinator(projects[i].groupID)
    let old = projects[i].status
    switch status {
    case .completed:
      guard old == .active, !tasks(in: id).isEmpty, tasks(in: id).allSatisfy({ $0.status == .done })
      else { try fail("Semua tugas harus selesai sebelum proyek diselesaikan.") }
    case .archived:
      guard old != .archived else { try fail("Proyek sudah diarsipkan.") }
      projects[i].previousStatus = old
    case .active: guard old == .completed else { try fail("Proyek tidak dapat dibuka kembali.") }
    }
    projects[i].status = status
    save()
  }
  func localCompleteProject(_ id: String) throws { try setProject(id, .completed) }
  func localReopenProject(_ id: String) throws { try setProject(id, .active) }
  func localArchiveProject(_ id: String) throws { try setProject(id, .archived) }
  func localRestoreProject(_ id: String) throws {
    guard let i = projects.firstIndex(where: { $0.id == id }) else {
      try fail("Proyek tidak ditemukan.")
    }
    _ = try coordinator(projects[i].groupID)
    guard projects[i].status == .archived else { try fail("Proyek belum diarsipkan.") }
    projects[i].status = projects[i].previousStatus ?? .active
    projects[i].previousStatus = nil
    save()
  }
  @discardableResult func localCreateTask(
    projectID: String, title: String, description: String, assigneeID: String, reviewerID: String,
    dueAt: Date
  ) throws -> String {
    try validDate(dueAt)
    let p = try active(projectID)
    let g = try coordinator(p.groupID)
    try assignment(g, assigneeID, reviewerID)
    let title = try text(title, max: 120)
    let description = try text(description, max: 2000, required: false)
    let id = UUID().uuidString
    let t = GLTask(
      id: id, projectID: projectID, title: title, description: description, assigneeID: assigneeID,
      reviewerID: reviewerID, dueAt: dueAt, status: .todo)
    tasks.append(t)
    activity(
      t, "membuat tugas untuk \(user(assigneeID)?.name ?? "anggota")", system: "membuat tugas ini")
    return id
  }
  func localUpdateTask(
    id: String, title: String, description: String, reviewerID: String, dueAt: Date,
    expectedVersion: Int
  ) throws {
    try validDate(dueAt)
    var t = try checkedTask(id, version: expectedVersion)
    let p = project(t.projectID)!
    _ = try coordinator(p.groupID)
    try editable(t)
    try assignment(group(p.groupID)!, t.assigneeID, reviewerID)
    let title = try text(title, max: 120)
    let description = try text(description, max: 2000, required: false)
    t.title = title
    t.description = description
    t.reviewerID = reviewerID
    t.dueAt = dueAt
    put(t)
    activity(t, "mengubah detail tugas", system: "mengubah detail tugas")
  }
  func localReassignTask(id: String, assigneeID: String, reviewerID: String, expectedVersion: Int) throws
  {
    var t = try checkedTask(id, version: expectedVersion)
    let g = try coordinator(project(t.projectID)!.groupID)
    try editable(t)
    try assignment(g, assigneeID, reviewerID)
    t.assigneeID = assigneeID
    t.reviewerID = reviewerID
    if t.status != .needsRevision { t.status = .todo }
    put(t)
    let to = user(assigneeID)?.name ?? "anggota"
    activity(t, "mengalihkan tugas ke \(to)", system: "mengalihkan tugas ke \(to)")
  }
  func localStartTask(_ id: String) throws {
    var t = try checkedTask(id)
    guard t.assigneeID == currentUserID, [.todo, .needsRevision].contains(t.status) else {
      try fail("Hanya pelaksana yang dapat memulai tugas baru.")
    }
    t.status = .inProgress
    put(t)
    activity(t, nil, system: "mulai mengerjakan")
  }
  func localReopenTask(_ id: String) throws {
    var t = try checkedTask(id)
    _ = try coordinator(project(t.projectID)!.groupID)
    guard t.status == .done else { try fail("Hanya tugas selesai yang dapat dibuka kembali.") }
    t.status = .inProgress
    put(t)
    activity(t, nil, system: "membuka kembali tugas")
  }
  func localSubmitWork(taskID: String, note: String, links: [String], expectedVersion: Int) throws {
    var t = try checkedTask(taskID, version: expectedVersion)
    guard t.assigneeID == currentUserID, [.inProgress, .needsRevision].contains(t.status) else {
      try fail("Hanya pelaksana dapat mengirim hasil tugas yang sedang dikerjakan.")
    }
    let note = try text(note, max: 5000)
    let links = links.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter {
      !$0.isEmpty
    }
    guard links.count <= 5,
      links.allSatisfy({ value in
        guard value.count <= 2048, let url = URLComponents(string: value) else { return false }
        return url.scheme?.lowercased() == "https" && !(url.host ?? "").isEmpty && url.user == nil
          && url.password == nil
      })
    else { try fail("Gunakan maksimal 5 tautan HTTPS yang valid.") }
    t.submissions.append(
      GLSubmission(
        revision: t.submissions.count + 1, authorID: try me(), note: note, links: links,
        createdAt: now))
    t.status = .inReview
    put(t)
    activity(t, "mengirim hasil", system: "mengirim revisi \(t.submissions.count)")
  }
  func localReview(taskID: String, approve: Bool, feedback: String, expectedVersion: Int) throws {
    var t = try checkedTask(taskID, version: expectedVersion)
    guard t.status == .inReview, t.reviewerID == currentUserID, let last = t.submissions.last,
      last.authorID != currentUserID, last.decision == nil
    else { try fail("Review hanya dapat dilakukan reviewer yang bukan penulis hasil terakhir.") }
    let feedback = try text(feedback, max: 3000, required: !approve)
    let i = t.submissions.count - 1
    t.submissions[i].decision = approve ? "approved" : "changes_requested"
    t.submissions[i].feedback = feedback
    t.submissions[i].reviewerID = try me()
    t.status = approve ? .done : .needsRevision
    put(t)
    activity(
      t, approve ? "menyetujui" : "meminta revisi",
      system: approve ? "menyetujui revisi \(t.submissions.count)" : "meminta revisi")
  }
  @discardableResult func localSendMessage(
    groupID: String, taskID: String? = nil, text: String, clientID: String = UUID().uuidString
  ) throws -> String {
    guard let actor = currentUserID, user(actor) != nil, isMember(groupID: groupID) else {
      try fail("Kamu bukan anggota grup ini.")
    }
    if let old = messages.first(where: { $0.id == clientID }) {
      guard old.senderID == actor, old.groupID == groupID, old.taskID == taskID else {
        try fail("Identitas pesan tidak valid.")
      }
      return old.id
    }
    if let taskID {
      guard let t = task(taskID), project(t.projectID)?.groupID == groupID else {
        try fail("Diskusi tugas tidak ditemukan.")
      }
      guard project(t.projectID)?.status == .active else { try fail("Proyek tidak aktif.") }
    }
    let body = try self.text(text, max: 2000)
    messages.append(
      GLMessage(
        id: clientID, groupID: groupID, taskID: taskID, senderID: actor, text: body, createdAt: now,
        delivery: simulatedOffline || simulateSendFailure ? .failed : .sent))
    save()
    return clientID
  }
  func localRetryMessage(_ id: String) throws {
    guard let i = messages.firstIndex(where: { $0.id == id }), messages[i].senderID == currentUserID
    else { try fail("Pesan tidak ditemukan.") }
    guard isMember(groupID: messages[i].groupID) else { try fail("Kamu bukan anggota grup ini.") }
    if let tid = messages[i].taskID {
      guard let t = task(tid) else { try fail("Tugas tidak ditemukan.") }
      guard project(t.projectID)?.status == .active else { try fail("Proyek tidak aktif.") }
    }
    guard messages[i].delivery == .failed else { return }
    messages[i].delivery = simulatedOffline || simulateSendFailure ? .failed : .sent
    save()
  }
  @discardableResult func localGenerateInvite(groupID: String) throws -> GLInvite {
    _ = try coordinator(groupID)
    let invite = GLInvite(
      groupID: groupID, code: String(UUID().uuidString.prefix(8)).uppercased(), createdAt: now,
      expiresAt: now.addingTimeInterval(7 * 86400))
    invites.append(invite)
    save()
    return invite
  }
  func localRevokeInvite(_ id: String) throws {
    guard let i = invites.firstIndex(where: { $0.id == id }) else {
      try fail("Undangan tidak ditemukan.")
    }
    _ = try coordinator(invites[i].groupID)
    invites[i].revoked = true
    save()
  }
  @discardableResult func localJoinGroup(code: String) throws -> String {
    let actor = try me()
    let code = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    guard let i = invites.firstIndex(where: { $0.code.uppercased() == code }), !invites[i].revoked,
      invites[i].expiresAt > now, invites[i].useCount < invites[i].maxUses,
      let gi = groups.firstIndex(where: { $0.id == invites[i].groupID })
    else { try fail("Undangan tidak valid, kedaluwarsa, dicabut, atau sudah digunakan.") }
    guard !groups[gi].memberIDs.contains(actor) else {
      try fail("Kamu sudah menjadi anggota grup ini.")
    }
    guard groups[gi].memberIDs.count < 8 else { try fail("Grup sudah mencapai batas 8 anggota.") }
    groups[gi].memberIDs.append(actor)
    invites[i].useCount += 1
    save()
    return groups[gi].id
  }
  func localTransferCoordinator(groupID: String, to id: String) throws {
    let g = try coordinator(groupID)
    guard g.memberIDs.contains(id), id != currentUserID else {
      try fail("Pilih anggota lain sebagai koordinator.")
    }
    groups[groups.firstIndex { $0.id == groupID }!].coordinatorID = id
    save()
  }
  private func ensureNoActiveAssignments(groupID: String, userID: String) throws {
    let pids = projects(in: groupID).map(\.id)
    guard
      !tasks.contains(where: {
        pids.contains($0.projectID) && $0.status != .done
          && ($0.assigneeID == userID || $0.reviewerID == userID)
      })
    else { try fail("Alihkan seluruh tugas aktif pelaksana dan reviewer sebelum anggota keluar.") }
  }
  func localRemoveMember(groupID: String, userID: String) throws {
    let g = try coordinator(groupID)
    guard g.memberIDs.contains(userID), userID != g.coordinatorID else {
      try fail("Koordinator tidak dapat dikeluarkan.")
    }
    try ensureNoActiveAssignments(groupID: groupID, userID: userID)
    groups[groups.firstIndex { $0.id == groupID }!].memberIDs.removeAll { $0 == userID }
    save()
  }
  func localLeaveGroup(_ id: String) throws {
    let g = try member(id)
    let actor = try me()
    guard g.coordinatorID != actor else { try fail("Serahkan peran koordinator sebelum keluar.") }
    try ensureNoActiveAssignments(groupID: id, userID: actor)
    groups[groups.firstIndex { $0.id == id }!].memberIDs.removeAll { $0 == actor }
    save()
  }
  func localUpdateProfile(name: String) throws {
    let actor = try me()
    let name = try text(name, max: 80)
    users[users.firstIndex { $0.id == actor }!].name = name
    save()
  }
  func localBlockUser(_ id: String) throws {
    let actor = try me()
    guard id != actor, user(id) != nil else { try fail("Pengguna tidak valid.") }
    if !blockedUserIDs.contains(id) { blocks[actor, default: []].append(id) }
    save()
  }
  func localUnblockUser(_ id: String) {
    guard let actor = currentUserID else { return }
    blocks[actor]?.removeAll { $0 == id }
    save()
  }
  func localReportMessage(_ id: String, reason: String) throws {
    let actor = try me()
    guard let message = messages.first(where: { $0.id == id }), message.senderID != actor else {
      try fail("Pesan tidak dapat dilaporkan.")
    }
    _ = try member(message.groupID)
    let reason = try text(reason, max: 500)
    reports.append(GLReport(messageID: id, reporterID: actor, reason: reason, createdAt: now))
    save()
  }
  func localDeleteAccount() throws {
    let actor = try me()
    guard !myGroups.contains(where: { $0.coordinatorID == actor }) else {
      try fail("Serahkan semua peran koordinator sebelum menghapus akun demo.")
    }
    for g in myGroups { try ensureNoActiveAssignments(groupID: g.id, userID: actor) }
    for i in groups.indices { groups[i].memberIDs.removeAll { $0 == actor } }
    if let i = users.firstIndex(where: { $0.id == actor }) {
      users[i].name = "Pengguna dihapus"
      users[i].email = ""
    }
    blocks.removeValue(forKey: actor)
    currentUserID = nil
    save()
  }
  private struct Snapshot: Codable {
    var users: [GLUser]
    var groups: [GLGroup]
    var projects: [GLProject]
    var tasks: [GLTask]
    var messages: [GLMessage]
    var invites: [GLInvite]
    var reports: [GLReport]
    var currentUserID: String?
    var blocks: [String: [String]]
    var advanceDemoTime: Bool
    var lastReadAt: [String: Date]? = nil
    var readMessageIDs: [String: Set<String>]? = nil
  }
  private func apply(_ s: Snapshot) {
    users = s.users
    groups = s.groups
    projects = s.projects
    tasks = s.tasks
    messages = s.messages
    invites = s.invites
    reports = s.reports
    currentUserID = s.currentUserID
    blocks = s.blocks
    readMessageIDs = s.readMessageIDs ?? [:]
    if s.readMessageIDs == nil {
      for (key, seenAt) in s.lastReadAt ?? [:] {
        let groupID = String(key.split(separator: ":", maxSplits: 1).last ?? "")
        readMessageIDs[key] = Set(
          messages.filter {
            $0.groupID == groupID && $0.taskID == nil && $0.delivery == .sent
              && $0.createdAt <= seenAt
          }.map(\.id))
      }
    }
    advanceDemoTime = s.advanceDemoTime
  }
  private func save() {
    guard persist, storageWritable, !isCloudMode else { return }
    do {
      let s = Snapshot(
        users: users, groups: groups, projects: projects, tasks: tasks, messages: messages,
        invites: invites, reports: reports, currentUserID: currentUserID, blocks: blocks,
        advanceDemoTime: advanceDemoTime, readMessageIDs: readMessageIDs)
      let data = try JSONEncoder().encode(s)
      try FileManager.default.createDirectory(
        at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: storageURL, options: .atomic)
      persistenceError = nil
    } catch { persistenceError = "Perubahan demo belum tersimpan: \(error.localizedDescription)" }
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
    guard let client = backend else { localSignOut(); return }
    stopRealtime()
    backend = nil
    loadSeed()
    currentUserID = nil
    reports = []
    blocks = [:]
    readMessageIDs = [:]
    persistenceError = nil
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
    guard let client = backend else { throw DemoError(message: "Sesi server tidak tersedia.") }
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

  @discardableResult func sendMessage(groupID: String, taskID: String? = nil, text: String, clientID: String = UUID().uuidString) async throws -> String {
    guard isCloudMode else { return try localSendMessage(groupID: groupID, taskID: taskID, text: text, clientID: clientID) }
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
    guard isCloudMode else { try localRetryMessage(id); return }
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
    simulatedOffline = false
    simulateSendFailure = false
    advanceDemoTime = false
    persistenceError = nil
    backendError = nil
  }

  private func clearExpiredBackend() {
    stopRealtime()
    backend = nil
    users = []; groups = []; projects = []; tasks = []; messages = []; invites = []; reports = []
    currentUserID = nil
    blocks = [:]; readMessageIDs = [:]
    loadSeed()
    currentUserID = nil
  }
}

extension DemoStore {
  /// "Kamu" for the signed-in user, like the prototype's `nm()`.
  func displayName(_ id: String) -> String {
    id == currentUserID ? "Kamu" : user(id)?.name ?? "Anggota"
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
