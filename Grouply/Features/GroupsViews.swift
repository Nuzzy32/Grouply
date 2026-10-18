import SwiftUI

struct GroupsView: View {
  @Environment(DemoStore.self) private var store
  @State private var sheet: String?
  @State private var createdGroupID: String?
  @State private var openedGroupID: String?
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          Text("Grup").gl(34, .bold, em: -0.03)
          Spacer()
          Button {
            sheet = "create"
          } label: {
            GLIcon("plus", size: 28).foregroundStyle(GLTheme.onInk).frame(width: 52, height: 52)
              .background(GLTheme.ink, in: Circle())
          }.buttonStyle(.plain).accessibilityLabel("Buat grup").accessibilityIdentifier("group-create")
        }
        if store.myGroups.isEmpty {
          GLEmptyState(
            title: "Belum ada grup",
            message:
              "Grup menyatukan proyek, tugas, dan chat kelompokmu. Buat grup dengan tombol + atau gabung pakai kode undangan.",
            systemImage: "person.3")
        }
        ForEach(store.myGroups) { group in
          NavigationLink(value: Route.group(group.id)) { GroupCard(group: group) }
            .buttonStyle(GLCardButtonStyle())
        }
        Button {
          sheet = "join"
        } label: {
          HStack(spacing: 8) {
            GLIcon("key", size: 20)
            Text("Gabung dengan kode undangan").gl(15, .semibold)
          }.frame(maxWidth: .infinity).frame(height: 56)
            .overlay(
              RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(
                GLTheme.ink.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
      }.padding(.horizontal, 20).padding(.top, 10)
    }.glScreen().refreshable { await store.refreshFromBackend() }.toolbar(
      .hidden, for: .navigationBar
    )
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

/// Group card on the Grup tab (prototype `groupsVals`).
struct GroupCard: View {
  @Environment(DemoStore.self) private var store
  let group: GLGroup
  var body: some View {
    let coord = group.coordinatorID == store.currentUserID
    let active = store.projects(in: group.id).filter { $0.status == .active }.count
    let unread = store.unreadCount(groupID: group.id)
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 14) {
        GLIcon(group.icon, size: 26).frame(width: 52, height: 52)
          .background(Color(tint: group.tint), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        VStack(alignment: .leading, spacing: 2) {
          Text(group.name).gl(18, .bold, em: -0.015).multilineTextAlignment(.leading)
          Text(group.course).gl(14).foregroundStyle(GLTheme.secondary)
        }
        Spacer(minLength: 0)
        GLIcon("chevron.right", size: 22).foregroundStyle(GLTheme.secondary)
      }
      HStack(spacing: 10) {
        HStack(spacing: -8) {
          ForEach(Array(group.memberIDs.prefix(5)), id: \.self) { id in
            GLAvatar(user: store.user(id), size: 32, fontSize: 11)
              .overlay(Circle().stroke(GLTheme.surface, lineWidth: 2.5))
          }
        }.padding(.trailing, 8)
        Text(
          "\(group.memberIDs.count) anggota · "
            + (active > 0 ? "\(active) proyek aktif" : "Belum ada proyek aktif")
        ).gl(14).foregroundStyle(GLTheme.text3)
      }
      HStack(spacing: 6) {
        GLChip(
          label: coord ? "Koordinator" : "Anggota", background: coord ? GLTheme.mint : GLTheme.muted,
          fontSize: 12)
        if unread > 0 {
          GLChip(
            label: "\(unread) pesan baru", icon: "bubble.left", background: GLTheme.ink,
            foreground: GLTheme.onInk, fontSize: 12, iconSize: 15)
        }
      }
    }
    .padding(18).frame(maxWidth: .infinity, alignment: .leading).glSurface(28)
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Group detail (prototype `isGroup` + `groupVals`)

struct GroupDetailView: View {
  let groupID: String
  @Environment(DemoStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var filter = "active"
  @State private var showSettings = false
  @State private var showMembers = false
  @State private var showNewProject = false
  @State private var memberID: String?
  @State private var invite: GLInvite?
  @State private var confirm: GLConfirmation?
  @State private var createdProjectID: String?
  @State private var openedProjectID: String?

  var body: some View {
    Group {
      if let group = store.group(groupID), store.isMember(groupID: groupID) {
        content(group)
      } else {
        GLAccessDenied()
      }
    }
    .navigationDestination(isPresented: $showSettings) {
      GroupSettingsView(groupID: groupID, filter: $filter, onLeft: left)
    }
    .navigationDestination(isPresented: $showMembers) {
      GroupMembersView(groupID: groupID, onLeft: left)
    }
    .navigationDestination(item: $openedProjectID) { ProjectDetailView(projectID: $0) }
    .sheet(
      isPresented: $showNewProject,
      onDismiss: {
        openedProjectID = createdProjectID
        createdProjectID = nil
      }
    ) { ProjectEditor(groupID: groupID, onCreated: { createdProjectID = $0 }) }
    .sheet(item: Binding(get: { memberID.map(GroupSheet.init) }, set: { memberID = $0?.id })) {
      GroupMemberSheet(groupID: groupID, userID: $0.id) { confirm = $0 }
    }
    .sheet(item: $invite) { GroupInviteSheet(inviteID: $0.id) }
    .glConfirm($confirm)
  }

  private func left() {
    showSettings = false
    showMembers = false
    dismiss()
  }

  @ViewBuilder private func content(_ group: GLGroup) -> some View {
    let coord = store.isCoordinator(groupID: groupID)
    let all = store.projects(in: groupID)
    let lists: [(key: String, label: String, items: [GLProject])] = [
      ("active", "Aktif", all.filter { $0.status == .active }),
      ("done", "Selesai", all.filter { $0.status == .completed }),
      ("archived", "Arsip", all.filter { $0.status == .archived }),
    ]
    let current = lists.first { $0.key == filter } ?? lists[0]
    let liveIDs = Set(all.filter { $0.status != .archived }.map(\.id))
    let running = store.tasks.filter { liveIDs.contains($0.projectID) && $0.status != .done }.count
    let unread = store.unreadCount(groupID: groupID)

    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        GLDetailHeader("Grup") {
          GLCircleButton(icon: "gearshape", label: "Pengaturan grup") { showSettings = true }
        }

        // Group card
        VStack(alignment: .leading, spacing: 14) {
          HStack(spacing: 14) {
            GLIcon(group.icon, size: 28).frame(width: 58, height: 58)
              .background(Color(tint: group.tint), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
              Text(group.name).gl(23, .bold, em: -0.02).multilineTextAlignment(.leading)
              Text(group.course).gl(14).foregroundStyle(GLTheme.secondary)
            }
            Spacer(minLength: 0)
          }
          if !group.description.isEmpty {
            Text(group.description).gl(15).lineSpacing(4).foregroundStyle(GLTheme.text3)
          }
          HStack(spacing: 6) {
            GLIcon("chart.xyaxis.line", size: 18)
            Text("\(lists[0].items.count) proyek aktif · \(running) tugas berjalan").gl(14)
          }.foregroundStyle(GLTheme.text3)
          HStack(spacing: 8) {
            NavigationLink(value: Route.chat(groupID)) {
              HStack(spacing: 6) {
                GLIcon("bubble.left", size: 19)
                Text("Chat grup").gl(15, .semibold)
                if unread > 0 {
                  Text("\(unread)").gl(12, .bold).foregroundStyle(GLTheme.ink)
                    .padding(.horizontal, 6).frame(minWidth: 22, minHeight: 22)
                    .background(GLTheme.mint, in: Capsule())
                }
              }.foregroundStyle(GLTheme.onInk).frame(maxWidth: .infinity).frame(height: 48)
                .background(GLTheme.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }.buttonStyle(.plain)
              .accessibilityLabel(unread > 0 ? "Chat grup, \(unread) pesan baru" : "Chat grup")
            GLOutlineButton(title: "Anggota", icon: "person.2", height: 48, radius: 16) {
              showMembers = true
            }
          }
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(GLTheme.surface, in: RoundedRectangle(cornerRadius: 32, style: .continuous))

        // Members
        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
              Text("Anggota").gl(21, .bold, em: -0.02)
              Text("\(group.memberIDs.count) dari 8 anggota").gl(13).foregroundStyle(GLTheme.secondary)
            }
            Spacer(minLength: 0)
            Button(action: inviteTapped) {
              HStack(spacing: 4) {
                GLIcon(coord ? "person.badge.plus" : "lock", size: 19)
                Text("Undang").gl(14, .semibold)
              }.padding(.leading, 10).padding(.trailing, 14).frame(height: 44)
                .overlay(Capsule().strokeBorder(GLTheme.ink, lineWidth: 1.5)).contentShape(Capsule())
            }.buttonStyle(.plain).accessibilityLabel("Undang anggota")
          }
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 4) {
              ForEach(group.memberIDs, id: \.self) { id in
                let isC = id == group.coordinatorID
                Button {
                  memberID = id
                } label: {
                  VStack(spacing: 4) {
                    GLAvatar(user: store.user(id), size: 48, fontSize: 14)
                    Text(store.displayName(id)).gl(13, .semibold).lineLimit(1).frame(maxWidth: 72)
                    Text(isC ? "Koordinator" : "Anggota").gl(11, .semibold).foregroundStyle(GLTheme.text3)
                      .lineLimit(1).fixedSize().padding(.vertical, 2).padding(.horizontal, 7)
                      .background(isC ? GLTheme.mint : .clear, in: Capsule())
                  }.padding(.vertical, 4).frame(width: 76).frame(minHeight: 96, alignment: .top)
                }.buttonStyle(GroupsPressStyle(scale: 0.94))
                  .accessibilityElement(children: .ignore)
                  .accessibilityLabel("\(store.displayName(id)), \(isC ? "Koordinator" : "Anggota")")
                  .accessibilityAddTraits(.isButton)
              }
            }.padding(.horizontal, 4).padding(.vertical, 2)
          }.padding(.horizontal, -4)
          if group.memberIDs.count == 1 {
            Text("Belum ada anggota lain. Undang teman sekelompok dengan kode undangan.")
              .gl(14).lineSpacing(4).foregroundStyle(GLTheme.text3)
              .padding(.vertical, 14).padding(.horizontal, 16)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(GLTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
          }
        }

        // Projects
        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 8) {
            Text("Proyek").gl(21, .bold, em: -0.02)
            Spacer(minLength: 0)
            Button(action: newProjectTapped) {
              HStack(spacing: 4) {
                GLIcon(coord ? "plus" : "lock", size: 19)
                Text("Buat proyek").gl(14, .semibold)
              }.foregroundStyle(GLTheme.onInk).padding(.leading, 10).padding(.trailing, 14).frame(height: 44)
                .background(GLTheme.ink, in: Capsule())
            }.buttonStyle(.plain).accessibilityLabel("Buat proyek")
              .accessibilityIdentifier("create-project")
          }
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
              ForEach(lists, id: \.key) { f in
                let on = f.key == current.key
                Button {
                  withAnimation(.easeOut(duration: 0.2)) { filter = f.key }
                } label: {
                  Text("\(f.label) · \(f.items.count)").gl(14, .semibold)
                    .foregroundStyle(on ? GLTheme.onInk : GLTheme.ink).padding(.horizontal, 16).frame(height: 44)
                    .background(on ? GLTheme.ink : GLTheme.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(GLTheme.ink, lineWidth: 1.5))
                }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
              }
            }.padding(.horizontal, 20)
          }.padding(.horizontal, -20)
          ForEach(current.items) { project in
            NavigationLink(value: Route.project(project.id)) { GroupProjectCard(project: project) }
              .buttonStyle(GLCardButtonStyle())
          }
          if all.isEmpty {
            VStack(spacing: 10) {
              GLIcon("folder", size: 28).frame(width: 56, height: 56)
                .background(GLTheme.butter, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
              Text("Belum ada proyek").gl(19, .bold)
              Text(
                coord
                  ? "Mulai proyek pertama untuk mengatur tugas dan kerja sama kelompokmu."
                  : "Koordinator belum membuat proyek. Proyek baru akan muncul di sini."
              ).gl(15).lineSpacing(4).foregroundStyle(GLTheme.secondary)
              if coord {
                Button(action: newProjectTapped) {
                  Text("Buat Proyek").gl(15, .semibold).foregroundStyle(GLTheme.onInk)
                    .padding(.horizontal, 24).frame(height: 50)
                    .background(GLTheme.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }.buttonStyle(.plain).padding(.top, 4)
              }
            }.multilineTextAlignment(.center).frame(maxWidth: .infinity)
              .padding(.vertical, 26).padding(.horizontal, 22)
              .background(GLTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
          } else if current.items.isEmpty {
            Text(
              current.key == "archived"
                ? "Belum ada proyek yang diarsipkan."
                : current.key == "done"
                  ? "Belum ada proyek yang selesai." : "Tidak ada proyek aktif. Lihat tab Selesai atau Arsip."
            ).gl(15).foregroundStyle(GLTheme.secondary).multilineTextAlignment(.center)
              .frame(maxWidth: .infinity).padding(.vertical, 20)
          }
        }.padding(.top, 4)
      }.padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 24)
    }
    .glDetailScreen()
    .refreshable { await store.refreshFromBackend() }
  }

  private func inviteTapped() {
    Task { if let made = await store.groupsCreateInvite(groupID) { invite = made } }
  }
  private func newProjectTapped() {
    guard store.isCoordinator(groupID: groupID) else {
      return store.flash("Hanya koordinator yang bisa membuat proyek.", .err)
    }
    showNewProject = true
  }
}

/// Group-detail project card: 12×40 tint bar, status chip, progress bar (prototype `vmProject`).
private struct GroupProjectCard: View {
  @Environment(DemoStore.self) private var store
  let project: GLProject
  var body: some View {
    let tasks = store.tasks(in: project.id)
    let done = tasks.filter { $0.status == .done }.count
    let status: (label: String, bg: Color, icon: String) =
      switch project.status {
      case .archived: ("Diarsipkan", GLTheme.chip, "archivebox")
      case .completed: ("Selesai", GLTheme.mint, "checkmark.circle")
      case .active: ("Aktif", GLTheme.sky, "bolt")
      }
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(Color(tint: store.group(project.groupID)?.tint ?? "FFFFFF")).frame(width: 12, height: 40)
        VStack(alignment: .leading, spacing: 2) {
          Text(project.title).gl(16, .semibold).multilineTextAlignment(.leading)
          Text("Deadline \(GLFormat.date(project.dueAt))").gl(13).foregroundStyle(GLTheme.secondary)
        }
        Spacer(minLength: 0)
        HStack(spacing: 4) {
          GLIcon(status.icon, size: 15)
          Text(status.label).gl(12, .semibold).lineLimit(1)
        }.padding(.leading, 7).padding(.trailing, 10).frame(height: 28)
          .background(status.bg, in: Capsule())
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
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Members screen (prototype `isMembers` + `membersVals`)

private struct GroupMembersView: View {
  let groupID: String
  var onLeft: () -> Void
  @Environment(DemoStore.self) private var store
  @State private var memberID: String?
  @State private var invite: GLInvite?
  @State private var confirm: GLConfirmation?
  var body: some View {
    Group {
      if let group = store.group(groupID), store.isMember(groupID: groupID) {
        let coord = store.isCoordinator(groupID: groupID)
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            GLDetailHeader("Anggota")
            HStack(spacing: 10) {
              Text("\(group.memberIDs.count) dari 8 anggota").gl(15).foregroundStyle(GLTheme.text3)
              Spacer(minLength: 0)
              Button {
                Task { if let made = await store.groupsCreateInvite(groupID) { invite = made } }
              } label: {
                HStack(spacing: 6) {
                  GLIcon(coord ? "person.badge.plus" : "lock", size: 19)
                  Text("Undang anggota").gl(14, .semibold)
                }.foregroundStyle(GLTheme.onInk).padding(.leading, 12).padding(.trailing, 16).frame(height: 44)
                  .background(GLTheme.ink, in: Capsule())
              }.buttonStyle(.plain)
            }
            VStack(spacing: 0) {
              ForEach(group.memberIDs, id: \.self) { id in
                Button { memberID = id } label: { row(id, group: group) }
                  .buttonStyle(GLRowButtonStyle())
              }
            }.padding(.vertical, 4).padding(.horizontal, 14)
              .background(GLTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            if group.memberIDs.count == 1 {
              Text("Belum ada anggota lain. Bagikan kode undangan supaya teman bisa bergabung.")
                .gl(14).lineSpacing(4).padding(.vertical, 14).padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GLTheme.muted, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            GroupLeaveButton {
              confirm = store.groupsLeaveConfirmation(groupID: groupID, pickCoordinator: {}, onLeft: onLeft)
            }
          }.padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 24)
        }.glDetailScreen()
      } else {
        GLAccessDenied()
      }
    }
    .sheet(item: Binding(get: { memberID.map(GroupSheet.init) }, set: { memberID = $0?.id })) {
      GroupMemberSheet(groupID: groupID, userID: $0.id) { confirm = $0 }
    }
    .sheet(item: $invite) { GroupInviteSheet(inviteID: $0.id) }
    .glConfirm($confirm)
  }

  private func row(_ id: String, group: GLGroup) -> some View {
    let isC = id == group.coordinatorID
    let blocked = store.blockedUserIDs.contains(id)
    let name = (store.user(id)?.name ?? "Pengguna") + (id == store.currentUserID ? " (kamu)" : "")
    return HStack(spacing: 12) {
      GLAvatar(user: store.user(id), size: 44, fontSize: 14)
      VStack(alignment: .leading, spacing: 2) {
        Text(name).gl(16, .semibold).multilineTextAlignment(.leading)
        Text(
          "\(isC ? "Koordinator" : "Anggota") · \(store.groupsActiveTaskCount(groupID: groupID, userID: id)) tugas aktif"
        ).gl(13).foregroundStyle(GLTheme.secondary)
      }
      Spacer(minLength: 0)
      if isC { GroupsSmallChip(label: "Koordinator", icon: "person.badge.shield.checkmark", bg: GLTheme.mint) }
      if blocked { GroupsSmallChip(label: "Diblokir", icon: "nosign", bg: GLTheme.coral) }
    }
    .padding(.vertical, 10).frame(minHeight: 64)
    .overlay(alignment: .bottom) { Rectangle().fill(GLTheme.border).frame(height: 1) }
    .accessibilityElement(children: .combine)
  }
}

private struct GroupsSmallChip: View {
  let label: String
  let icon: String
  let bg: Color
  var body: some View {
    HStack(spacing: 3) {
      GLIcon(icon, size: 15)
      Text(label).gl(12, .semibold).lineLimit(1)
    }.padding(.leading, 6).padding(.trailing, 9).frame(height: 26).background(bg, in: Capsule())
  }
}

/// `height:52px;border-radius:18px;border:1.5px solid #A8231B` "Keluar dari grup".
private struct GroupLeaveButton: View {
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        GLIcon("rectangle.portrait.and.arrow.right", size: 19)
        Text("Keluar dari grup").gl(15, .semibold)
      }.foregroundStyle(GLTheme.danger).frame(maxWidth: .infinity).frame(height: 52)
        .overlay(
          RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(GLTheme.danger, lineWidth: 1.5)
        ).contentShape(Rectangle())
    }.buttonStyle(.plain)
  }
}

// MARK: - Settings screen (prototype `isSettings`)

private struct GroupSettingsView: View {
  let groupID: String
  @Binding var filter: String
  var onLeft: () -> Void
  @Environment(DemoStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var desc = ""
  @State private var error: String?
  @State private var invite: GLInvite?
  @State private var confirm: GLConfirmation?
  @State private var showMembers = false
  var body: some View {
    let coord = store.isCoordinator(groupID: groupID)
    Group {
      if let group = store.group(groupID), store.isMember(groupID: groupID) {
        ScrollView {
          VStack(alignment: .leading, spacing: 16) {
            GLDetailHeader("Pengaturan grup")
            VStack(alignment: .leading, spacing: 14) {
              GLField("Nama grup") {
                TextField("", text: $name).gl(16).groupsSettingsInput()
                  .onChange(of: name) { _, v in if v.count > 40 { name = String(v.prefix(40)) } }
              }
              GLField("Deskripsi", trailing: "\(desc.count)/140") {
                TextField("Tujuan atau catatan singkat grup", text: $desc, axis: .vertical)
                  .gl(16).lineSpacing(3).lineLimit(3, reservesSpace: true).groupsSettingsInput(height: nil)
                  .onChange(of: desc) { _, v in if v.count > 140 { desc = String(v.prefix(140)) } }
              }
              if let error { GLFormError(text: error) }
              if coord {
                Button { save(group) } label: {
                  Text(store.isBusy ? "Menyimpan…" : "Simpan").gl(16, .semibold).foregroundStyle(GLTheme.onInk)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(GLTheme.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .opacity(store.isBusy ? 0.6 : 1)
                }.buttonStyle(.plain).disabled(store.isBusy)
              } else {
                HStack(spacing: 6) {
                  GLIcon("lock", size: 18)
                  Text("Hanya koordinator yang bisa mengubah pengaturan grup.").gl(14)
                }.foregroundStyle(GLTheme.text3)
              }
            }.disabled(!coord).padding(18).frame(maxWidth: .infinity, alignment: .leading)
              .background(GLTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            VStack(spacing: 0) {
              settingsRow(coord ? "qrcode" : "lock", "Buat kode undangan", divider: true) {
                Task { if let made = await store.groupsCreateInvite(groupID) { invite = made } }
              }
              settingsRow("archivebox", "Proyek diarsipkan", divider: false) {
                filter = "archived"
                dismiss()
              }
            }.padding(.vertical, 4).padding(.horizontal, 16)
              .background(GLTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            GroupLeaveButton {
              confirm = store.groupsLeaveConfirmation(
                groupID: groupID, pickCoordinator: { showMembers = true }, onLeft: onLeft)
            }
          }.padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 24)
        }.glDetailScreen()
          .onAppear {
            name = group.name
            desc = group.description
          }
      } else {
        GLAccessDenied()
      }
    }
    .navigationDestination(isPresented: $showMembers) { GroupMembersView(groupID: groupID, onLeft: onLeft) }
    .sheet(item: $invite) { GroupInviteSheet(inviteID: $0.id) }
    .glConfirm($confirm)
  }

  private func settingsRow(_ icon: String, _ title: String, divider: Bool, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      HStack(spacing: 12) {
        GLIcon(icon, size: 22)
        Text(title).gl(16, .semibold).frame(maxWidth: .infinity, alignment: .leading)
        GLIcon("chevron.right", size: 22).foregroundStyle(GLTheme.secondary)
      }.frame(minHeight: 58)
        .overlay(alignment: .bottom) {
          if divider { Rectangle().fill(GLTheme.border).frame(height: 1) }
        }
    }.buttonStyle(GLRowButtonStyle())
  }

  private func save(_ group: GLGroup) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard store.isCoordinator(groupID: groupID) else {
      return store.flash("Hanya koordinator yang bisa mengubah pengaturan grup.", .err)
    }
    if trimmed.count < 3 { return error = "Nama grup minimal 3 karakter." }
    if trimmed.count > 40 { return error = "Nama grup maksimal 40 karakter." }
    if desc.count > 140 { return error = "Deskripsi maksimal 140 karakter." }
    error = nil
    Task {
      do {
        try await store.updateGroup(
          id: groupID, name: trimmed, description: desc.trimmingCharacters(in: .whitespacesAndNewlines),
          course: group.course)
        store.flash("Pengaturan grup disimpan")
      } catch { self.error = error.localizedDescription }
    }
  }
}

extension View {
  /// Settings inputs sit on #F8F9F7 instead of white.
  fileprivate func groupsSettingsInput(height: CGFloat? = 50) -> some View {
    padding(.horizontal, 16).padding(.vertical, height == nil ? 12 : 0)
      .frame(minHeight: height, alignment: .leading)
      .background(GLTheme.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(GLTheme.border))
  }
}

// MARK: - Sheets

/// "Buat grup" (`sheetNewGroup`) and "Gabung ke grup" (`sheetJoin`). `groupID` is unused (editing
/// moved to the settings screen) but kept so the GroupsView call site stays unchanged.
private struct GroupFormView: View {
  let groupID: String?
  let joining: Bool
  var onCreated: (String) -> Void = { _ in }
  @Environment(DemoStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var course = ""
  @State private var code = ""
  @State private var error: String?

  var body: some View {
    Group {
      if joining { joinSheet } else { createSheet }
    }.interactiveDismissDisabled(store.isBusy)
  }

  private var createSheet: some View {
    GLSheet("Buat grup") {
      GLField("Nama grup", required: true) {
        TextField("Contoh: PPL · Kelompok 2", text: $name).gl(16).glInput()
          .accessibilityIdentifier("group-name")
          .onChange(of: name) { _, v in if v.count > 40 { name = String(v.prefix(40)) } }
      }
      GLField("Mata kuliah") {
        TextField("Contoh: Pengembangan Perangkat Lunak", text: $course).gl(16).glInput()
          .onChange(of: course) { _, v in if v.count > 60 { course = String(v.prefix(60)) } }
      }
      Text("Kamu jadi koordinator. Maksimal 8 anggota. Chat grup dibuat otomatis.")
        .gl(14).lineSpacing(4).foregroundStyle(GLTheme.secondary)
      if let error { GLFormError(text: error) }
      GLSubmitButton(title: store.isBusy ? "Membuat…" : "Buat grup", busy: store.isBusy, action: create)
        .accessibilityIdentifier("group-save")
    }
  }

  private var joinSheet: some View {
    GLSheet("Gabung ke grup") {
      GLField("Kode atau link undangan") {
        TextField("Contoh: STAT-K1Q", text: $code).gl(18, .semibold, em: 0.06)
          .textInputAutocapitalization(.characters).autocorrectionDisabled()
          .glInput(height: 54).accessibilityIdentifier("join-code")
      }
      if let error { GLFormError(text: error) }
      GLSubmitButton(title: store.isBusy ? "Bergabung…" : "Gabung", busy: store.isBusy, action: join)
        .accessibilityIdentifier("group-save")
    }
  }

  private func create() {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.count < 3 { return error = "Nama grup minimal 3 karakter." }
    if trimmed.count > 40 { return error = "Nama grup maksimal 40 karakter." }
    error = nil
    let c = course.trimmingCharacters(in: .whitespacesAndNewlines)
    Task {
      do {
        let id = try await store.createGroup(
          name: trimmed, description: "", course: c.isEmpty ? "Mata kuliah belum diisi" : c)
        store.flash("Grup dibuat. Undang anggota lewat kode undangan.")
        onCreated(id)
        dismiss()
      } catch { self.error = error.localizedDescription }
    }
  }

  private func join() {
    let raw = code.trimmingCharacters(in: .whitespacesAndNewlines)
    let parsed = raw.components(separatedBy: "/invite/").dropFirst().first ?? raw
    if let message = store.groupsJoinError(code: parsed) { return error = message }
    error = nil
    Task {
      do {
        let id = try await store.joinGroup(code: parsed)
        store.flash("Kamu bergabung ke \(store.group(id)?.name ?? "grup")")
        onCreated(id)
        dismiss()
      } catch { self.error = error.localizedDescription }
    }
  }
}

/// `sheetInvite`: mint code card, status chip, revoke, copy + share.
private struct GroupInviteSheet: View {
  let inviteID: String
  @Environment(DemoStore.self) private var store
  var body: some View {
    GLSheet("Undang anggota") {
      if let invite = store.invites.first(where: { $0.id == inviteID }) {
        let status = store.groupsInviteStatus(invite)
        let chip: (String, Color, String) =
          switch status {
          case "valid": ("Undangan aktif", GLTheme.surface, "checkmark.circle")
          case "expired": ("Undangan kedaluwarsa", GLTheme.coral, "clock.badge.xmark")
          case "used": ("Undangan tidak berlaku · sudah dipakai", GLTheme.coral, "nosign")
          default: ("Undangan tidak berlaku", GLTheme.coral, "nosign")
          }
        VStack(spacing: 6) {
          Text(store.group(invite.groupID)?.name ?? "").gl(14, .semibold).foregroundStyle(GLTheme.text3)
          Text(invite.code).gl(34, .heavy, em: 0.08).monospacedDigit().textSelection(.enabled)
            .minimumScaleFactor(0.6).lineLimit(1)
          HStack(spacing: 4) {
            GLIcon(chip.2, size: 16)
            Text(chip.0).gl(13, .semibold)
          }.padding(.leading, 8).padding(.trailing, 11).frame(height: 28).background(chip.1, in: Capsule())
          Text(
            "Berlaku sampai \(GLFormat.weekday(invite.expiresAt)), \(GLFormat.date(invite.expiresAt)), \(GLFormat.time(invite.expiresAt)) · \(invite.useCount)/\(invite.maxUses) pemakaian"
          ).gl(13).foregroundStyle(GLTheme.text3)
        }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(22)
          .background(GLTheme.mint, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        if status == "valid" {
          Button { revoke(invite) } label: {
            HStack(spacing: 6) {
              GLIcon("nosign", size: 18)
              Text("Nonaktifkan kode").gl(14, .semibold)
            }.foregroundStyle(GLTheme.danger).frame(minHeight: 44).contentShape(Rectangle())
          }.buttonStyle(.plain).frame(maxWidth: .infinity)
        }
        HStack(spacing: 10) {
          GLOutlineButton(title: "Salin", icon: "doc.on.doc", height: 52, radius: 18) {
            UIPasteboard.general.string = invite.code
            store.flash("Kode \(invite.code) disalin")
          }
          let share = HStack(spacing: 6) {
            GLIcon("square.and.arrow.up", size: 19)
            Text("Bagikan").gl(15, .semibold)
          }.foregroundStyle(GLTheme.onInk).frame(maxWidth: .infinity).frame(height: 52)
            .background(GLTheme.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
          if status == "valid" {
            ShareLink(item: "Gabung ke grup GROUPLY. Kode undangan: \(invite.code)") { share }
              .buttonStyle(.plain)
          } else {
            Button {
              store.flash("Kode ini sudah tidak berlaku. Buat kode baru.", .err)
            } label: { share }.buttonStyle(.plain)
          }
        }
        Text("Bagikan kode ini kepada anggota yang ingin bergabung. Kode berlaku 7 hari dan sekali pakai.").gl(13).lineSpacing(3).foregroundStyle(GLTheme.secondary)
      }
    }
  }
  private func revoke(_ invite: GLInvite) {
    guard store.isCoordinator(groupID: invite.groupID) else {
      return store.flash("Hanya koordinator yang bisa menonaktifkan undangan.", .err)
    }
    Task {
      do {
        try await store.revokeInvite(invite.id)
        store.flash("Kode \(invite.code) dinonaktifkan", .info)
      } catch { store.flash(error.localizedDescription, .err) }
    }
  }
}

/// `sheetMember`: profile header + transfer / remove / block rows. Actions close the sheet, then
/// hand a confirmation to the presenting screen (prototype closes the sheet before `ask`).
private struct GroupMemberSheet: View {
  let groupID: String
  let userID: String
  let ask: (GLConfirmation) -> Void
  @Environment(DemoStore.self) private var store
  @Environment(\.dismiss) private var dismiss

  private struct Row: Identifiable {
    let label: String
    let icon: String
    let color: Color
    let go: () -> Void
    var id: String { label }
  }

  var body: some View {
    GLSheet("") {
      if let group = store.group(groupID) {
        let coord = group.coordinatorID == store.currentUserID
        let isSelf = userID == store.currentUserID
        let isC = userID == group.coordinatorID
        let user = store.user(userID)
        let rows = rows(group: group, coord: coord, isSelf: isSelf, isC: isC)
        VStack(spacing: 6) {
          GLAvatar(user: user, size: 72, fontSize: 22)
          Text((user?.name ?? "Pengguna") + (isSelf ? " (kamu)" : "")).gl(20, .bold)
          if let email = user?.email, !email.isEmpty {
            Text(email).gl(14).foregroundStyle(GLTheme.secondary)
          }
          Text(isC ? "Koordinator" : "Anggota").gl(13, .semibold).padding(.horizontal, 12).frame(height: 28)
            .background(isC ? GLTheme.mint : GLTheme.muted, in: Capsule())
          Text(
            "\(store.groupsActiveTaskCount(groupID: groupID, userID: userID)) tugas aktif · \(store.groupsDoneTaskCount(groupID: groupID, userID: userID)) tugas selesai di grup ini"
          ).gl(14).foregroundStyle(GLTheme.text3)
        }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, -30)
        if !rows.isEmpty {
          VStack(spacing: 0) {
            ForEach(rows) { row in
              Button {
                dismiss()
                row.go()
              } label: {
                HStack(spacing: 12) {
                  GLIcon(row.icon, size: 22)
                  Text(row.label).gl(16, .semibold)
                  Spacer(minLength: 0)
                }.foregroundStyle(row.color).frame(minHeight: 56)
                  .overlay(alignment: .bottom) { Rectangle().fill(GLTheme.border).frame(height: 1) }
              }.buttonStyle(GLRowButtonStyle())
            }
          }.padding(.vertical, 4).padding(.horizontal, 16)
            .background(GLTheme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        if !coord && !isSelf {
          Text("Aksi bertanda gembok hanya untuk koordinator.").gl(13).foregroundStyle(GLTheme.text3)
            .multilineTextAlignment(.center).frame(maxWidth: .infinity)
        }
      }
    }
  }

  private func rows(group: GLGroup, coord: Bool, isSelf: Bool, isC: Bool) -> [Row] {
    let name = store.user(userID)?.name ?? "Anggota"
    let blocked = store.blockedUserIDs.contains(userID)
    var rows: [Row] = []
    if !isSelf && !isC {
      rows.append(
        Row(label: "Jadikan koordinator", icon: coord ? "person.badge.shield.checkmark" : "lock", color: GLTheme.ink) {
          guard coord else {
            return store.flash("Hanya koordinator yang bisa menyerahkan peran koordinator.", .err)
          }
          ask(
            GLConfirmation(
              title: "Jadikan \(name) koordinator?",
              text: "\(name) akan bisa mengelola anggota, proyek, dan tugas. Kamu tetap jadi anggota grup.",
              ok: "Jadikan koordinator"
            ) {
              store.groupsRun("\(name) sekarang koordinator") {
                try await store.transferCoordinator(groupID: groupID, to: userID)
              }
            })
        })
      rows.append(
        Row(
          label: "Keluarkan dari grup", icon: coord ? "person.badge.minus" : "lock",
          color: coord ? GLTheme.danger : GLTheme.ink
        ) {
          guard coord else { return store.flash("Hanya koordinator yang bisa mengeluarkan anggota.", .err) }
          ask(
            GLConfirmation(
              title: "Keluarkan \(name)?",
              text:
                "\(name) tidak bisa lagi membuka proyek dan chat grup ini. Hasil kerja dan tugas yang sudah selesai tetap tercatat atas nama \(name).",
              ok: "Keluarkan", destructive: true
            ) {
              store.groupsRun("\(name) dikeluarkan dari grup", .info) {
                try await store.removeMember(groupID: groupID, userID: userID)
              }
            })
        })
    }
    if !isSelf {
      rows.append(
        Row(label: blocked ? "Buka blokir" : "Blokir \(name)", icon: "nosign", color: GLTheme.danger) {
          if blocked {
            return store.groupsRun("\(name) tidak lagi diblokir", .info) { try await store.unblockUser(userID) }
          }
          ask(
            GLConfirmation(
              title: "Blokir \(name)?",
              text:
                "Pesan \(name) di chat dan diskusi akan disembunyikan untukmu. \(name) tetap anggota grup, tugas bersama tetap berjalan, dan \(name) tidak diberi tahu.",
              ok: "Blokir", destructive: true
            ) {
              store.groupsRun("\(name) diblokir", .info) { try await store.blockUser(userID) }
            })
        })
    }
    return rows
  }
}

// MARK: - Small helpers

private struct GroupsPressStyle: ButtonStyle {
  var scale: CGFloat
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.contentShape(Rectangle()).scaleEffect(configuration.isPressed ? scale : 1)
      .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
  }
}

extension DemoStore {
  /// Unfinished tasks assigned to `userID` in this group's projects.
  func groupsActiveTaskCount(groupID: String, userID: String) -> Int {
    let pids = Set(projects(in: groupID).map(\.id))
    return tasks.filter { pids.contains($0.projectID) && $0.assigneeID == userID && $0.status != .done }.count
  }
  func groupsDoneTaskCount(groupID: String, userID: String) -> Int {
    let pids = Set(projects(in: groupID).map(\.id))
    return tasks.filter { pids.contains($0.projectID) && $0.assigneeID == userID && $0.status == .done }.count
  }
  /// Prototype `invStatus`: valid / expired / revoked / used / nogroup.
  func groupsInviteStatus(_ invite: GLInvite) -> String {
    if group(invite.groupID) == nil { return "nogroup" }
    if invite.revoked { return "revoked" }
    if now >= invite.expiresAt { return "expired" }
    if invite.useCount >= invite.maxUses { return "used" }
    return "valid"
  }
  /// Empty-code check before the server call; the server enforces the invite rules.
  func groupsJoinError(code: String) -> String? {
    code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Isi kode undangan." : nil
  }
  /// Prototype `invite(gid)`: permission/capacity checks, then a fresh 7-day code.
  func groupsCreateInvite(_ groupID: String) async -> GLInvite? {
    guard isCoordinator(groupID: groupID) else {
      flash("Hanya koordinator yang bisa mengundang anggota.", .err)
      return nil
    }
    if (group(groupID)?.memberIDs.count ?? 0) >= 8 {
      flash("Grup sudah penuh (maksimal 8 anggota).", .err)
      return nil
    }
    do { return try await generateInvite(groupID: groupID) } catch {
      flash(error.localizedDescription, .err)
      return nil
    }
  }
  /// Runs a mutation, flashing `success` or the store's error.
  func groupsRun(_ success: String, _ kind: GLToastKind = .ok, _ action: @escaping () async throws -> Void) {
    Task {
      do {
        try await action()
        flash(success, kind)
      } catch { flash(error.localizedDescription, .err) }
    }
  }
  /// Prototype `leave(gid)` dialogs.
  func groupsLeaveConfirmation(
    groupID: String, pickCoordinator: @escaping () -> Void, onLeft: @escaping () -> Void
  ) -> GLConfirmation? {
    guard let g = group(groupID), let me = currentUserID else { return nil }
    if g.coordinatorID == me && g.memberIDs.count > 1 {
      return GLConfirmation(
        title: "Serahkan peran koordinator dulu",
        text: "Grup harus selalu punya koordinator. Pilih anggota lain sebagai koordinator sebelum kamu keluar.",
        ok: "Pilih koordinator", run: pickCoordinator)
    }
    let leave = { [self] in
      Task {
        do {
          try await leaveGroup(groupID)
          flash(g.memberIDs.count == 1 ? "Grup dihapus" : "Kamu keluar dari \(g.name)", .info)
          onLeft()
        } catch { flash(error.localizedDescription, .err) }
      }
    }
    if g.memberIDs.count == 1 {
      return GLConfirmation(
        title: "Kamu anggota terakhir",
        text:
          "Kalau kamu keluar, \(g.name) beserta proyek, tugas, dan chat-nya tidak bisa kamu buka lagi. Data diproses sesuai kebijakan retensi.",
        ok: "Keluar & hapus grup", destructive: true, run: { _ = leave() })
    }
    return GLConfirmation(
      title: "Keluar dari grup?",
      text:
        "Kamu tidak bisa lagi membuka proyek dan chat \(g.name). Hasil kerja dan tugas yang sudah selesai tetap tercatat atas nama kamu.",
      ok: "Keluar", destructive: true, run: { _ = leave() })
  }
}
