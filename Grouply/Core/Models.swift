import Foundation

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
  case todo
  case inProgress = "in_progress"
  case inReview = "in_review"
  case needsRevision = "needs_revision"
  case done
  var id: String { rawValue }
  var label: String {
    switch self {
    case .todo: "Belum dimulai"
    case .inProgress: "Dikerjakan"
    case .inReview: "Menunggu review"
    case .needsRevision: "Perlu revisi"
    case .done: "Selesai"
    }
  }
  var icon: String {
    switch self {
    case .todo: "circle"
    case .inProgress: "play.circle"
    case .inReview: "eye"
    case .needsRevision: "arrow.uturn.backward"
    case .done: "checkmark.circle.fill"
    }
  }
}
enum ProjectStatus: String, Codable, CaseIterable { case active, completed, archived }
enum DeliveryStatus: String, Codable { case sending, sent, failed }
struct GLUser: Codable, Equatable, Identifiable { var id, name, email, tint: String }
struct GLGroup: Codable, Equatable, Identifiable {
  var id, name, description, course: String
  var memberIDs: [String]
  var coordinatorID, tint, icon: String
}
struct GLProject: Codable, Equatable, Identifiable {
  var id, groupID, title, description: String
  var dueAt: Date
  var status: ProjectStatus
  var previousStatus: ProjectStatus? = nil
}
struct GLTask: Codable, Equatable, Identifiable {
  var id, projectID, title, description, assigneeID, reviewerID: String
  var dueAt: Date
  var status: TaskStatus
  var version: Int = 1
  var submissions: [GLSubmission] = []
}
struct GLSubmission: Codable, Equatable, Identifiable {
  var id: String = UUID().uuidString
  var revision: Int
  var authorID, note: String
  var links: [String]
  var createdAt: Date
  var decision: String? = nil
  var feedback: String? = nil
  var reviewerID: String? = nil
}
struct GLMessage: Codable, Equatable, Identifiable {
  var id: String = UUID().uuidString
  var groupID: String
  var taskID: String?
  var senderID, text: String
  var createdAt: Date
  var kind: String = "text"
  var delivery: DeliveryStatus = .sent
  var targetTaskID: String? = nil
}
struct GLInvite: Codable, Equatable, Identifiable {
  var id: String = UUID().uuidString
  var groupID, code: String
  var createdAt, expiresAt: Date
  var maxUses: Int = 1
  var useCount: Int = 0
  var revoked: Bool = false
}
struct GLReport: Codable, Equatable, Identifiable {
  var id: String = UUID().uuidString
  var messageID, reporterID, reason: String
  var createdAt: Date
}
struct DemoError: LocalizedError {
  let message: String
  var errorDescription: String? { message }
}
