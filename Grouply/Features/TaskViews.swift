import SwiftUI

struct GLTaskRow: View {
  @Environment(DemoStore.self) private var store
  @Environment(\.dynamicTypeSize) private var typeSize
  let task: GLTask
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      let layout =
        typeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        : AnyLayout(HStackLayout(spacing: 8))
      layout {
        GLStatusChip(status: task.status)
        if task.status != .done && task.dueAt < store.now {
          Label("Terlambat", systemImage: "exclamationmark.circle").font(.caption.bold())
        }
      }
      Text(task.title).font(.headline)
      Text(store.project(task.projectID)?.title ?? "Proyek").font(.caption).foregroundStyle(
        GLTheme.secondary)
      HStack(spacing: 6) {
        GLAvatar(user: store.user(task.assigneeID), size: 28)
        Image(systemName: "arrow.right").font(.caption2)
        GLAvatar(user: store.user(task.reviewerID), size: 28)
        Spacer(minLength: 4)
        Label(GLFormat.deadline(task.dueAt, now: store.now), systemImage: "clock").font(.caption)
      }
    }.glCard().accessibilityElement(children: .combine)
  }
}

struct MyTasksView: View {
  @Environment(DemoStore.self) private var store
  @State private var filter: TaskStatus?
  private var tasks: [GLTask] {
    store.memberTasks.filter { task in
      store.project(task.projectID)?.status != .archived && (filter == nil || task.status == filter)
    }.sorted { $0.dueAt < $1.dueAt }
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("Tugas Saya").font(.largeTitle.bold()).tracking(-1)
        Text("Satu langkah kecil, progres bareng.").font(.subheadline).foregroundStyle(
          GLTheme.secondary)
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            chip("Semua", value: nil)
            ForEach(TaskStatus.allCases) { status in chip(status.label, value: status) }
          }
        }
        if tasks.isEmpty {
          GLEmptyState(
            title: "Tidak ada tugas di sini",
            message: "Tugas yang ditujukan kepadamu akan muncul sesuai filter yang dipilih.",
            systemImage: "checkmark.circle")
        }
        ForEach(tasks) { task in
          NavigationLink(value: Route.task(task.id)) { GLTaskRow(task: task) }.buttonStyle(.plain)
        }
      }.padding(20)
    }.glScreen().toolbar(.hidden, for: .navigationBar)
  }
  private func chip(_ label: String, value: TaskStatus?) -> some View {
    Button {
      filter = value
    } label: {
      Text(label).font(.subheadline.bold()).padding(.horizontal, 16).frame(minHeight: 44)
        .foregroundStyle(filter == value ? .white : GLTheme.ink)
        .background(filter == value ? GLTheme.ink : .white, in: Capsule())
    }.buttonStyle(.plain)
  }
}

struct TaskDetailView: View {
  @Environment(DemoStore.self) private var store
  @Environment(\.dynamicTypeSize) private var typeSize
  let taskID: String
  @State private var section = 0
  @State private var editor = false
  @State private var reassign = false
  @State private var submission = false
  @State private var review = false
  @State private var confirmReopen = false
  @State private var error: String?
  private var task: GLTask? { store.task(taskID) }
  var body: some View {
    Group {
      if let task, let project = store.project(task.projectID),
        store.isMember(groupID: project.groupID)
      {
        VStack(spacing: 0) {
          if section == 2 {
            ChatDetailView(groupID: project.groupID, taskID: taskID)
          } else {
            ScrollView {
              VStack(alignment: .leading, spacing: 22) {
                GLStatusChip(status: task.status)
                Text(task.title).font(.largeTitle.bold()).tracking(-0.8)
                NavigationLink(value: Route.project(project.id)) {
                  Label(project.title, systemImage: "folder").font(.subheadline)
                }
                if project.status != .active {
                  GLNotice(
                    text:
                      "Proyek \(project.status == .completed ? "selesai" : "diarsipkan") · riwayat tetap dapat dibaca. Buka kembali proyek untuk melanjutkan perubahan."
                  )
                }
                if section == 0 { overview(task, project) } else { history(task, project) }
              }.padding(20)
            }
          }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
          Group {
            if typeSize.isAccessibilitySize {
              Picker("Bagian tugas", selection: $section) {
                Text("Ringkasan").tag(0)
                Text("Hasil Kerja").tag(1)
                Text("Diskusi").tag(2)
              }.pickerStyle(.menu)
            } else {
              Picker("Bagian tugas", selection: $section) {
                Text("Ringkasan").tag(0)
                Text("Hasil Kerja").tag(1)
                Text("Diskusi").tag(2)
              }.pickerStyle(.segmented)
            }
          }.padding(.horizontal, 20).padding(.vertical, 12).background(GLTheme.background)
        }
        .toolbar {
          ToolbarItemGroup(placement: .topBarTrailing) {
            ShareLink(
              item:
                "\(task.title) · \(task.status.label)\ngrouply://task/\(task.id)\nTautan demo lokal; perangkat penerima perlu memiliki data demo yang sama."
            ) {
              Image(systemName: "square.and.arrow.up")
            }.accessibilityLabel("Bagikan tugas")
            if store.isCoordinator(groupID: project.groupID) {
              Menu {
                Button("Edit Tugas", systemImage: "pencil") { editor = true }.disabled(
                  project.status != .active || task.status == .inReview || task.status == .done)
                Button("Alihkan Tugas", systemImage: "arrow.left.arrow.right") { reassign = true }
                  .disabled(
                    project.status != .active || task.status == .inReview || task.status == .done)
                if task.status == .done {
                  Button("Buka Kembali Tugas", systemImage: "arrow.counterclockwise") {
                    confirmReopen = true
                  }.disabled(project.status != .active)
                }
              } label: {
                Image(systemName: "ellipsis").frame(minWidth: 32, minHeight: 44)
              }.accessibilityLabel("Opsi tugas")
            }
          }
        }
      } else {
        GLEmptyState(
          title: "Kamu tidak punya akses",
          message: "Tugas ini tidak tersedia untuk akun yang aktif.", systemImage: "lock"
        ).padding(20)
      }
    }
    .glScreen().navigationTitle("Detail Tugas").navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $editor) {
      if let task { NavigationStack { TaskEditor(projectID: task.projectID, taskID: taskID) } }
    }
    .sheet(isPresented: $reassign) {
      if let task { NavigationStack { ReassignEditor(task: task) } }
    }
    .sheet(isPresented: $submission) {
      if let task { NavigationStack { SubmissionEditor(task: task) } }
    }
    .sheet(isPresented: $review) { if let task { NavigationStack { ReviewEditor(task: task) } } }
    .alert(
      "Belum bisa dilakukan",
      isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    ) {
      Button("Mengerti", role: .cancel) {}
    } message: {
      Text(error ?? "")
    }
    .confirmationDialog(
      "Buka kembali tugas?", isPresented: $confirmReopen, titleVisibility: .visible
    ) {
      Button("Buka Kembali") { perform { try store.reopenTask(taskID) } }
    } message: {
      Text("Riwayat hasil dan keputusan review tetap disimpan.")
    }
  }
  private func overview(_ task: GLTask, _ project: GLProject) -> some View {
    VStack(alignment: .leading, spacing: 22) {
      VStack(alignment: .leading, spacing: 12) {
        Text("Tentang tugas").font(.headline)
        Text(task.description.isEmpty ? "Belum ada deskripsi." : task.description).foregroundStyle(
          GLTheme.secondary)
        Divider()
        HStack(alignment: .top, spacing: 24) {
          person("Pelaksana", id: task.assigneeID)
          person("Reviewer", id: task.reviewerID)
        }
        Divider()
        Label("Deadline \(GLFormat.date(task.dueAt))", systemImage: "calendar").font(.subheadline)
      }.glCard()
      if let feedback = task.submissions.last?.feedback, !feedback.isEmpty {
        VStack(alignment: .leading, spacing: 10) {
          Label(
            task.status == .needsRevision ? "Catatan revisi" : "Catatan reviewer",
            systemImage: "text.bubble"
          ).font(.headline)
          Text(feedback).font(.subheadline)
        }.glCard(task.status == .needsRevision ? GLTheme.coral : GLTheme.mint)
      }
      if project.status == .active {
        if task.assigneeID == store.currentUserID {
          if task.status == .todo {
            GLPrimaryButton(title: "Mulai Kerjakan", systemImage: "play") {
              perform { try store.startTask(taskID) }
            }
          } else if task.status == .inProgress || task.status == .needsRevision {
            GLPrimaryButton(
              title: task.status == .needsRevision ? "Kirim Revisi" : "Kirim Hasil",
              systemImage: "arrow.up.doc"
            ) { submission = true }
          } else if task.status == .inReview {
            GLNotice(
              text:
                "Hasilmu sedang diperiksa oleh \(store.user(task.reviewerID)?.name ?? "reviewer"). Kamu tetap bisa berdiskusi.",
              color: GLTheme.lavender)
          }
        }
        if task.reviewerID == store.currentUserID && task.status == .inReview {
          GLPrimaryButton(title: "Review Hasil Kerja", systemImage: "eye") {
            section = 1
            review = true
          }.accessibilityIdentifier("open-review")
        }
        if store.isCoordinator(groupID: project.groupID)
          && (task.status == .inReview || task.status == .done)
        {
          Text(
            task.status == .inReview
              ? "Edit dan pengalihan dikunci selama hasil sedang direview."
              : "Buka kembali tugas sebelum mengedit atau mengalihkannya."
          )
          .font(.caption).foregroundStyle(GLTheme.secondary)
        }
      }
      Button {
        section = 2
      } label: {
        Label("Diskusikan tugas ini", systemImage: "bubble.left.and.bubble.right").font(.headline)
          .frame(maxWidth: .infinity, minHeight: 52).background(
            .white, in: RoundedRectangle(cornerRadius: 18))
      }.buttonStyle(.plain)
    }
  }
  private func person(_ label: String, id: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(label).font(.caption).foregroundStyle(GLTheme.secondary)
      HStack {
        GLAvatar(user: store.user(id))
        Text(store.user(id)?.name ?? "Anggota").font(.subheadline.bold())
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  private func history(_ task: GLTask, _ project: GLProject) -> some View {
    VStack(alignment: .leading, spacing: 18) {
      if task.submissions.isEmpty {
        GLEmptyState(
          title: "Belum ada hasil",
          message: "Hasil dan riwayat revisi akan muncul setelah pelaksana mengirim pekerjaan.",
          systemImage: "doc.text")
      }
      ForEach(task.submissions.reversed()) { sub in
        VStack(alignment: .leading, spacing: 14) {
          HStack {
            Text("Revisi \(sub.revision)").font(.headline)
            Spacer()
            Text(
              sub.decision == "approved"
                ? "Disetujui"
                : sub.decision == "changes_requested" ? "Perlu revisi" : "Menunggu review"
            ).font(.caption.bold())
          }
          HStack {
            GLAvatar(user: store.user(sub.authorID), size: 28)
            Text(store.user(sub.authorID)?.name ?? "Anggota")
            Spacer()
            Text(GLFormat.date(sub.createdAt))
          }.font(.caption).foregroundStyle(GLTheme.secondary)
          Text(sub.note).font(.body).textSelection(.enabled)
          ForEach(sub.links, id: \.self) { link in
            if let url = URL(string: link), url.scheme == "https" {
              Link(destination: url) {
                Label(link, systemImage: "link").font(.subheadline).lineLimit(2)
              }
            }
          }
          if let feedback = sub.feedback, !feedback.isEmpty {
            Text(feedback).font(.subheadline).padding(12).frame(
              maxWidth: .infinity, alignment: .leading
            ).background(GLTheme.muted, in: RoundedRectangle(cornerRadius: 14))
          }
        }.glCard()
      }
      if project.status == .active && task.status == .inReview
        && task.reviewerID == store.currentUserID
      {
        GLPrimaryButton(title: "Berikan Review", systemImage: "checkmark.bubble") { review = true }
      }
    }
  }
  private func perform(_ action: () throws -> Void) {
    do { try action() } catch { self.error = error.localizedDescription }
  }
}

struct TaskEditor: View {
  @Environment(DemoStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let projectID: String
  var taskID: String? = nil
  @State private var title = ""
  @State private var description = ""
  @State private var dueAt = Date.now.addingTimeInterval(86400)
  @State private var assigneeID = ""
  @State private var reviewerID = ""
  @State private var version = 0
  @State private var error: String?
  private var members: [GLUser] {
    guard let p = store.project(projectID), let group = store.group(p.groupID) else { return [] }
    return group.memberIDs.compactMap(store.user)
  }
  var body: some View {
    Form {
      Section { Text(store.project(projectID)?.title ?? "Proyek").font(.headline) }
      Section("Detail tugas") {
        TextField("Judul tugas", text: $title).accessibilityIdentifier("task-title")
        TextField("Jelaskan apa yang perlu dikerjakan…", text: $description, axis: .vertical)
          .lineLimit(3...6)
        DatePicker("Deadline", selection: $dueAt, displayedComponents: .date)
        if let project = store.project(projectID), dueAt > project.dueAt {
          Label(
            "Deadline ini melewati deadline proyek. Tanggal pilihanmu tetap digunakan.",
            systemImage: "exclamationmark.triangle"
          ).font(.caption).foregroundStyle(GLTheme.secondary)
        }
      }
      Section("Tanggung jawab") {
        if taskID == nil {
          Picker("Pelaksana", selection: $assigneeID) {
            ForEach(members) { Text($0.name).tag($0.id) }
          }
        } else {
          LabeledContent("Pelaksana", value: store.user(assigneeID)?.name ?? "Anggota")
        }
        Picker("Reviewer", selection: $reviewerID) { ForEach(members) { Text($0.name).tag($0.id) } }
        Text("Pelaksana dan reviewer wajib berbeda.").font(.caption).foregroundStyle(
          GLTheme.secondary)
      }
      if let error {
        Section { Text(error).foregroundStyle(.red).accessibilityIdentifier("form-error") }
      }
      Section {
        GLPrimaryButton(title: taskID == nil ? "Buat Tugas" : "Simpan Perubahan") { save() }
          .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
      }
    }.scrollContentBackground(.hidden).glScreen().navigationTitle(
      taskID == nil ? "Buat Tugas" : "Edit Tugas"
    ).navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() } } }
      .onAppear {
        if let id = taskID, let t = store.task(id) {
          title = t.title
          description = t.description
          dueAt = t.dueAt
          assigneeID = t.assigneeID
          reviewerID = t.reviewerID
          version = t.version
        } else {
          assigneeID = members.first?.id ?? ""
          reviewerID = members.dropFirst().first?.id ?? ""
        }
      }
  }
  private func save() {
    do {
      if let id = taskID {
        try store.updateTask(
          id: id, title: title, description: description, reviewerID: reviewerID, dueAt: dueAt,
          expectedVersion: version)
      } else {
        _ = try store.createTask(
          projectID: projectID, title: title, description: description, assigneeID: assigneeID,
          reviewerID: reviewerID, dueAt: dueAt)
      }
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}

struct ReassignEditor: View {
  @Environment(DemoStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let task: GLTask
  @State private var assigneeID = ""
  @State private var reviewerID = ""
  @State private var error: String?
  @State private var confirm = false
  private var members: [GLUser] {
    guard let p = store.project(task.projectID), let g = store.group(p.groupID) else { return [] }
    return g.memberIDs.compactMap(store.user)
  }
  var body: some View {
    Form {
      Section {
        Text(task.title).font(.headline)
        Text("Riwayat hasil dan penulis asli tetap tersimpan.").font(.subheadline).foregroundStyle(
          GLTheme.secondary)
      }
      Section {
        Picker("Pelaksana", selection: $assigneeID) {
          ForEach(members) { Text($0.name).tag($0.id) }
        }
        Picker("Reviewer", selection: $reviewerID) { ForEach(members) { Text($0.name).tag($0.id) } }
      }
      if let error { Text(error).foregroundStyle(.red) }
      GLPrimaryButton(title: "Alihkan Tugas") { confirm = true }.listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }.navigationTitle("Alihkan Tugas").navigationBarTitleDisplayMode(.inline)
      .scrollContentBackground(.hidden).glScreen()
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() } } }
      .onAppear {
        assigneeID = task.assigneeID
        reviewerID = task.reviewerID
      }
      .confirmationDialog(
        "Alihkan tanggung jawab tugas?", isPresented: $confirm, titleVisibility: .visible
      ) {
        Button("Konfirmasi Pengalihan") {
          do {
            try store.reassignTask(
              id: task.id, assigneeID: assigneeID, reviewerID: reviewerID,
              expectedVersion: task.version)
            dismiss()
          } catch { self.error = error.localizedDescription }
        }
      } message: {
        Text(
          task.status == .needsRevision
            ? "Pelaksana baru melanjutkan revisi dengan seluruh hasil dan feedback sebelumnya."
            : "Pelaksana baru akan melihat tugas ini di Tugas Saya.")
      }
  }
}

struct SubmissionEditor: View {
  @Environment(DemoStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let task: GLTask
  @State private var note = ""
  @State private var links = [""]
  @State private var error: String?
  var body: some View {
    Form {
      Section {
        Text(task.title).font(.headline)
        Text(
          "Revisi \(task.submissions.count + 1) · hasil akan diperiksa oleh \(store.user(task.reviewerID)?.name ?? "reviewer")"
        ).font(.subheadline).foregroundStyle(GLTheme.secondary)
      }
      Section("Catatan hasil (wajib)") {
        TextField("Jelaskan hasil pekerjaanmu…", text: $note, axis: .vertical).lineLimit(4...10)
          .accessibilityIdentifier("submission-note")
      }
      Section {
        ForEach(links.indices, id: \.self) { i in
          TextField("https://…", text: $links[i]).keyboardType(.URL).textInputAutocapitalization(
            .never
          ).autocorrectionDisabled()
        }
        if links.count < 5 { Button("Tambah tautan", systemImage: "plus") { links.append("") } }
      } header: {
        Text("Tautan hasil (opsional)")
      } footer: {
        Text("Maksimal 5 tautan HTTPS. Tidak ada unggahan file.")
      }
      if let error { Section { Text(error).foregroundStyle(.red) } }
      Section {
        GLPrimaryButton(title: "Kirim untuk Direview", systemImage: "arrow.up.doc") {
          do {
            try store.submitWork(
              taskID: task.id, note: note, links: links, expectedVersion: task.version)
            dismiss()
          } catch { self.error = error.localizedDescription }
        }.listRowInsets(EdgeInsets()).listRowBackground(Color.clear).accessibilityIdentifier(
          "submit-work")
      }
    }.scrollContentBackground(.hidden).glScreen().navigationTitle("Kirim Hasil")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() } } }
  }
}

struct ReviewEditor: View {
  @Environment(DemoStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let task: GLTask
  @State private var feedback = ""
  @State private var error: String?
  var body: some View {
    Form {
      Section("Hasil yang diperiksa") {
        Text(task.title).font(.headline)
        if let sub = task.submissions.last {
          Text("Revisi \(sub.revision) · \(store.user(sub.authorID)?.name ?? "Anggota")").font(
            .subheadline)
          Text(sub.note).textSelection(.enabled)
          ForEach(sub.links, id: \.self) { link in
            if let url = URL(string: link), url.scheme == "https" { Link(link, destination: url) }
          }
        }
      }
      Section("Feedback") {
        TextField("Wajib diisi jika meminta revisi…", text: $feedback, axis: .vertical).lineLimit(
          3...8
        ).accessibilityIdentifier("review-feedback")
      }
      if let error { Text(error).foregroundStyle(.red) }
      Section {
        GLPrimaryButton(title: "Setujui Hasil", systemImage: "checkmark") { decide(true) }
          .listRowInsets(EdgeInsets()).listRowBackground(Color.clear).accessibilityIdentifier(
            "approve-work")
        Button("Minta Revisi", systemImage: "arrow.uturn.backward") { decide(false) }.frame(
          maxWidth: .infinity, minHeight: 48)
      }
    }.scrollContentBackground(.hidden).glScreen().navigationTitle("Review Hasil")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() } } }
  }
  private func decide(_ approve: Bool) {
    do {
      try store.review(
        taskID: task.id, approve: approve, feedback: feedback, expectedVersion: task.version)
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}
