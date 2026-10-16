import SwiftUI

struct ChatsView: View {
  @Environment(DemoStore.self) private var store
  @State private var query = ""
  private var filteredGroups: [GLGroup] {
    store.myGroups.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text("Chat").font(.largeTitle.bold())
        Text("Satu ruang obrolan untuk tiap grup").foregroundStyle(GLTheme.secondary)
        if store.myGroups.isEmpty {
          GLEmptyState(
            title: "Belum ada obrolan", message: "Gabung grup untuk mulai berdiskusi dengan tim.",
            systemImage: "bubble.left.and.bubble.right")
        }
        HStack(spacing: 10) {
          Image(systemName: "magnifyingglass").foregroundStyle(GLTheme.secondary)
          TextField("Cari grup", text: $query).textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 18))
        if !store.myGroups.isEmpty && filteredGroups.isEmpty {
          GLEmptyState(
            title: "Grup tidak ditemukan", message: "Coba nama grup lain.",
            systemImage: "magnifyingglass")
        }
        ForEach(filteredGroups) { group in
          NavigationLink(value: Route.chat(group.id)) {
            GLCard {
              HStack(spacing: 14) {
                Image(systemName: "bubble.left.and.bubble.right.fill").font(.title2).frame(
                  width: 48, height: 48
                ).background(Color(hex: group.tint), in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 6) {
                  Text(group.name).font(.headline)
                  Text(preview(groupID: group.id)).font(.subheadline).foregroundStyle(
                    GLTheme.secondary
                  ).lineLimit(2)
                }
                Spacer(minLength: 0)
                if store.unreadCount(groupID: group.id) > 0 {
                  Text("\(store.unreadCount(groupID: group.id))").font(.caption.bold()).padding(8)
                    .background(GLTheme.lavender, in: Circle()).accessibilityLabel(
                      "\(store.unreadCount(groupID: group.id)) pesan belum dibaca")
                } else {
                  Image(systemName: "chevron.right").font(.caption).foregroundStyle(
                    GLTheme.secondary)
                }
              }
            }
          }.buttonStyle(.plain)
        }
        GLNotice(
          text:
            "Pesan dalam demo tersimpan di perangkat ini. Sinkronisasi Realtime belum terhubung.",
          color: GLTheme.sky)
      }.padding(20)
    }.glScreen().toolbar(.hidden, for: .navigationBar)
  }
  private func preview(groupID: String) -> String {
    guard let message = store.messages(groupID: groupID).last else { return "Sapa timmu di sini." }
    return store.blockedUserIDs.contains(message.senderID)
      ? "Pesan dari akun diblokir" : message.text
  }
}

struct ChatDetailView: View {
  let groupID: String
  var taskID: String? = nil
  @Environment(DemoStore.self) private var store
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var draft = ""
  @State private var error: String?
  @State private var success: String?
  @State private var revealed: Set<String> = []
  @State private var reportID: String?
  private var canAccess: Bool {
    guard store.isMember(groupID: groupID) else { return false }
    guard let taskID else { return true }
    guard let task = store.task(taskID) else { return false }
    return store.project(task.projectID)?.groupID == groupID
  }
  private var readOnly: Bool {
    guard let taskID, let task = store.task(taskID), let project = store.project(task.projectID)
    else { return false }
    return project.status != .active
  }
  var body: some View {
    Group {
      if canAccess {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
              Text("DEMO LOKAL · \(taskID == nil ? "CHAT GRUP" : "DISKUSI TUGAS")").font(
                .caption2.bold()
              ).tracking(1.3).foregroundStyle(GLTheme.secondary).frame(maxWidth: .infinity).padding(
                .vertical, 12)
              let messages = store.messages(groupID: groupID, taskID: taskID)
              if messages.isEmpty {
                GLEmptyState(
                  title: "Mulai percakapan",
                  message: "Bagikan pertanyaan atau kabar progres timmu.",
                  systemImage: "bubble.left")
              }
              ForEach(messages) { message in messageView(message).id(message.id) }
              Color.clear.frame(height: 1).id("bottom")
            }.padding(20)
          }
          .onAppear {
            proxy.scrollTo("bottom", anchor: .bottom)
            if taskID == nil { store.markRead(groupID: groupID) }
          }
          .onChange(of: store.messages(groupID: groupID, taskID: taskID).count) { _, _ in
            if taskID == nil { store.markRead(groupID: groupID) }
            if store.messages(groupID: groupID, taskID: taskID).last?.senderID
              == store.currentUserID
            {
              if reduceMotion {
                proxy.scrollTo("bottom", anchor: .bottom)
              } else {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
              }
            }
          }
          .safeAreaInset(edge: .bottom) {
            if readOnly {
              GLNotice(
                text: "Diskusi hanya-baca. Proyek telah selesai atau diarsipkan.",
                color: GLTheme.sky
              ).padding(12).background(.regularMaterial)
            } else {
              HStack(alignment: .bottom, spacing: 12) {
                TextField(
                  taskID == nil ? "Tulis pesan…" : "Diskusikan tugas…", text: $draft,
                  axis: .vertical
                ).lineLimit(1...5).padding(12).background(
                  .white, in: RoundedRectangle(cornerRadius: 22))
                Button {
                  do {
                    _ = try store.sendMessage(groupID: groupID, taskID: taskID, text: draft)
                    draft = ""
                  } catch { self.error = error.localizedDescription }
                } label: {
                  Image(systemName: "arrow.up").font(.headline).foregroundStyle(.white).frame(
                    width: 44, height: 44
                  ).background(GLTheme.ink, in: Circle())
                }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                  .accessibilityLabel("Kirim pesan")
              }.padding(.horizontal, 16).padding(.vertical, 10).background(.regularMaterial)
            }
          }
        }
      } else {
        GLEmptyState(
          title: "Akses diskusi berakhir", message: "Kamu sudah bukan anggota grup ini.",
          systemImage: "lock")
      }
    }.glScreen().navigationTitle(
      taskID == nil ? store.group(groupID)?.name ?? "Chat" : "Diskusi tugas"
    ).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
      .confirmationDialog(
        "Laporkan pesan",
        isPresented: Binding(get: { reportID != nil }, set: { if !$0 { reportID = nil } }),
        titleVisibility: .visible
      ) {
        ForEach(["Pelecehan", "Spam", "Konten tidak pantas", "Lainnya"], id: \.self) { reason in
          Button(reason) {
            if let id = reportID {
              perform {
                try store.reportMessage(id, reason: reason)
                success = "Laporan tersimpan lokal. Belum terkirim ke moderator."
              }
            }
            reportID = nil
          }
        }
      }
      .alert(
        "Belum bisa dilakukan",
        isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
      ) {
        Button("Mengerti") { error = nil }
      } message: {
        Text(error ?? "")
      }
      .alert(
        "Laporan demo",
        isPresented: Binding(get: { success != nil }, set: { if !$0 { success = nil } })
      ) {
        Button("Mengerti") { success = nil }
      } message: {
        Text(success ?? "")
      }
  }
  @ViewBuilder private func messageView(_ message: GLMessage) -> some View {
    let mine = message.senderID == store.currentUserID
    let blocked = store.blockedUserIDs.contains(message.senderID) && !revealed.contains(message.id)
    if blocked {
      HStack {
        Label("Pesan dari akun diblokir", systemImage: "hand.raised").font(.caption)
        Spacer()
        Button("Tampilkan") { revealed.insert(message.id) }
      }.padding(16).background(GLTheme.sky.opacity(0.4), in: RoundedRectangle(cornerRadius: 18))
    } else if message.kind == "activity" {
      GLCard {
        VStack(alignment: .leading, spacing: 10) {
          Label(message.text, systemImage: "checkmark.circle").font(.subheadline)
          if let id = message.targetTaskID {
            NavigationLink(value: Route.task(id)) { Text("Lihat tugas").font(.subheadline.bold()) }
          }
        }
      }
    } else {
      HStack(alignment: .bottom, spacing: 8) {
        if mine {
          Spacer(minLength: 36)
        } else {
          GLAvatar(user: store.user(message.senderID), size: 30)
        }
        VStack(alignment: .leading, spacing: 6) {
          if !mine {
            Text(store.user(message.senderID)?.name ?? "Pengguna").font(.caption.bold())
              .foregroundStyle(GLTheme.secondary)
          }
          Text(message.text).font(.body).textSelection(.enabled).tint(GLTheme.ink)
          HStack(spacing: 6) {
            Text(message.createdAt.formatted(date: .omitted, time: .shortened)).font(.caption2)
              .foregroundStyle(GLTheme.secondary)
            if mine && message.delivery == .sent {
              Text("Tersimpan lokal").font(.caption2).foregroundStyle(GLTheme.secondary)
            }
            if message.delivery == .failed {
              Button("Gagal · Coba lagi") { perform { try store.retryMessage(message.id) } }.font(
                .caption.bold()
              ).foregroundStyle(.red).frame(minHeight: 44)
            }
          }
        }.padding(14).background(
          mine ? GLTheme.lavender : .white, in: RoundedRectangle(cornerRadius: 22)
        )
        .contextMenu {
          if !mine {
            Button("Laporkan pesan", systemImage: "flag") { reportID = message.id }
            Button("Blokir pengguna", systemImage: "hand.raised", role: .destructive) {
              perform { try store.blockUser(message.senderID) }
            }
          }
        }
        if !mine { Spacer(minLength: 24) }
      }
    }
  }
  private func perform(_ action: () throws -> Void) {
    do { try action() } catch { self.error = error.localizedDescription }
  }
}
