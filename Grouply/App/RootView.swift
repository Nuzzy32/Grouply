import SwiftUI

enum Route: Hashable {
  case group(String)
  case project(String)
  case task(String)
  case chat(String)
  case profile
}

struct RootView: View {
  @Environment(DemoStore.self) private var store
  @State private var tab = 0
  @State private var paths: [[Route]] = [[], [], [], []]
  @State private var linkError: String?
  @Environment(\.scenePhase) private var scenePhase
  var body: some View {
    Group {
      if store.currentUserID == nil {
        WelcomeView()
      } else {
        NavigationStack(path: $paths[tab]) {
          Group {
            switch tab {
            case 1: GroupsView()
            case 2: ChatsView()
            case 3: MyTasksView()
            default: HomeView(openProfile: { paths[tab].append(.profile) }, openTab: { tab = $0 })
            }
          }
          // Prototype: content ends 120pt above the screen bottom, under the floating tab bar.
          .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 86) }
          .navigationDestination(for: Route.self) { route in
            switch route {
            case .group(let id): GroupDetailView(groupID: id)
            case .project(let id): ProjectDetailView(projectID: id)
            case .task(let id): TaskDetailView(taskID: id)
            case .chat(let id): ChatDetailView(groupID: id)
            case .profile: ProfileView()
            }
          }
        }
        .id(tab)
        .overlay {
          if paths[tab].isEmpty {
            VStack { Spacer(minLength: 0); tabBar }.ignoresSafeArea(.container, edges: .bottom)
              .transition(.opacity)
          }
        }
        .background(GLTheme.background)
      }
    }
    .task { await store.restoreBackendSession() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await store.refreshFromBackend() } }
    }
    .disabled(store.isBusy)
    .overlay {
      if store.isBusy && !store.isRestoringSession {
        ProgressView(store.isRestoringSession ? "Memulihkan sesi…" : "Menghubungi server…")
          .padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
      }
    }
    .overlay(alignment: .top) {
      if let toast = store.toast {
        GLToastView(text: toast.text, kind: toast.kind).padding(.top, 4)
          .transition(.move(edge: .top).combined(with: .opacity)).allowsHitTesting(false)
      }
    }
    .animation(.easeOut(duration: 0.2), value: store.toast?.text)
    .safeAreaInset(edge: .top) {
      if let message = store.backendError {
        HStack {
          Text(message).gl(13)
          Button("Tutup") { store.backendError = nil }.gl(13, .semibold)
        }.padding(12).frame(maxWidth: .infinity).background(GLTheme.butter)
      }
    }
    .onChange(of: store.currentUserID) { _, _ in
      paths = [[], [], [], []]
    }
    .onOpenURL(perform: openLink)
    .alert(
      "Tautan tidak dapat dibuka",
      isPresented: Binding(get: { linkError != nil }, set: { if !$0 { linkError = nil } })
    ) {
      Button("Mengerti", role: .cancel) { linkError = nil }
    } message: {
      Text(linkError ?? "")
    }
  }

  private var totalUnread: Int { store.myGroups.reduce(0) { $0 + store.unreadCount(groupID: $1.id) } }

  // Prototype tab bar: left/right 12, bottom 22, height 68, radius 34, buttons 56 high.
  private var tabBar: some View {
    HStack(spacing: 2) {
      tabButton(0, "Beranda", "house")
      tabButton(1, "Grup", "person.2")
      tabButton(2, "Chat", "bubble.left", badge: totalUnread)
      tabButton(3, "Tugas Saya", "checkmark.circle")
    }
    .padding(.horizontal, 6).frame(height: 68)
    .background(GLTheme.ink, in: Capsule())
    .shadow(color: .black.opacity(0.4), radius: 15, y: 16)
    .padding(.horizontal, 12).padding(.bottom, 22)
  }

  private func tabButton(_ index: Int, _ label: String, _ icon: String, badge: Int = 0) -> some View
  {
    let active = tab == index
    return Button {
      tab = index
    } label: {
      VStack(spacing: 1) {
        GLIcon(active ? icon + ".fill" : icon, size: 23)
          .overlay(alignment: .topTrailing) {
            if badge > 0 {
              Text("\(badge)").font(.system(size: 11, weight: .bold)).foregroundStyle(GLTheme.ink)
                .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                .background(GLTheme.mint, in: Capsule())
                .overlay(Capsule().stroke(GLTheme.ink, lineWidth: 2))
                .offset(x: 10, y: -4)
            }
          }
        Text(label).font(.system(size: 12, weight: .semibold)).lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      .frame(maxWidth: .infinity).frame(height: 56)
      .foregroundStyle(active ? GLTheme.ink : .white.opacity(0.78))
      .background(active ? Color.white : .clear, in: Capsule())
      .contentShape(Capsule())
    }.buttonStyle(.plain).accessibilityIdentifier("tab-\(index)")
      .accessibilityLabel(badge > 0 ? "\(label), \(badge) pesan baru" : label)
      .accessibilityAddTraits(active ? .isSelected : [])
  }

  private func openLink(_ url: URL) {
    guard url.scheme == "grouply" else { return }
    guard store.currentUserID != nil else {
      linkError = "Masuk ke demo terlebih dahulu, lalu buka lagi tautannya."
      return
    }
    if url.host == "task", let id = url.pathComponents.last,
      let task = store.task(id), let project = store.project(task.projectID),
      store.isMember(groupID: project.groupID)
    {
      tab = 0
      paths[0] = [.task(id)]
    } else {
      linkError = "Tugas tidak ditemukan atau kamu tidak memiliki akses."
    }
  }
}

struct WelcomeView: View {
  @Environment(DemoStore.self) private var store
  @State private var backendLogin = false
  @State private var privacy = false
  var body: some View {
    Group {
      if store.isRestoringSession { restoring } else { welcome }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity).glScreen()
    .sheet(isPresented: $backendLogin) { BackendLoginView() }
    .sheet(isPresented: $privacy) { ProfilePrivacySheet() }
  }

  /// Prototype `showRestoring`.
  private var restoring: some View {
    VStack(spacing: 16) {
      GLIcon("person.3", size: 36).frame(width: 72, height: 72)
        .background(GLTheme.mint, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
      Text("GROUPLY").gl(15, .heavy, em: 0.12)
      HStack(spacing: 8) {
        ProgressView().controlSize(.small)
        Text("Memulihkan sesi…").gl(14)
      }.foregroundStyle(GLTheme.secondary)
    }
  }

  private var welcome: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        HStack(spacing: 10) {
          GLIcon("person.3", size: 22).frame(width: 40, height: 40)
            .background(GLTheme.mint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
          Text("GROUPLY").gl(15, .heavy, em: 0.12)
        }
        previewCards
        VStack(alignment: .leading, spacing: 8) {
          Text("Kerja kelompok yang beneran jalan.").gl(30, .bold, em: -0.03)
          Text("Bagi tugas, kirim hasil, review bareng, dan pantau progres grup dalam satu tempat.")
            .gl(15).lineSpacing(4.5).foregroundStyle(GLTheme.secondary)
        }
        VStack(spacing: 8) {
          Button { backendLogin = true } label: {
            Text("Masuk dengan Akun").gl(17, .semibold).foregroundStyle(.white)
              .frame(maxWidth: .infinity).frame(height: 56)
              .background(.black, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
          }.buttonStyle(.plain).accessibilityIdentifier("open-backend-login")
          Text("Akun Supabase terpisah dari persona demo di bawah.").gl(12)
            .foregroundStyle(GLTheme.secondary).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 6) {
            Text("DEMO").gl(11, .bold, em: 0.06).padding(.horizontal, 8).frame(height: 22)
              .background(GLTheme.butter, in: Capsule())
            Text("Masuk cepat sebagai").gl(13, .semibold)
          }
          LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(profilePersonas, id: \.id) { persona in
              if let user = store.user(persona.id), !user.email.isEmpty {
                personaButton(user, role: persona.role)
              }
            }
          }
        }
        Button { privacy = true } label: {
          Text("Privasi & data").gl(14, .semibold).underline().frame(minHeight: 44)
        }.buttonStyle(.plain).frame(maxWidth: .infinity)
      }
      .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 32)
    }
  }

  private func personaButton(_ user: GLUser, role: String) -> some View {
    Button {
      store.signIn(as: user.id)
      if store.currentUserID == user.id { store.flash("Masuk sebagai " + user.name) }
    } label: {
      HStack(spacing: 8) {
        GLAvatar(user: user, size: 32, fontSize: 11)
        VStack(alignment: .leading, spacing: 0) {
          Text(user.name).gl(14, .semibold).lineLimit(1)
          Text(role).gl(12).foregroundStyle(GLTheme.secondary).lineLimit(1)
        }
        Spacer(minLength: 0)
      }
      .padding(.vertical, 6).padding(.leading, 6).padding(.trailing, 10).frame(minHeight: 48)
      .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(GLTheme.border))
      .contentShape(Rectangle())
    }.buttonStyle(.plain).accessibilityIdentifier("persona-\(user.id)")
  }

  /// Three tilted preview cards (`flex:1 1 220px`, clamped 170–260).
  private var previewCards: some View {
    GeometryReader { geo in
      let w = geo.size.width, h = geo.size.height
      ZStack(alignment: .topLeading) {
        VStack(alignment: .leading, spacing: 6) {
          Text("Perlu perhatian").gl(14, .bold)
          Text("Revisi diminta oleh Nadia").gl(13).foregroundStyle(GLTheme.text2)
          Text("Tulis script DDL SQL").gl(15, .semibold)
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
        .frame(width: w * 0.7, alignment: .leading)
        .background(GLTheme.butter, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 10)
        .rotationEffect(.degrees(-3))
        .offset(y: h * 0.06)
        VStack(alignment: .leading, spacing: 8) {
          GLChip(label: "Menunggu review", icon: "eye", background: GLTheme.lavender, height: 26, fontSize: 12, iconSize: 15)
          Text("Draft diagram ERD").gl(15, .semibold)
        }
        .padding(.vertical, 14).padding(.horizontal, 16)
        .frame(width: w * 0.66, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.14), radius: 14, y: 14)
        .rotationEffect(.degrees(2.5))
        .offset(x: w * 0.34, y: h * 0.34)
        Text("ERD udah aku kirim ya!").gl(14)
          .padding(.vertical, 10).padding(.horizontal, 14)
          .background(
            GLTheme.lavender,
            in: UnevenRoundedRectangle(
              topLeadingRadius: 18, bottomLeadingRadius: 6, bottomTrailingRadius: 18,
              topTrailingRadius: 18, style: .continuous)
          )
          .frame(maxWidth: w * 0.62, alignment: .leading)
          .rotationEffect(.degrees(-1.5))
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
          .offset(x: w * 0.08)
      }
    }
    .frame(height: 220)
    .accessibilityHidden(true)
  }
}

struct HomeView: View {
  @Environment(DemoStore.self) private var store
  let openProfile: () -> Void
  let openTab: (Int) -> Void
  private var me: String { store.currentUserID ?? "" }
  /// Prototype `liveTasks`: tasks in non-archived projects of my groups.
  private var live: [GLTask] {
    store.tasks.filter { task in
      guard let p = store.project(task.projectID) else { return false }
      return p.status != .archived && store.isMember(groupID: p.groupID)
    }
  }
  private var attention: [(task: GLTask, icon: String, reason: String)] {
    live.filter { $0.assigneeID == me && $0.status != .done && $0.status != .inReview }
      .compactMap { t -> (Int, GLTask, String, String)? in
        if t.status == .needsRevision {
          let by = t.submissions.last?.reviewerID.flatMap { store.user($0)?.name }
          return (0, t, "arrow.uturn.backward", "Revisi diminta" + (by.map { " oleh " + $0 } ?? ""))
        }
        if GLFormat.isOverdue(t.dueAt, status: t.status, now: store.now) {
          return (1, t, "exclamationmark.circle", "Terlambat sejak " + GLFormat.date(t.dueAt))
        }
        return nil
      }
      .sorted { $0.0 < $1.0 }.map { ($0.1, $0.2, $0.3) }
  }
  private var reviews: [GLTask] {
    live.filter { $0.reviewerID == me && $0.status == .inReview }
  }
  private var deadlines: [GLTask] {
    let skip = Set(attention.map(\.task.id))
    let end = store.now.addingTimeInterval(7 * 86400)
    return live.filter {
      $0.assigneeID == me && $0.status != .done && $0.status != .inReview && !skip.contains($0.id)
        && $0.dueAt >= store.now && $0.dueAt <= end
    }.sorted { $0.dueAt < $1.dueAt }
  }
  private var activeProjects: [GLProject] {
    store.projects.filter { $0.status == .active && store.isMember(groupID: $0.groupID) }
  }
  private var activity: [GLMessage] {
    store.messages.filter {
      $0.kind == "activity" && $0.taskID == nil && store.isMember(groupID: $0.groupID)
        && $0.targetTaskID.flatMap(store.task) != nil
    }.sorted { $0.createdAt > $1.createdAt }.prefix(3).map { $0 }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        header
        Label(store.isCloudMode ? "Akun server · Supabase" : "Demo lokal · data contoh", systemImage: store.isCloudMode ? "externaldrive.connected.to.line.below" : "iphone")
          .gl(12, .medium).foregroundStyle(GLTheme.secondary)
        if store.myGroups.isEmpty {
          emptyGroups
        } else {
          if let error = store.persistenceError { GLNotice(text: error, color: GLTheme.coral) }
          if store.simulatedOffline {
            GLNotice(
              text: "Simulasi offline aktif. Perubahan dinonaktifkan; data terakhir tetap terlihat.",
              color: GLTheme.coral, icon: "wifi.slash")
          }
          attentionCard
          if !reviews.isEmpty { reviewCard }
          VStack(alignment: .leading, spacing: 12) {
            GLSectionHeading(title: "Deadline terdekat", actionTitle: "Semua tugas") { openTab(3) }
            deadlineList
          }
          VStack(alignment: .leading, spacing: 12) {
            GLSectionHeading(title: "Proyek aktif", actionTitle: "Semua grup") { openTab(1) }
            if activeProjects.isEmpty {
              Text("Belum ada proyek aktif. Buka grup untuk membuat atau melihat proyek.")
                .gl(15).lineSpacing(4).foregroundStyle(GLTheme.secondary).padding(18)
                .frame(maxWidth: .infinity, alignment: .leading).glSurface(24)
            }
            ForEach(activeProjects) { project in
              NavigationLink(value: Route.project(project.id)) { HomeProjectCard(project: project) }
                .buttonStyle(GLCardButtonStyle())
            }
          }
          if !activity.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
              Text("Aktivitas terbaru").gl(21, .bold, em: -0.02)
              VStack(spacing: 0) {
                ForEach(activity) { message in activityRow(message) }
              }.padding(.horizontal, 16).padding(.vertical, 4)
                .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
          }
        }
      }.padding(.horizontal, 20).padding(.top, 10)
    }.glScreen().toolbar(.hidden, for: .navigationBar)
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(
          store.now.formatted(
            .dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "id_ID")))
        ).gl(15).foregroundStyle(GLTheme.secondary)
        Text("Halo, \(store.currentUser?.name ?? "teman")").gl(30, .bold, em: -0.03)
      }
      Spacer(minLength: 0)
      Button(action: openProfile) { GLAvatar(user: store.currentUser, size: 48, fontSize: 15) }
        .buttonStyle(.plain)
        .accessibilityLabel("Profil dan pengaturan").accessibilityIdentifier("open-profile")
    }
  }

  private func cardHeader(_ title: String, _ count: Int) -> some View {
    HStack {
      Text(title).gl(19, .bold, em: -0.02)
      Spacer()
      GLCountBadge(count: count)
    }.padding(.bottom, 4)
  }

  private var attentionCard: some View {
    VStack(alignment: .leading, spacing: 0) {
      cardHeader("Perlu perhatian", attention.count)
      if attention.isEmpty {
        HStack(spacing: 8) {
          GLIcon("checkmark.circle", size: 20)
          Text("Semua aman, tidak ada yang mendesak.").gl(15)
        }.foregroundStyle(GLTheme.text2).padding(.top, 12).padding(.bottom, 14)
      }
      ForEach(attention, id: \.task.id) { item in
        NavigationLink(value: Route.task(item.task.id)) {
          HStack(spacing: 12) {
            GLIcon(item.icon, size: 20).frame(width: 40, height: 40)
              .background(.white.opacity(0.7), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
              Text(item.reason).gl(13, .semibold).foregroundStyle(GLTheme.text2)
              Text(item.task.title).gl(16, .semibold)
            }
            Spacer(minLength: 0)
            GLIcon("chevron.right", size: 22).foregroundStyle(GLTheme.text2)
          }
          .padding(.vertical, 12).frame(minHeight: 60)
          .overlay(alignment: .top) { Rectangle().fill(GLTheme.ink.opacity(0.1)).frame(height: 1) }
        }.buttonStyle(GLRowButtonStyle())
      }
    }
    .padding(.top, 18).padding(.horizontal, 18).padding(.bottom, 8)
    .background(GLTheme.butter, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
  }

  private var reviewCard: some View {
    VStack(alignment: .leading, spacing: 0) {
      cardHeader("Menunggu review kamu", reviews.count)
      ForEach(reviews) { task in
        NavigationLink(value: Route.task(task.id)) {
          HStack(spacing: 12) {
            GLAvatar(user: store.user(task.assigneeID), size: 40, fontSize: 13)
              .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 2))
            VStack(alignment: .leading, spacing: 3) {
              Text(task.title).gl(16, .semibold)
              // flex-wrap: the stale chip drops to its own line when it doesn't fit.
              let from = Text(
                "Dari \(store.user(task.assigneeID)?.name ?? "anggota") · revisi \(task.submissions.count)"
              ).gl(13).foregroundStyle(GLTheme.text3)
              if let hours = waitingHours(task), hours > 48 {
                let chip = GLChip(
                  label: "Menunggu \(hours) jam", icon: "list.bullet.clipboard",
                  background: .white, outlined: true, height: 24, fontSize: 12, iconSize: 15
                ).fixedSize()
                ViewThatFits(in: .horizontal) {
                  HStack(spacing: 6) { from; chip }
                  VStack(alignment: .leading, spacing: 6) { from; chip }
                }
              } else {
                from
              }
            }
            Spacer(minLength: 0)
            GLIcon("chevron.right", size: 22).foregroundStyle(GLTheme.text3)
          }
          .padding(.vertical, 12).frame(minHeight: 60)
          .overlay(alignment: .top) { Rectangle().fill(GLTheme.ink.opacity(0.1)).frame(height: 1) }
        }.buttonStyle(GLRowButtonStyle())
      }
    }
    .padding(.top, 18).padding(.horizontal, 18).padding(.bottom, 8)
    .background(GLTheme.lavender, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
  }

  private var deadlineList: some View {
    VStack(spacing: 0) {
      if deadlines.isEmpty {
        Text("Tidak ada deadline 7 hari ke depan.").gl(15).foregroundStyle(GLTheme.secondary)
          .padding(.vertical, 16).frame(maxWidth: .infinity, alignment: .leading)
      }
      ForEach(deadlines) { task in
        NavigationLink(value: Route.task(task.id)) {
          HStack(spacing: 14) {
            VStack(spacing: 0) {
              Text(task.dueAt.formatted(.dateTime.day())).gl(20, .bold)
              Text(GLFormat.weekday(task.dueAt)).gl(12, .semibold).foregroundStyle(GLTheme.secondary)
            }.frame(width: 50, height: 54)
              .background(GLTheme.muted, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
              Text(task.title).gl(16, .semibold)
              Text(
                GLFormat.due(task.dueAt, status: task.status, now: store.now) + " · "
                  + task.status.label
              ).gl(13).foregroundStyle(GLTheme.secondary)
            }
            Spacer(minLength: 0)
            GLIcon("chevron.right", size: 22).foregroundStyle(GLTheme.secondary)
          }
          .padding(.vertical, 12)
          .overlay(alignment: .bottom) { Rectangle().fill(GLTheme.border).frame(height: 1) }
        }.buttonStyle(GLRowButtonStyle())
      }
    }.padding(.horizontal, 16).padding(.vertical, 4).glSurface(24)
  }

  private func activityRow(_ message: GLMessage) -> some View {
    let style = ActivityStyle(message.text)
    let actor = message.senderID == me ? "Kamu" : store.user(message.senderID)?.name ?? "Anggota"
    return NavigationLink(value: Route.task(message.targetTaskID ?? "")) {
      HStack(spacing: 12) {
        GLIcon(style.icon, size: 19).frame(width: 38, height: 38)
          .background(style.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        VStack(alignment: .leading, spacing: 1) {
          Text("\(actor) \(message.text) · \(GLFormat.activityStamp(message.createdAt, now: store.now))")
            .gl(13).foregroundStyle(GLTheme.text2)
          Text(message.targetTaskID.flatMap(store.task)?.title ?? "Tugas tidak tersedia").gl(15, .semibold)
        }
        Spacer(minLength: 0)
      }
      .padding(.vertical, 12).frame(minHeight: 60)
      .overlay(alignment: .bottom) { Rectangle().fill(GLTheme.border).frame(height: 1) }
    }.buttonStyle(GLRowButtonStyle())
  }

  private var emptyGroups: some View {
    VStack(alignment: .leading, spacing: 14) {
      GLIcon("person.badge.plus", size: 28).frame(width: 56, height: 56)
        .background(GLTheme.mint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
      Text("Mulai dari grupmu").gl(22, .bold, em: -0.02)
      Text(
        "Kamu belum tergabung di grup mana pun. Buat grup lalu bagikan kode undangan, atau gabung dengan kode dari temanmu."
      ).gl(15).lineSpacing(4).foregroundStyle(GLTheme.secondary)
      HStack(spacing: 10) {
        Button { openTab(1) } label: {
          Text("Buat grup").gl(15, .semibold).frame(maxWidth: .infinity).frame(height: 52)
        }.buttonStyle(GLButtonStyle(radius: 18))
        Button { openTab(1) } label: {
          Text("Gabung dengan kode").gl(15, .semibold).frame(maxWidth: .infinity).frame(height: 52)
            .overlay(
              RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(
                GLTheme.ink, lineWidth: 1.5))
        }.buttonStyle(.plain)
      }.padding(.top, 6)
    }.padding(.vertical, 28).padding(.horizontal, 22).frame(maxWidth: .infinity, alignment: .leading)
      .background(.white, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
  }

  private func waitingHours(_ task: GLTask) -> Int? {
    guard let submitted = task.submissions.last?.createdAt else { return nil }
    return Int(store.now.timeIntervalSince(submitted) / 3600)
  }
}

/// Icon + tint for an activity line, keyed by the prototype's ACT verbs.
struct ActivityStyle {
  let icon: String
  let tint: Color
  init(_ verb: String) {
    switch true {
    case verb.hasPrefix("mengirim"): (icon, tint) = ("square.and.arrow.up", GLTheme.lavender)
    case verb.hasPrefix("menyetujui"): (icon, tint) = ("checkmark.circle", GLTheme.mint)
    case verb.hasPrefix("meminta"): (icon, tint) = ("arrow.uturn.backward", GLTheme.coral)
    case verb.hasPrefix("membuat"): (icon, tint) = ("checklist", GLTheme.sky)
    case verb.hasPrefix("mengalihkan"): (icon, tint) = ("arrow.left.arrow.right", GLTheme.sky)
    default: (icon, tint) = ("pencil", GLTheme.butter)
    }
  }
}

/// Project card used on Beranda (prototype `vmProject`).
struct HomeProjectCard: View {
  @Environment(DemoStore.self) private var store
  let project: GLProject
  var body: some View {
    let group = store.group(project.groupID)
    let tasks = store.tasks(in: project.id)
    let done = tasks.filter { $0.status == .done }.count
    HStack(spacing: 14) {
      GLIcon(group?.icon ?? "folder", size: 22).frame(width: 48, height: 48)
        .background(Color(hex: group?.tint ?? "FFFFFF"), in: Circle())
      VStack(alignment: .leading, spacing: 8) {
        VStack(alignment: .leading, spacing: 1) {
          Text(project.title).gl(16, .semibold)
          Text("\(group?.name ?? "") · deadline \(GLFormat.date(project.dueAt))").gl(13)
            .foregroundStyle(GLTheme.secondary)
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
    }
    .padding(.vertical, 14).padding(.leading, 14).padding(.trailing, 16)
    .frame(maxWidth: .infinity, alignment: .leading).glSurface(24)
    .accessibilityElement(children: .combine)
  }
}
