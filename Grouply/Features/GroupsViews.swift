import SwiftUI

struct GroupsView: View {
  @Environment(DemoStore.self) private var store
  @State private var sheet: String?
  @State private var createdGroupID: String?
  @State private var openedGroupID: String?
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        HStack {
          Text("Grup").font(.largeTitle.bold())
          Spacer()
          Button {
            sheet = "create"
          } label: {
            Image(systemName: "plus").font(.title3.weight(.semibold)).foregroundStyle(.white).frame(
              width: 44, height: 44
            ).background(GLTheme.ink, in: Circle())
          }.accessibilityLabel("Buat grup").accessibilityIdentifier("group-create")
        }
        if store.myGroups.isEmpty {
          GLEmptyState(
            title: "Mulai bareng timmu",
            message: "Buat grup baru atau gabung dengan kode undangan.", systemImage: "person.3")
        }
        ForEach(store.myGroups) { group in
          NavigationLink(value: Route.group(group.id)) {
            GLCard {
              VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                  Image(systemName: "person.3.fill").font(.title2).frame(width: 52, height: 52)
                    .background(Color(hex: group.tint), in: RoundedRectangle(cornerRadius: 18))
                  VStack(alignment: .leading, spacing: 4) {
                    Text(group.name).font(.headline).multilineTextAlignment(.leading)
                    Text(group.course).font(.subheadline).foregroundStyle(GLTheme.secondary)
                  }
                  Spacer(minLength: 4)
                  Image(systemName: "chevron.right").font(.caption).foregroundStyle(
                    GLTheme.secondary)
                }
                HStack(spacing: 0) {
                  ForEach(Array(group.memberIDs.prefix(4)), id: \.self) { id in
                    GLAvatar(user: store.user(id), size: 28).overlay(
                      Circle().stroke(.white, lineWidth: 2)
                    ).padding(.trailing, -6)
                  }
                  Spacer(minLength: 10)
                  Text(store.isCoordinator(groupID: group.id) ? "Koordinator" : "Anggota").font(
                    .caption.weight(.semibold)
                  ).padding(.horizontal, 10).padding(.vertical, 6).background(
                    store.isCoordinator(groupID: group.id) ? GLTheme.lavender : GLTheme.muted,
                    in: Capsule())
                }
                HStack {
                  Text("\(group.memberIDs.count) anggota")
                  Text("·")
                  Text("\(store.projects(in: group.id).count) proyek")
                }.font(.caption).foregroundStyle(GLTheme.secondary)
              }
            }
          }.buttonStyle(.plain)
        }
        Button {
          sheet = "join"
        } label: {
          Label("Gabung dengan kode undangan", systemImage: "link").font(
            .subheadline.weight(.semibold)
          ).frame(maxWidth: .infinity, minHeight: 56)
            .overlay(
              RoundedRectangle(cornerRadius: 20).stroke(
                GLTheme.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [5])))
        }.buttonStyle(.plain)

      }.padding(20)
    }.glScreen().toolbar(.hidden, for: .navigationBar)
      .sheet(
        item: Binding(get: { sheet.map(GroupSheet.init) }, set: { sheet = $0?.id }),
        onDismiss: {
          openedGroupID = createdGroupID
          createdGroupID = nil
        }
      ) { selection in
        GroupFormView(
          groupID: nil, joining: selection.id == "join", onCreated: { createdGroupID = $0 })
      }
      .navigationDestination(item: $openedGroupID) { GroupDetailView(groupID: $0) }
  }
}
private struct GroupSheet: Identifiable { var id: String }

struct GroupDetailView: View {
  let groupID: String
  @Environment(DemoStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var sheet: String?
  @State private var filter = "Aktif"
  @State private var error: String?
  @State private var confirmLeave = false
  @State private var invite: GLInvite?
  @State private var createdProjectID: String?
  @State private var openedProjectID: String?
  var body: some View {
    Group {
      if let group = store.group(groupID), store.isMember(groupID: groupID) {
        ScrollView {
          VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
              Image(systemName: "person.3.fill").font(.largeTitle).padding(18).background(
                Color(hex: group.tint), in: RoundedRectangle(cornerRadius: 24))
              Spacer()
              Text(store.isCoordinator(groupID: groupID) ? "Koordinator" : "Anggota").font(
                .caption.bold()
              ).padding(10).background(GLTheme.lavender, in: Capsule())
            }
            Text(group.name).font(.largeTitle.bold())
            Text(group.course).foregroundStyle(GLTheme.secondary)
            if !group.description.isEmpty { Text(group.description) }
            HStack {
              NavigationLink(value: Route.chat(groupID)) {
                Label("Chat grup", systemImage: "bubble.left.and.bubble.right")
              }
              Spacer()
              Button {
                sheet = "members"
              } label: {
                Label("\(group.memberIDs.count) anggota", systemImage: "person.2")
              }
            }.buttonStyle(.bordered).controlSize(.large)
            HStack {
              Text("Proyek").font(.title2.bold())
              Spacer()
              if store.isCoordinator(groupID: groupID) {
                Button {
                  sheet = "project"
                } label: {
                  Image(systemName: "plus").frame(width: 44, height: 44)
                }.accessibilityLabel("Buat proyek").accessibilityIdentifier("create-project")
              }
            }
            Picker("Status proyek", selection: $filter) {
              ForEach(["Aktif", "Selesai", "Arsip"], id: \.self) { Text($0) }
            }.pickerStyle(.segmented)
            let projects = store.projects(in: groupID).filter {
              filter == "Arsip"
                ? $0.status == .archived
                : filter == "Selesai" ? $0.status == .completed : $0.status == .active
            }
            if projects.isEmpty {
              GLEmptyState(
                title: "Belum ada proyek \(filter.lowercased())",
                message: "Proyek dan semua tugas tim akan muncul di sini.", systemImage: "folder")
            }
            ForEach(projects) { project in
              NavigationLink(value: Route.project(project.id)) { GLProjectRow(project: project) }
                .buttonStyle(.plain)
            }
          }.padding(20)
        }.glScreen()
          .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
              Menu {
                if store.isCoordinator(groupID: groupID) {
                  Button("Edit grup", systemImage: "pencil") { sheet = "edit" }
                  Button("Buat undangan", systemImage: "link") {
                    perform {
                      invite = try store.generateInvite(groupID: groupID)
                      sheet = "invite"
                    }
                  }
                }
                Button("Anggota", systemImage: "person.2") { sheet = "members" }
                Button(
                  "Keluar dari grup", systemImage: "rectangle.portrait.and.arrow.right",
                  role: .destructive
                ) { confirmLeave = true }
              } label: {
                Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
              }.accessibilityLabel("Pengaturan grup")
            }
          }
      } else {
        GLEmptyState(
          title: "Akses grup berakhir", message: "Kamu sudah bukan anggota grup ini.",
          systemImage: "lock")
      }
    }.navigationTitle("Detail grup").navigationBarTitleDisplayMode(.inline).toolbar(
      .visible, for: .navigationBar
    )
    .sheet(
      item: Binding(get: { sheet.map(GroupSheet.init) }, set: { sheet = $0?.id }),
      onDismiss: {
        openedProjectID = createdProjectID
        createdProjectID = nil
      }
    ) { item in
      if item.id == "members" {
        MembersView(groupID: groupID)
      } else if item.id == "project" {
        NavigationStack { ProjectEditor(groupID: groupID, onCreated: { createdProjectID = $0 }) }
      } else if item.id == "invite", let invite {
        InviteView(invite: invite)
      } else {
        GroupFormView(groupID: groupID, joining: false)
      }
    }
    .navigationDestination(item: $openedProjectID) { ProjectDetailView(projectID: $0) }
    .confirmationDialog("Keluar dari grup?", isPresented: $confirmLeave, titleVisibility: .visible)
    {
      Button("Keluar", role: .destructive) {
        perform {
          try store.leaveGroup(groupID)
          dismiss()
        }
      }
    } message: {
      Text(
        "Akses proyek dan chat akan berakhir. Alihkan tugas aktif dan peran koordinator terlebih dahulu."
      )
    }
    .alert(
      "Belum bisa dilakukan",
      isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
    ) {
      Button("Mengerti") { error = nil }
    } message: {
      Text(error ?? "")
    }
  }
  private func perform(_ action: () throws -> Void) {
    do { try action() } catch { self.error = error.localizedDescription }
  }
}

private struct GroupFormView: View {
  let groupID: String?
  let joining: Bool
  var onCreated: (String) -> Void = { _ in }
  @Environment(DemoStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var course = ""
  @State private var description = ""
  @State private var code = ""
  @State private var error: String?
  var body: some View {
    NavigationStack {
      Form {
        if joining {
          Section("Kode undangan") {
            TextField("Contoh: STAT-K1Q", text: $code).accessibilityIdentifier("join-code")
              .textInputAutocapitalization(.characters).autocorrectionDisabled()
          }
          Section {
            Text("Undangan berlaku 7 hari. Untuk demo, coba STAT-K1Q.").foregroundStyle(
              GLTheme.secondary)
          }
        } else {
          Section("Tentang grup") {
            TextField("Nama grup", text: $name).accessibilityIdentifier("group-name")
            TextField("Mata kuliah", text: $course)
            TextField("Deskripsi", text: $description, axis: .vertical).lineLimit(3...6)
          }
        }
        if let error { Text(error).foregroundStyle(.red) }
        Button(joining ? "Gabung grup" : "Simpan grup") {
          do {
            if joining {
              onCreated(try store.joinGroup(code: code))
            } else if let groupID {
              try store.updateGroup(
                id: groupID, name: name, description: description, course: course)
            } else {
              onCreated(try store.createGroup(name: name, description: description, course: course))
            }
            dismiss()
          } catch { self.error = error.localizedDescription }
        }.fontWeight(.semibold).accessibilityIdentifier("group-save")
      }.navigationTitle(joining ? "Gabung grup" : groupID == nil ? "Buat grup" : "Edit grup")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Batal") { dismiss() } } }
        .onAppear {
          if let groupID, let group = store.group(groupID) {
            name = group.name
            course = group.course
            description = group.description
          }
        }
    }
  }
}

private struct MembersView: View {
  let groupID: String
  @Environment(DemoStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var error: String?
  @State private var pending: String?
  @State private var transfer = false
  var body: some View {
    NavigationStack {
      List {
        if let group = store.group(groupID) {
          Section {
            Text("\(group.memberIDs.count) dari maksimal 8 anggota").foregroundStyle(
              GLTheme.secondary)
          }
          ForEach(group.memberIDs, id: \.self) { id in
            HStack {
              GLAvatar(user: store.user(id))
              VStack(alignment: .leading) {
                Text(store.user(id)?.name ?? "Pengguna").fontWeight(.semibold)
                Text(group.coordinatorID == id ? "Koordinator" : "Anggota").font(.caption)
                  .foregroundStyle(GLTheme.secondary)
              }
              Spacer()
              if store.isCoordinator(groupID: groupID), id != store.currentUserID {
                Menu {
                  Button("Jadikan koordinator") {
                    pending = id
                    transfer = true
                  }
                  Button("Keluarkan anggota", role: .destructive) {
                    pending = id
                    transfer = false
                  }
                } label: {
                  Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }.accessibilityLabel("Kelola \(store.user(id)?.name ?? "anggota")")
              }
            }
          }
        }
      }.navigationTitle("Anggota grup").toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Selesai") { dismiss() } }
      }
      .confirmationDialog(
        transfer ? "Alihkan peran koordinator?" : "Keluarkan anggota?",
        isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
        titleVisibility: .visible
      ) {
        Button(transfer ? "Alihkan peran" : "Keluarkan", role: transfer ? nil : .destructive) {
          guard let id = pending else { return }
          pending = nil
          do {
            if transfer {
              try store.transferCoordinator(groupID: groupID, to: id)
            } else {
              try store.removeMember(groupID: groupID, userID: id)
            }
          } catch { self.error = error.localizedDescription }
        }
      } message: {
        Text(
          transfer
            ? "Kamu menjadi anggota biasa. Koordinator baru akan mengelola grup."
            : "Alihkan tugas aktif anggota ini sebelum menghapus aksesnya.")
      }
      .alert(
        "Belum bisa dilakukan",
        isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
      ) {
        Button("Mengerti") { error = nil }
      } message: {
        Text(error ?? "")
      }
    }
  }
}

private struct InviteView: View {
  let invite: GLInvite
  @Environment(DemoStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var error: String?
  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        Image(systemName: "link").font(.largeTitle).padding(24).background(
          GLTheme.mint, in: RoundedRectangle(cornerRadius: 24))
        Text("Ajak timmu bergabung").font(.title2.bold())
        Text(invite.code).font(.largeTitle.monospaced().bold()).textSelection(.enabled)
        Text("Berlaku sampai \(invite.expiresAt.formatted(date: .abbreviated, time: .shortened))")
          .foregroundStyle(GLTheme.secondary).multilineTextAlignment(.center)
        GLNotice(text: "Kode ini hanya bekerja di demo lokal pada perangkat ini.")
        ShareLink(item: "Gabung ke grup GROUPLY. Kode demo: \(invite.code)") {
          Label("Bagikan kode", systemImage: "square.and.arrow.up").foregroundStyle(.white)
        }.buttonStyle(.borderedProminent).tint(GLTheme.ink).controlSize(.large)
        Button("Nonaktifkan undangan", role: .destructive) {
          do {
            try store.revokeInvite(invite.id)
            dismiss()
          } catch { self.error = error.localizedDescription }
        }
        if let error { Text(error).foregroundStyle(.red) }
        Spacer()
      }.padding(24).navigationTitle("Undangan").toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Selesai") { dismiss() } }
      }
    }
  }
}
