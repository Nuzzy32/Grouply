import XCTest

@testable import Grouply

final class WorkflowTests: XCTestCase {
  @MainActor func testCompletedTaskWithDeletedParticipantCannotReopen() async throws {
    let store = DemoStore(persist: false)
    store.signIn(as: "u1")
    let taskIndex = try XCTUnwrap(store.tasks.firstIndex { $0.projectID == "p1" })
    store.tasks[taskIndex].status = .done
    store.tasks[taskIndex].assigneeID = ""
    do {
      try await store.reopenTask(store.tasks[taskIndex].id)
      XCTFail("Deleted participant cannot become active again")
    } catch {
      XCTAssertTrue(error.localizedDescription.contains("Buat tugas pengganti"))
    }
    XCTAssertEqual(store.tasks[taskIndex].status, .done)
  }

  @MainActor private func assertThrows<T>(_ action: @autoclosure () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
    do { _ = try await action(); XCTFail("Expected operation to fail", file: file, line: line) } catch { }
  }

  @MainActor func testSubmissionReviewVersionAndHistory() async throws {
    let store = DemoStore(persist: false)
    store.signIn(as: "u1")
    await assertThrows(
      try await store.review(taskID: "t3", approve: true, feedback: "", expectedVersion: 1))
    await assertThrows(
      try await store.submitWork(
        taskID: "t3", note: "Hasil", links: ["javascript:alert(1)"], expectedVersion: 1))
    try await store.submitWork(
      taskID: "t3", note: "Constraint diperbaiki", links: ["https://example.org/ddl"],
      expectedVersion: 1)
    XCTAssertEqual(store.task("t3")?.status, .inReview)
    XCTAssertEqual(store.task("t3")?.submissions.count, 2)
    store.signIn(as: "u4")
    await assertThrows(
      try await store.review(taskID: "t3", approve: true, feedback: "", expectedVersion: 1))
    try await store.review(taskID: "t3", approve: true, feedback: "Sudah sesuai", expectedVersion: 2)
    XCTAssertEqual(store.task("t3")?.status, .done)
    XCTAssertEqual(store.task("t3")?.submissions.last?.reviewerID, "u4")
  }
  @MainActor func testReviewerCannotReviewHistoricalOwnSubmission() async throws {
    let store = DemoStore(persist: false)
    store.signIn(as: "u1")
    try await store.reassignTask(id: "t3", assigneeID: "u2", reviewerID: "u1", expectedVersion: 1)
    XCTAssertEqual(store.task("t3")?.status, .needsRevision)
    XCTAssertEqual(store.task("t3")?.submissions.count, 1)
    // Simulate an externally restored pending submission to verify the trust boundary.
    let i = store.tasks.firstIndex { $0.id == "t3" }!
    store.tasks[i].status = .inReview
    store.tasks[i].submissions[0].decision = nil
    await assertThrows(
      try await store.review(taskID: "t3", approve: true, feedback: "", expectedVersion: 2))
  }
  @MainActor func testReadOnlyProjectsEditAndReassignmentLocks() async throws {
    let store = DemoStore(persist: false)
    store.signIn(as: "u1")
    await assertThrows(
      try await store.createTask(
        projectID: "p3", title: "Baru", description: "", assigneeID: "u1", reviewerID: "u2",
        dueAt: Date()))
    await assertThrows(
      try await store.reassignTask(id: "t1", assigneeID: "u3", reviewerID: "u1", expectedVersion: 1))
    await assertThrows(
      try await store.updateTask(
        id: "t1", title: "Ubah", description: "", reviewerID: "u3", dueAt: Date(),
        expectedVersion: 1))
    try await store.archiveProject("p3")
    try await store.restoreProject("p3")
    XCTAssertEqual(store.project("p3")?.status, .completed)
    try await store.reopenProject("p3")
    try await store.reopenTask("t12")
    XCTAssertEqual(store.task("t12")?.status, .inProgress)
    await assertThrows(try await store.completeProject("p3"))
  }
  @MainActor func testRoleMembershipAndRemoval() async throws {
    let store = DemoStore(persist: false)
    store.signIn(as: "u2")
    await assertThrows(
      try await store.createProject(groupID: "g1", title: "Tidak berhak", description: "", dueAt: Date()))
    await assertThrows(try await store.sendMessage(groupID: "g2", text: "Bukan anggota"))
    await assertThrows(try await store.leaveGroup("g1"))
    store.signIn(as: "u1")
    await assertThrows(try await store.removeMember(groupID: "g1", userID: "u4"))
    await assertThrows(try await store.deleteAccount())
    XCTAssertNotNil(store.currentUser)
  }
  @MainActor func testInvitesExpiryRevocationAndUsage() async throws {
    let store = DemoStore(persist: false)
    store.signIn(as: "u1")
    await assertThrows(try await store.joinGroup(code: "UIX-OLD1"))
    await assertThrows(try await store.joinGroup(code: "BD3-USED"))
    await assertThrows(try await store.joinGroup(code: "BD3-OFF9"))
    let joined = try await store.joinGroup(code: " stat-k1q ")
    XCTAssertEqual(joined, "g3")
    XCTAssertEqual(store.invites.first { $0.id == "i1" }?.useCount, 1)
    store.signIn(as: "u2")
    await assertThrows(try await store.joinGroup(code: "STAT-K1Q"))
    store.advanceDemoTime = true
    await assertThrows(try await store.joinGroup(code: "BD3-7KQ2"))
  }
  @MainActor func testChatRetryIsIdempotentAndBlocksArePerPersona() async throws {
    let store = DemoStore(persist: false)
    store.signIn(as: "u1")
    store.simulateSendFailure = true
    let id = try await store.sendMessage(groupID: "g1", text: "Uji kirim", clientID: "retry-test")
    XCTAssertEqual(store.messages.first { $0.id == id }?.delivery, .failed)
    store.simulateSendFailure = false
    try await store.retryMessage(id)
    try await store.retryMessage(id)
    _ = try await store.sendMessage(groupID: "g1", text: "Uji kirim", clientID: id)
    XCTAssertEqual(store.messages.filter { $0.id == id }.count, 1)
    XCTAssertEqual(store.messages.first { $0.id == id }?.delivery, .sent)
    try await store.blockUser("u2")
    store.switchPersona("u3")
    XCTAssertTrue(store.blockedUserIDs.isEmpty)
    store.switchPersona("u1")
    XCTAssertEqual(store.blockedUserIDs, ["u2"])
  }
  @MainActor func testPersistenceAcrossSessions() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("demo.json")
    let store = DemoStore(storageURL: url)
    store.signIn(as: "u1")
    try await store.updateProfile(name: "Alex Baru")
    try await store.blockUser("u2")
    store.advanceDemoTime = true
    store.markChatRead(groupID: "g1")
    let restored = DemoStore(storageURL: url)
    XCTAssertEqual(restored.currentUser?.name, "Alex Baru")
    XCTAssertEqual(restored.blockedUserIDs, ["u2"])
    XCTAssertTrue(restored.advanceDemoTime)
    XCTAssertEqual(restored.unreadCount(groupID: "g1"), 0)
    XCTAssertNil(restored.persistenceError)
  }
  @MainActor func testCapacityOfflineDateAndReassignmentValidation() async throws {
    let store = DemoStore(persist: false)
    store.signIn(as: "u1")
    await assertThrows(
      try await store.createProject(
        groupID: "g1", title: "Bad date", description: "",
        dueAt: Date(timeIntervalSinceReferenceDate: .nan)))
    store.simulatedOffline = true
    await assertThrows(try await store.updateProfile(name: "Offline"))
    store.simulatedOffline = false
    try await store.reassignTask(id: "t2", assigneeID: "u2", reviewerID: "u3", expectedVersion: 1)
    XCTAssertEqual(store.task("t2")?.status, .todo)
    try await store.reassignTask(id: "t3", assigneeID: "u2", reviewerID: "u4", expectedVersion: 1)
    XCTAssertEqual(store.task("t3")?.status, .needsRevision)
    store.signIn(as: "u2")
    try await store.startTask("t3")
    XCTAssertEqual(store.task("t3")?.status, .inProgress)
    let i = store.groups.firstIndex { $0.id == "g3" }!
    store.groups[i].memberIDs = ["u3", "u4", "u5", "u6", "u7", "x1", "x2", "x3"]
    await assertThrows(try await store.joinGroup(code: "STAT-K1Q"))
  }
  @MainActor func testUnreadablePersistenceIsBackedUp() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent("demo.json")
    let original = Data("broken snapshot".utf8)
    try original.write(to: url)
    let store = DemoStore(storageURL: url)
    XCTAssertNotNil(store.persistenceError)
    let backups = try FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: nil)
    XCTAssertEqual(backups.count, 1)
    XCTAssertEqual(try Data(contentsOf: backups[0]), original)
    store.signIn(as: "u1")
    XCTAssertEqual(DemoStore(storageURL: url).currentUserID, "u1")
  }

  @MainActor func testUnreadIsPerPersonaAndTracksNewMessages() async throws {
    let store = DemoStore(persist: false)
    store.signIn(as: "u1")
    XCTAssertGreaterThan(store.unreadCount(groupID: "g1"), 0)
    store.markChatRead(groupID: "g1")
    XCTAssertEqual(store.unreadCount(groupID: "g1"), 0)
    store.signIn(as: "u2")
    XCTAssertGreaterThan(store.unreadCount(groupID: "g1"), 0)
    _ = try await store.sendMessage(groupID: "g1", text: "Pesan baru")
    store.signIn(as: "u1")
    XCTAssertEqual(store.unreadCount(groupID: "g1"), 1)
    store.markRead(groupID: "g1")
    XCTAssertEqual(store.unreadCount(groupID: "g1"), 0)
    XCTAssertEqual(store.unreadCount(groupID: "g3"), 0)
  }
  @MainActor func testTaskAssignmentCannotReferenceAnotherGroupMember() async throws {
    let store = DemoStore(persist: false)
    store.signIn(as: "u1")
    await assertThrows(
      try await store.createTask(
        projectID: "p1", title: "Task", description: "", assigneeID: "u1", reviewerID: "u6",
        dueAt: Date()))
    await assertThrows(
      try await store.updateTask(
        id: "t2", title: "Task", description: "", reviewerID: "u6", dueAt: Date(),
        expectedVersion: 1))
    XCTAssertEqual(store.task("t2")?.reviewerID, "u3")
  }

  @MainActor func testFailedDraftIsPrivateToItsSender() async throws {
    let store = DemoStore(persist: false)
    store.signIn(as: "u1")
    store.simulateSendFailure = true
    let id = try await store.sendMessage(groupID: "g1", text: "Draft belum terkirim")
    XCTAssertTrue(store.messages(groupID: "g1").contains { $0.id == id })
    store.signIn(as: "u2")
    XCTAssertFalse(store.messages(groupID: "g1").contains { $0.id == id })
    store.markChatRead(groupID: "g1")
    XCTAssertEqual(store.unreadCount(groupID: "g1"), 0)
    store.signIn(as: "u1")
    store.simulateSendFailure = false
    try await store.retryMessage(id)
    store.signIn(as: "u2")
    XCTAssertTrue(store.messages(groupID: "g1").contains { $0.id == id })
    XCTAssertEqual(store.unreadCount(groupID: "g1"), 1)
  }
  @MainActor func testUnreadSurvivesDemoTimeMovingBackwards() async throws {
    let store = DemoStore(persist: false)
    store.signIn(as: "u2")
    store.advanceDemoTime = true
    _ = try await store.sendMessage(groupID: "g1", text: "Dari waktu simulasi")
    store.signIn(as: "u1")
    store.markChatRead(groupID: "g1")
    XCTAssertEqual(store.unreadCount(groupID: "g1"), 0)
    store.advanceDemoTime = false
    store.signIn(as: "u2")
    _ = try await store.sendMessage(groupID: "g1", text: "Setelah waktu dipulihkan")
    store.signIn(as: "u1")
    XCTAssertEqual(store.unreadCount(groupID: "g1"), 1)
  }

  func testDeadlineReminderPlanOnlyOpenTasksInActiveProjects() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    func task(_ id: String, _ status: TaskStatus, project: String = "p1", dueIn days: Double) -> GLTask {
      GLTask(id: id, projectID: project, title: id, description: "", assigneeID: "u1", reviewerID: "u2",
        dueAt: now.addingTimeInterval(days * 86400), status: status)
    }
    let plan = DeadlineReminders.plan(
      tasks: [
        task("open", .todo, dueIn: 3), task("revise", .needsRevision, dueIn: 2),
        task("review", .inReview, dueIn: 3), task("done", .done, dueIn: 3),
        task("archived", .todo, project: "p9", dueIn: 3), task("soon", .inProgress, dueIn: 0.5),
      ], activeProjectIDs: ["p1"], now: now)
    XCTAssertEqual(plan.map(\.id).sorted(), ["deadline-open", "deadline-revise"])
    XCTAssertEqual(plan.first { $0.id == "deadline-open" }?.fireAt, now.addingTimeInterval(2 * 86400))
  }
}
