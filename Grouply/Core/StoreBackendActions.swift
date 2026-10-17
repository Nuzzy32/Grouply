import Foundation

extension DemoStore {
  @discardableResult func createGroup(name: String, description: String, course: String)
    async throws -> String
  {
    if isCloudMode {
      let result = try await mutateBackend(
        "createGroup",
        ["name": .string(name), "description": .string(description), "course": .string(course)])
      guard let id = result.id else { throw DemoError(message: "Server tidak mengembalikan ID.") }
      return id
    }
    return try localCreateGroup(name: name, description: description, course: course)
  }
  func updateGroup(id: String, name: String, description: String, course: String) async throws {
    if isCloudMode {
      let result = try await mutateBackend(
        "updateGroup",
        [
          "id": .string(id), "name": .string(name), "description": .string(description),
          "course": .string(course),
        ])
      _ = result
      return
    }
    try localUpdateGroup(id: id, name: name, description: description, course: course)
  }
  @discardableResult func createProject(
    groupID: String, title: String, description: String, dueAt: Date
  ) async throws -> String {
    if isCloudMode {
      let result = try await mutateBackend(
        "createProject",
        [
          "groupID": .string(groupID), "title": .string(title), "description": .string(description),
          "dueAt": .date(dueAt),
        ])
      guard let id = result.id else { throw DemoError(message: "Server tidak mengembalikan ID.") }
      return id
    }
    return try localCreateProject(
      groupID: groupID, title: title, description: description, dueAt: dueAt)
  }
  func updateProject(id: String, title: String, description: String, dueAt: Date) async throws {
    if isCloudMode {
      let result = try await mutateBackend(
        "updateProject",
        [
          "id": .string(id), "title": .string(title), "description": .string(description),
          "dueAt": .date(dueAt),
        ])
      _ = result
      return
    }
    try localUpdateProject(id: id, title: title, description: description, dueAt: dueAt)
  }
  func completeProject(_ id: String) async throws {
    if isCloudMode {
      let result = try await mutateBackend("completeProject", ["id": .string(id)])
      _ = result
      return
    }
    try localCompleteProject(id)
  }
  func reopenProject(_ id: String) async throws {
    if isCloudMode {
      let result = try await mutateBackend("reopenProject", ["id": .string(id)])
      _ = result
      return
    }
    try localReopenProject(id)
  }
  func archiveProject(_ id: String) async throws {
    if isCloudMode {
      let result = try await mutateBackend("archiveProject", ["id": .string(id)])
      _ = result
      return
    }
    try localArchiveProject(id)
  }
  func restoreProject(_ id: String) async throws {
    if isCloudMode {
      let result = try await mutateBackend("restoreProject", ["id": .string(id)])
      _ = result
      return
    }
    try localRestoreProject(id)
  }
  func revokeInvite(_ id: String) async throws {
    if isCloudMode {
      let result = try await mutateBackend("revokeInvite", ["id": .string(id)])
      _ = result
      return
    }
    try localRevokeInvite(id)
  }
  func leaveGroup(_ id: String) async throws {
    if isCloudMode {
      let result = try await mutateBackend("leaveGroup", ["id": .string(id)])
      _ = result
      return
    }
    try localLeaveGroup(id)
  }
  func blockUser(_ id: String) async throws {
    if isCloudMode {
      let result = try await mutateBackend("blockUser", ["id": .string(id)])
      _ = result
      return
    }
    try localBlockUser(id)
  }
  @discardableResult func createTask(
    projectID: String, title: String, description: String, assigneeID: String, reviewerID: String,
    dueAt: Date
  ) async throws -> String {
    if isCloudMode {
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
    return try localCreateTask(
      projectID: projectID, title: title, description: description, assigneeID: assigneeID,
      reviewerID: reviewerID, dueAt: dueAt)
  }
  func updateTask(
    id: String, title: String, description: String, reviewerID: String, dueAt: Date,
    expectedVersion: Int
  ) async throws {
    if isCloudMode {
      let result = try await mutateBackend(
        "updateTask",
        [
          "id": .string(id), "title": .string(title), "description": .string(description),
          "reviewerID": .string(reviewerID), "dueAt": .date(dueAt),
          "expectedVersion": .int(expectedVersion),
        ])
      _ = result
      return
    }
    try localUpdateTask(
      id: id, title: title, description: description, reviewerID: reviewerID, dueAt: dueAt,
      expectedVersion: expectedVersion)
  }
  func reassignTask(id: String, assigneeID: String, reviewerID: String, expectedVersion: Int)
    async throws
  {
    if isCloudMode {
      let result = try await mutateBackend(
        "reassignTask",
        [
          "id": .string(id), "assigneeID": .string(assigneeID), "reviewerID": .string(reviewerID),
          "expectedVersion": .int(expectedVersion),
        ])
      _ = result
      return
    }
    try localReassignTask(
      id: id, assigneeID: assigneeID, reviewerID: reviewerID, expectedVersion: expectedVersion)
  }
  func startTask(_ id: String) async throws {
    if isCloudMode {
      let result = try await mutateBackend(
        "startTask", ["id": .string(id), "expectedVersion": .int(task(id)?.version ?? 0)])
      _ = result
      return
    }
    try localStartTask(id)
  }
  func reopenTask(_ id: String) async throws {
    if let task = task(id), task.assigneeID.isEmpty || task.reviewerID.isEmpty {
      throw DemoError(message: "Pelaksana atau reviewer telah menghapus akun. Buat tugas pengganti; riwayat ini tetap disimpan.")
    }
    if isCloudMode {
      let result = try await mutateBackend(
        "reopenTask", ["id": .string(id), "expectedVersion": .int(task(id)?.version ?? 0)])
      _ = result
      return
    }
    try localReopenTask(id)
  }
  func submitWork(taskID: String, note: String, links: [String], expectedVersion: Int) async throws
  {
    if isCloudMode {
      let result = try await mutateBackend(
        "submitWork",
        [
          "taskID": .string(taskID), "note": .string(note),
          "links": .array(links.map { .string($0) }), "expectedVersion": .int(expectedVersion),
        ])
      _ = result
      return
    }
    try localSubmitWork(taskID: taskID, note: note, links: links, expectedVersion: expectedVersion)
  }
  func review(taskID: String, approve: Bool, feedback: String, expectedVersion: Int) async throws {
    if isCloudMode {
      let result = try await mutateBackend(
        "review",
        [
          "taskID": .string(taskID), "approve": .bool(approve), "feedback": .string(feedback),
          "expectedVersion": .int(expectedVersion),
        ])
      _ = result
      return
    }
    try localReview(
      taskID: taskID, approve: approve, feedback: feedback, expectedVersion: expectedVersion)
  }
  @discardableResult func generateInvite(groupID: String) async throws -> GLInvite {
    if isCloudMode {
      let result = try await mutateBackend("generateInvite", ["groupID": .string(groupID)])
      guard let invite = result.invite else { throw DemoError(message: "Undangan tidak tersedia.") }
      if let index = invites.firstIndex(where: { $0.id == invite.id }) { invites[index] = invite }
      else { invites.append(invite) }
      return invite
    }
    return try localGenerateInvite(groupID: groupID)
  }
  @discardableResult func joinGroup(code: String) async throws -> String {
    if isCloudMode {
      let result = try await mutateBackend("joinGroup", ["code": .string(code)])
      guard let id = result.id else { throw DemoError(message: "Server tidak mengembalikan ID.") }
      return id
    }
    return try localJoinGroup(code: code)
  }
  func transferCoordinator(groupID: String, to id: String) async throws {
    if isCloudMode {
      let result = try await mutateBackend(
        "transferCoordinator", ["groupID": .string(groupID), "to": .string(id)])
      _ = result
      return
    }
    try localTransferCoordinator(groupID: groupID, to: id)
  }
  func removeMember(groupID: String, userID: String) async throws {
    if isCloudMode {
      let result = try await mutateBackend(
        "removeMember", ["groupID": .string(groupID), "userID": .string(userID)])
      _ = result
      return
    }
    try localRemoveMember(groupID: groupID, userID: userID)
  }
  func updateProfile(name: String) async throws {
    if isCloudMode {
      let result = try await mutateBackend("updateProfile", ["name": .string(name)])
      _ = result
      return
    }
    try localUpdateProfile(name: name)
  }
  func reportMessage(_ id: String, reason: String) async throws {
    if isCloudMode {
      let result = try await mutateBackend(
        "reportMessage", ["id": .string(id), "reason": .string(reason)])
      _ = result
      return
    }
    try localReportMessage(id, reason: reason)
  }
  func deleteAccount() async throws {
    if isCloudMode {
      try await deleteBackendAccount()
      return
    }
    try localDeleteAccount()
  }
  func unblockUser(_ id: String) async throws {
    if isCloudMode {
      _ = try await mutateBackend("unblockUser", ["id": .string(id)])
      return
    }
    localUnblockUser(id)
  }
}
