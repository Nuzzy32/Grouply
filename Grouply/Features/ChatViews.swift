import SwiftUI

struct ChatsView: View {
  @Environment(DemoStore.self) private var store
  @State private var query = ""
  private var filteredGroups: [GLGroup] {
    let q = query.trimmingCharacters(in: .whitespaces)
    return store.myGroups.filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) }
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        VStack(alignment: .leading, spacing: 4) {
          Text("Chat").gl(34, .bold, em: -0.03)
          Text("Satu ruang obrolan untuk tiap grup").gl(15).foregroundStyle(GLTheme.secondary)
        }
        if !store.myGroups.isEmpty {
          HStack(spacing: 8) {
            GLIcon("magnifyingglass", size: 20).foregroundStyle(GLTheme.secondary)
            TextField("Cari nama grup", text: $query).gl(16).textInputAutocapitalization(.never)
              .autocorrectionDisabled().accessibilityLabel("Cari nama grup")
            if !query.isEmpty {
              Button { query = "" } label: {
                GLIcon("xmark", size: 18).frame(width: 40, height: 40)
                  .background(GLTheme.muted, in: Circle())
              }.buttonStyle(.plain).accessibilityLabel("Hapus pencarian")
            }
          }
          .padding(.leading, 14).padding(.trailing, 4).frame(height: 48)
          .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(GLTheme.border))
        }
        VStack(spacing: 0) {
          ForEach(filteredGroups) { group in
            NavigationLink(value: Route.chat(group.id)) { row(group) }
              .buttonStyle(GLChatRowStyle())
          }
          if store.myGroups.isEmpty {
            VStack(spacing: 10) {
              GLIcon("bubble.left.and.bubble.right", size: 28).frame(width: 56, height: 56)
                .background(GLTheme.lavender, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
              Text("Belum ada chat").gl(19, .bold)
              Text("Chat grup dibuat otomatis saat kamu membuat atau bergabung ke grup.").gl(15)
                .lineSpacing(4).foregroundStyle(GLTheme.secondary)
            }.multilineTextAlignment(.center).padding(.vertical, 30).padding(.horizontal, 22)
          } else if filteredGroups.isEmpty {
            VStack(spacing: 6) {
              GLIcon("magnifyingglass", size: 30).foregroundStyle(GLTheme.secondary)
              Text("Tidak ada grup “\(query)”").gl(16, .semibold)
              Text("Coba kata kunci lain.").gl(14).foregroundStyle(GLTheme.secondary)
            }.multilineTextAlignment(.center).frame(maxWidth: .infinity)
              .padding(.vertical, 28).padding(.horizontal, 20)
          }
        }
        .frame(maxWidth: .infinity)
        .glSurface(28).clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
      }.padding(.horizontal, 20).padding(.top, 10)
    }.glScreen().refreshable { await store.refreshFromBackend() }.toolbar(
      .hidden, for: .navigationBar)
  }

  private func row(_ group: GLGroup) -> some View {
    let unread = store.unreadCount(groupID: group.id)
    let last = store.messages(groupID: group.id).last
    return HStack(spacing: 14) {
      GLIcon(group.icon, size: 26).frame(width: 52, height: 52)
        .background(Color(hex: group.tint), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
      VStack(alignment: .leading, spacing: 3) {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(group.name).gl(16, unread > 0 ? .bold : .semibold).lineLimit(1)
          Spacer(minLength: 0)
          if let last {
            Text(GLFormat.chatStamp(last.createdAt, now: store.now))
              .gl(13, unread > 0 ? .bold : .regular)
              .foregroundStyle(unread > 0 ? GLTheme.ink : GLTheme.secondary)
          }
        }
        HStack(spacing: 8) {
          Text(preview(last)).gl(14, unread > 0 ? .medium : .regular).lineSpacing(2)
            .foregroundStyle(unread > 0 ? GLTheme.ink : GLTheme.secondary)
            .lineLimit(2).multilineTextAlignment(.leading)
          Spacer(minLength: 0)
          if unread > 0 {
            Text("\(unread)").gl(12, .bold).foregroundStyle(.white).padding(.horizontal, 7)
              .frame(minWidth: 24, minHeight: 24).background(GLTheme.ink, in: Capsule())
              .accessibilityLabel("\(unread) pesan belum dibaca")
          }
        }
      }
    }
    .padding(.vertical, 14).padding(.horizontal, 16)
    .overlay(alignment: .bottom) { Rectangle().fill(GLTheme.border).frame(height: 1) }
  }

  /// Prototype `preview(gid)`.
  private func preview(_ m: GLMessage?) -> String {
    guard let m else { return "Belum ada pesan. Sapa kelompokmu!" }
    let name = m.senderID == store.currentUserID ? "Kamu" : store.user(m.senderID)?.name ?? "Anggota"
    var text: String
    switch m.kind {
    case "activity":
      text = name + " " + m.text + " " + (m.targetTaskID.flatMap(store.task)?.title ?? "")
    case "system": text = name + " " + m.text
    default:
      text =
        store.blockedUserIDs.contains(m.senderID) && m.senderID != store.currentUserID
        ? "Pesan dari pengguna yang kamu blokir" : name + ": " + m.text
    }
    if m.delivery == .failed { text = "Gagal terkirim · " + text }
    return text
  }
}

/// Row highlight used in the chat list (`style-active="background:#F0F3F1"`).
struct GLChatRowStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.contentShape(Rectangle())
      .background(configuration.isPressed ? GLTheme.muted : .clear)
  }
}

// MARK: - Group chat screen (prototype `isChat`)

struct ChatDetailView: View {
  let groupID: String
  var taskID: String? = nil
  @Environment(DemoStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var canAccess: Bool {
    guard store.isMember(groupID: groupID) else { return false }
    guard let taskID else { return true }
    guard let task = store.task(taskID) else { return false }
    return store.project(task.projectID)?.groupID == groupID
  }
  private var messages: [GLMessage] { store.messages(groupID: groupID, taskID: taskID) }

  var body: some View {
    if canAccess {
      ScrollViewReader { proxy in
        ScrollView {
          VStack(spacing: 0) {
            ChatThread(groupID: groupID, taskID: taskID)
            Color.clear.frame(height: 1).id("bottom")
          }
        }
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        .refreshable { await store.refreshFromBackend() }
        .safeAreaInset(edge: .top, spacing: 0) { if taskID == nil { header } }
        .safeAreaInset(edge: .bottom, spacing: 0) { ChatComposer(groupID: groupID, taskID: taskID) }
        .onAppear {
          proxy.scrollTo("bottom", anchor: .bottom)
          if taskID == nil { store.markRead(groupID: groupID) }
        }
        .onChange(of: messages.count) { _, _ in
          if taskID == nil { store.markRead(groupID: groupID) }
          guard messages.last?.senderID == store.currentUserID else { return }
          if reduceMotion {
            proxy.scrollTo("bottom", anchor: .bottom)
          } else {
            withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
          }
        }
      }
      .glDetailScreen()
    } else {
      GLAccessDenied()
    }
  }

  /// Blurred header: back chevron, group tile, name + member count, group button.
  private var header: some View {
    let group = store.group(groupID)
    return HStack(spacing: 10) {
      Button { dismiss() } label: {
        GLIcon("chevron.backward", size: 26).frame(width: 44, height: 44).contentShape(Circle())
      }.buttonStyle(.plain).accessibilityLabel("Kembali")
      GLIcon(group?.icon ?? "person.3", size: 22).frame(width: 42, height: 42)
        .background(
          Color(hex: group?.tint ?? "FFFFFF"),
          in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      VStack(alignment: .leading, spacing: 0) {
        Text(group?.name ?? "").gl(16, .bold).lineLimit(1).truncationMode(.tail)
        Text("\(group?.memberIDs.count ?? 0) anggota").gl(13).foregroundStyle(GLTheme.secondary)
      }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
      NavigationLink(value: Route.group(groupID)) {
        GLIcon("person.2", size: 22).frame(width: 44, height: 44)
          .background {
            Circle().fill(.white).shadow(color: .black.opacity(0.06), radius: 1, y: 1)
          }
      }.buttonStyle(.plain).accessibilityLabel("Buka detail grup")
    }
    .padding(.top, 4).padding(.horizontal, 12).padding(.bottom, 10)
    .background {
      GLTheme.background.opacity(0.94).background(.ultraThinMaterial)
        .ignoresSafeArea(edges: .top)
    }
    .overlay(alignment: .bottom) { Rectangle().fill(GLTheme.border).frame(height: 1) }
  }
}

// MARK: - Thread (prototype `showThread` / `threadVals`)

/// Message list for a group chat (taskID nil) or a task discussion, without its own ScrollView.
struct ChatThread: View {
  let groupID: String
  var taskID: String? = nil
  @Environment(DemoStore.self) private var store
  @State private var revealed: Set<String> = []
  @State private var width: CGFloat = 358
  @State private var sheet: ChatSheet?
  @State private var confirm: GLConfirmation?
  @State private var pendingConfirm: GLConfirmation?

  var body: some View {
    let list = store.messages(groupID: groupID, taskID: taskID)
    VStack(alignment: .leading, spacing: 0) {
      if store.simulatedOffline {
        HStack(spacing: 8) {
          GLIcon("icloud.slash", size: 18)
          Text("Kamu sedang offline. Pesan akan gagal terkirim.").gl(14, .medium)
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GLTheme.butter, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.bottom, 8)
      }
      ForEach(Array(list.enumerated()), id: \.element.id) { i, m in
        let day = ChatFormat.day(m.createdAt, now: store.now)
        if i == 0 || ChatFormat.day(list[i - 1].createdAt, now: store.now) != day {
          daySeparator(day)
        }
        row(m, prev: i > 0 ? list[i - 1] : nil, next: i + 1 < list.count ? list[i + 1] : nil)
      }
      if list.isEmpty { empty }
    }
    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    .padding(.top, 6).padding(.horizontal, 16).padding(.bottom, 8)
    .sheet(item: $sheet, onDismiss: showPendingConfirm) { item in
      switch item {
      case .message(let id):
        ChatMessageSheet(messageID: id) { action in handle(action, messageID: id) }
      case .report(let id):
        ChatReportSheet(messageID: id)
      }
    }
    .fullScreenCover(isPresented: Binding(get: { confirm != nil }, set: { if !$0 { setConfirm(nil) } })) {
      Color.clear.glConfirm(Binding(get: { confirm }, set: { setConfirm($0) }))
        .presentationBackground(.clear)
    }
  }

  // MARK: Rows

  private func daySeparator(_ label: String) -> some View {
    Text(label).gl(12, .semibold).foregroundStyle(GLTheme.text2)
      .padding(.horizontal, 12).frame(height: 26)
      .background(Color(hex: "ECEEEB"), in: Capsule())
      .frame(maxWidth: .infinity)
      .padding(.top, 14).padding(.bottom, 6)
      .accessibilityAddTraits(.isHeader)
  }

  @ViewBuilder
  private func row(_ m: GLMessage, prev: GLMessage?, next: GLMessage?) -> some View {
    switch m.kind {
    case "system": systemRow(m)
    case "activity": activityRow(m)
    default:
      let day = ChatFormat.day(m.createdAt, now: store.now)
      let samePrev = prev.map { chains($0, m, day: day) } ?? false
      let sameNext = next.map { chains(m, $0, day: day) } ?? false
      if m.senderID == store.currentUserID {
        mine(m, samePrev: samePrev, sameNext: sameNext)
      } else {
        other(m, samePrev: samePrev, sameNext: sameNext)
      }
    }
  }

  /// Two consecutive text messages from the same sender on the same day group together.
  private func chains(_ a: GLMessage, _ b: GLMessage, day: String) -> Bool {
    a.kind == "text" && b.kind == "text" && a.senderID == b.senderID
      && ChatFormat.day(a.createdAt, now: store.now) == ChatFormat.day(b.createdAt, now: store.now)
  }

  private func systemRow(_ m: GLMessage) -> some View {
    HStack(spacing: 6) {
      GLIcon("bolt", size: 16)
      Text("\(store.displayName(m.senderID)) \(m.text) · \(GLFormat.time(m.createdAt))")
        .gl(13, .medium)
    }
    .foregroundStyle(GLTheme.text3).multilineTextAlignment(.center)
    .padding(.vertical, 6).padding(.horizontal, 12)
    .background(Color(hex: "ECEEEB"), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .frame(maxWidth: width * 0.92).frame(maxWidth: .infinity)
    .padding(.vertical, 8)
    .accessibilityElement(children: .combine)
  }

  private func activityRow(_ m: GLMessage) -> some View {
    let style = ActivityStyle(m.text)
    let task = m.targetTaskID.flatMap(store.task)
    return HStack(spacing: 12) {
      GLIcon(style.icon, size: 20).frame(width: 40, height: 40)
        .background(style.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      VStack(alignment: .leading, spacing: 1) {
        Text(
          "\(store.displayName(m.senderID)) \(m.text) · \(GLFormat.activityStamp(m.createdAt, now: store.now))"
        ).gl(13).foregroundStyle(GLTheme.text2)
        Text(task?.title ?? "Tugas tidak tersedia").gl(15, .semibold).lineSpacing(1)
      }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
      NavigationLink(value: Route.task(m.targetTaskID ?? "")) {
        Text("Lihat tugas").gl(13, .semibold).padding(.horizontal, 14).frame(height: 44)
          .overlay(Capsule().strokeBorder(GLTheme.ink, lineWidth: 1.5)).contentShape(Capsule())
      }.buttonStyle(.plain).disabled(task == nil)
    }
    .padding(.vertical, 12).padding(.leading, 14).padding(.trailing, 12)
    .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(GLTheme.border))
    .padding(.vertical, 10).padding(.horizontal, 6)
  }

  private func other(_ m: GLMessage, samePrev: Bool, sameNext: Bool) -> some View {
    let shape = UnevenRoundedRectangle(
      topLeadingRadius: samePrev ? 6 : 18, bottomLeadingRadius: sameNext ? 6 : 18,
      bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous)
    let hidden = store.blockedUserIDs.contains(m.senderID) && !revealed.contains(m.id)
    return HStack(alignment: .bottom, spacing: 8) {
      if sameNext {
        Color.clear.frame(width: 30, height: 1)
      } else {
        GLAvatar(user: store.user(m.senderID), size: 30, fontSize: 11).padding(.bottom, 22)
          .accessibilityHidden(true)
      }
      VStack(alignment: .leading, spacing: 3) {
        if !samePrev {
          Text(store.displayName(m.senderID)).gl(13, .semibold).foregroundStyle(GLTheme.text2)
            .padding(.leading, 4).accessibilityHidden(!hidden)
        }
        if hidden {
          Button { revealed.insert(m.id) } label: {
            HStack(spacing: 6) {
              GLIcon("eye.slash", size: 17)
              Text("Pesan dari pengguna yang kamu blokir · Tampilkan").gl(14)
                .multilineTextAlignment(.leading)
            }
            .foregroundStyle(GLTheme.text3).padding(.vertical, 8).padding(.horizontal, 12)
            .frame(minHeight: 44)
            .overlay(shape.strokeBorder(Color(hex: "9AA0A6"), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
            .contentShape(shape)
          }.buttonStyle(.plain)
        } else {
          bubble(m, color: .white, link: Color(hex: "1F4F86"), shape: shape)
            .shadow(color: .black.opacity(0.06), radius: 0.75, y: 1)
        }
        if !sameNext {
          Text(GLFormat.time(m.createdAt)).gl(12).foregroundStyle(GLTheme.secondary)
            .padding(.leading, 4).accessibilityHidden(!hidden)
        }
      }
    }
    .frame(maxWidth: width * 0.84, alignment: .leading)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.top, samePrev ? 2 : 10)
  }

  private func mine(_ m: GLMessage, samePrev: Bool, sameNext: Bool) -> some View {
    let shape = UnevenRoundedRectangle(
      topLeadingRadius: 18, bottomLeadingRadius: 18,
      bottomTrailingRadius: sameNext ? 6 : 18, topTrailingRadius: samePrev ? 6 : 18,
      style: .continuous)
    return VStack(alignment: .trailing, spacing: 3) {
      bubble(m, color: GLTheme.lavender, link: Color(hex: "1F3F76"), shape: shape)
        .opacity(m.delivery == .sending ? 0.6 : 1)
        .animation(.easeOut(duration: 0.2), value: m.delivery)
      switch m.delivery {
      case .failed:
        Button { retry(m.id) } label: {
          HStack(spacing: 4) {
            GLIcon("exclamationmark.circle", size: 16)
            Text("Gagal terkirim · Coba lagi").gl(13, .semibold)
          }.foregroundStyle(GLTheme.danger).padding(2).frame(minHeight: 40)
        }.buttonStyle(.plain)
      case .sending:
        HStack(spacing: 4) {
          ProgressView().controlSize(.mini).frame(width: 14, height: 14)
          Text("Mengirim…").gl(12)
        }.foregroundStyle(GLTheme.secondary).accessibilityHidden(true)
      case .sent:
        if !sameNext {
          HStack(spacing: 3) {
            Text("\(GLFormat.time(m.createdAt)) · Terkirim").gl(12)
            GLIcon("checkmark", size: 14)
          }.foregroundStyle(GLTheme.secondary).accessibilityHidden(true)
        }
      }
    }
    .frame(maxWidth: width * 0.8, alignment: .trailing)
    .frame(maxWidth: .infinity, alignment: .trailing)
    .padding(.top, samePrev ? 2 : 10)
  }

  private func bubble(_ m: GLMessage, color: Color, link: Color, shape: UnevenRoundedRectangle)
    -> some View
  {
    let delivery: String =
      switch m.delivery {
      case .sending: "Mengirim"
      case .sent: "Terkirim"
      case .failed: "Gagal terkirim"
      }
    let mine = m.senderID == store.currentUserID
    return Text(ChatFormat.linked(m.text, color: link)).gl(16).lineSpacing(2.6)
      .tint(link).fixedSize(horizontal: false, vertical: true)
      .padding(.vertical, 8).padding(.horizontal, 12)
      .background(color, in: shape)
      .contentShape(shape)
      .onLongPressGesture(minimumDuration: 0.48) { sheet = .message(m.id) }
      .accessibilityValue(
        mine
          ? "Kamu, \(GLFormat.time(m.createdAt)), \(delivery)"
          : "Dari \(store.displayName(m.senderID)), \(GLFormat.time(m.createdAt))"
      )
      .accessibilityAction(named: "Opsi pesan") { sheet = .message(m.id) }
  }

  private var empty: some View {
    VStack(spacing: 8) {
      GLIcon("hand.wave", size: 28).frame(width: 56, height: 56)
        .background(GLTheme.lavender, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
      Text(taskID == nil ? "Belum ada pesan" : "Mulai diskusi").gl(17, .semibold)
      Text(
        taskID == nil
          ? "Sapa kelompokmu dan mulai koordinasi di sini."
          : "Pertanyaan soal tugas ini tetap di sini, tidak tenggelam di chat grup."
      ).gl(14).lineSpacing(4).foregroundStyle(GLTheme.secondary)
    }
    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
    .padding(.vertical, 40).padding(.horizontal, 16)
  }

  // MARK: Actions

  private func retry(_ id: String) {
    Task {
      do { try await store.retryMessage(id) } catch { store.flash(error.localizedDescription, .err) }
    }
  }

  private func handle(_ action: ChatMessageAction, messageID id: String) {
    guard let m = store.messages.first(where: { $0.id == id }) else { sheet = nil; return }
    switch action {
    case .copy:
      UIPasteboard.general.string = m.text
      sheet = nil
      store.flash("Teks disalin")
    case .retry:
      sheet = nil
      retry(id)
    case .report:
      if store.reports.contains(where: { $0.messageID == id && $0.reporterID == store.currentUserID }) {
        sheet = nil
        store.flash("Kamu sudah melaporkan pesan ini.", .err)
      } else {
        sheet = .report(id)
      }
    case .block:
      let who = m.senderID, name = store.user(who)?.name ?? "Anggota"
      sheet = nil
      if store.blockedUserIDs.contains(who) {
        Task {
          do {
            try await store.unblockUser(who)
            store.flash(name + " tidak lagi diblokir", .info)
          } catch { store.flash(error.localizedDescription, .err) }
        }
        return
      }
      pendingConfirm = GLConfirmation(
        title: "Blokir \(name)?",
        text:
          "Pesan \(name) di chat dan diskusi akan disembunyikan untukmu. \(name) tetap anggota grup, tugas bersama tetap berjalan, dan \(name) tidak diberi tahu.",
        ok: "Blokir", destructive: true
      ) {
        Task {
          do {
            try await store.blockUser(who)
            store.flash(name + " diblokir", .info)
          } catch { store.flash(error.localizedDescription, .err) }
        }
      }
    }
  }

  /// The confirm dialog waits for the action sheet to finish dismissing.
  private func showPendingConfirm() {
    guard let p = pendingConfirm else { return }
    pendingConfirm = nil
    setConfirm(p)
  }

  /// Full-screen host without the slide-up animation, so the dialog reads as an overlay.
  private func setConfirm(_ value: GLConfirmation?) {
    var t = Transaction()
    t.disablesAnimations = true
    withTransaction(t) { confirm = value }
  }
}

private enum ChatSheet: Identifiable {
  case message(String), report(String)
  var id: String {
    switch self {
    case .message(let id): "m" + id
    case .report(let id): "r" + id
    }
  }
}

private enum ChatMessageAction { case copy, retry, report, block }

enum ChatFormat {
  /// Day separator label: "Hari ini", "Kemarin", otherwise "Rab, 14 Okt".
  static func day(_ date: Date, now: Date) -> String {
    let cal = Calendar.current
    let n = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
    if n == 0 { return "Hari ini" }
    if n == -1 { return "Kemarin" }
    return GLFormat.weekday(date) + ", " + GLFormat.date(date)
  }

  /// Prototype `segs()`: URLs drop their scheme and are underlined; only https is tappable.
  static func linked(_ text: String, color: Color) -> AttributedString {
    var out = AttributedString()
    var rest = text[...]
    for match in text.matches(of: /https?:\/\/\S+/) {
      out += AttributedString(text[rest.startIndex..<match.range.lowerBound])
      let raw = String(match.output)
      if raw.hasPrefix("https://"), let url = URL(string: raw) {
        var link = AttributedString(raw.dropFirst("https://".count))
        link.link = url
        link.foregroundColor = color
        link.underlineStyle = .single
        out += link
      } else {
        out += AttributedString(raw)
      }
      rest = text[match.range.upperBound...]
    }
    out += AttributedString(rest)
    return out
  }
}

// MARK: - Sheets (prototype `sheetMsg` / `sheetReport`)

/// Sheet chrome without a title row: handle, 14pt gaps, height fits content.
private struct ChatSheetBody<Content: View>: View {
  @ViewBuilder var content: Content
  @State private var height: CGFloat = 400
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        Capsule().fill(Color(hex: "C4C7C5")).frame(width: 38, height: 5).frame(maxWidth: .infinity)
        content
      }
      .padding(.top, 10).padding(.horizontal, 20).padding(.bottom, 34)
      .foregroundStyle(GLTheme.ink)
      .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
    }
    .scrollBounceBehavior(.basedOnSize)
    .presentationDetents([.height(height)])
    .presentationDragIndicator(.hidden)
    .presentationCornerRadius(32)
    .presentationBackground(GLTheme.background)
  }
}

private struct ChatMessageSheet: View {
  let messageID: String
  let onAction: (ChatMessageAction) -> Void
  @Environment(DemoStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    ChatSheetBody {
      if let m = store.messages.first(where: { $0.id == messageID }) {
        let mine = m.senderID == store.currentUserID
        let blocked = store.blockedUserIDs.contains(m.senderID)
        let name = store.user(m.senderID)?.name ?? "Anggota"
        VStack(alignment: .leading, spacing: 4) {
          Text(
            "\(store.displayName(m.senderID)) · \(ChatFormat.day(m.createdAt, now: store.now)), \(GLFormat.time(m.createdAt))"
          ).gl(13, .semibold).foregroundStyle(GLTheme.text2)
          Text(m.text.count > 140 ? m.text.prefix(140) + "…" : m.text).gl(15).lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        VStack(spacing: 0) {
          actionRow("Salin teks", icon: "doc.on.doc", color: GLTheme.ink, .copy)
          if mine && m.delivery == .failed {
            actionRow("Coba kirim lagi", icon: "arrow.clockwise", color: GLTheme.ink, .retry)
          }
          if !mine {
            actionRow("Laporkan pesan", icon: "flag", color: GLTheme.danger, .report)
            actionRow(
              blocked ? "Buka blokir \(name)" : "Blokir \(name)", icon: "nosign",
              color: GLTheme.danger, .block)
          }
        }
        .padding(.vertical, 4).padding(.horizontal, 16)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
      }
      Button { dismiss() } label: {
        Text("Batal").gl(16, .semibold).frame(maxWidth: .infinity).frame(height: 52)
          .background(Color(hex: "ECEEEB"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      }.buttonStyle(.plain)
    }
  }
  private func actionRow(_ label: String, icon: String, color: Color, _ action: ChatMessageAction)
    -> some View
  {
    Button { onAction(action) } label: {
      HStack(spacing: 12) {
        GLIcon(icon, size: 22)
        Text(label).gl(16, .semibold)
        Spacer(minLength: 0)
      }
      .foregroundStyle(color).frame(minHeight: 56).contentShape(Rectangle())
      .overlay(alignment: .bottom) { Rectangle().fill(GLTheme.border).frame(height: 1) }
    }.buttonStyle(.plain)
  }
}

private struct ChatReportSheet: View {
  let messageID: String
  @Environment(DemoStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var reason: String?
  @State private var details = ""
  @State private var error: String?
  @State private var busy = false
  @State private var done = false
  private static let reasons = ["Pelecehan", "Spam", "Konten tidak pantas", "Lainnya"]

  var body: some View {
    ChatSheetBody {
      if done { doneView } else { form }
    }
  }

  private var form: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(spacing: 8) {
        Text("Laporkan pesan").gl(22, .bold, em: -0.02)
        Spacer(minLength: 0)
        Button { dismiss() } label: {
          GLIcon("xmark", size: 22).frame(width: 44, height: 44)
            .background(Color(hex: "ECEEEB"), in: Circle())
        }.buttonStyle(.plain).accessibilityLabel("Tutup")
      }
      Text("Pengirim tidak akan tahu siapa yang melapor.").gl(14).foregroundStyle(GLTheme.text3)
        .padding(.top, -6)
      VStack(spacing: 0) {
        ForEach(Self.reasons, id: \.self) { r in
          Button { reason = r } label: {
            HStack(spacing: 12) {
              GLIcon(reason == r ? "largecircle.fill.circle" : "circle", size: 22)
              Text(r).gl(16, .medium)
              Spacer(minLength: 0)
            }
            .frame(minHeight: 54).contentShape(Rectangle())
            .overlay(alignment: .bottom) { Rectangle().fill(GLTheme.border).frame(height: 1) }
          }
          .buttonStyle(.plain)
          .accessibilityAddTraits(reason == r ? [.isSelected] : [])
        }
      }
      .padding(.vertical, 4).padding(.horizontal, 16)
      .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
      VStack(alignment: .leading, spacing: 6) {
        Text("Detail (opsional)").gl(14, .semibold)
        TextField("Ceritakan singkat apa yang terjadi", text: $details, axis: .vertical)
          .gl(16).lineSpacing(4).lineLimit(3, reservesSpace: true)
          .onChange(of: details) { _, v in if v.count > 500 { details = String(v.prefix(500)) } }
          .padding(.vertical, 12).padding(.horizontal, 16)
          .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(GLTheme.border))
      }
      if let error { GLFormError(text: error) }
      GLSubmitButton(
        title: busy ? "Menyimpan…" : "Kirim laporan", busy: busy, background: GLTheme.danger,
        action: submit)
    }
  }

  private var doneView: some View {
    VStack(spacing: 12) {
      GLIcon("checkmark.circle", size: 32).frame(width: 64, height: 64)
        .background(GLTheme.mint, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
      Text("Laporan tersimpan").gl(21, .bold)
      Text(
        "Terima kasih sudah menjaga grup tetap nyaman. Di versi produksi, laporan ditinjau tim moderasi."
      ).gl(15).lineSpacing(4).foregroundStyle(GLTheme.text3)
      Text(
        store.isCloudMode
          ? "Laporan berhasil tersimpan di server."
          : "Simulasi: laporan hanya disimpan di prototipe ini dan tidak dikirim ke moderator sungguhan."
      )
      .gl(13).lineSpacing(3).foregroundStyle(GLTheme.secondary)
      .padding(.vertical, 10).padding(.horizontal, 12)
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .strokeBorder(Color(hex: "9AA0A6"), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
      Button { dismiss() } label: {
        Text("Selesai").gl(16, .semibold).foregroundStyle(.white).frame(maxWidth: .infinity)
          .frame(height: 54)
          .background(GLTheme.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
      }.buttonStyle(.plain)
    }
    .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 8)
    .fixedSize(horizontal: false, vertical: true)
  }

  private func submit() {
    guard let reason else { error = "Pilih alasan laporan."; return }
    let extra = details.trimmingCharacters(in: .whitespacesAndNewlines)
    if reason == "Lainnya" && extra.isEmpty { error = "Ceritakan singkat alasannya."; return }
    error = nil
    busy = true
    // ponytail: details ride inside the store's single `reason` field (500 chars) until reports get their own column.
    let full = String((extra.isEmpty ? reason : reason + " — " + extra).prefix(500))
    Task {
      do {
        try await store.reportMessage(messageID, reason: full)
        done = true
      } catch { self.error = error.localizedDescription }
      busy = false
    }
  }
}

// MARK: - Composer (prototype `showComposer` / `showReadOnly`)

/// Bottom composer bar; shows the read-only bar for discussions of completed/archived projects.
struct ChatComposer: View {
  let groupID: String
  var taskID: String? = nil
  @Environment(DemoStore.self) private var store
  @State private var draft = ""
  private var readOnlyProject: GLProject? {
    guard let taskID, let task = store.task(taskID), let p = store.project(task.projectID),
      p.status != .active
    else { return nil }
    return p
  }
  private var placeholder: String { taskID == nil ? "Tulis pesan…" : "Komentari tugas ini…" }
  private var hasText: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

  var body: some View {
    Group {
      if let p = readOnlyProject {
        HStack(spacing: 8) {
          GLIcon("lock", size: 18)
          Text(
            p.status == .archived
              ? "Diskusi hanya-baca karena proyek diarsipkan."
              : "Diskusi hanya-baca karena proyek sudah selesai."
          ).gl(14, .medium)
        }
        .foregroundStyle(GLTheme.text3).multilineTextAlignment(.center)
        .frame(maxWidth: .infinity).padding(.top, 12).padding(.horizontal, 16).padding(.bottom, 12)
        .accessibilityElement(children: .combine)
      } else {
        HStack(spacing: 8) {
          TextField(placeholder, text: $draft).gl(16)
            .submitLabel(.send).onSubmit(send)
            .onChange(of: draft) { _, v in if v.count > 2000 { draft = String(v.prefix(2000)) } }
            .padding(.horizontal, 16).frame(height: 44)
            .background(.white, in: Capsule())
            .overlay(Capsule().strokeBorder(GLTheme.border))
          Button(action: send) {
            GLIcon("arrow.up", size: 22).foregroundStyle(.white).frame(width: 44, height: 44)
              .background(hasText ? GLTheme.ink : Color(hex: "B4B8BC"), in: Circle())
              .animation(.easeOut(duration: 0.15), value: hasText)
          }
          .buttonStyle(ChatPressStyle()).accessibilityLabel("Kirim pesan")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
      }
    }
    .background(GLTheme.background.ignoresSafeArea(edges: .bottom))
    .overlay(alignment: .top) { Rectangle().fill(GLTheme.border).frame(height: 1) }
    .foregroundStyle(GLTheme.ink)
  }

  /// Prototype `sendCurrent()`.
  private func send() {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    if let p = readOnlyProject {
      store.flash(
        "Diskusi hanya-baca karena proyek "
          + (p.status == .archived ? "diarsipkan" : "sudah selesai") + ".", .err)
      return
    }
    if text.count > 2000 { store.flash("Pesan maksimal 2000 karakter.", .err); return }
    draft = ""
    Task {
      do {
        _ = try await store.sendMessage(groupID: groupID, taskID: taskID, text: text)
      } catch {
        if draft.isEmpty { draft = text }
        store.flash(error.localizedDescription, .err)
      }
    }
  }
}

/// `style-active="transform:scale(.9)"`.
private struct ChatPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.scaleEffect(configuration.isPressed ? 0.9 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}
