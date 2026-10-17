import SwiftUI

// MARK: - Project card (group detail list)

/// Prototype group-detail project card: tint bar, title, deadline, status chip, progress bar.
struct GLProjectRow: View {
  @Environment(DemoStore.self) private var store
  let project: GLProject
  var body: some View {
    let tasks = store.tasks(in: project.id)
    let done = tasks.filter { $0.status == .done }.count
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(Color(hex: store.group(project.groupID)?.tint ?? "FFFFFF")).frame(width: 12, height: 40)
        VStack(alignment: .leading, spacing: 2) {
          Text(project.title).gl(16, .semibold)
          Text("Deadline \(GLFormat.date(project.dueAt))").gl(13).foregroundStyle(GLTheme.secondary)
        }
        Spacer(minLength: 0)
        ProjectStatusChip(status: project.status)
      }
      HStack(spacing: 10) {
        GeometryReader { geo in
          Capsule().fill(GLTheme.muted).overlay(alignment: .leading) {
            Capsule().fill(GLTheme.ink)
              .frame(width: tasks.isEmpty ? 0 : geo.size.width * Double(done) / Double(tasks.count))
          }
        }.frame(height: 6)
        Text("\(done)/\(tasks.count) selesai").gl(13, .semibold).monospacedDigit().fixedSize()
      }
    }
    .padding(16).frame(maxWidth: .infinity, alignment: .leading).glSurface(24)
    .multilineTextAlignment(.leading).accessibilityElement(children: .combine)
  }
}

/// 28pt project status pill (`padding:0 10px 0 7px`, 12/600, 15pt icon).
private struct ProjectStatusChip: View {
  let status: ProjectStatus
  var body: some View {
    let (label, bg, icon): (String, String, String) =
      switch status {
      case .archived: ("Diarsipkan", "ECEEEB", "archivebox")
      case .completed: ("Selesai", "C9F2D6", "checkmark.circle")
      case .active: ("Aktif", "D8EAF4", "bolt")
      }
    HStack(spacing: 4) {
      GLIcon(icon, size: 15)
      Text(label).gl(12, .semibold).lineLimit(1)
    }
    .padding(.leading, 7).padding(.trailing, 10).frame(height: 28)
    .background(Color(hex: bg), in: Capsule()).fixedSize()
  }
}

extension TaskStatus {
  /// `ST[k].ring` from the prototype: pulse ring segment and legend ring colour.
  var projectRing: Color {
    switch self {
    case .todo: Color(hex: "E6C25E")
    case .inProgress: Color(hex: "86B8D6")
    case .inReview: Color(hex: "A893EE")
    case .needsRevision: Color(hex: "E08C94")
    case .done: Color(hex: "62C484")
    }
  }
  /// Prototype `ORDER` (ring + legend).
  static let projectOrder: [TaskStatus] = [.done, .inReview, .inProgress, .needsRevision, .todo]
}

// MARK: - Project detail

struct ProjectDetailView: View {
  enum SheetKind: String, Identifiable {
    case actions, edit, newTask
    var id: String { rawValue }
  }
  @Environment(DemoStore.self) private var store
  @Environment(\.dynamicTypeSize) private var typeSize
  let projectID: String
  @State private var sheet: SheetKind?
  @State private var nextSheet: SheetKind?
  @State private var filter: TaskStatus?
  @State private var member: String?
  @State private var confirm: GLConfirmation?
  @State private var ringReady = false
  @State private var pulseWidth: CGFloat = 310
  private var project: GLProject? { store.project(projectID) }

  var body: some View {
    if let project, store.isMember(groupID: project.groupID) {
      content(project)
    } else {
      GLAccessDenied()
    }
  }

  private func content(_ p: GLProject) -> some View {
    let tasks = store.tasks(in: p.id)
    let isCoord = store.isCoordinator(groupID: p.groupID)
    let shown = tasks.filter { filter == nil || $0.status == filter }
    let stale = tasks.filter { (store.reviewWaitHours($0) ?? 0) > 48 }.count
    return ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        GLDetailHeader("Proyek") {
          GLCircleButton(icon: "ellipsis", label: "Aksi proyek", iconSize: 24) { sheet = .actions }
        }
        if p.status == .archived {
          HStack(spacing: 10) {
            GLIcon("archivebox", size: 20)
            Text("Proyek ini telah diarsipkan. Informasi dan riwayatnya tetap dapat dilihat.")
              .gl(14).lineSpacing(2).frame(maxWidth: .infinity, alignment: .leading)
            Button { archive(p) } label: {
              Text("Pulihkan Proyek").gl(13, .semibold).padding(.horizontal, 14).frame(height: 44)
                .overlay(Capsule().strokeBorder(GLTheme.ink, lineWidth: 1.5)).fixedSize()
            }.buttonStyle(.plain)
          }
          .padding(.vertical, 12).padding(.horizontal, 14)
          .background(Color(hex: "ECEEEB"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        if p.status == .completed {
          doneBanner(p, isCoord: isCoord)
        }
        hero(p)
        pulse(p, tasks: tasks, isCoord: isCoord, stale: stale)
        HStack(spacing: 8) {
          Text("Tugas").gl(22, .bold, em: -0.02)
          Spacer(minLength: 0)
          Button { openNewTask(p) } label: {
            HStack(spacing: 4) {
              GLIcon(isCoord && p.status == .active ? "plus" : "lock", size: 20)
              Text("Buat tugas").gl(15, .semibold)
            }
            .padding(.leading, 12).padding(.trailing, 16).frame(height: 44)
            .overlay(Capsule().strokeBorder(GLTheme.ink, lineWidth: 1.5)).contentShape(Capsule())
          }.buttonStyle(.plain).accessibilityIdentifier("add-task")
        }.padding(.top, 4)
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 6) {
            filterPill("Semua", nil)
            filterPill("Belum dimulai", .todo)
            filterPill("Dikerjakan", .inProgress)
            filterPill("Review", .inReview)
            filterPill("Revisi", .needsRevision)
            filterPill("Selesai", .done)
          }.padding(.horizontal, 20)
        }.padding(.horizontal, -20)
        VStack(spacing: 10) {
          ForEach(shown) { task in
            NavigationLink(value: Route.task(task.id)) { GLTaskRow(task: task) }
              .buttonStyle(GLCardButtonStyle())
          }
          if shown.isEmpty {
            Text(
              !tasks.isEmpty
                ? "Tidak ada tugas dengan status ini."
                : "Belum ada tugas. "
                  + (isCoord ? "Tambahkan tugas pertama." : "Koordinator akan menambahkan tugas.")
            )
            .gl(15).foregroundStyle(GLTheme.secondary).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.vertical, 24)
          }
        }
      }
      .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 32)
    }
    .glDetailScreen()
    .onAppear {
      guard !ringReady else { return }
      withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.8).delay(0.1)) { ringReady = true }
    }
    .sheet(
      item: $sheet,
      onDismiss: {
        sheet = nextSheet
        nextSheet = nil
      }
    ) { kind in
      switch kind {
      case .actions: actionsSheet(p)
      case .edit: ProjectEditor(projectID: p.id, groupID: p.groupID)
      case .newTask: TaskEditor(projectID: p.id)
      }
    }
    .glConfirm($confirm)
  }

  // MARK: Banners & hero

  private func doneBanner(_ p: GLProject, isCoord: Bool) -> some View {
    let text = Text("Proyek ini sudah selesai. Buka kembali proyek untuk mengubah tugas.").gl(14)
      .lineSpacing(2)
    let button = Button { reopen(p) } label: {
      HStack(spacing: 4) {
        GLIcon(isCoord ? "arrow.counterclockwise" : "lock", size: 17)
        Text("Buka Kembali Proyek").gl(13, .semibold)
      }
      .padding(.leading, 10).padding(.trailing, 14).frame(height: 44)
      .overlay(Capsule().strokeBorder(GLTheme.ink, lineWidth: 1.5)).contentShape(Capsule()).fixedSize()
    }.buttonStyle(.plain)
    // `flex-wrap`: the 160pt-min text and the button only share a row on wide screens.
    return ViewThatFits(in: .horizontal) {
      HStack(spacing: 10) {
        GLIcon("checkmark.circle", size: 20)
        text.frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
        button
      }
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: 10) {
          GLIcon("checkmark.circle", size: 20)
          text.frame(maxWidth: .infinity, alignment: .leading)
        }
        button
      }
    }
    .padding(.vertical, 12).padding(.horizontal, 14)
    .background(GLTheme.mint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  private func hero(_ p: GLProject) -> some View {
    let members = store.group(p.groupID)?.memberIDs ?? []
    return VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        NavigationLink(value: Route.group(p.groupID)) {
          HStack(spacing: 2) {
            Text(store.group(p.groupID)?.name ?? "").gl(14, .semibold)
            GLIcon("chevron.right", size: 18)
          }.foregroundStyle(GLTheme.text2).frame(minHeight: 32)
        }.buttonStyle(.plain)
        Spacer(minLength: 0)
        ProjectStatusChip(status: p.status)
      }
      Text(p.title).gl(27, .bold, em: -0.025).fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 6) {
        GLIcon("calendar", size: 18)
        Text("Deadline \(GLFormat.weekday(p.dueAt)), \(GLFormat.date(p.dueAt)) · 23:59").gl(14)
      }.foregroundStyle(GLTheme.text3)
      Text(p.description.isEmpty ? "Belum ada deskripsi." : p.description).gl(15).lineSpacing(4)
        .foregroundStyle(GLTheme.text3).fixedSize(horizontal: false, vertical: true)
      HStack(spacing: -8) {
        ForEach(members, id: \.self) { id in
          GLAvatar(user: store.user(id), size: 34, fontSize: 11)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
            .accessibilityLabel(store.displayName(id))
        }
      }.padding(.top, 2)
    }
    .padding(.vertical, 22).padding(.horizontal, 20).frame(maxWidth: .infinity, alignment: .leading)
    .background(.white, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
  }

  // MARK: Group Pulse

  private func pulse(_ p: GLProject, tasks: [GLTask], isCoord: Bool, stale: Int) -> some View {
    let n = tasks.count
    let c = { (s: TaskStatus) in tasks.filter { $0.status == s }.count }
    let stats: [(String, Int)] = [
      ("Total", n), ("Selesai", c(.done)), ("Berjalan", c(.inProgress) + c(.needsRevision)),
      ("Review", c(.inReview)), ("Belum mulai", c(.todo)),
    ]
    return VStack(alignment: .leading, spacing: 16) {
      Text("Group Pulse").gl(20, .bold, em: -0.02)
      HStack(alignment: .top, spacing: 4) {
        ForEach(stats, id: \.0) { stat in
          VStack(spacing: 1) {
            Text("\(stat.1)").gl(19, .heavy).monospacedDigit()
            Text(stat.0).gl(11, .semibold).foregroundStyle(GLTheme.text2)
          }.multilineTextAlignment(.center).frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        }
      }
      .padding(.vertical, 10).padding(.horizontal, 4)
      .background(GLTheme.muted, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      if n > 0 {
        // `flex-wrap` row: 140pt ring + legend (flex 1 1 140px) with an 18pt gap.
        let layout =
          pulseWidth >= 298 && !typeSize.isAccessibilitySize
          ? AnyLayout(HStackLayout(spacing: 18)) : AnyLayout(VStackLayout(spacing: 18))
        layout {
          ring(tasks)
          legend(tasks)
        }.frame(maxWidth: .infinity)
      } else {
        Text("Belum ada tugas, jadi belum ada progres. Pulse muncul setelah tugas pertama dibuat.")
          .gl(15).lineSpacing(4).foregroundStyle(GLTheme.secondary).multilineTextAlignment(.center)
          .frame(maxWidth: .infinity).padding(.vertical, 8)
      }
      members(p, tasks: tasks)
      if isCoord && stale > 0 {
        HStack(spacing: 10) {
          GLIcon("list.bullet.clipboard", size: 20)
          Text("\(stale) tugas menunggu review lebih dari 48 jam").gl(14, .medium)
          Spacer(minLength: 0)
        }
        .padding(.vertical, 12).padding(.horizontal, 14)
        .background(GLTheme.lavender, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(
            GLTheme.ink, lineWidth: 1.5))
      }
    }
    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
    .background(.white, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
    .onGeometryChange(for: CGFloat.self) { $0.size.width - 40 } action: { pulseWidth = $0 }
  }

  private func ring(_ tasks: [GLTask]) -> some View {
    let n = tasks.count
    let done = tasks.filter { $0.status == .done }.count
    let circumference = 2 * Double.pi * 56
    var acc = 0.0
    let segments: [(TaskStatus, Double, Double)] = TaskStatus.projectOrder.map { s in
      let len = Double(tasks.filter { $0.status == s }.count) / Double(n) * circumference
      defer { acc += len }
      // Same 3pt gap between segments as the SVG dasharray (`len - 3`).
      return (s, acc / circumference, len > 0 ? max(len - 3, 0.01) / circumference : 0)
    }
    let sub = "\(done) dari \(n) disetujui"
    return ZStack {
      Circle().stroke(GLTheme.muted, lineWidth: 16).frame(width: 112, height: 112)
      ForEach(segments, id: \.0) { s, start, length in
        Circle().trim(from: ringReady ? start : 0, to: ringReady ? start + length : 0)
          .stroke(s.projectRing, lineWidth: 16).frame(width: 112, height: 112)
          .rotationEffect(.degrees(-90))
      }
      VStack(spacing: 1) {
        Text("\(Int((Double(done) / Double(n) * 100).rounded()))%").gl(30, .heavy, em: -0.04)
          .monospacedDigit()
        Text(sub).gl(12).foregroundStyle(GLTheme.secondary).multilineTextAlignment(.center)
          .frame(maxWidth: 84)
      }
    }
    .frame(width: 140, height: 140)
    .accessibilityElement(children: .ignore).accessibilityLabel(sub)
  }

  private func legend(_ tasks: [GLTask]) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      ForEach(TaskStatus.projectOrder) { s in
        let count = tasks.filter { $0.status == s }.count
        HStack(spacing: 8) {
          GLIcon(s.icon, size: 14).frame(width: 24, height: 24)
            .background(s.tint, in: Circle())
            .overlay(Circle().strokeBorder(s.projectRing, lineWidth: 2))
          Text(s.label).gl(14).foregroundStyle(GLTheme.text3).frame(maxWidth: .infinity, alignment: .leading)
          Text("\(count)").gl(14, .bold).monospacedDigit()
        }.opacity(count > 0 ? 1 : 0.45).accessibilityElement(children: .combine)
      }
    }.frame(minWidth: 140, maxWidth: .infinity)
  }

  private func members(_ p: GLProject, tasks: [GLTask]) -> some View {
    let ids = store.group(p.groupID)?.memberIDs ?? []
    return VStack(alignment: .leading, spacing: 10) {
      Text("Anggota · ketuk untuk melihat tugasnya").gl(13, .semibold).foregroundStyle(GLTheme.text2)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
          ForEach(ids, id: \.self) { id in memberButton(id, tasks: tasks.filter { $0.assigneeID == id }) }
        }.padding(4)
      }.padding(.horizontal, -4)
      if let member, ids.contains(member) {
        memberPanel(member, tasks: tasks.filter { $0.assigneeID == member })
          .transition(.opacity.combined(with: .offset(y: 8)))
      }
    }
  }

  private func memberButton(_ id: String, tasks: [GLTask]) -> some View {
    let selected = member == id
    let done = tasks.filter { $0.status == .done }.count
    return Button {
      withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) { member = selected ? nil : id }
    } label: {
      VStack(spacing: 5) {
        GLAvatar(user: store.user(id), size: 48, fontSize: 14)
          .background {
            if selected {
              Circle().fill(GLTheme.ink).padding(-4.5)
                .overlay(Circle().fill(.white).padding(-2.5))
            }
          }
          .overlay(alignment: .bottomTrailing) {
            Text("\(done)/\(tasks.count)").gl(11, .bold).padding(.horizontal, 5)
              .frame(minWidth: 24, minHeight: 20).background(.white, in: Capsule())
              .overlay(Capsule().stroke(GLTheme.border, lineWidth: 1).padding(-0.5))
              .fixedSize().offset(x: 4, y: 4)
          }
        Text(store.displayName(id)).gl(13, selected ? .bold : .medium).lineLimit(1)
          .truncationMode(.tail).frame(maxWidth: 60)
      }
      .padding(.vertical, 4).frame(width: 62).scaleEffect(selected ? 1.06 : 1)
    }
    .buttonStyle(ProjectMemberButtonStyle())
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func memberPanel(_ id: String, tasks: [GLTask]) -> some View {
    let name = store.displayName(id)
    let done = tasks.filter { $0.status == .done }.count
    return VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 6) {
        Text((id == store.currentUserID ? "Tugasmu" : "Tugas \(name)") + " di proyek ini").gl(15, .bold)
        HStack(spacing: 10) {
          GeometryReader { geo in
            Capsule().fill(.white).overlay(alignment: .leading) {
              Capsule().fill(GLTheme.ink).frame(
                width: tasks.isEmpty ? 0 : geo.size.width * Double(done) / Double(tasks.count))
            }
          }.frame(height: 6)
          Text("\(done) dari \(tasks.count) selesai · \(tasks.count - done) belum").gl(13, .semibold)
            .fixedSize()
        }
      }
      ForEach(tasks) { task in
        NavigationLink(value: Route.task(task.id)) {
          HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
              Text(task.title).gl(15, .semibold)
              Text(GLFormat.due(task.dueAt, status: task.status, now: store.now)).gl(13)
                .foregroundStyle(GLTheme.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 3) {
              GLIcon(task.status.icon, size: 15)
              Text(task.status.label).gl(12, .semibold).lineLimit(1)
            }
            .padding(.leading, 6).padding(.trailing, 9).frame(height: 26)
            .background(task.status.tint, in: Capsule()).fixedSize()
          }
          .multilineTextAlignment(.leading)
          .padding(.vertical, 10).padding(.horizontal, 12).frame(minHeight: 52)
          .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }.buttonStyle(GLCardButtonStyle())
      }
      if tasks.isEmpty {
        Text("Belum ada tugas untuk \(name) di proyek ini.").gl(14).foregroundStyle(GLTheme.text3)
      }
      Text("Ringkasan pembagian tugas, bukan penilaian kontribusi.").gl(12)
        .foregroundStyle(GLTheme.text2)
    }
    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
    .background(GLTheme.muted, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
  }

  private func filterPill(_ label: String, _ status: TaskStatus?) -> some View {
    let on = filter == status
    return Button {
      withAnimation(.easeOut(duration: 0.2)) { filter = status }
    } label: {
      Text(label).gl(14, .semibold).padding(.horizontal, 16).frame(height: 44)
        .foregroundStyle(on ? .white : GLTheme.ink)
        .background(on ? GLTheme.ink : .white, in: Capsule())
        .overlay(Capsule().strokeBorder(GLTheme.ink, lineWidth: 1.5))
    }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
  }

  // MARK: Actions sheet

  private func actionsSheet(_ p: GLProject) -> some View {
    let coord = store.isCoordinator(groupID: p.groupID)
    let archived = p.status == .archived
    let completed = p.status == .completed || (archived && p.previousStatus == .completed)
    return GLSheet("Aksi proyek") {
      VStack(spacing: 0) {
        actionRow("Edit proyek", "Nama, deskripsi, deadline", coord ? "pencil" : "lock") {
          sheet = nil
          openEdit(p)
        }
        actionRow(
          completed ? "Buka kembali proyek" : "Tandai proyek selesai",
          completed ? "Status kembali Aktif, riwayat tetap ada" : "Bisa setelah semua tugas disetujui",
          coord && !archived ? (completed ? "arrow.counterclockwise" : "checkmark.circle") : "lock"
        ) { completed ? reopen(p) : complete(p) }
        actionRow(
          archived ? "Pulihkan proyek" : "Arsipkan proyek",
          archived ? "Kembalikan ke daftar proyek" : "Riwayat tetap tersimpan",
          coord ? (archived ? "tray.and.arrow.up" : "archivebox") : "lock"
        ) { archive(p) }
      }
      .padding(.vertical, 4).padding(.horizontal, 16)
      .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
      if !coord {
        HStack(spacing: 6) {
          GLIcon("lock", size: 16)
          Text("Hanya koordinator yang bisa mengubah proyek.").gl(13)
        }.foregroundStyle(GLTheme.text3)
      }
    }
  }

  private func actionRow(_ label: String, _ sub: String, _ icon: String, go: @escaping () -> Void)
    -> some View
  {
    Button(action: go) {
      HStack(spacing: 12) {
        GLIcon(icon, size: 22)
        VStack(alignment: .leading, spacing: 0) {
          Text(label).gl(16, .semibold)
          Text(sub).gl(13).foregroundStyle(GLTheme.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.vertical, 8).frame(minHeight: 62)
      .overlay(alignment: .bottom) { Rectangle().fill(GLTheme.border).frame(height: 1) }
    }.buttonStyle(GLRowButtonStyle())
  }

  // MARK: Rules (prototype copy)

  private func deny(_ text: String) { store.flash(text, .err) }

  private func run(_ work: @escaping () async throws -> Void, ok: String) {
    Task {
      do {
        try await work()
        store.flash(ok)
      } catch { store.flash(error.localizedDescription, .err) }
    }
  }

  private func openEdit(_ p: GLProject) {
    guard store.isCoordinator(groupID: p.groupID) else {
      return deny("Hanya koordinator yang bisa mengedit proyek.")
    }
    if p.status == .archived {
      confirm = GLConfirmation(
        title: "Proyek diarsipkan",
        text: "Proyek ini telah diarsipkan. Pulihkan proyek dulu untuk mengubah detailnya.",
        ok: "Mengerti", info: true)
      return
    }
    nextSheet = .edit
  }

  private func openNewTask(_ p: GLProject) {
    guard store.isCoordinator(groupID: p.groupID) else {
      return deny("Hanya koordinator yang bisa membuat tugas.")
    }
    switch p.status {
    case .archived:
      confirm = GLConfirmation(
        title: "Proyek diarsipkan",
        text: "Proyek ini telah diarsipkan. Pulihkan proyek dulu untuk menambah tugas.",
        ok: "Mengerti", info: true)
    case .completed:
      confirm = GLConfirmation(
        title: "Proyek sudah selesai",
        text: "Proyek ini sudah selesai. Buka kembali proyek untuk menambah tugas.",
        ok: "Buka kembali proyek", run: { reopen(p) })
    case .active:
      sheet = .newTask
    }
  }

  private func complete(_ p: GLProject) {
    sheet = nil
    guard store.isCoordinator(groupID: p.groupID) else {
      return deny("Hanya koordinator yang bisa menandai proyek selesai.")
    }
    if p.status == .archived { return deny("Pulihkan proyek dari arsip dulu.") }
    let ts = store.tasks(in: p.id)
    let open = ts.filter { $0.status != .done }.count
    if ts.isEmpty {
      confirm = GLConfirmation(
        title: "Belum bisa ditandai selesai",
        text: "Proyek ini belum punya tugas. Tambahkan dan selesaikan tugas dulu.", ok: "Mengerti",
        info: true)
      return
    }
    if open > 0 {
      let parts = [
        (TaskStatus.inReview, "menunggu review"), (.needsRevision, "perlu revisi"),
        (.inProgress, "sedang dikerjakan"), (.todo, "belum dimulai"),
      ].compactMap { s, label -> String? in
        let n = ts.filter { $0.status == s }.count
        return n > 0 ? "\(n) \(label)" : nil
      }.joined(separator: ", ")
      confirm = GLConfirmation(
        title: "Belum bisa ditandai selesai",
        text:
          "\(open) dari \(ts.count) tugas belum disetujui (\(parts)). Proyek bisa ditandai selesai setelah semua tugas berstatus Selesai. Tugas tidak akan disetujui otomatis.",
        ok: "Mengerti", info: true)
      return
    }
    confirm = GLConfirmation(
      title: "Tandai proyek selesai?",
      text: "Semua \(ts.count) tugas sudah disetujui. Proyek pindah ke daftar Selesai di grup.",
      ok: "Tandai selesai",
      run: { run({ try await store.completeProject(p.id) }, ok: "Proyek selesai. Kerja bagus, tim!") })
  }

  private func reopen(_ p: GLProject) {
    sheet = nil
    guard store.isCoordinator(groupID: p.groupID) else {
      return deny("Hanya koordinator yang bisa membuka kembali proyek.")
    }
    if p.status == .archived { return deny("Pulihkan proyek dari arsip dulu.") }
    guard p.status == .completed else { return }
    confirm = GLConfirmation(
      title: "Buka kembali proyek?",
      text:
        "Proyek kembali berstatus Aktif. Tugas bisa ditambah, diedit, dan dialihkan lagi. Semua riwayat tugas tetap tersimpan.",
      ok: "Buka kembali",
      run: { run({ try await store.reopenProject(p.id) }, ok: "Proyek aktif kembali") })
  }

  private func archive(_ p: GLProject) {
    sheet = nil
    guard store.isCoordinator(groupID: p.groupID) else {
      return deny("Hanya koordinator yang bisa mengarsipkan proyek.")
    }
    if p.status == .archived {
      let label = p.previousStatus == .completed ? "Selesai" : "Aktif"
      return run({ try await store.restoreProject(p.id) }, ok: "Proyek dipulihkan · status \(label)")
    }
    confirm = GLConfirmation(
      title: "Arsipkan proyek?",
      text:
        "Proyek tidak lagi muncul di Beranda dan daftar aktif. Tugas, hasil kerja, dan diskusinya tetap tersimpan dan bisa dibuka dari filter Arsip di grup.",
      ok: "Arsipkan", run: { run({ try await store.archiveProject(p.id) }, ok: "Proyek diarsipkan") })
  }
}

/// `style-active="transform:scale(.9)"` on the pulse member buttons.
private struct ProjectMemberButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.contentShape(Rectangle()).scaleEffect(configuration.isPressed ? 0.9 : 1)
      .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
  }
}

// MARK: - Create / edit project sheet

struct ProjectEditor: View {
  @Environment(DemoStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  var projectID: String? = nil
  let groupID: String
  var onCreated: (String) -> Void = { _ in }
  @State private var selectedGroup: String?
  @State private var title = ""
  @State private var description = ""
  @State private var dueAt = ProjectEditor.day(14)
  @State private var originalDue: Date?
  @State private var error: String?
  @State private var busy = false

  private var cal: Calendar { Calendar.current }
  private static func day(_ n: Int) -> Date {
    Calendar.current.date(byAdding: .day, value: n, to: Calendar.current.startOfDay(for: .now))!
  }
  private var gid: String { selectedGroup ?? groupID }
  private var placeholder: Color { Color(hex: "80868B") }

  var body: some View {
    GLSheet(projectID == nil ? "Buat proyek" : "Edit proyek") {
      VStack(alignment: .leading, spacing: 8) {
        Text("Grup").gl(14, .semibold)
        if projectID == nil {
          ProjectFlow(spacing: 8) {
            ForEach(store.groups.filter { store.isCoordinator(groupID: $0.id) && store.isMember(groupID: $0.id) }) { g in
              let on = g.id == gid
              Button { selectedGroup = g.id } label: {
                Text(g.name).gl(14, .semibold).multilineTextAlignment(.leading)
                  .padding(.vertical, 8).padding(.horizontal, 14).frame(minHeight: 44)
                  .foregroundStyle(on ? .white : GLTheme.ink)
                  .background(
                    on ? GLTheme.ink : .white, in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                  )
                  .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(
                      GLTheme.ink, lineWidth: 1.5))
              }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
            }
          }
        } else {
          Text(store.group(gid)?.name ?? "").gl(15).foregroundStyle(GLTheme.text3)
        }
      }
      GLField("Nama proyek", required: true, trailing: "\(title.count)/60") {
        TextField("", text: $title, prompt: Text("Contoh: Aplikasi Kantin Kampus").foregroundStyle(placeholder))
          .gl(16).glInput().accessibilityIdentifier("project-title")
          .onChange(of: title) { _, v in if v.count > 60 { title = String(v.prefix(60)) } }
      }
      GLField("Deskripsi", trailing: "\(description.count)/300") {
        TextField(
          "", text: $description,
          prompt: Text("Tujuan proyek dan hasil akhir yang diharapkan").foregroundStyle(placeholder),
          axis: .vertical
        )
        .lineLimit(3, reservesSpace: true).gl(16).lineSpacing(5).glInput(height: nil)
        .onChange(of: description) { _, v in if v.count > 300 { description = String(v.prefix(300)) } }
      }
      VStack(alignment: .leading, spacing: 8) {
        (Text("Deadline") + Text(" *").foregroundColor(GLTheme.danger)).gl(14, .semibold)
        HStack(spacing: 8) {
          quick("Besok", 1)
          quick("3 hari lagi", 3)
          quick("Minggu depan", 7)
        }
        HStack(spacing: 10) {
          GLIcon("calendar", size: 20)
          DatePicker(
            "Pilih tanggal deadline proyek", selection: $dueAt,
            in: min(Self.day(0), originalDue ?? .distantFuture)...,
            displayedComponents: .date
          ).labelsHidden()
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).frame(height: 50)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(GLTheme.border))
        Text("\(GLFormat.weekday(dueAt)), \(GLFormat.date(dueAt)) · 23:59").gl(13)
          .foregroundStyle(GLTheme.secondary)
      }
      // ponytail: accent picker ("Warna aksen (opsional)") skipped, GLProject has no accent field.
      if let error { GLFormError(text: error) }
      GLSubmitButton(
        title: busy
          ? "Menyimpan…"
          : (error?.contains("Gagal") ?? false)
            ? "Coba lagi" : projectID == nil ? "Buat proyek" : "Simpan perubahan",
        busy: busy
      ) { save() }
      .accessibilityIdentifier("project-save")
    }
    .interactiveDismissDisabled(busy)
    .onAppear {
      guard let id = projectID, let p = store.project(id), originalDue == nil else { return }
      title = p.title
      description = p.description
      dueAt = cal.startOfDay(for: p.dueAt)
      originalDue = dueAt
    }
  }

  private func quick(_ label: String, _ days: Int) -> some View {
    let on = cal.isDate(dueAt, inSameDayAs: Self.day(days))
    return Button { dueAt = Self.day(days) } label: {
      Text(label).gl(14, .semibold).lineLimit(1).minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity).frame(height: 44)
        .foregroundStyle(on ? .white : GLTheme.ink)
        .background(on ? GLTheme.ink : .white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(GLTheme.ink, lineWidth: 1.5))
    }.buttonStyle(.plain)
  }

  private func save() {
    let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let day = cal.startOfDay(for: dueAt)
    let unchanged = originalDue.map { cal.isDate($0, inSameDayAs: day) } ?? false
    let maxDay = cal.date(from: DateComponents(year: 2027, month: 12, day: 31))!
    if name.count < 3 { return error = "Nama proyek minimal 3 karakter." }
    if name.count > 60 { return error = "Nama proyek maksimal 60 karakter." }
    if description.count > 300 { return error = "Deskripsi maksimal 300 karakter." }
    if let id = projectID, store.project(id)?.status == .archived {
      return error = "Proyek diarsipkan. Pulihkan dulu untuk mengubah detail."
    }
    if !(unchanged || (day >= Self.day(0) && day <= maxDay)) {
      return error = "Pilih deadline yang valid, mulai hari ini."
    }
    if !store.isCoordinator(groupID: gid) {
      return error = "Hanya koordinator grup ini yang bisa mengelola proyek."
    }
    let due = cal.date(bySettingHour: 23, minute: 59, second: 0, of: day) ?? day
    error = nil
    busy = true
    Task {
      defer { busy = false }
      do {
        if let id = projectID {
          try await store.updateProject(id: id, title: name, description: description, dueAt: due)
          store.flash("Perubahan proyek disimpan")
          dismiss()
        } else {
          let id = try await store.createProject(
            groupID: gid, title: name, description: description, dueAt: due)
          store.flash("Proyek dibuat. Tambahkan tugas pertama.")
          dismiss()
          onCreated(id)
        }
      } catch {
        self.error =
          store.simulatedOffline
          ? (projectID == nil
            ? "Gagal membuat proyek. Periksa koneksimu lalu coba lagi."
            : "Gagal menyimpan perubahan. Coba lagi.")
          : error.localizedDescription
      }
    }
  }
}

/// Minimal wrapping row (`display:flex;flex-wrap:wrap`).
private struct ProjectFlow: Layout {
  var spacing: CGFloat
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = arrange(proposal.width ?? .infinity, subviews)
    return CGSize(width: proposal.width ?? rows.width, height: rows.height)
  }
  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for (i, point) in arrange(bounds.width, subviews).points.enumerated() {
      subviews[i].place(
        at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
        proposal: ProposedViewSize(width: min(subviews[i].sizeThatFits(.unspecified).width, bounds.width), height: nil))
    }
  }
  private func arrange(_ maxWidth: CGFloat, _ subviews: Subviews) -> (points: [CGPoint], width: CGFloat, height: CGFloat) {
    var points: [CGPoint] = []
    var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, width: CGFloat = 0
    for view in subviews {
      let w = min(view.sizeThatFits(.unspecified).width, maxWidth)
      let h = view.sizeThatFits(ProposedViewSize(width: w, height: nil)).height
      if x > 0 && x + w > maxWidth {
        x = 0
        y += rowH + spacing
        rowH = 0
      }
      points.append(CGPoint(x: x, y: y))
      x += w + spacing
      width = max(width, x - spacing)
      rowH = max(rowH, h)
    }
    return (points, width, y + rowH)
  }
}
