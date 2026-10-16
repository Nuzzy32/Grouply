import SwiftUI

enum Route: Hashable {
  case group(String)
  case project(String)
  case task(String)
  case chat(String)
}

struct RootView: View {
  @Environment(DemoStore.self) private var store
  @State private var tab = 0
  @State private var profile = false
  @State private var paths: [[Route]] = [[], [], [], []]
  @State private var linkError: String?
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    Group {
      if store.currentUserID == nil {
        WelcomeView()
      } else {
        VStack(spacing: 0) {
          NavigationStack(path: $paths[tab]) {
            Group {
              switch tab {
              case 1: GroupsView()
              case 2: ChatsView()
              case 3: MyTasksView()
              default: HomeView(openProfile: { profile = true }, openTab: { tab = $0 })
              }
            }
            .navigationDestination(for: Route.self) { route in
              switch route {
              case .group(let id): GroupDetailView(groupID: id)
              case .project(let id): ProjectDetailView(projectID: id)
              case .task(let id): TaskDetailView(taskID: id)
              case .chat(let id): ChatDetailView(groupID: id)
              }
            }
          }
          .id(tab)
          tabBar
        }.background(GLTheme.background)
      }
    }
    .sheet(isPresented: $profile) {
      NavigationStack { ProfileView() }.presentationDragIndicator(.visible)
    }
    .onChange(of: store.currentUserID) { _, _ in
      paths = [[], [], [], []]
      profile = false
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

  private var tabBar: some View {
    HStack(spacing: 4) {
      tabButton(0, "Beranda", "square.grid.2x2")
      tabButton(1, "Grup", "person.3")
      tabButton(2, "Chat", "bubble.left.and.bubble.right")
      tabButton(3, "Tugas Saya", "checkmark.circle")
    }
    .padding(8).background(GLTheme.ink, in: RoundedRectangle(cornerRadius: 28))
    .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 4)
  }

  private func tabButton(_ index: Int, _ label: String, _ icon: String) -> some View {
    Button {
      tab = index
    } label: {
      VStack(spacing: 5) {
        Image(systemName: icon).font(.system(size: 20, weight: .semibold))
        Text(typeSize.isAccessibilitySize && index == 3 ? "Tugas" : label).font(
          .caption2.weight(.semibold)
        ).lineLimit(1)
          .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
      }.frame(maxWidth: .infinity).frame(minHeight: typeSize.isAccessibilitySize ? 62 : 50)
        .padding(.horizontal, 2)
        .foregroundStyle(tab == index ? GLTheme.ink : .white)
        .background(tab == index ? GLTheme.mint : .clear, in: RoundedRectangle(cornerRadius: 21))
    }.buttonStyle(.plain).accessibilityIdentifier("tab-\(index)")
      .accessibilityLabel(label)
      .accessibilityAddTraits(tab == index ? .isSelected : [])
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
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        HStack {
          Image(systemName: "person.3.sequence.fill").font(.title2).padding(12)
            .background(GLTheme.mint, in: RoundedRectangle(cornerRadius: 15))
          Text("GROUPLY").font(.headline).tracking(3)
        }
        VStack(alignment: .leading, spacing: 12) {
          VStack(alignment: .leading, spacing: 8) {
            Label("Perlu perhatian", systemImage: "sparkle").font(.headline)
            Text("Revisi diminta oleh Nadia").font(.subheadline)
            Text("Tulis script DDL SQL").font(.headline)
          }.glCard(GLTheme.butter).rotationEffect(.degrees(-3)).padding(.trailing, 35)
          VStack(alignment: .leading, spacing: 10) {
            GLStatusChip(status: .inReview)
            Text("Draft diagram ERD").font(.headline)
          }.glCard().rotationEffect(.degrees(3)).padding(.leading, 48)
          Text("ERD udah aku kirim ya!").font(.subheadline).padding(16)
            .background(GLTheme.lavender, in: RoundedRectangle(cornerRadius: 20)).padding(
              .leading, 15)
        }.padding(.vertical, 20).accessibilityElement(children: .ignore).accessibilityLabel(
          "Bagi tugas, kirim hasil, review bareng")
        VStack(alignment: .leading, spacing: 12) {
          Text("Kerja kelompok\nyang beneran jalan.").font(.largeTitle.bold()).tracking(-1)
          Text("Bagi tugas, kirim hasil, review bareng, dan pantau progres grup dalam satu tempat.")
            .foregroundStyle(GLTheme.secondary)
        }
        GLNotice(
          text:
            "Demo lokal · pilih persona untuk mencoba. Data tersimpan di perangkat ini. Akun Apple dan sinkronisasi Supabase belum terhubung.",
          color: GLTheme.sky)
        Text("MASUK KE DEMO SEBAGAI").font(.caption.bold()).tracking(1)
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
          ForEach(store.users.filter { !$0.email.isEmpty }) { user in
            Button {
              store.signIn(as: user.id)
            } label: {
              HStack {
                GLAvatar(user: user)
                Text(user.name).font(.subheadline.bold())
                Spacer(minLength: 0)
              }
              .padding(12).frame(minHeight: 54).background(
                .white, in: RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(.plain).accessibilityIdentifier("persona-\(user.id)")
          }
        }
        Text("Tanpa unggahan dokumen, pelacakan iklan, atau pengiriman data demo ke server.")
          .font(.caption).foregroundStyle(GLTheme.secondary)
      }.padding(24)
    }.glScreen()
  }
}

struct HomeView: View {
  @Environment(DemoStore.self) private var store
  let openProfile: () -> Void
  let openTab: (Int) -> Void
  private var visibleTasks: [GLTask] {
    store.tasks.filter { task in
      guard let p = store.project(task.projectID) else { return false }
      return p.status == .active && store.isMember(groupID: p.groupID)
    }
  }
  private var attention: [GLTask] {
    visibleTasks.filter {
      ($0.assigneeID == store.currentUserID
        && ($0.status == .needsRevision || ($0.dueAt < store.now && $0.status != .done)))
        || stale($0)
    }
  }
  private var reviews: [GLTask] {
    visibleTasks.filter { $0.reviewerID == store.currentUserID && $0.status == .inReview }
  }
  private var deadlines: [GLTask] {
    visibleTasks.filter { $0.assigneeID == store.currentUserID && $0.status != .done }.sorted {
      $0.dueAt < $1.dueAt
    }
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        HStack(alignment: .top) {
          VStack(alignment: .leading, spacing: 5) {
            Text(
              store.now.formatted(
                .dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "id_ID")))
            )
            .font(.subheadline).foregroundStyle(GLTheme.secondary)
            Text("Halo, \(store.currentUser?.name ?? "teman")!").font(.largeTitle.bold()).tracking(
              -1)
          }
          Spacer(minLength: 8)
          Button(action: openProfile) { GLAvatar(user: store.currentUser, size: 48) }
            .accessibilityLabel("Profil dan pengaturan").accessibilityIdentifier("open-profile")
        }
        HStack(spacing: 6) {
          Circle().fill(GLTheme.secondary).frame(width: 6, height: 6)
          Text("DEMO LOKAL").font(.caption2.bold()).tracking(1)
          Text("· data contoh, tersimpan di perangkat").font(.caption)
        }.foregroundStyle(GLTheme.secondary)
        if let error = store.persistenceError { GLNotice(text: error, color: GLTheme.coral) }
        if store.simulatedOffline {
          GLNotice(
            text: "Simulasi offline aktif. Perubahan dinonaktifkan; data terakhir tetap terlihat.",
            color: GLTheme.coral)
        }
        if store.myGroups.isEmpty {
          GLEmptyState(
            title: "Mulai dari grupmu",
            message: "Buat grup atau gabung memakai kode undangan dari temanmu.",
            systemImage: "person.3.sequence")
          GLPrimaryButton(title: "Buka Grup", systemImage: "arrow.right") { openTab(1) }
        } else {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Text("Perlu perhatian").font(.title3.bold())
              Spacer()
              count(attention.count)
            }
            if attention.isEmpty {
              Label("Semua aman, tidak ada yang mendesak.", systemImage: "checkmark.circle").font(
                .subheadline
              ).padding(.vertical, 8)
            }
            ForEach(attention.prefix(3)) { task in
              Divider().overlay(GLTheme.ink.opacity(0.05))
              NavigationLink(value: Route.task(task.id)) {
                HStack(spacing: 12) {
                  Image(
                    systemName: stale(task) ? "clock.badge.exclamationmark" : "arrow.uturn.backward"
                  )
                  .frame(width: 40, height: 40).background(.white.opacity(0.7), in: Circle())
                  VStack(alignment: .leading, spacing: 4) {
                    Text(
                      stale(task)
                        ? "Review pending > 48 jam"
                        : task.status == .needsRevision ? "Revisi diminta" : "Deadline terlewat"
                    ).font(.caption.weight(.semibold))
                    Text(task.title).font(.headline)
                  }
                  Spacer(minLength: 0)
                  Image(systemName: "chevron.right").font(.caption)
                }.padding(.vertical, 4)
              }.buttonStyle(.plain)
            }
          }.glCard(GLTheme.butter)
          if !reviews.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
              HStack {
                Text("Menunggu review kamu").font(.title3.bold())
                Spacer()
                count(reviews.count)
              }
              ForEach(reviews) { task in
                NavigationLink(value: Route.task(task.id)) {
                  HStack(spacing: 12) {
                    GLAvatar(user: store.user(task.assigneeID))
                    VStack(alignment: .leading, spacing: 4) {
                      Text(task.title).font(.headline)
                      Text("Dari \(store.user(task.assigneeID)?.name ?? "anggota")").font(.caption)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption)
                  }.padding(.vertical, 5)
                }.buttonStyle(.plain)
              }
            }.glCard(GLTheme.lavender)
          }
          HStack {
            GLSectionHeading(title: "Deadline terdekat")
            Button("Semua tugas") { openTab(3) }.font(.subheadline.bold())
          }
          if deadlines.isEmpty {
            Text("Tidak ada deadline yang menunggu.").foregroundStyle(GLTheme.secondary)
          } else {
            VStack(spacing: 0) {
              ForEach(deadlines.prefix(3)) { task in
                NavigationLink(value: Route.task(task.id)) {
                  HStack(spacing: 14) {
                    VStack(spacing: 0) {
                      Text(task.dueAt.formatted(.dateTime.day())).font(.title2.bold())
                      Text(
                        task.dueAt.formatted(
                          .dateTime.month(.abbreviated).locale(Locale(identifier: "id_ID")))
                      ).font(.caption)
                    }.frame(width: 50, height: 56).background(
                      GLTheme.muted, in: RoundedRectangle(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 5) {
                      Text(task.title).font(.headline)
                      Text(GLFormat.deadline(task.dueAt, now: store.now)).font(.caption)
                        .foregroundStyle(GLTheme.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption)
                  }.padding(.vertical, 10)
                }.buttonStyle(.plain)
              }
            }.glCard()
          }
          HStack {
            GLSectionHeading(title: "Proyek aktif")
            Button("Semua grup") { openTab(1) }.font(.subheadline.bold())
          }
          ForEach(
            store.projects.filter { $0.status == .active && store.isMember(groupID: $0.groupID) }
          ) { project in
            NavigationLink(value: Route.project(project.id)) { GLProjectRow(project: project) }
              .buttonStyle(.plain)
          }
        }
      }.padding(20)
    }.glScreen().toolbar(.hidden, for: .navigationBar)
  }
  private func count(_ number: Int) -> some View {
    Text("\(number)").font(.subheadline.bold()).foregroundStyle(.white).padding(8).background(
      GLTheme.ink, in: Circle())
  }
  private func stale(_ task: GLTask) -> Bool {
    guard task.status == .inReview, let submitted = task.submissions.last,
      let project = store.project(task.projectID)
    else { return false }
    return store.isCoordinator(groupID: project.groupID)
      && store.now.timeIntervalSince(submitted.createdAt) > 48 * 3600
  }
}
