import Foundation

extension DemoStore {
  @discardableResult func createGroup(name: String, description: String, course: String)
    async throws -> String
  {
    let result = try await mutateBackend(
      "createGroup",
      ["name": .string(name), "description": .string(description), "course": .string(course)])
    guard let id = result.id else { throw DemoError(message: "Server tidak mengembalikan ID.") }
    return id
  }
  func updateGroup(id: String, name: String, description: String, course: String) async throws {
    _ = try await mutateBackend(
      "updateGroup",
      [
        "id": .string(id), "name": .string(name), "description": .string(description),
        "course": .string(course),
      ])
  }
  @discardableResult func createProject(
    groupID: String, title: String, description: String, dueAt: Date
  ) async throws -> String {
    let result = try await mutateBackend(
      "createProject",
      [
        "groupID": .string(groupID), "title": .string(title), "description": .string(description),
        "dueAt": .date(dueAt),
      ])
    guard let id = result.id else { throw DemoError(message: "Server tidak mengembalikan ID.") }
    return id
  }
  func updateProject(id: String, title: String, description: String, dueAt: Date) async throws {
    _ = try await mutateBackend(
      "updateProject",
      [
        "id": .string(id), "title": .string(title), "description": .string(description),
        "dueAt": .date(dueAt),
      ])
  }
  func completeProject(_ id: String) async throws {
    _ = try await mutateBackend("completeProject", ["id": .string(id)])
  }
  func reopenProject(_ id: String) async throws {
    _ = try await mutateBackend("reopenProject", ["id": .string(id)])
  }
  func archiveProject(_ id: String) async throws {
    _ = try await mutateBackend("archiveProject", ["id": .string(id)])
  }
  func restoreProject(_ id: String) async throws {
    _ = try await mutateBackend("restoreProject", ["id": .string(id)])
  }
  func revokeInvite(_ id: String) async throws {
    _ = try await mutateBackend("revokeInvite", ["id": .string(id)])
  }
  func leaveGroup(_ id: String) async throws {
    _ = try await mutateBackend("leaveGroup", ["id": .string(id)])
  }
  func blockUser(_ id: String) async throws {
    _ = try await mutateBackend("blockUser", ["id": .string(id)])
  }
  @discardableResult func createTask(
    projectID: String, title: String, description: String, assigneeID: String, reviewerID: String,
    dueAt: Date
  ) async throws -> String {
    let result = try await mutateBackend(
      "createTask",
      [
        "projectID": .string(projectID), "title": .string(title),
        "description": .string(description), "assigneeID": .string(assigneeID),
        "reviewerID": .string(reviewerID), "dueAt": .date(dueAt),
      ])
    guard let id = result.id else { throw DemoError(message: "Server tidak mengembalikan ID.") }
    return id
  }
  func updateTask(
    id: String, title: String, description: String, reviewerID: String, dueAt: Date,
    expectedVersion: Int
  ) async throws {
    _ = try await mutateBackend(
      "updateTask",
      [
        "id": .string(id), "title": .string(title), "description": .string(description),
        "reviewerID": .string(reviewerID), "dueAt": .date(dueAt),
        "expectedVersion": .int(expectedVersion),
      ])
  }
  func reassignTask(id: String, assigneeID: String, reviewerID: String, expectedVersion: Int)
    async throws
  {
    _ = try await mutateBackend(
      "reassignTask",
      [
        "id": .string(id), "assigneeID": .string(assigneeID), "reviewerID": .string(reviewerID),
        "expectedVersion": .int(expectedVersion),
      ])
  }
  func startTask(_ id: String) async throws {
    _ = try await mutateBackend(
      "startTask", ["id": .string(id), "expectedVersion": .int(task(id)?.version ?? 0)])
  }
  func reopenTask(_ id: String) async throws {
    if let task = task(id), task.assigneeID.isEmpty || task.reviewerID.isEmpty {
      throw DemoError(message: "Pelaksana atau reviewer telah menghapus akun. Buat tugas pengganti; riwayat ini tetap disimpan.")
    }
    _ = try await mutateBackend(
      "reopenTask", ["id": .string(id), "expectedVersion": .int(task(id)?.version ?? 0)])
  }
  func submitWork(taskID: String, note: String, links: [String], expectedVersion: Int) async throws
  {
    _ = try await mutateBackend(
      "submitWork",
      [
        "taskID": .string(taskID), "note": .string(note),
        "links": .array(links.map { .string($0) }), "expectedVersion": .int(expectedVersion),
      ])
  }
  func review(taskID: String, approve: Bool, feedback: String, expectedVersion: Int) async throws {
    _ = try await mutateBackend(
      "review",
      [
        "taskID": .string(taskID), "approve": .bool(approve), "feedback": .string(feedback),
        "expectedVersion": .int(expectedVersion),
      ])
  }
  @discardableResult func generateInvite(groupID: String) async throws -> GLInvite {
    let result = try await mutateBackend("generateInvite", ["groupID": .string(groupID)])
    guard let invite = result.invite else { throw DemoError(message: "Undangan tidak tersedia.") }
    if let index = invites.firstIndex(where: { $0.id == invite.id }) { invites[index] = invite }
    else { invites.append(invite) }
    return invite
  }
  @discardableResult func joinGroup(code: String) async throws -> String {
    let result = try await mutateBackend("joinGroup", ["code": .string(code)])
    guard let id = result.id else { throw DemoError(message: "Server tidak mengembalikan ID.") }
    return id
  }
  func transferCoordinator(groupID: String, to id: String) async throws {
    _ = try await mutateBackend(
      "transferCoordinator", ["groupID": .string(groupID), "to": .string(id)])
  }
  func removeMember(groupID: String, userID: String) async throws {
    _ = try await mutateBackend(
      "removeMember", ["groupID": .string(groupID), "userID": .string(userID)])
  }
  func updateProfile(name: String) async throws {
    _ = try await mutateBackend("updateProfile", ["name": .string(name)])
  }
  func reportMessage(_ id: String, reason: String) async throws {
    _ = try await mutateBackend(
      "reportMessage", ["id": .string(id), "reason": .string(reason)])
  }
  func deleteAccount() async throws { try await deleteBackendAccount() }
  func unblockUser(_ id: String) async throws {
    _ = try await mutateBackend("unblockUser", ["id": .string(id)])
  }
}
