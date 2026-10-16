import SwiftUI

struct GLProjectRow: View {
  @Environment(DemoStore.self) private var store
  let project: GLProject
  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: "folder").font(.title2).frame(width: 48, height: 48)
        .background(Color(hex: store.group(project.groupID)?.tint ?? "C9F2D6"), in: Circle())
      VStack(alignment: .leading, spacing: 10) {
        Text(project.title).font(.headline)
        Text(store.group(project.groupID)?.name ?? "Grup").font(.caption).foregroundStyle(
          GLTheme.secondary)
        HStack {
          ProgressView(value: store.progress(projectID: project.id)).tint(GLTheme.ink)
          Text(
            "\(store.tasks(in: project.id).filter { $0.status == .done }.count)/\(store.tasks(in: project.id).count)"
          )
          .font(.caption.bold()).monospacedDigit()
        }
        HStack {
          Text(GLFormat.date(project.dueAt))
          Spacer()
          Text(
            project.status == .active
              ? "Aktif" : project.status == .completed ? "Selesai" : "Diarsipkan")
        }.font(.caption).foregroundStyle(GLTheme.secondary)
      }
    }.glCard().accessibilityElement(children: .combine)
  }
}

struct ProjectDetailView: View {
  @Environment(DemoStore.self) private var store
  @Environment(\.dynamicTypeSize) private var typeSize
  let projectID: String
  @State private var edit = false
  @State private var createTask = false
  @State private var filter: TaskStatus?
  @State private var error: String?
  @State private var pendingAction: String?
  private var project: GLProject? { store.project(projectID) }
  var body: some View {
    ScrollView {
      if let project, store.isMember(groupID: project.groupID) {
        VStack(alignment: .leading, spacing: 22) {
          HStack {
            Label(
              project.status == .active
                ? "Proyek aktif" : project.status == .completed ? "Selesai" : "Diarsipkan",
              systemImage: project.status == .archived ? "archivebox" : "folder"
            )
            .font(.subheadline.bold()).padding(10).background(GLTheme.mint, in: Capsule())
            Spacer()
            if store.isCoordinator(groupID: project.groupID) { projectMenu(project) }
          }
          Text(project.title).font(.largeTitle.bold()).tracking(-0.8)
          Text(project.description).font(.body).foregroundStyle(GLTheme.secondary)
          Label("Deadline \(GLFormat.date(project.dueAt))", systemImage: "calendar").font(
            .subheadline)
          if project.status != .active {
            GLNotice(
              text: project.status == .completed
                ? "Proyek ini sudah selesai. Buka kembali proyek untuk mengubah tugas."
                : "Proyek ini telah diarsipkan. Informasi dan riwayatnya tetap dapat dilihat.")
          }
          pulse(project)
          HStack {
            GLSectionHeading(title: "Daftar tugas")
            if project.status == .active && store.isCoordinator(groupID: project.groupID) {
              Button {
                createTask = true
              } label: {
                Label("Tambah", systemImage: "plus").font(.subheadline.bold()).frame(minHeight: 44)
              }
              .accessibilityIdentifier("add-task")
            }
          }
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              filterChip("Semua", status: nil)
              ForEach(TaskStatus.allCases, id: \.self) { status in
                filterChip(status.label, status: status)
              }
            }
          }
          let tasks = store.tasks(in: projectID).filter { filter == nil || $0.status == filter }
          if tasks.isEmpty {
            GLEmptyState(
              title: "Belum ada tugas",
              message: "Tugas yang cocok dengan filter ini akan muncul di sini.",
              systemImage: "checklist")
          }
          ForEach(tasks) { task in
            NavigationLink(value: Route.task(task.id)) { GLTaskRow(task: task) }.buttonStyle(.plain)
          }
        }.padding(20)
      } else {
        GLEmptyState(
          title: "Kamu tidak punya akses",
          message: "Proyek ini tidak tersedia untuk akun yang aktif.", systemImage: "lock"
        ).padding(20)
      }
    }.glScreen().navigationTitle("Detail Proyek").navigationBarTitleDisplayMode(.inline)
      .sheet(isPresented: $edit) {
        NavigationStack { ProjectEditor(projectID: projectID, groupID: project?.groupID ?? "") }
      }
      .sheet(isPresented: $createTask) { NavigationStack { TaskEditor(projectID: projectID) } }
      .alert("Belum bisa melanjutkan", isPresented: errorBinding) {
        Button("Mengerti", role: .cancel) {}
      } message: {
        Text(error ?? "")
      }
      .confirmationDialog(
        pendingAction ?? "",
        isPresented: Binding(
          get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }),
        titleVisibility: .visible
      ) {
        Button("Konfirmasi", role: pendingAction == "Arsipkan proyek?" ? .destructive : nil) {
          applyAction()
        }
        Button("Batal", role: .cancel) { pendingAction = nil }
      } message: {
        Text("Riwayat tugas, submission, dan diskusi tetap tersimpan.")
      }
  }
  private var errorBinding: Binding<Bool> {
    Binding(get: { error != nil }, set: { if !$0 { error = nil } })
  }
  private func projectMenu(_ p: GLProject) -> some View {
    Menu {
      if p.status == .active {
        Button("Edit Proyek", systemImage: "pencil") { edit = true }
        Button("Tandai Selesai", systemImage: "checkmark.circle") {
          pendingAction = "Selesaikan proyek?"
        }
      }
      if p.status == .completed {
        Button("Buka Kembali Proyek", systemImage: "arrow.counterclockwise") {
          pendingAction = "Buka kembali proyek?"
        }
      }
      if p.status == .archived {
        Button("Pulihkan Proyek", systemImage: "tray.and.arrow.up") {
          pendingAction = "Pulihkan proyek?"
        }
      } else {
        Button("Arsipkan Proyek", systemImage: "archivebox", role: .destructive) {
          pendingAction = "Arsipkan proyek?"
        }
      }
    } label: {
      Image(systemName: "ellipsis").frame(width: 44, height: 44).background(.white, in: Circle())
    }
    .accessibilityLabel("Opsi proyek")
  }
  private func applyAction() {
    let action = pendingAction
    pendingAction = nil
    do {
      switch action {
      case "Selesaikan proyek?": try store.completeProject(projectID)
      case "Buka kembali proyek?": try store.reopenProject(projectID)
      case "Arsipkan proyek?": try store.archiveProject(projectID)
      default: try store.restoreProject(projectID)
      }
    } catch { self.error = error.localizedDescription }
  }
  private func filterChip(_ label: String, status: TaskStatus?) -> some View {
    Button {
      filter = status
    } label: {
      Text(label).font(.subheadline.weight(.semibold)).padding(.horizontal, 15).frame(minHeight: 44)
        .foregroundStyle(filter == status ? .white : GLTheme.ink)
        .background(filter == status ? GLTheme.ink : .white, in: Capsule())
    }.buttonStyle(.plain)
  }
  private func pulse(_ p: GLProject) -> some View {
    let tasks = store.tasks(in: p.id)
    let done = tasks.filter { $0.status == .done }.count
    return VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Group Pulse").font(.title3.bold())
        Spacer()
        Text("\(done)/\(tasks.count) disetujui").font(.caption.bold())
      }
      let layout =
        typeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 24))
        : AnyLayout(HStackLayout(spacing: 24))
      layout {
        ZStack {
          Circle().stroke(GLTheme.muted, lineWidth: 12)
          Circle().trim(from: 0, to: store.progress(projectID: p.id)).stroke(
            GLTheme.ink, style: StrokeStyle(lineWidth: 12, lineCap: .round)
          ).rotationEffect(.degrees(-90))
          VStack {
            Text(tasks.isEmpty ? "—" : "\(Int(store.progress(projectID: p.id) * 100))%").font(
              .title.bold())
            Text("selesai").font(.caption)
          }
        }.frame(width: 100, height: 100).padding(6)
          .accessibilityElement(children: .ignore).accessibilityLabel(
            tasks.isEmpty ? "Belum ada task" : "\(done) dari \(tasks.count) tugas disetujui")
        VStack(alignment: .leading, spacing: 9) {
          ForEach(TaskStatus.allCases, id: \.self) { status in
            HStack {
              Circle().fill(status.tint).frame(width: 8, height: 8)
              Text(status.label).font(.caption)
              Spacer(minLength: 0)
              Text("\(tasks.filter { $0.status == status }.count)").font(.caption.bold())
            }
          }
        }
      }
    }.glCard()
  }
}

struct ProjectEditor: View {
  @Environment(DemoStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  var projectID: String? = nil
  let groupID: String
  var onCreated: (String) -> Void = { _ in }
  @State private var title = ""
  @State private var description = ""
  @State private var dueAt = Date.now.addingTimeInterval(7 * 86400)
  @State private var error: String?
  var body: some View {
    Form {
      Section("Proyek di \(store.group(groupID)?.name ?? "grup")") {
        TextField("Nama proyek", text: $title).accessibilityIdentifier("project-title")
        TextField("Deskripsi (opsional)", text: $description, axis: .vertical).lineLimit(3...6)
        DatePicker("Deadline", selection: $dueAt, displayedComponents: .date)
      }
      if let error { Section { Text(error).foregroundStyle(.red) } }
      Section {
        GLPrimaryButton(title: projectID == nil ? "Buat Proyek" : "Simpan Perubahan") { save() }
          .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
      }
    }.scrollContentBackground(.hidden).glScreen().navigationTitle(
      projectID == nil ? "Buat Proyek" : "Edit Proyek"
    )
    .navigationBarTitleDisplayMode(.inline).toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() } }
    }
    .onAppear {
      if let id = projectID, let p = store.project(id) {
        title = p.title
        description = p.description
        dueAt = p.dueAt
      }
    }
  }
  private func save() {
    do {
      if let id = projectID {
        try store.updateProject(id: id, title: title, description: description, dueAt: dueAt)
      } else {
        onCreated(
          try store.createProject(
            groupID: groupID, title: title, description: description, dueAt: dueAt))
      }
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}
