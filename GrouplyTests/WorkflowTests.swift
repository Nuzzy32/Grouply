import XCTest

@testable import Grouply

final class WorkflowTests: XCTestCase {
  @MainActor func testSubmissionReviewVersionAndHistory() throws {
    let store = DemoStore(persist: false)
    store.signIn(as: "u1")
    XCTAssertThrowsError(
      try store.review(taskID: "t3", approve: true, feedback: "", expectedVersion: 1))
    XCTAssertThrowsError(
      try store.submitWork(
        taskID: "t3", note: "Hasil", links: ["javascript:alert(1)"], expectedVersion: 1))
    try store.submitWork(
      taskID: "t3", note: "Constraint diperbaiki", links: ["https://example.org/ddl"],
      expectedVersion: 1)
    XCTAssertEqual(store.task("t3")?.status, .inReview)
    XCTAssertEqual(store.task("t3")?.submissions.count, 2)
    store.signIn(as: "u4")
    XCTAssertThrowsError(
      try store.review(taskID: "t3", approve: true, feedback: "", expectedVersion: 1))
    try store.review(taskID: "t3", approve: true, feedback: "Sudah sesuai", expectedVersion: 2)
    XCTAssertEqual(store.task("t3")?.status, .done)
    XCTAssertEqual(store.task("t3")?.submissions.last?.reviewerID, "u4")
  }
  @MainActor func testReviewerCannotReviewHistoricalOwnSubmission() throws {
    let store = DemoStore(persist: false)
    store.signIn(as: "u1")
    try store.reassignTask(id: "t3", assigneeID: "u2", reviewerID: "u1", expectedVersion: 1)
    XCTAssertEqual(store.task("t3")?.status, .needsRevision)
    XCTAssertEqual(store.task("t3")?.submissions.count, 1)
    // Simulate an externally restored pending submission to verify the trust boundary.
    let i = store.tasks.firstIndex { $0.id == "t3" }!
    store.tasks[i].status = .inReview
    store.tasks[i].submissions[0].decision = nil
    XCTAssertThrowsError(
      try store.review(taskID: "t3", approve: true, feedback: "", expectedVersion: 2))
  }
  @MainActor func testReadOnlyProjectsEditAndReassignmentLocks() throws {
    let store = DemoStore(persist: false)
    store.signIn(as: "u1")
    XCTAssertThrowsError(
      try store.createTask(
        projectID: "p3", title: "Baru", description: "", assigneeID: "u1", reviewerID: "u2",
        dueAt: Date()))
    XCTAssertThrowsError(
      try store.reassignTask(id: "t1", assigneeID: "u3", reviewerID: "u1", expectedVersion: 1))
    XCTAssertThrowsError(
      try store.updateTask(
        id: "t1", title: "Ubah", description: "", reviewerID: "u3", dueAt: Date(),
        expectedVersion: 1))
    try store.archiveProject("p3")
    try store.restoreProject("p3")
    XCTAssertEqual(store.project("p3")?.status, .completed)
    try store.reopenProject("p3")
    try store.reopenTask("t12")
    XCTAssertEqual(store.task("t12")?.status, .inProgress)
    XCTAssertThrowsError(try store.completeProject("p3"))
  }
  @MainActor func testRoleMembershipAndRemoval() throws {
    let store = DemoStore(persist: false)
    store.signIn(as: "u2")
    XCTAssertThrowsError(
      try store.createProject(groupID: "g1", title: "Tidak berhak", description: "", dueAt: Date()))
    XCTAssertThrowsError(try store.sendMessage(groupID: "g2", text: "Bukan anggota"))
    XCTAssertThrowsError(try store.leaveGroup("g1"))
    store.signIn(as: "u1")
    XCTAssertThrowsError(try store.removeMember(groupID: "g1", userID: "u4"))
    XCTAssertThrowsError(try store.deleteAccount())
    XCTAssertNotNil(store.currentUser)
  }
  @MainActor func testInvitesExpiryRevocationAndUsage() throws {
    let store = DemoStore(persist: false)
    store.signIn(as: "u1")
    XCTAssertThrowsError(try store.joinGroup(code: "UIX-OLD1"))
    XCTAssertThrowsError(try store.joinGroup(code: "BD3-USED"))
    XCTAssertThrowsError(try store.joinGroup(code: "BD3-OFF9"))
    XCTAssertEqual(try store.joinGroup(code: " stat-k1q "), "g3")
    XCTAssertEqual(store.invites.first { $0.id == "i1" }?.useCount, 1)
    store.signIn(as: "u2")
    XCTAssertThrowsError(try store.joinGroup(code: "STAT-K1Q"))
    store.advanceDemoTime = true
    XCTAssertThrowsError(try store.joinGroup(code: "BD3-7KQ2"))
  }
  @MainActor func testChatRetryIsIdempotentAndBlocksArePerPersona() throws {
    let store = DemoStore(persist: false)
    store.signIn(as: "u1")
    store.simulateSendFailure = true
    let id = try store.sendMessage(groupID: "g1", text: "Uji kirim", clientID: "retry-test")
    XCTAssertEqual(store.messages.first { $0.id == id }?.delivery, .failed)
    store.simulateSendFailure = false
    try store.retryMessage(id)
    try store.retryMessage(id)
    _ = try store.sendMessage(groupID: "g1", text: "Uji kirim", clientID: id)
    XCTAssertEqual(store.messages.filter { $0.id == id }.count, 1)
    XCTAssertEqual(store.messages.first { $0.id == id }?.delivery, .sent)
    try store.blockUser("u2")
    store.switchPersona("u3")
    XCTAssertTrue(store.blockedUserIDs.isEmpty)
    store.switchPersona("u1")
    XCTAssertEqual(store.blockedUserIDs, ["u2"])
  }
  @MainActor func testPersistenceAcrossSessions() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("demo.json")
    let store = DemoStore(storageURL: url)
    store.signIn(as: "u1")
    try store.updateProfile(name: "Alex Baru")
    try store.blockUser("u2")
    store.advanceDemoTime = true
    store.markChatRead(groupID: "g1")
    let restored = DemoStore(storageURL: url)
    XCTAssertEqual(restored.currentUser?.name, "Alex Baru")
    XCTAssertEqual(restored.blockedUserIDs, ["u2"])
    XCTAssertTrue(restored.advanceDemoTime)
    XCTAssertEqual(restored.unreadCount(groupID: "g1"), 0)
    XCTAssertNil(restored.persistenceError)
  }
  @MainActor func testCapacityOfflineDateAndReassignmentValidation() throws {
    let store = DemoStore(persist: false)
    store.signIn(as: "u1")
    XCTAssertThrowsError(
      try store.createProject(
        groupID: "g1", title: "Bad date", description: "",
        dueAt: Date(timeIntervalSinceReferenceDate: .nan)))
    store.simulatedOffline = true
    XCTAssertThrowsError(try store.updateProfile(name: "Offline"))
    store.simulatedOffline = false
    try store.reassignTask(id: "t2", assigneeID: "u2", reviewerID: "u3", expectedVersion: 1)
    XCTAssertEqual(store.task("t2")?.status, .todo)
    try store.reassignTask(id: "t3", assigneeID: "u2", reviewerID: "u4", expectedVersion: 1)
    XCTAssertEqual(store.task("t3")?.status, .needsRevision)
    store.signIn(as: "u2")
    try store.startTask("t3")
    XCTAssertEqual(store.task("t3")?.status, .inProgress)
    let i = store.groups.firstIndex { $0.id == "g3" }!
    store.groups[i].memberIDs = ["u3", "u4", "u5", "u6", "u7", "x1", "x2", "x3"]
    XCTAssertThrowsError(try store.joinGroup(code: "STAT-K1Q"))
  }
  @MainActor func testUnreadablePersistenceIsBackedUp() throws {
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

  @MainActor func testUnreadIsPerPersonaAndTracksNewMessages() throws {
    let store = DemoStore(persist: false)
    store.signIn(as: "u1")
    XCTAssertGreaterThan(store.unreadCount(groupID: "g1"), 0)
    store.markChatRead(groupID: "g1")
    XCTAssertEqual(store.unreadCount(groupID: "g1"), 0)
    store.signIn(as: "u2")
    XCTAssertGreaterThan(store.unreadCount(groupID: "g1"), 0)
    _ = try store.sendMessage(groupID: "g1", text: "Pesan baru")
    store.signIn(as: "u1")
    XCTAssertEqual(store.unreadCount(groupID: "g1"), 1)
    store.markRead(groupID: "g1")
    XCTAssertEqual(store.unreadCount(groupID: "g1"), 0)
    XCTAssertEqual(store.unreadCount(groupID: "g3"), 0)
  }
  @MainActor func testTaskAssignmentCannotReferenceAnotherGroupMember() throws {
    let store = DemoStore(persist: false)
    store.signIn(as: "u1")
    XCTAssertThrowsError(
      try store.createTask(
        projectID: "p1", title: "Task", description: "", assigneeID: "u1", reviewerID: "u6",
        dueAt: Date()))
    XCTAssertThrowsError(
      try store.updateTask(
        id: "t2", title: "Task", description: "", reviewerID: "u6", dueAt: Date(),
        expectedVersion: 1))
    XCTAssertEqual(store.task("t2")?.reviewerID, "u3")
  }

  @MainActor func testFailedDraftIsPrivateToItsSender() throws {
    let store = DemoStore(persist: false)
    store.signIn(as: "u1")
    store.simulateSendFailure = true
    let id = try store.sendMessage(groupID: "g1", text: "Draft belum terkirim")
    XCTAssertTrue(store.messages(groupID: "g1").contains { $0.id == id })
    store.signIn(as: "u2")
    XCTAssertFalse(store.messages(groupID: "g1").contains { $0.id == id })
    store.markChatRead(groupID: "g1")
    XCTAssertEqual(store.unreadCount(groupID: "g1"), 0)
    store.signIn(as: "u1")
    store.simulateSendFailure = false
    try store.retryMessage(id)
    store.signIn(as: "u2")
    XCTAssertTrue(store.messages(groupID: "g1").contains { $0.id == id })
    XCTAssertEqual(store.unreadCount(groupID: "g1"), 1)
  }
  @MainActor func testUnreadSurvivesDemoTimeMovingBackwards() throws {
    let store = DemoStore(persist: false)
    store.signIn(as: "u2")
    store.advanceDemoTime = true
    _ = try store.sendMessage(groupID: "g1", text: "Dari waktu simulasi")
    store.signIn(as: "u1")
    store.markChatRead(groupID: "g1")
    XCTAssertEqual(store.unreadCount(groupID: "g1"), 0)
    store.advanceDemoTime = false
    store.signIn(as: "u2")
    _ = try store.sendMessage(groupID: "g1", text: "Setelah waktu dipulihkan")
    store.signIn(as: "u1")
    XCTAssertEqual(store.unreadCount(groupID: "g1"), 1)
  }

}
