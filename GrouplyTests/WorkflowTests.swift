import XCTest

@testable import Grouply

final class WorkflowTests: XCTestCase {
  /// Server-shaped state built in memory; the server itself enforces workflow rules (SQL tests).
  @MainActor private func signedInStore(as actor: String = "u1") -> DemoStore {
    let store = DemoStore()
    store.currentUserID = actor
    store.users = ["u1", "u2"].map { GLUser(id: $0, name: $0, email: "\($0)@example.org", tint: "#D8EAF4") }
    store.groups = [
      GLGroup(
        id: "g1", name: "Grup", description: "", course: "", memberIDs: ["u1", "u2"],
        coordinatorID: "u1", tint: "#D8EAF4", icon: "person.3")
    ]
    store.projects = [
      GLProject(id: "p1", groupID: "g1", title: "Proyek", description: "", dueAt: Date(), status: .active)
    ]
    return store
  }

  @MainActor func testCompletedTaskWithDeletedParticipantCannotReopen() async throws {
    let store = signedInStore()
    store.tasks = [
      GLTask(
        id: "t1", projectID: "p1", title: "Tugas", description: "", assigneeID: "",
        reviewerID: "u2", dueAt: Date(), status: .done)
    ]
    do {
      try await store.reopenTask("t1")
      XCTFail("Deleted participant cannot become active again")
    } catch {
      XCTAssertTrue(error.localizedDescription.contains("Buat tugas pengganti"))
    }
    XCTAssertEqual(store.task("t1")?.status, .done)
  }

  @MainActor func testActionsRequireServerAccount() async throws {
    let store = signedInStore()
    XCTAssertFalse(store.isCloudMode)
    do {
      _ = try await store.createGroup(name: "Grup baru", description: "", course: "")
      XCTFail("Mutations need a signed-in server account")
    } catch {
      XCTAssertEqual(error.localizedDescription, "Masuk ke akun terlebih dahulu.")
    }
    do {
      try await store.deleteAccount()
      XCTFail("Deletion needs a signed-in server account")
    } catch {
      XCTAssertEqual(error.localizedDescription, "Masuk ke akun terlebih dahulu.")
    }
    XCTAssertEqual(store.groups.count, 1)
  }

  @MainActor func testUnreadIgnoresOwnReadAndFailedMessages() {
    let store = signedInStore()
    store.messages = [
      GLMessage(id: "m1", groupID: "g1", taskID: nil, senderID: "u2", text: "Sudah dibaca", createdAt: Date()),
      GLMessage(id: "m2", groupID: "g1", taskID: nil, senderID: "u2", text: "Baru", createdAt: Date()),
      GLMessage(id: "m3", groupID: "g1", taskID: nil, senderID: "u1", text: "Milikku", createdAt: Date()),
      GLMessage(id: "m4", groupID: "g1", taskID: "t1", senderID: "u2", text: "Diskusi tugas", createdAt: Date()),
      GLMessage(
        id: "m5", groupID: "g1", taskID: nil, senderID: "u2", text: "Draft", createdAt: Date(),
        delivery: .failed),
    ]
    store.readMessageIDs = ["u1:g1": ["m1"]]
    XCTAssertEqual(store.unreadCount(groupID: "g1"), 1)
    XCTAssertEqual(store.unreadCount(groupID: "g-other"), 0)
    store.currentUserID = "outsider"
    XCTAssertEqual(store.unreadCount(groupID: "g1"), 0)
  }

  @MainActor func testFailedDraftIsPrivateToItsSender() {
    let store = signedInStore()
    store.messages = [
      GLMessage(
        id: "draft", groupID: "g1", taskID: nil, senderID: "u1", text: "Draft belum terkirim",
        createdAt: Date(), delivery: .failed)
    ]
    XCTAssertTrue(store.messages(groupID: "g1").contains { $0.id == "draft" })
    store.currentUserID = "u2"
    XCTAssertFalse(store.messages(groupID: "g1").contains { $0.id == "draft" })
    XCTAssertEqual(store.unreadCount(groupID: "g1"), 0)
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

  @MainActor func testProjectActivityListsOnlyThisProjectsTaskEventsNewestFirst() {
    let store = signedInStore()
    store.projects.append(
      GLProject(id: "p2", groupID: "g1", title: "Lain", description: "", dueAt: Date(), status: .active))
    store.tasks = [
      GLTask(id: "t1", projectID: "p1", title: "A", description: "", assigneeID: "u1", reviewerID: "u2", dueAt: Date(), status: .inReview),
      GLTask(id: "t2", projectID: "p2", title: "B", description: "", assigneeID: "u1", reviewerID: "u2", dueAt: Date(), status: .todo),
    ]
    let t0 = Date(timeIntervalSince1970: 1_000)
    store.messages = [
      GLMessage(id: "m1", groupID: "g1", taskID: "t1", senderID: "u1", text: "mengirim hasil", createdAt: t0, kind: "activity"),
      GLMessage(id: "m2", groupID: "g1", taskID: "t1", senderID: "u2", text: "meminta revisi", createdAt: t0.addingTimeInterval(60), kind: "activity"),
      GLMessage(id: "m3", groupID: "g1", taskID: "t1", senderID: "u2", text: "obrolan biasa", createdAt: t0.addingTimeInterval(120)),
      GLMessage(id: "m4", groupID: "g1", taskID: "t2", senderID: "u1", text: "mengirim hasil", createdAt: t0.addingTimeInterval(180), kind: "activity"),
      GLMessage(id: "m5", groupID: "g1", taskID: nil, senderID: "u1", text: "mengirim hasil", createdAt: t0.addingTimeInterval(240), kind: "activity"),
    ]
    XCTAssertEqual(store.projectActivity("p1").map(\.id), ["m2", "m1"])
  }
}
