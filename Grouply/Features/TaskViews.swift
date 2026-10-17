import SwiftUI

/// Task card used on Tugas Saya and Project Detail (prototype `vmTask`).
struct GLTaskRow: View {
  @Environment(DemoStore.self) private var store
  let task: GLTask
  var showProject = false
  var body: some View {
    let overdue = GLFormat.isOverdue(task.dueAt, status: task.status, now: store.now)
    let hours = store.reviewWaitHours(task)
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 6) {
        GLStatusChip(status: task.status)
        if overdue {
          GLChip(label: "Terlambat", icon: "exclamationmark.circle", background: GLTheme.coral, outlined: true)
        }
        if let hours, hours > 48 {
          GLChip(
            label: "Menunggu \(hours) jam", icon: "list.bullet.clipboard",
            background: GLTheme.lavender, outlined: true)
        }
      }
      if showProject {
        VStack(alignment: .leading, spacing: 3) {
          Text(task.title).gl(17, .semibold)
          Text(store.project(task.projectID)?.title ?? "").gl(13).foregroundStyle(GLTheme.secondary)
        }
      } else {
        Text(task.title).gl(17, .semibold)
      }
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 8) { pair; Spacer(minLength: 0); meta }
        VStack(alignment: .leading, spacing: 10) { pair; meta }
      }
    }
    .padding(16).frame(maxWidth: .infinity, alignment: .leading).glSurface(24)
    .multilineTextAlignment(.leading)
    .accessibilityElement(children: .combine)
  }
  private var pair: some View {
    HStack(spacing: 6) {
      GLAvatar(user: store.user(task.assigneeID), size: 28, fontSize: 11)
      GLIcon("arrow.right", size: 16).foregroundStyle(GLTheme.secondary)
      GLAvatar(user: store.user(task.reviewerID), size: 28, fontSize: 11)
      Text("\(store.displayName(task.assigneeID)) → \(store.displayName(task.reviewerID))").gl(13)
        .lineLimit(1)
    }.foregroundStyle(GLTheme.text3).fixedSize()
  }
  private var meta: some View {
    HStack(spacing: 12) {
      HStack(spacing: 4) {
        GLIcon("clock", size: 17)
        Text(GLFormat.due(task.dueAt, status: task.status, now: store.now)).gl(13)
      }
      if showProject {
        HStack(spacing: 4) {
          GLIcon("bubble.left", size: 17)
          Text("\(store.messages(groupID: store.project(task.projectID)?.groupID ?? "", taskID: task.id).filter { $0.kind == "text" }.count)").gl(13)
        }
      }
    }.foregroundStyle(GLTheme.text3).fixedSize()
  }
}

struct MyTasksView: View {
  @Environment(DemoStore.self) private var store
  @State private var filter = "all"
  private var live: [GLTask] {
    store.tasks.filter { task in
      guard let p = store.project(task.projectID) else { return false }
      return p.status != .archived && store.isMember(groupID: p.groupID)
    }
  }
  private var mine: [GLTask] { live.filter { $0.assigneeID == store.currentUserID } }
  private var toReview: [GLTask] {
    live.filter { $0.reviewerID == store.currentUserID && $0.status == .inReview }
  }
  /// Prototype `myTasksVals` sections.
  private var sections: [(title: String, items: [GLTask])] {
    let now = store.now
    let overdue = { (t: GLTask) in GLFormat.isOverdue(t.dueAt, status: t.status, now: now) }
    let action = mine.filter { $0.status == .needsRevision || (overdue($0) && $0.status != .inReview) } + toReview
    let ids = Set(action.map(\.id))
    let soon = mine.filter {
      !ids.contains($0.id) && GLFormat.isSoon($0.dueAt, status: $0.status, now: now) && $0.status != .inReview
    }
    let soonIDs = Set(soon.map(\.id))
    let rest = mine.filter { !ids.contains($0.id) && !soonIDs.contains($0.id) && $0.status != .done }
    let done = mine.filter { $0.status == .done }
    switch filter {
    case "review": return [("Perlu review", toReview)]
    case "active": return [("Dikerjakan", mine.filter { $0.status == .inProgress })]
    case "done": return [("Selesai", done)]
    default:
      return [("Perlu tindakan", action), ("Segera", soon), ("Sedang berjalan", rest), ("Selesai", done)]
        .filter { !$0.1.isEmpty }.map { ($0.0, $0.1) }
    }
  }
  var body: some View {
    let none = mine.isEmpty && toReview.isEmpty
    let done = mine.filter { $0.status == .done }.count
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Tugas Saya").gl(34, .bold, em: -0.03)
          Text(
            none
              ? "Belum ada tugas untukmu"
              : "\(mine.count - done) terbuka · \(toReview.count) menunggu review kamu"
          ).gl(15).foregroundStyle(GLTheme.secondary)
        }.padding(.horizontal, 20)
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            chip("all", "Semua", mine.count + toReview.count)
            chip("review", "Perlu review", toReview.count)
            chip("active", "Dikerjakan", mine.filter { $0.status == .inProgress }.count)
            chip("done", "Selesai", done)
          }.padding(.horizontal, 20)
        }
        VStack(alignment: .leading, spacing: 22) {
          if none {
            GLEmptyState(
              title: "Belum ada tugas",
              message:
                "Belum ada tugas yang ditugaskan ke kamu atau menunggu review kamu. Saat koordinator membagi tugas, semuanya muncul di sini.",
              systemImage: "checkmark.circle", tint: GLTheme.sky)
          } else {
            ForEach(sections, id: \.title) { section in
              VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                  Text(section.title.uppercased()).gl(14, .bold, em: 0.04).foregroundStyle(GLTheme.text2)
                  Text("\(section.items.count)").gl(14).foregroundStyle(GLTheme.secondary)
                }
                ForEach(section.items) { task in
                  NavigationLink(value: Route.task(task.id)) { GLTaskRow(task: task, showProject: true) }
                    .buttonStyle(GLCardButtonStyle())
                }
                if section.items.isEmpty {
                  Text("Tidak ada tugas di kategori ini.").gl(15).foregroundStyle(GLTheme.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 22)
                }
              }
            }
          }
        }.padding(.horizontal, 20)
      }.padding(.top, 10)
    }.glScreen().toolbar(.hidden, for: .navigationBar)
  }
  private func chip(_ key: String, _ label: String, _ n: Int) -> some View {
    let on = filter == key
    return Button {
      withAnimation(.easeOut(duration: 0.2)) { filter = key }
    } label: {
      HStack(spacing: 8) {
        Text(label).gl(15, .semibold)
        Text("\(n)").gl(13).foregroundStyle(GLTheme.ink).padding(.horizontal, 8)
          .frame(minWidth: 28, minHeight: 28).background(on ? GLTheme.mint : GLTheme.muted, in: Capsule())
      }
      .padding(.leading, 16).padding(.trailing, 7).frame(height: 44)
      .foregroundStyle(on ? .white : GLTheme.ink)
      .background(on ? GLTheme.ink : .white, in: Capsule())
      .overlay(Capsule().strokeBorder(GLTheme.ink, lineWidth: 1.5))
    }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
  }
}

// MARK: - Task detail (prototype `isTask`)

private enum TaskSheet: String, Identifiable {
  case actions, edit, reassign, submit, review
  var id: String { rawValue }
}

private enum TaskTab: Int { case overview, submission, discussion }

struct TaskDetailView: View {
  @Environment(DemoStore.self) private var store
  let taskID: String
  @State private var tab = TaskTab.overview
  @State private var sheet: TaskSheet?
  @State private var afterDismiss: (() -> Void)?
  @State private var confirm: GLConfirmation?
  @State private var refreshing = false
  private var task: GLTask? { store.task(taskID) }

  var body: some View {
    if let task, let project = store.project(task.projectID), store.isMember(groupID: project.groupID) {
      content(task, project)
    } else {
      GLAccessDenied()
    }
  }

  private func content(_ task: GLTask, _ project: GLProject) -> some View {
    let readOnly = project.status != .active
    return ScrollView {
      LazyVStack(alignment: .leading, spacing: 14, pinnedViews: [.sectionHeaders]) {
        GLDetailHeader("Tugas") {
          GLCircleButton(icon: "ellipsis", label: "Opsi tugas", iconSize: 24) { sheet = .actions }
        }.padding(.horizontal, 20)
        heading(task, project).padding(.horizontal, 22).padding(.top, 2)
        Section {
          switch tab {
          case .overview: overview(task, project).padding(.horizontal, 20)
          case .submission: submissions(task).padding(.horizontal, 20)
          case .discussion: discussion(task, project)
          }
        } header: {
          tabs(task, project).padding(.horizontal, 20)
        }
      }.padding(.top, 4).padding(.bottom, 16)
    }
    .overlay(alignment: .top) { GLTheme.background.frame(height: 0).ignoresSafeArea(edges: .top) }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if tab != .discussion {
        ctaBar(task, project)
      } else if readOnly {
        HStack(spacing: 8) {
          GLIcon("lock", size: 18)
          Text(project.status == .archived
            ? "Diskusi hanya-baca karena proyek diarsipkan."
            : "Diskusi hanya-baca karena proyek sudah selesai.").gl(14, .medium)
        }
        .foregroundStyle(GLTheme.text3).multilineTextAlignment(.center)
        .frame(maxWidth: .infinity).padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
        .background(GLTheme.background.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(GLTheme.border).frame(height: 1) }
        .accessibilityElement(children: .combine)
      } else {
        ChatComposer(groupID: project.groupID, taskID: taskID)
      }
    }
    .glDetailScreen()
    .sheet(item: $sheet, onDismiss: {
      let next = afterDismiss
      afterDismiss = nil
      next?()
    }) { which in
      switch which {
      case .actions: TaskActionsSheet(task: task, project: project) { pick in
          afterDismiss = {
            guard let task = store.task(taskID) else { return }
            switch pick {
            case .edit: openEdit(task, project)
            case .reassign: openReassign(task, project)
            case .reopen: reopen(task)
            }
          }
          sheet = nil
        }
      case .edit: TaskEditor(projectID: task.projectID, taskID: taskID)
      case .reassign: ReassignEditor(task: task) { confirm = $0 }
      case .submit: SubmissionEditor(task: task) { tab = .submission }
      case .review: ReviewEditor(task: task) { tab = .submission }
      }
    }
    .glConfirm($confirm)
  }

  // MARK: Heading & tabs

  private func heading(_ task: GLTask, _ project: GLProject) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 6) { chips(task) }
        VStack(alignment: .leading, spacing: 6) { chips(task) }
      }
      Text(task.title).gl(28, .bold, em: -0.03).fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)
      NavigationLink(value: Route.project(project.id)) {
        HStack(spacing: 2) {
          Text(project.title).gl(14).multilineTextAlignment(.leading)
          GLIcon("chevron.right", size: 18)
        }.foregroundStyle(GLTheme.text3).frame(minHeight: 36)
      }.buttonStyle(GLRowButtonStyle()).accessibilityHint("Buka proyek")
    }
  }

  @ViewBuilder private func chips(_ task: GLTask) -> some View {
    headerChip(task.status.label, task.status.icon, task.status.tint, outlined: false)
    if GLFormat.isOverdue(task.dueAt, status: task.status, now: store.now) {
      headerChip("Terlambat", "exclamationmark.circle", GLTheme.coral, outlined: true)
    }
    if let hours = store.reviewWaitHours(task), hours > 48 {
      headerChip("Menunggu \(hours) jam", "list.bullet.clipboard", GLTheme.lavender, outlined: true)
    }
  }

  private func headerChip(_ label: String, _ icon: String, _ bg: Color, outlined: Bool) -> some View {
    HStack(spacing: 5) {
      GLIcon(icon, size: 17)
      Text(label).gl(13, .semibold).lineLimit(1)
    }
    .padding(.leading, 9).padding(.trailing, 12).frame(height: 30)
    .background(bg, in: Capsule())
    .overlay { if outlined { Capsule().strokeBorder(GLTheme.ink, lineWidth: 1.5) } }
    .animation(.easeOut(duration: 0.3), value: bg)
  }

  private func tabs(_ task: GLTask, _ project: GLProject) -> some View {
    let items: [(TaskTab, String, Int)] = [
      (.overview, "Ringkasan", 0), (.submission, "Hasil kerja", task.submissions.count),
      (.discussion, "Diskusi", store.taskCommentCount(task)),
    ]
    return HStack(spacing: 2) {
      ForEach(items, id: \.0) { key, label, count in
        let on = tab == key
        Button {
          withAnimation(.easeOut(duration: 0.18)) { tab = key }
        } label: {
          HStack(spacing: 5) {
            Text(label).gl(14, .semibold).lineLimit(1).minimumScaleFactor(0.8)
            if count > 0 && key != .overview {
              Text("\(count)").gl(12, .semibold).padding(.horizontal, 6)
                .frame(minWidth: 20, minHeight: 20).background(GLTheme.lavender, in: Capsule())
            }
          }
          .padding(.horizontal, 4).frame(maxWidth: .infinity).frame(height: 44)
          .background {
            if on {
              RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white)
                .shadow(color: .black.opacity(0.08), radius: 1.5, y: 1)
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
        .accessibilityLabel(count > 0 && key != .overview ? "\(label), \(count)" : label)
      }
    }
    .padding(4)
    .background(Color(hex: "ECEEEB"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  // MARK: Overview tab

  private func overview(_ task: GLTask, _ project: GLProject) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      if task.status == .needsRevision, let last = task.submissions.last,
        let feedback = last.feedback, !feedback.isEmpty
      {
        VStack(alignment: .leading, spacing: 6) {
          HStack(spacing: 6) {
            GLIcon("arrow.uturn.backward", size: 18)
            Text("\(store.displayName(last.reviewerID ?? task.reviewerID)) meminta revisi").gl(14, .bold)
          }
          Text(feedback).gl(15).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 16).padding(.horizontal, 18).frame(maxWidth: .infinity, alignment: .leading)
        .background(GLTheme.coral, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
      }
      VStack(spacing: 0) {
        HStack(spacing: 12) {
          GLAvatar(user: store.user(task.assigneeID), size: 40, fontSize: 13)
          infoText("Pelaksana", store.displayName(task.assigneeID))
          if task.status != .done && project.status == .active {
            let open = store.isCoordinator(groupID: project.groupID) && task.status != .inReview
            Button { openReassign(task, project) } label: {
              HStack(spacing: 4) {
                GLIcon(open ? "arrow.left.arrow.right" : "lock", size: 18)
                Text("Alihkan").gl(14, .semibold)
              }
              .padding(.leading, 10).padding(.trailing, 12).frame(height: 44)
              .overlay(Capsule().strokeBorder(GLTheme.ink, lineWidth: 1.5)).contentShape(Capsule())
            }.buttonStyle(GLRowButtonStyle()).accessibilityLabel("Alihkan pelaksana")
          }
        }.padding(.vertical, 12)
        Rectangle().fill(GLTheme.border).frame(height: 1)
        HStack(spacing: 12) {
          GLAvatar(user: store.user(task.reviewerID), size: 40, fontSize: 13)
          infoText("Reviewer", store.displayName(task.reviewerID))
        }.padding(.vertical, 12)
        Rectangle().fill(GLTheme.border).frame(height: 1)
        HStack(spacing: 12) {
          GLIcon("clock", size: 20).frame(width: 40, height: 40).background(GLTheme.muted, in: Circle())
          infoText("Deadline", GLFormat.due(task.dueAt, status: task.status, now: store.now))
        }.padding(.vertical, 12)
      }
      .padding(.vertical, 4).padding(.horizontal, 18)
      .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
      VStack(alignment: .leading, spacing: 8) {
        Text("DESKRIPSI").gl(13, .bold, em: 0.04).foregroundStyle(GLTheme.text2)
        Text(task.description.isEmpty ? "Belum ada deskripsi." : task.description).gl(15)
          .lineSpacing(5).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
      }
      .padding(18).frame(maxWidth: .infinity, alignment: .leading)
      .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
      Button {
        withAnimation(.easeOut(duration: 0.18)) { tab = .discussion }
      } label: {
        HStack(spacing: 14) {
          GLIcon("bubble.left.and.bubble.right", size: 22).frame(width: 44, height: 44)
            .overlay(
              RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(GLTheme.ink, lineWidth: 1.5))
          VStack(alignment: .leading, spacing: 1) {
            Text("Diskusi tugas ini").gl(16, .semibold)
            Text("\(store.taskCommentCount(task)) komentar · khusus tugas ini").gl(13)
              .foregroundStyle(GLTheme.text3)
          }.frame(maxWidth: .infinity, alignment: .leading)
          GLIcon("chevron.right", size: 22)
        }
        .padding(.vertical, 16).padding(.horizontal, 18)
        .background(GLTheme.lavender, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .multilineTextAlignment(.leading)
      }.buttonStyle(GLCardButtonStyle()).accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
  }

  private func infoText(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(label).gl(13).foregroundStyle(GLTheme.secondary)
      Text(value).gl(16, .semibold)
    }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
  }

  // MARK: Submission tab

  private func submissions(_ task: GLTask) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(task.submissions.reversed()) { sub in submissionCard(sub, task) }
      if task.submissions.isEmpty {
        VStack(spacing: 8) {
          GLIcon("archivebox", size: 26).frame(width: 52, height: 52)
            .background(GLTheme.butter, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
          Text("Belum ada hasil kerja").gl(17, .semibold)
          Text("Pelaksana mengirim catatan dan maksimal 5 link https. Semua revisi tersimpan di sini.")
            .gl(14).lineSpacing(4).foregroundStyle(GLTheme.secondary)
        }
        .multilineTextAlignment(.center).frame(maxWidth: .infinity)
        .padding(.vertical, 28).padding(.horizontal, 20)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
      }
    }
  }

  private func submissionCard(_ sub: GLSubmission, _ task: GLTask) -> some View {
    let pending = sub.decision == nil && sub.revision == task.submissions.count && task.status == .inReview
    let chip: (String, String, Color) =
      sub.decision == "approved"
      ? ("Disetujui", "checkmark.circle", GLTheme.mint)
      : sub.decision != nil
        ? ("Perlu revisi", "arrow.uturn.backward", GLTheme.coral)
        : (pending ? "Menunggu review" : "Terkirim", "eye", GLTheme.lavender)
    let mine = task.assigneeID == store.currentUserID
    return VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 1) {
          Text("Revisi \(sub.revision)").gl(16, .bold)
          Text("\(store.displayName(sub.authorID)) · \(store.taskStamp(sub.createdAt))").gl(13)
            .foregroundStyle(GLTheme.secondary)
        }
        Spacer(minLength: 0)
        GLChip(label: chip.0, icon: chip.1, background: chip.2, fontSize: 12)
      }
      Text(sub.note).gl(15).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
      ForEach(sub.links, id: \.self) { TaskLinkRow(url: $0, external: true) }
      if let feedback = sub.feedback, !feedback.isEmpty {
        VStack(alignment: .leading, spacing: 4) {
          Text("Catatan \(store.displayName(sub.reviewerID ?? task.reviewerID))").gl(13, .semibold)
            .foregroundStyle(GLTheme.secondary)
          Text(feedback).gl(15).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12).frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(GLTheme.border).frame(height: 1) }
      }
      if pending && task.reviewerID != store.currentUserID {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 10) { lockText(task, mine); lockButton(task) }
          VStack(alignment: .leading, spacing: 10) { lockText(task, mine); lockButton(task) }
        }
        .padding(.top, 12).frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(GLTheme.border).frame(height: 1) }
      }
    }
    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
    .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
  }

  private func lockText(_ task: GLTask, _ mine: Bool) -> some View {
    Text(mine
      ? "Kamu tidak bisa menyetujui hasil kerjamu sendiri."
      : "Hanya \(store.displayName(task.reviewerID)) yang bisa mereview.")
      .gl(13).lineSpacing(2).foregroundStyle(GLTheme.text3)
      .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func lockButton(_ task: GLTask) -> some View {
    Button { lockedApprove(task) } label: {
      HStack(spacing: 4) {
        GLIcon("lock", size: 18)
        Text("Setujui").gl(14, .semibold)
      }
      .foregroundStyle(GLTheme.text2)
      .padding(.leading, 10).padding(.trailing, 14).frame(height: 44)
      .overlay(
        Capsule().strokeBorder(Color(hex: "9AA0A6"), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
      .contentShape(Capsule())
    }.buttonStyle(GLRowButtonStyle()).fixedSize().accessibilityLabel("Setujui, terkunci")
  }

  // MARK: Discussion tab

  private func discussion(_ task: GLTask, _ project: GLProject) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        Text("Komentar di sini hanya untuk tugas ini. Tekan lama pesan untuk opsi.").gl(13)
          .lineSpacing(2).foregroundStyle(GLTheme.secondary).fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
        Button { refresh() } label: {
          HStack(spacing: 5) {
            GLIcon("arrow.clockwise", size: 18)
              .rotationEffect(.degrees(refreshing ? 360 : 0))
              .animation(
                refreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                value: refreshing)
            Text(refreshing ? "Memuat…" : "Muat ulang").gl(13, .semibold)
          }
          .padding(.horizontal, 12).frame(height: 44)
          .background { Capsule().fill(.white).shadow(color: .black.opacity(0.06), radius: 1, y: 1) }
        }.buttonStyle(.plain).fixedSize().accessibilityLabel("Muat ulang komentar")
      }.padding(.horizontal, 20)
      ChatThread(groupID: project.groupID, taskID: task.id)
    }
  }

  private func refresh() {
    guard !refreshing else { return }
    refreshing = true
    Task {
      await store.refreshFromBackend()
      refreshing = false
      if store.backendError != nil {
        store.flash("Gagal memuat ulang. Kamu sedang offline.", .err)
      } else {
        store.flash("Komentar sudah terbaru")
      }
    }
  }

  // MARK: CTA bar (prototype `hasCtaBar`)

  @ViewBuilder private func ctaBar(_ task: GLTask, _ project: GLProject) -> some View {
    let cta = ctaAction(task, project)
    VStack {
      if let cta {
        GLPrimaryButton(title: cta.label, systemImage: cta.icon, action: cta.run)
          .shadow(color: .black.opacity(0.22), radius: 12, y: 12)
          // Identifiers keep the existing UI tests ("Mulai Kerjakan", "Kirim Hasil", "open-review").
          .accessibilityIdentifier(cta.id)
      } else {
        let info = infoLine(task, project)
        HStack(spacing: 8) {
          GLIcon(info.icon, size: 20)
          Text(info.text).gl(15, .medium)
        }
        .multilineTextAlignment(.center)
        .padding(.vertical, 8).padding(.horizontal, 16)
        .frame(maxWidth: .infinity).frame(minHeight: 54)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(GLTheme.border))
        .accessibilityElement(children: .combine)
      }
    }
    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 4)
    .background {
      LinearGradient(
        stops: [.init(color: GLTheme.background.opacity(0), location: 0), .init(color: GLTheme.background, location: 0.28)],
        startPoint: .top, endPoint: .bottom
      ).ignoresSafeArea(edges: .bottom)
    }
    .transition(.move(edge: .bottom).combined(with: .opacity))
  }

  private func ctaAction(_ task: GLTask, _ project: GLProject)
    -> (label: String, icon: String, id: String, run: () -> Void)?
  {
    guard project.status == .active else { return nil }
    let me = store.currentUserID
    if task.assigneeID == me {
      switch task.status {
      case .todo: return ("Mulai kerjakan", "play.fill", "Mulai Kerjakan", { start(task) })
      case .inProgress: return ("Kirim hasil", "square.and.arrow.up", "Kirim Hasil", { sheet = .submit })
      case .needsRevision: return ("Kirim revisi", "square.and.arrow.up", "Kirim Hasil", { sheet = .submit })
      default: break
      }
    }
    if task.reviewerID == me && task.status == .inReview {
      return ("Review revisi \(task.submissions.count)", "square.and.pencil", "open-review", { sheet = .review })
    }
    return nil
  }

  private func infoLine(_ task: GLTask, _ project: GLProject) -> (text: String, icon: String) {
    if project.status == .archived { return ("Proyek diarsipkan · tugas hanya bisa dilihat", "archivebox") }
    if project.status == .completed { return ("Proyek selesai · tugas hanya bisa dilihat", "checkmark.circle") }
    switch task.status {
    case .done:
      let by = task.submissions.last?.reviewerID.map { store.displayName($0).replacingOccurrences(of: "Kamu", with: "kamu") }
      return ("Disetujui oleh " + (by ?? "reviewer"), "checkmark.circle")
    case .inReview: return ("Menunggu review dari " + store.displayName(task.reviewerID), "hourglass")
    case .needsRevision: return ("Menunggu revisi dari " + store.displayName(task.assigneeID), "hourglass")
    case .inProgress: return ("Sedang dikerjakan " + store.displayName(task.assigneeID), "arrow.triangle.2.circlepath")
    case .todo: return ("Belum dimulai oleh " + store.displayName(task.assigneeID), "hourglass")
    }
  }

  // MARK: Actions

  private func start(_ task: GLTask) {
    Task {
      do {
        try await store.startTask(task.id)
        store.flash("Tugas dimulai. Semangat!")
      } catch { store.flash(error.localizedDescription, .err) }
    }
  }

  private func lockedApprove(_ task: GLTask) {
    let reviewer = store.user(task.reviewerID)?.name ?? "Reviewer"
    store.flash(
      task.assigneeID == store.currentUserID
        ? "Kamu tidak bisa menyetujui hasil kerjamu sendiri. \(reviewer) yang akan mereview."
        : "Hanya \(reviewer) (reviewer) yang bisa menyetujui tugas ini.", .err)
  }

  private func openReassign(_ task: GLTask, _ project: GLProject) {
    if let lock = store.taskProjectLock(project) { return store.flash(lock, .err) }
    guard store.isCoordinator(groupID: project.groupID) else {
      return store.flash("Hanya koordinator yang bisa mengalihkan tugas.", .err)
    }
    if task.status == .inReview {
      confirm = GLConfirmation(
        title: "Sedang Menunggu Review",
        text: "Tugas ini tidak dapat dialihkan karena hasil pekerjaan sedang diperiksa. Selesaikan atau batalkan proses review terlebih dahulu.",
        ok: "Mengerti", info: true)
    } else if task.status == .done {
      confirm = GLConfirmation(
        title: "Tugas sudah selesai", text: "Tugas yang sudah disetujui tidak bisa dialihkan.", ok: "Mengerti",
        info: true)
    } else {
      sheet = .reassign
    }
  }

  private func openEdit(_ task: GLTask, _ project: GLProject) {
    if let lock = store.taskEditLock(task) {
      confirm = GLConfirmation(title: lock.title, text: lock.text, ok: "Mengerti", info: true)
    } else {
      sheet = .edit
    }
  }

  private func reopen(_ task: GLTask) {
    confirm = GLConfirmation(
      title: "Buka kembali tugas?", text: "Riwayat hasil dan keputusan review tetap disimpan.",
      ok: "Buka kembali"
    ) {
      Task {
        do {
          try await store.reopenTask(task.id)
          store.flash("Tugas dibuka kembali")
        } catch { store.flash(error.localizedDescription, .err) }
      }
    }
  }
}

// MARK: - Shared sheet pieces

/// Link pill used in submission cards and the review sheet.
private struct TaskLinkRow: View {
  let url: String
  var external = false
  var body: some View {
    let label = HStack(spacing: 8) {
      GLIcon("link", size: 18)
      Text(url.replacingOccurrences(of: "https://", with: "")).gl(14, .medium).lineLimit(1)
        .truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
      if external { GLIcon("arrow.up.right.square", size: 17).foregroundStyle(GLTheme.secondary) }
    }
    .padding(.horizontal, 12).frame(minHeight: 44)
    .background(GLTheme.muted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    if external, let link = URL(string: url), link.scheme == "https" {
      Link(destination: link) { label }.buttonStyle(GLRowButtonStyle())
        .accessibilityLabel("Buka tautan \(url)")
    } else {
      label
    }
  }
}

/// Multiline input box (`textarea`): white, 1pt border.
private struct TaskTextArea: View {
  let placeholder: String
  @Binding var text: String
  var rows = 3
  var radius: CGFloat = 16
  var vertical: CGFloat = 12
  var body: some View {
    TextField(placeholder, text: $text, axis: .vertical).gl(16).lineLimit(rows...max(rows, 10))
      .padding(.horizontal, 16).padding(.vertical, vertical)
      .background(.white, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(GLTheme.border))
  }
}

/// Member pick chip (prototype `ntAssignees` / `ntReviewers`).
private struct TaskMemberChip: View {
  @Environment(DemoStore.self) private var store
  let id: String
  let on: Bool
  var dimmed = false
  let pick: () -> Void
  var body: some View {
    Button(action: pick) {
      HStack(spacing: 7) {
        GLAvatar(user: store.user(id), size: 32, fontSize: 11).foregroundStyle(GLTheme.ink)
        Text(store.displayName(id)).gl(14, .semibold)
      }
      .padding(.leading, 5).padding(.trailing, 14).frame(height: 44)
      .foregroundStyle(on ? .white : GLTheme.ink)
      .background(on ? GLTheme.ink : .white, in: Capsule())
      .overlay(Capsule().strokeBorder(GLTheme.ink, lineWidth: 1.5))
      .opacity(dimmed ? 0.4 : 1)
      .animation(.easeOut(duration: 0.15), value: on)
    }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
  }
}

/// Wrapping row (`flex-wrap:wrap`).
private struct TaskFlowLayout: Layout {
  var spacing: CGFloat = 8
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = arrange(proposal.width ?? .infinity, subviews)
    return CGSize(width: proposal.width ?? rows.width, height: rows.height)
  }
  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for (i, p) in arrange(bounds.width, subviews).points.enumerated() {
      subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
    }
  }
  private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (points: [CGPoint], width: CGFloat, height: CGFloat) {
    var points: [CGPoint] = []
    var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxW: CGFloat = 0
    for v in subviews {
      let s = v.sizeThatFits(.unspecified)
      if x > 0 && x + s.width > width {
        x = 0
        y += rowH + spacing
        rowH = 0
      }
      points.append(CGPoint(x: x, y: y))
      x += s.width + spacing
      rowH = max(rowH, s.height)
      maxW = max(maxW, x - spacing)
    }
    return (points, maxW, y + rowH)
  }
}

/// "Proyek" card on the new/edit task sheets.
private struct TaskProjectCard: View {
  let title: String
  let sub: String
  var body: some View {
    HStack(spacing: 10) {
      GLIcon("folder", size: 20)
      VStack(alignment: .leading, spacing: 0) {
        Text(title).gl(15, .semibold)
        Text(sub).gl(13).foregroundStyle(GLTheme.secondary)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 12).padding(.horizontal, 14)
    .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(GLTheme.border))
    .accessibilityElement(children: .combine)
  }
}

/// Deadline block: quick picks, date field, label and the project-deadline warning.
private struct TaskDeadlineField: View {
  @Binding var date: Date
  let projectDue: Date?
  var minimum: Date
  var body: some View {
    let cal = Calendar.current
    VStack(alignment: .leading, spacing: 8) {
      (Text("Deadline") + Text(" *").foregroundColor(GLTheme.danger)).gl(14, .semibold)
      HStack(spacing: 8) {
        ForEach([(1, "Besok"), (3, "3 hari lagi"), (7, "Minggu depan")], id: \.0) { days, label in
          let value = DemoStore.taskEndOfDay(cal.date(byAdding: .day, value: days, to: .now) ?? .now)
          let on = cal.isDate(value, inSameDayAs: date)
          Button { date = value } label: {
            Text(label).gl(14, .semibold).lineLimit(1).minimumScaleFactor(0.8)
              .frame(maxWidth: .infinity).frame(height: 44)
              .foregroundStyle(on ? .white : GLTheme.ink)
              .background(on ? GLTheme.ink : .white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
              .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(GLTheme.ink, lineWidth: 1.5))
          }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
        }
      }
      HStack(spacing: 10) {
        GLIcon("calendar", size: 20)
        DatePicker(
          "Pilih tanggal deadline",
          selection: Binding(get: { date }, set: { date = DemoStore.taskEndOfDay($0) }),
          in: minimum...(cal.date(from: DateComponents(year: 2027, month: 12, day: 31)) ?? .distantFuture),
          displayedComponents: .date
        ).labelsHidden().tint(GLTheme.ink)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 14).frame(height: 50)
      .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(GLTheme.border))
      Text("\(GLFormat.weekday(date)), \(GLFormat.date(date)) · 23:59").gl(13).foregroundStyle(GLTheme.secondary)
      if let projectDue, cal.startOfDay(for: date) > cal.startOfDay(for: projectDue) {
        HStack(alignment: .top, spacing: 8) {
          GLIcon("exclamationmark.triangle", size: 18)
          Text(
            "Deadline tugas melewati deadline proyek (\(GLFormat.date(projectDue))). Tetap bisa disimpan, pastikan ini disengaja."
          ).gl(14).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12).padding(.horizontal, 14).frame(maxWidth: .infinity, alignment: .leading)
        .background(GLTheme.butter, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      }
    }
  }
}

/// Labeled field with a right-aligned character count (prototype `counts.*`).
private struct TaskCountedLabel: View {
  let label: String
  var required = false
  let count: String
  var body: some View {
    HStack {
      (Text(label) + Text(required ? " *" : "").foregroundColor(GLTheme.danger)).gl(14, .semibold)
      Spacer(minLength: 0)
      Text(count).gl(14).foregroundStyle(GLTheme.secondary)
    }
  }
}

// MARK: - Task actions sheet (prototype `sheetTaskActions`)

private struct TaskActionsSheet: View {
  @Environment(DemoStore.self) private var store
  let task: GLTask
  let project: GLProject
  /// Closes this sheet, then runs the follow-up (opening another sheet or dialog).
  enum Pick { case edit, reassign, reopen }
  let then: (Pick) -> Void
  var body: some View {
    let coord = store.isCoordinator(groupID: project.groupID)
    let lock = store.taskEditLock(task)
    let reassignOpen = coord && task.status != .inReview && task.status != .done && project.status == .active
    GLSheet("Opsi tugas") {
      VStack(spacing: 0) {
        row(
          "Edit tugas", lock?.title ?? "Judul, deskripsi, deadline, reviewer", lock == nil ? "pencil" : "lock"
        ) { then(.edit) }
        row(
          "Alihkan pelaksana",
          !coord
            ? "Khusus koordinator"
            : task.status == .inReview
              ? "Terkunci selama review"
              : task.status == .done
                ? "Tugas sudah selesai" : project.status != .active ? "Proyek tidak aktif" : "Pilih anggota lain",
          reassignOpen ? "arrow.left.arrow.right" : "lock"
        ) { then(.reassign) }
        ShareLink(item: shareText) {
          rowLabel("Bagikan tugas", "Kirim tautan ke WhatsApp", "square.and.arrow.up")
        }.buttonStyle(GLRowButtonStyle())
        if coord && task.status == .done && project.status == .active {
          if task.assigneeID.isEmpty || task.reviewerID.isEmpty {
            GLNotice(text: "Pelaksana atau reviewer telah menghapus akun. Buat tugas pengganti; riwayat ini tetap disimpan.", icon: "person.crop.circle.badge.minus")
          } else {
            row("Buka kembali tugas", "Riwayat hasil dan review tetap disimpan", "arrow.counterclockwise") {
              then(.reopen)
            }
          }
        }
      }
      .padding(.vertical, 4).padding(.horizontal, 16)
      .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
  }
  private var shareText: String {
    "\(task.title) · \(task.status.label)\ngrouply://task/\(task.id)\n"
      + "Buka dengan GROUPLY menggunakan akun anggota grup."
  }
  private func row(_ label: String, _ sub: String, _ icon: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { rowLabel(label, sub, icon) }.buttonStyle(GLRowButtonStyle())
  }
  private func rowLabel(_ label: String, _ sub: String, _ icon: String) -> some View {
    HStack(spacing: 12) {
      GLIcon(icon, size: 22)
      VStack(alignment: .leading, spacing: 0) {
        Text(label).gl(16, .semibold)
        Text(sub).gl(13).foregroundStyle(GLTheme.secondary)
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
    .multilineTextAlignment(.leading).padding(.vertical, 8).frame(minHeight: 62)
    .overlay(alignment: .bottom) { Rectangle().fill(GLTheme.border).frame(height: 1) }
    .foregroundStyle(GLTheme.ink).accessibilityElement(children: .combine)
  }
}

// MARK: - New / edit task sheet (prototype `sheetNewTask` / `sheetEditTask`)

struct TaskEditor: View {
  @Environment(DemoStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let projectID: String
  var taskID: String? = nil
  @State private var title = ""
  @State private var description = ""
  @State private var dueAt = DemoStore.taskEndOfDay(Calendar.current.date(byAdding: .day, value: 3, to: .now) ?? .now)
  @State private var originalDue: Date?
  @State private var assigneeID: String?
  @State private var reviewerID: String?
  @State private var version = 0
  @State private var error: String?
  @State private var busy = false
  private var project: GLProject? { store.project(projectID) }
  private var members: [String] {
    project.flatMap { store.group($0.groupID)?.memberIDs } ?? []
  }
  private var editing: GLTask? { taskID.flatMap(store.task) }
  private var minimum: Date {
    let today = Calendar.current.startOfDay(for: .now)
    return min(today, originalDue.map { Calendar.current.startOfDay(for: $0) } ?? today)
  }

  var body: some View {
    GLSheet(taskID == nil ? "Buat tugas" : "Edit tugas") {
      if let task = editing {
        TaskProjectCard(
          title: project?.title ?? "",
          sub: "\(task.status.label) · Pelaksana: \(store.displayName(task.assigneeID)) (ubah lewat Alihkan pelaksana)")
        if task.status == .needsRevision {
          HStack(alignment: .top, spacing: 6) {
            GLIcon("clock.arrow.circlepath", size: 17)
            Text("Riwayat hasil kerja dan review tetap tersimpan.").gl(13).lineSpacing(3)
          }.foregroundStyle(GLTheme.text3)
        }
      } else if let project {
        TaskProjectCard(
          title: project.title,
          sub: "Deadline proyek \(GLFormat.weekday(project.dueAt)), \(GLFormat.date(project.dueAt))")
      }
      VStack(alignment: .leading, spacing: 6) {
        TaskCountedLabel(label: "Judul", required: true, count: "\(title.count)/120")
        TextField(taskID == nil ? "Contoh: Buat use case diagram" : "", text: $title).gl(16)
          .glInput().accessibilityIdentifier("task-title").accessibilityLabel("Judul tugas")
          .onChange(of: title) { _, v in if v.count > 120 { title = String(v.prefix(120)) } }
      }
      VStack(alignment: .leading, spacing: 6) {
        TaskCountedLabel(label: "Deskripsi", count: "\(description.count)/2000")
        TaskTextArea(
          placeholder: "Jelaskan apa yang perlu dikerjakan dan hasil yang diharapkan...", text: $description,
          rows: taskID == nil ? 3 : 4
        ).accessibilityLabel("Deskripsi tugas")
          .onChange(of: description) { _, v in if v.count > 2000 { description = String(v.prefix(2000)) } }
      }
      if taskID == nil {
        memberPicker("Pelaksana", selected: assigneeID, dimmed: { _ in false }) { id in
          assigneeID = id
          if reviewerID == id { reviewerID = nil }
          error = nil
        }
        memberPicker("Reviewer", selected: reviewerID, dimmed: { $0 == assigneeID }) { id in
          if id == assigneeID { error = "Pelaksana dan reviewer harus orang berbeda." } else { reviewerID = id; error = nil }
        }
        TaskDeadlineField(date: $dueAt, projectDue: project?.dueAt, minimum: minimum)
      } else {
        TaskDeadlineField(date: $dueAt, projectDue: project?.dueAt, minimum: minimum)
        memberPicker("Reviewer", selected: reviewerID, dimmed: { $0 == editing?.assigneeID }) { id in
          if id == editing?.assigneeID { error = "Reviewer harus berbeda dari pelaksana." } else { reviewerID = id; error = nil }
        }
      }
      if let error { GLFormError(text: error).accessibilityIdentifier("form-error") }
      if taskID == nil {
        GLSubmitButton(title: busy ? "Menyimpan…" : retry ? "Coba lagi" : "Buat tugas", busy: busy) { save() }
      } else {
        HStack(spacing: 10) {
          Button { dismiss() } label: {
            Text("Batal").gl(16, .semibold).frame(maxWidth: .infinity).frame(height: 56)
              .background(Color(hex: "ECEEEB"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
          }.buttonStyle(.plain)
          Button { save() } label: {
            Text(busy ? "Menyimpan…" : retry ? "Coba lagi" : "Simpan perubahan").gl(16, .semibold)
              .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 56)
              .background(GLTheme.ink, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
              .opacity(busy ? 0.6 : 1)
          }.buttonStyle(.plain).disabled(busy).layoutPriority(1)
            .containerRelativeFrame(.horizontal) { w, _ in (w - 40 - 10) * 2 / 3 }
        }
      }
    }
    .interactiveDismissDisabled(busy)
    .onAppear(perform: load)
  }

  private var retry: Bool { error?.contains("Gagal") == true }

  private func memberPicker(
    _ label: String, selected: String?, dimmed: @escaping (String) -> Bool, pick: @escaping (String) -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      (Text(label) + Text(" *").foregroundColor(GLTheme.danger)).gl(14, .semibold)
      TaskFlowLayout {
        ForEach(members, id: \.self) { id in
          TaskMemberChip(id: id, on: selected == id, dimmed: dimmed(id)) { pick(id) }
        }
      }
    }
  }

  private func load() {
    guard let t = editing, originalDue == nil else { return }
    title = t.title
    description = t.description
    dueAt = t.dueAt
    originalDue = t.dueAt
    assigneeID = t.assigneeID
    reviewerID = t.reviewerID
    version = t.version
  }

  private func save() {
    let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
      .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    let desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
    if let t = editing {
      if let lock = store.taskEditLock(t) { return error = lock.text }
      if cleanTitle.isEmpty { return error = "Judul tugas wajib diisi." }
      if cleanTitle.count > 120 { return error = "Judul tugas maksimal 120 karakter." }
      if desc.count > 2000 { return error = "Deskripsi maksimal 2000 karakter." }
      guard let r = reviewerID, members.contains(r) else { return error = "Reviewer harus anggota aktif grup." }
      if r == t.assigneeID { return error = "Reviewer harus berbeda dari pelaksana." }
      let sameDay = Calendar.current.isDate(dueAt, inSameDayAs: t.dueAt)
      if cleanTitle == t.title && desc == t.description && sameDay && r == t.reviewerID {
        dismiss()
        return store.flash("Tidak ada perubahan", .info)
      }
      run {
        try await store.updateTask(
          id: t.id, title: cleanTitle, description: desc, reviewerID: r, dueAt: sameDay ? t.dueAt : dueAt,
          expectedVersion: version)
        store.flash("Tugas diperbarui")
      }
    } else {
      if cleanTitle.count < 3 { return error = "Judul tugas minimal 3 karakter." }
      if cleanTitle.count > 120 { return error = "Judul tugas maksimal 120 karakter." }
      if desc.count > 2000 { return error = "Deskripsi maksimal 2000 karakter." }
      if let project, let lock = store.taskProjectLock(project, verb: "menambah tugas") { return error = lock }
      guard let a = assigneeID else { return error = "Pilih pelaksana tugas." }
      guard let r = reviewerID else { return error = "Pilih reviewer tugas." }
      if a == r { return error = "Pelaksana dan reviewer harus orang berbeda." }
      run {
        _ = try await store.createTask(
          projectID: projectID, title: cleanTitle, description: desc, assigneeID: a, reviewerID: r, dueAt: dueAt)
        store.flash(
          "Tugas dibuat. "
            + (a == store.currentUserID ? "Ditugaskan ke kamu." : "\(store.user(a)?.name ?? "Anggota") akan diberi tahu."))
      }
    }
  }

  private func run(_ action: @escaping () async throws -> Void) {
    busy = true
    error = nil
    Task {
      defer { busy = false }
      do {
        try await action()
        dismiss()
      } catch { self.error = error.localizedDescription }
    }
  }
}

// MARK: - Reassign sheet (prototype `sheetReassign`)

struct ReassignEditor: View {
  @Environment(DemoStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let task: GLTask
  /// Presents the needs-revision confirmation after the sheet closes; nil = reassign directly.
  var ask: ((GLConfirmation) -> Void)? = nil
  @State private var newAssignee: String?
  @State private var error: String?
  private var group: GLGroup? { store.project(task.projectID).flatMap { store.group($0.groupID) } }

  var body: some View {
    let members = group?.memberIDs ?? []
    GLSheet(newAssignee == nil ? "Alihkan pelaksana" : "Pilih reviewer baru") {
      VStack(spacing: 0) {
        if let newA = newAssignee {
          ForEach(members.filter { $0 != newA }, id: \.self) { id in
            row(id, sub: id == group?.coordinatorID ? "Koordinator" : "Anggota", current: false) {
              apply(newA, reviewer: id)
            }
          }
        } else {
          ForEach(members, id: \.self) { id in
            row(
              id,
              sub: id == task.reviewerID
                ? "Reviewer saat ini · perlu reviewer pengganti"
                : id == task.assigneeID
                  ? "Pelaksana saat ini" : id == group?.coordinatorID ? "Koordinator" : "Anggota",
              current: id == task.assigneeID
            ) { pick(id) }
          }
        }
      }
      .padding(.vertical, 4).padding(.horizontal, 14)
      .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
      if let error { GLFormError(text: error) }
      Text(
        newAssignee.map {
          "\(store.user($0)?.name ?? "Anggota") saat ini reviewer tugas ini. Pilih reviewer lain supaya pelaksana dan reviewer tetap berbeda."
        }
          ?? (task.status == .needsRevision
            ? "Tugas ini punya riwayat revisi. Hasil kerja dan catatan review sebelumnya tetap tersimpan untuk pelaksana baru."
            : "Status tugas tidak berubah. Riwayat pesan dan hasil kerja tetap tersimpan.")
      ).gl(13).lineSpacing(3).foregroundStyle(GLTheme.text3).fixedSize(horizontal: false, vertical: true)
    }
  }

  private func row(_ id: String, sub: String, current: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        GLAvatar(user: store.user(id), size: 40, fontSize: 13)
        VStack(alignment: .leading, spacing: 0) {
          Text(store.displayName(id)).gl(16, .semibold)
          Text(sub).gl(13).foregroundStyle(GLTheme.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
        if current { GLIcon("checkmark", size: 22) }
      }
      .multilineTextAlignment(.leading).padding(.vertical, 8).frame(minHeight: 60)
      .overlay(alignment: .bottom) { Rectangle().fill(GLTheme.border).frame(height: 1) }
    }
    .buttonStyle(GLRowButtonStyle()).accessibilityElement(children: .combine)
    .accessibilityAddTraits(current ? .isSelected : [])
  }

  private func pick(_ id: String) {
    guard let group, store.isCoordinator(groupID: group.id) else {
      return error = "Hanya koordinator yang bisa mengalihkan tugas."
    }
    if id == task.assigneeID { return dismiss() }
    if id == task.reviewerID {
      error = nil
      return withAnimation(.easeOut(duration: 0.2)) { newAssignee = id }
    }
    apply(id, reviewer: nil)
  }

  private func apply(_ assignee: String, reviewer: String?) {
    if reviewer == assignee { return error = "Reviewer harus berbeda dari pelaksana." }
    let store = store
    let task = task
    let run = {
      Task {
        do {
          try await store.reassignTask(
            id: task.id, assigneeID: assignee, reviewerID: reviewer ?? task.reviewerID,
            expectedVersion: task.version)
          store.flash(
            "Pelaksana diganti ke \(store.user(assignee)?.name ?? "Anggota")"
              + (reviewer.map { " · reviewer \(store.user($0)?.name ?? "Anggota")" } ?? ""))
        } catch { store.flash(error.localizedDescription, .err) }
      }
    }
    dismiss()
    if task.status == .needsRevision, let ask {
      ask(
        GLConfirmation(
          title: "Alihkan tugas revisi?",
          text: "Tugas ini memiliki riwayat revisi. Pelaksana baru akan melanjutkan pekerjaan tanpa menghapus hasil sebelumnya.",
          ok: "Alihkan", run: { _ = run() }))
    } else {
      _ = run()
    }
  }
}

// MARK: - Submit sheet (prototype `sheetSubmit`)

struct SubmissionEditor: View {
  @Environment(DemoStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let task: GLTask
  var onDone: () -> Void = {}
  @State private var note = ""
  @State private var links = [""]
  @State private var error: String?
  @State private var busy = false

  var body: some View {
    GLSheet(
      task.status == .needsRevision ? "Kirim revisi" : "Kirim hasil",
      subtitle: "\(task.title) · \(store.user(task.reviewerID)?.name ?? "Reviewer") akan diberi tahu untuk mereview."
    ) {
      GLField("Apa yang kamu kerjakan?", required: true) {
        TaskTextArea(
          placeholder: "Contoh: Tabel sudah 3NF, alasan dekomposisi ada di halaman 2.", text: $note, rows: 4,
          radius: 18, vertical: 14
        )
        .accessibilityIdentifier("submission-note").accessibilityLabel("Apa yang kamu kerjakan?")
        .onChange(of: note) { _, v in if v.count > 1000 { note = String(v.prefix(1000)) } }
      }
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Link (opsional)").gl(14, .semibold)
          Spacer(minLength: 0)
          Text("\(links.count)/5").gl(13).foregroundStyle(GLTheme.secondary)
        }
        ForEach(links.indices, id: \.self) { i in
          HStack(spacing: 8) {
            GLIcon("link", size: 18).foregroundStyle(GLTheme.secondary)
            TextField("https://docs.google.com/…", text: $links[i]).gl(16)
              .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
              .accessibilityLabel("Link hasil kerja")
              .onChange(of: links[i]) { _, _ in error = nil }
          }
          .padding(.horizontal, 14).frame(height: 48)
          .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(GLTheme.border))
        }
        if links.count < 5 {
          Button { links.append("") } label: {
            HStack(spacing: 4) {
              GLIcon("plus", size: 20)
              Text("Tambah link").gl(15, .semibold)
            }.frame(height: 44)
          }.buttonStyle(GLRowButtonStyle())
        }
      }
      if let error { GLFormError(text: error) }
      GLSubmitButton(
        title: busy ? "Mengirim…" : error?.contains("Gagal") == true ? "Coba lagi" : "Kirim untuk direview",
        busy: busy
      ) { submit() }
      .accessibilityIdentifier("submit-work")
    }
    .interactiveDismissDisabled(busy)
  }

  private func submit() {
    let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
    let clean = links.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    if text.isEmpty { return error = "Tulis catatan singkat tentang yang kamu kerjakan." }
    if text.count > 1000 { return error = "Catatan maksimal 1000 karakter." }
    if clean.contains(where: { $0.range(of: #"^https://[^\s]+\.[^\s]+"#, options: .regularExpression) == nil }) {
      return error = "Link harus diawali https:// dan berupa alamat lengkap."
    }
    busy = true
    error = nil
    Task {
      defer { busy = false }
      do {
        try await store.submitWork(taskID: task.id, note: text, links: clean, expectedVersion: task.version)
        store.flash("Terkirim. \(store.user(task.reviewerID)?.name ?? "Reviewer") akan diberi tahu.")
        onDone()
        dismiss()
      } catch { self.error = error.localizedDescription }
    }
  }
}

// MARK: - Review sheet (prototype `sheetReview`)

struct ReviewEditor: View {
  @Environment(DemoStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let task: GLTask
  var onDone: () -> Void = {}
  @State private var changes = false
  @State private var feedback = ""
  @State private var error: String?
  @State private var pending: Bool?

  var body: some View {
    let busy = pending != nil
    GLSheet("Review hasil kerja") {
      if let sub = task.submissions.last {
        VStack(alignment: .leading, spacing: 10) {
          Text("Revisi \(sub.revision) · \(store.displayName(sub.authorID)) · \(store.taskStamp(sub.createdAt))")
            .gl(13, .semibold).foregroundStyle(GLTheme.secondary)
          Text(sub.note).gl(15).lineSpacing(4).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
          ForEach(sub.links, id: \.self) { TaskLinkRow(url: $0, external: true) }
        }
        .padding(.vertical, 16).padding(.horizontal, 18).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
      }
      if let error { GLFormError(text: error) }
      if changes {
        VStack(alignment: .leading, spacing: 10) {
          (Text("Apa yang perlu diubah?") + Text(" *").foregroundColor(GLTheme.danger)).gl(14, .semibold)
          TaskTextArea(
            placeholder: "Spesifik dan ramah, misal: pisahkan Fine jadi entity sendiri.", text: $feedback,
            radius: 18, vertical: 14
          )
          .accessibilityIdentifier("review-feedback").accessibilityLabel("Apa yang perlu diubah?")
          .onChange(of: feedback) { _, v in if v.count > 1000 { feedback = String(v.prefix(1000)) } }
          HStack(spacing: 10) {
            Button {
              withAnimation(.easeOut(duration: 0.2)) { changes = false }
              error = nil
            } label: {
              Text("Kembali").gl(16, .semibold).frame(maxWidth: .infinity).frame(height: 54)
                .background(Color(hex: "ECEEEB"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }.buttonStyle(.plain)
            Button { decide(false) } label: {
              Text(busy ? "Mengirim…" : "Kirim ke \(store.user(task.assigneeID)?.name ?? "Pelaksana")")
                .gl(16, .semibold).lineLimit(1).minimumScaleFactor(0.8).foregroundStyle(.white)
                .padding(.horizontal, 8).frame(maxWidth: .infinity).frame(height: 54)
                .background(GLTheme.ink, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .opacity(busy ? 0.6 : 1)
            }.buttonStyle(.plain).disabled(busy)
              .containerRelativeFrame(.horizontal) { w, _ in (w - 40 - 10) * 2 / 3 }
          }
        }.transition(.opacity)
      } else {
        VStack(spacing: 10) {
          Button { decide(true) } label: {
            HStack(spacing: 8) {
              if pending == true { ProgressView().tint(.white) } else { GLIcon("checkmark.circle", size: 22) }
              Text(pending == true ? "Menyimpan…" : "Setujui").gl(17, .semibold)
            }
            .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 56)
            .background(GLTheme.ink, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .opacity(busy ? 0.6 : 1)
          }.buttonStyle(.plain).disabled(busy).accessibilityIdentifier("approve-work")
          Button {
            withAnimation(.easeOut(duration: 0.2)) { changes = true }
            error = nil
          } label: {
            HStack(spacing: 8) {
              GLIcon("arrow.uturn.backward", size: 22)
              Text("Minta revisi").gl(17, .semibold)
            }
            .frame(maxWidth: .infinity).frame(height: 56)
            .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(GLTheme.ink, lineWidth: 1.5))
          }.buttonStyle(.plain).disabled(busy)
        }
      }
    }
    .interactiveDismissDisabled(busy)
  }

  private func decide(_ approve: Bool) {
    let text = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
    if !approve && text.isEmpty { return error = "Jelaskan apa yang perlu diubah." }
    if task.assigneeID == store.currentUserID { return error = "Kamu tidak bisa menyetujui hasil kerjamu sendiri." }
    pending = approve
    error = nil
    Task {
      defer { pending = nil }
      do {
        try await store.review(
          taskID: task.id, approve: approve, feedback: approve ? "" : text, expectedVersion: task.version)
        store.flash(
          approve
            ? "Disetujui. Tugas selesai."
            : "Revisi diminta. \(store.user(task.assigneeID)?.name ?? "Pelaksana") akan diberi tahu.")
        onDone()
        dismiss()
      } catch { self.error = error.localizedDescription }
    }
  }
}

// MARK: - Store helpers (task screens only)

extension DemoStore {
  /// Text comments in a task's discussion (prototype `tk.comments`).
  func taskCommentCount(_ task: GLTask) -> Int {
    guard let groupID = project(task.projectID)?.groupID else { return 0 }
    return messages(groupID: groupID, taskID: task.id).filter { $0.kind == "text" }.count
  }
  /// Submission timestamp, e.g. "Rab 14 Okt, 15:20".
  func taskStamp(_ date: Date) -> String {
    "\(GLFormat.weekday(date)) \(GLFormat.date(date)), \(GLFormat.time(date))"
  }
  /// Prototype `projLock`.
  func taskProjectLock(_ p: GLProject, verb: String = "mengubah tugas") -> String? {
    switch p.status {
    case .archived: return "Proyek ini telah diarsipkan. Pulihkan proyek dulu untuk \(verb)."
    case .completed: return "Proyek ini sudah selesai. Buka kembali proyek untuk \(verb)."
    case .active: return nil
    }
  }
  /// Prototype `editLock`: (dialog title, message) when editing is not allowed.
  func taskEditLock(_ t: GLTask) -> (title: String, text: String)? {
    guard let p = project(t.projectID) else { return ("Tidak bisa mengedit", "Proyek tidak ditemukan.") }
    if !isCoordinator(groupID: p.groupID) {
      return ("Tidak bisa mengedit", "Hanya koordinator yang bisa mengedit detail tugas.")
    }
    if p.status == .archived { return ("Proyek diarsipkan", taskProjectLock(p, verb: "mengedit tugas")!) }
    if p.status == .completed { return ("Proyek sudah selesai", taskProjectLock(p, verb: "mengedit tugas")!) }
    if t.status == .inReview {
      return (
        "Sedang Menunggu Review",
        "Edit dikunci sementara karena hasil pekerjaan sedang diperiksa. Coba lagi setelah review selesai."
      )
    }
    if t.status == .done { return ("Tugas sudah selesai", "Tugas yang sudah disetujui tidak bisa diedit.") }
    return nil
  }
  /// Deadlines are stored as 23:59 on the chosen day, like the prototype.
  static func taskEndOfDay(_ date: Date) -> Date {
    Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: date) ?? date
  }
}
