import SwiftUI

// Prototype `isProfile` + `isNotif` / `isBlocked` / `isAbout` and the profile sheets.

private enum ProfileSub: Hashable { case notif, blocked, about }
enum ProfileSheet: String, Identifiable {
  case editName, perm, personas, delete, privacy
  var id: String { rawValue }
}

/// Prototype `PERSONAS`.
let profilePersonas: [(id: String, role: String)] = [
  ("u1", "Koordinator"), ("u2", "Pelaksana"), ("u3", "Reviewer"), ("u4", "Anggota"),
  ("u5", "Anggota"), ("u6", "Koordinator"), ("u7", "Anggota"),
]

struct ProfileView: View {
  @Environment(DemoStore.self) private var store
  @AppStorage("grouply.local.perm") private var perm = "off"
  @State private var sub: ProfileSub?
  @State private var sheet: ProfileSheet?
  @State private var confirm: GLConfirmation?

  private var me: String { store.currentUserID ?? "" }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        GLDetailHeader("Profil")
        if let error = store.persistenceError { GLNotice(text: error, color: GLTheme.coral) }
        profileCard
        sectionLabel("Preferensi")
        ProfileGroup {
          navRow(
            "bell", GLTheme.butter, "Notifikasi",
            perm == "on" ? "Izin aktif" : perm == "denied" ? "Diblokir di Pengaturan iOS" : "Izin belum aktif",
            divider: true
          ) { sub = .notif }
          navRow("info.circle", GLTheme.sky, "Tentang GROUPLY", "Versi, privasi, moderasi") { sub = .about }
        }
        sectionLabel("Keamanan")
        ProfileGroup {
          let blocked = store.blockedUserIDs.count
          navRow(
            "nosign", GLTheme.coral, "Pengguna diblokir", blocked > 0 ? "\(blocked) pengguna" : "Tidak ada",
            divider: true
          ) { sub = .blocked }
          navRow(
            "flag", Color(hex: "ECEEEB"), "Pelaporan",
            "\(store.reports.filter { $0.reporterID == me }.count) laporan tersimpan \(store.isCloudMode ? "di server" : "lokal")"
          ) { sub = .about }
        }
        sectionLabel("Akun")
        ProfileGroup {
          actionRow("rectangle.portrait.and.arrow.right", "Keluar akun", divider: true) {
            confirm = GLConfirmation(
              title: "Keluar dari GROUPLY?", text: "Kamu perlu masuk lagi untuk membuka grup dan tugasmu.",
              ok: "Keluar", destructive: true
            ) {
              Task {
                do { try await store.signOut() } catch { store.flash(error.localizedDescription, .err) }
              }
            }
          }
          actionRow("trash", "Hapus akun", color: GLTheme.danger) { sheet = .delete }
            .accessibilityIdentifier("delete-account")
        }
        if !store.isCloudMode { demoBox }
      }
      .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 32)
    }
    .glDetailScreen()
    .navigationDestination(item: $sub) { sub in
      switch sub {
      case .notif: ProfileNotifView()
      case .blocked: ProfileBlockedView()
      case .about: ProfileAboutView()
      }
    }
    .sheet(item: $sheet) { ProfileSheetView(sheet: $0) }
    .glConfirm($confirm)
  }

  private var profileCard: some View {
    HStack(spacing: 14) {
      GLAvatar(user: store.currentUser, size: 64, fontSize: 20)
      VStack(alignment: .leading, spacing: 2) {
        Text(store.currentUser?.name ?? "").gl(20, .bold)
        Text(store.currentUser?.email ?? "").gl(14).foregroundStyle(GLTheme.secondary)
      }.frame(maxWidth: .infinity, alignment: .leading)
      ProfilePillButton(title: "Edit") { sheet = .editName }
    }
    .padding(20).background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
  }

  private var demoBox: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 6) {
        Text("PROTOTIPE").gl(11, .bold, em: 0.04).padding(.horizontal, 8).frame(height: 22)
          .background(GLTheme.butter, in: Capsule())
        Text("Pengaturan demo").gl(13, .bold, em: 0.04)
      }
      Text("Hanya untuk pengujian. Tidak ada di aplikasi produksi.").gl(13).lineSpacing(2.5)
        .foregroundStyle(GLTheme.text3)
      HStack(spacing: 8) {
        GLOutlineButton(title: "Ganti persona", height: 44, radius: 14, fontSize: 14) { sheet = .personas }
        GLOutlineButton(title: "Reset data demo", height: 44, radius: 14, fontSize: 14) {
          confirm = GLConfirmation(
            title: "Reset data demo?",
            text:
              "Semua perubahan di prototipe (grup, proyek, tugas, pesan, laporan) kembali ke data awal. Tidak ada data server yang terpengaruh.",
            ok: "Reset", destructive: true
          ) {
            store.reset()
            store.flash("Data demo direset")
          }
        }
      }
    }
    .padding(.vertical, 14).padding(.horizontal, 16).frame(maxWidth: .infinity, alignment: .leading)
    .overlay(
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .strokeBorder(Color(hex: "9AA0A6"), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
  }

  private func sectionLabel(_ text: String) -> some View {
    Text(text.uppercased()).gl(14, .bold, em: 0.04).foregroundStyle(GLTheme.text2).padding(.top, 4)
  }

  private func navRow(
    _ icon: String, _ tint: Color, _ title: String, _ subtitle: String, divider: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        GLIcon(icon, size: 20).frame(width: 38, height: 38)
          .background(tint, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        VStack(alignment: .leading, spacing: 0) {
          Text(title).gl(16, .semibold)
          Text(subtitle).gl(13).foregroundStyle(GLTheme.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
        GLIcon("chevron.right", size: 22).foregroundStyle(GLTheme.secondary)
      }
      .frame(minHeight: 60).profileDivider(divider)
    }.buttonStyle(GLRowButtonStyle())
  }

  private func actionRow(
    _ icon: String, _ title: String, color: Color = GLTheme.ink, divider: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 12) {
        GLIcon(icon, size: 22)
        Text(title).gl(16, .semibold)
        Spacer(minLength: 0)
      }
      .foregroundStyle(color).frame(minHeight: 56).profileDivider(divider)
    }.buttonStyle(GLRowButtonStyle())
  }
}

// MARK: - Shared bits

/// White grouped list (`border-radius:24px;padding:4px 16px`).
private struct ProfileGroup<Content: View>: View {
  var vertical: CGFloat = 4
  @ViewBuilder var content: Content
  var body: some View {
    VStack(spacing: 0) { content }
      .padding(.horizontal, 16).padding(.vertical, vertical)
      .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
  }
}

extension View {
  fileprivate func profileDivider(_ on: Bool = true) -> some View {
    overlay(alignment: .bottom) { if on { Rectangle().fill(GLTheme.border).frame(height: 1) } }
  }
}

/// 44pt capsule outline button ("Edit", "Buka blokir").
private struct ProfilePillButton: View {
  let title: String
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      Text(title).gl(14, .semibold).padding(.horizontal, 14).frame(height: 44)
        .overlay(Capsule().strokeBorder(GLTheme.ink, lineWidth: 1.5)).contentShape(Capsule())
    }.buttonStyle(.plain).fixedSize()
  }
}

/// iOS-style switch from the prototype's `sw()` (51×31, #34C759 / #D5D8DB, 27pt knob).
private struct ProfileSwitch: View {
  let on: Bool
  var body: some View {
    Capsule().fill(on ? Color(hex: "34C759") : Color(hex: "D5D8DB")).frame(width: 51, height: 31)
      .overlay(alignment: on ? .trailing : .leading) {
        Circle().fill(.white).frame(width: 27, height: 27)
          .shadow(color: .black.opacity(0.2), radius: 2, y: 2).padding(2)
      }
      .animation(.spring(response: 0.25, dampingFraction: 0.6), value: on)
  }
}

private struct ProfileDashedNote: View {
  let text: String
  var body: some View {
    Text(text).gl(13).lineSpacing(2.5).foregroundStyle(GLTheme.secondary)
      .padding(.vertical, 10).padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading)
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .strokeBorder(Color(hex: "9AA0A6"), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
  }
}

// MARK: - Notifikasi

private struct ProfileNotifView: View {
  @Environment(DemoStore.self) private var store
  @AppStorage("grouply.local.perm") private var perm = "off"
  @AppStorage("grouply.local.deadline") private var deadline = true
  @AppStorage("grouply.local.review") private var review = true
  @AppStorage("grouply.local.comment") private var comment = true
  @AppStorage("grouply.local.chat") private var chat = false
  @State private var sheet: ProfileSheet?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        GLDetailHeader("Notifikasi")
        Button {
          if perm == "on" {
            store.flash("Untuk mencabut izin, buka Pengaturan iOS (simulasi).", .info)
          } else if perm == "denied" {
            store.flash("Buka Pengaturan iOS untuk mengizinkan notifikasi (simulasi).", .info)
          } else {
            sheet = .perm
          }
        } label: {
          HStack(spacing: 12) {
            GLIcon("bell.badge", size: 21).frame(width: 40, height: 40)
              .background(GLTheme.butter, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
              Text("Izinkan notifikasi").gl(16, .semibold)
              Text(
                perm == "on"
                  ? "GROUPLY boleh mengirim notifikasi"
                  : perm == "denied" ? "Ditolak · ubah lewat Pengaturan iOS" : "Ketuk untuk mengaktifkan"
              ).gl(13).foregroundStyle(GLTheme.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            ProfileSwitch(on: perm == "on")
          }
          .padding(.vertical, 14).padding(.horizontal, 16).frame(minHeight: 68)
          .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(GLRowButtonStyle())
        .accessibilityValue(perm == "on" ? "Aktif" : "Nonaktif")
        if perm != "on" {
          Text("Pilihan di bawah tersimpan dan berlaku setelah izin notifikasi aktif.").gl(13)
            .lineSpacing(2.5).foregroundStyle(GLTheme.text3).padding(.horizontal, 4)
        }
        ProfileGroup {
          row("Deadline mendekat", "H-1 sebelum deadline tugasmu", $deadline)
          row("Review & revisi", "Saat hasilmu direview atau ada yang perlu kamu review", $review)
          row("Komentar di tugasku", "Diskusi tugas yang kamu kerjakan atau review", $comment)
          row("Pesan chat grup", "Semua pesan baru di chat grup", $chat)
        }
      }.padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 32)
    }
    .glDetailScreen()
    .sheet(item: $sheet) { ProfileSheetView(sheet: $0) }
  }

  private func row(_ label: String, _ sub: String, _ on: Binding<Bool>) -> some View {
    Button { on.wrappedValue.toggle() } label: {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(label).gl(16, .semibold)
          Text(sub).gl(13).lineSpacing(1.5).foregroundStyle(GLTheme.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
        ProfileSwitch(on: on.wrappedValue)
      }
      .padding(.vertical, 10).frame(minHeight: 64).profileDivider()
    }
    .buttonStyle(GLRowButtonStyle())
    .accessibilityValue(on.wrappedValue ? "Aktif" : "Nonaktif")
  }
}

// MARK: - Pengguna diblokir

private struct ProfileBlockedView: View {
  @Environment(DemoStore.self) private var store
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        GLDetailHeader("Pengguna diblokir")
        Text(
          "Pesan dari pengguna yang kamu blokir disembunyikan. Mereka tetap anggota grup dan tugas bersama tetap berjalan."
        ).gl(14).lineSpacing(3.5).foregroundStyle(GLTheme.text3)
        if store.blockedUserIDs.isEmpty {
          VStack(spacing: 10) {
            GLIcon("checkmark.shield", size: 28).frame(width: 56, height: 56)
              .background(GLTheme.mint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text("Belum ada yang kamu blokir").gl(18, .bold)
            Text("Kamu bisa memblokir dari detail anggota, atau dengan menekan lama sebuah pesan.")
              .gl(15).lineSpacing(4).foregroundStyle(GLTheme.secondary)
          }
          .multilineTextAlignment(.center).frame(maxWidth: .infinity)
          .padding(.vertical, 28).padding(.horizontal, 22)
          .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        } else {
          ProfileGroup(vertical: 0) {
            ForEach(store.blockedUserIDs, id: \.self) { id in
              let user = store.user(id)
              HStack(spacing: 12) {
                GLAvatar(user: user, size: 44, fontSize: 14)
                Text(user?.name ?? "Pengguna").gl(16, .semibold)
                  .frame(maxWidth: .infinity, alignment: .leading)
                ProfilePillButton(title: "Buka blokir") {
                  Task {
                    do {
                      try await store.unblockUser(id)
                      store.flash((user?.name ?? "Pengguna") + " tidak lagi diblokir", .info)
                    } catch { store.flash(error.localizedDescription, .err) }
                  }
                }
              }
              .padding(.vertical, 10).frame(minHeight: 64).profileDivider()
            }
          }
        }
      }.padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 32)
    }.glDetailScreen()
  }
}

// MARK: - Tentang

private struct ProfileAboutView: View {
  @Environment(DemoStore.self) private var store
  private var myReports: [GLReport] { store.reports.filter { $0.reporterID == store.currentUserID } }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        GLDetailHeader("Tentang GROUPLY")
        HStack(spacing: 14) {
          GLIcon("person.3", size: 26).frame(width: 52, height: 52)
            .background(GLTheme.mint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
          VStack(alignment: .leading, spacing: 0) {
            Text("GROUPLY").gl(17, .bold)
            Text("Versi 0.3 · prototipe desain").gl(13).foregroundStyle(GLTheme.secondary)
          }
        }.glCard()
        VStack(alignment: .leading, spacing: 8) {
          Text("Pelaporan & moderasi").gl(16, .bold)
          Text(store.isCloudMode
            ? "Tekan lama pesan untuk melaporkan atau memblokir pengirimnya. Laporan masuk antrean privat di server dan dapat ditinjau operator berwenang. Belum ada jaminan waktu respons."
            : "Tekan lama pesan untuk melaporkan atau memblokir pengirimnya. Dalam demo, laporan hanya disimpan di perangkat, bukan dikirim kepada moderator.")
            .gl(14).lineSpacing(5).foregroundStyle(GLTheme.text3)
          ForEach(myReports) { report in
            let from = store.messages.first { $0.id == report.messageID }
              .flatMap { store.user($0.senderID)?.name } ?? "anggota"
            HStack(spacing: 8) {
              GLIcon("flag", size: 18)
              Text("\(report.reason) · Pesan dari \(from)").gl(14)
                .frame(maxWidth: .infinity, alignment: .leading)
              Text(store.isCloudMode ? report.statusLabel : "Tersimpan lokal").gl(12).foregroundStyle(GLTheme.secondary)
            }
            .padding(.vertical, 10).padding(.horizontal, 12)
            .background(GLTheme.muted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
          }
        }.glCard()
        VStack(alignment: .leading, spacing: 8) {
          Text("Privasi").gl(16, .bold)
          Text(
            "Akun memakai nama dan identitas login. Pada mode server, akses grup, tugas, dan pesan diperiksa melalui membership dan aturan backend."
          ).gl(14).lineSpacing(5).foregroundStyle(GLTheme.text3)
        }.glCard()
      }.padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 32)
    }.glDetailScreen()
  }
}

// MARK: - Sheets

/// Prototype sheet without the title row (perm, personas, privacy draw their own).
private struct ProfileBareSheet<Content: View>: View {
  var spacing: CGFloat = 14
  var horizontal: CGFloat = 20
  var centered = false
  @ViewBuilder var content: Content
  @State private var height: CGFloat = 400
  var body: some View {
    ScrollView {
      VStack(alignment: centered ? .center : .leading, spacing: spacing) {
        Capsule().fill(Color(hex: "C4C7C5")).frame(width: 38, height: 5).frame(maxWidth: .infinity)
        content
      }
      .multilineTextAlignment(centered ? .center : .leading)
      .padding(.top, 10).padding(.horizontal, horizontal).padding(.bottom, 34)
      .foregroundStyle(GLTheme.ink)
      .background {
        GeometryReader { geo in
          Color.clear.onAppear { height = geo.size.height }
            .onChange(of: geo.size.height) { _, h in height = h }
        }
      }
    }
    .scrollBounceBehavior(.basedOnSize)
    .presentationDetents([.height(height)])
    .presentationDragIndicator(.hidden)
    .presentationCornerRadius(32)
    .presentationBackground(GLTheme.background)
  }
}

/// Filled sheet button (`height:54px;border-radius:18px;font-size:16px`).
private struct ProfileFilledButton: View {
  let title: String
  var height: CGFloat = 54
  var radius: CGFloat = 18
  var fontSize: CGFloat = 16
  var background: Color = GLTheme.ink
  var busy = false
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      Text(title).gl(fontSize, .semibold).foregroundStyle(.white).frame(maxWidth: .infinity)
        .frame(height: height)
        .background(background, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        .opacity(busy ? 0.6 : 1)
    }.buttonStyle(.plain).disabled(busy)
  }
}

struct ProfileSheetView: View {
  let sheet: ProfileSheet
  var body: some View {
    switch sheet {
    case .editName: ProfileEditNameSheet()
    case .perm: ProfilePermSheet()
    case .personas: ProfilePersonasSheet()
    case .delete: ProfileDeleteSheet()
    case .privacy: ProfilePrivacySheet()
    }
  }
}

private struct ProfileEditNameSheet: View {
  @Environment(DemoStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var error: String?
  @State private var busy = false
  var body: some View {
    GLSheet("Edit profil") {
      GLField("Nama tampilan") {
        TextField("", text: $name).gl(16).glInput()
          .onChange(of: name) { _, v in if v.count > 30 { name = String(v.prefix(30)) } }
      }
      Text("Nama baru terlihat di semua grup, chat, dan tugas.").gl(13).foregroundStyle(GLTheme.secondary)
      if let error { GLFormError(text: error) }
      GLSubmitButton(title: busy ? "Menyimpan…" : "Simpan", busy: busy) { save() }
    }
    .onAppear { name = store.currentUser?.name ?? "" }
  }
  private func save() {
    let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.count < 2 { error = "Nama minimal 2 karakter."; return }
    if value.count > 30 { error = "Nama maksimal 30 karakter."; return }
    busy = true
    Task {
      defer { busy = false }
      do {
        try await store.updateProfile(name: value)
        store.flash("Nama diperbarui di semua grup")
        dismiss()
      } catch { self.error = error.localizedDescription }
    }
  }
}

private struct ProfilePermSheet: View {
  @Environment(DemoStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @AppStorage("grouply.local.perm") private var perm = "off"
  @State private var simulate = false
  var body: some View {
    ProfileBareSheet(horizontal: 24, centered: true) {
      if !simulate {
        VStack(spacing: 14) {
          GLIcon("bell.badge", size: 36).frame(width: 72, height: 72)
            .background(GLTheme.lavender, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .padding(.top, 10)
          Text("Dapat kabar yang penting saja").gl(22, .bold, em: -0.02)
          Text(
            "Kami memberi tahu saat kamu ditugaskan, hasil kerjamu direview, ada komentar di tugasmu, atau deadline sudah dekat. Isi pesan tidak tampil di lock screen."
          ).gl(15).lineSpacing(4.5).foregroundStyle(GLTheme.secondary)
          ProfileFilledButton(title: "Lanjutkan", height: 56, radius: 20, fontSize: 17) {
            withAnimation(.easeOut(duration: 0.2)) { simulate = true }
          }.padding(.top, 6)
          Button { dismiss() } label: {
            Text("Nanti saja").gl(16, .semibold).frame(maxWidth: .infinity).frame(height: 48)
              .contentShape(Rectangle())
          }.buttonStyle(.plain)
        }
      } else {
        VStack(spacing: 12) {
          HStack(spacing: 5) {
            GLIcon("flask", size: 16)
            Text("SIMULASI PROTOTIPE").gl(12, .bold, em: 0.04)
          }
          .padding(.horizontal, 12).frame(height: 28).background(GLTheme.butter, in: Capsule())
          .padding(.top, 6)
          VStack(spacing: 8) {
            Text("Di sini aplikasi iOS akan menampilkan dialog izin sistem.").gl(16, .semibold)
            Text("Pilih hasil yang ingin disimulasikan.").gl(14).foregroundStyle(GLTheme.secondary)
          }
          .padding(18).frame(maxWidth: .infinity)
          .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
              .strokeBorder(Color(hex: "9AA0A6"), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
          HStack(spacing: 10) {
            GLOutlineButton(title: "Ditolak", height: 52, radius: 18) {
              perm = "denied"
              dismiss()
              store.flash("Izin ditolak. Kamu tetap bisa cek Beranda.", .info)
            }
            ProfileFilledButton(title: "Diizinkan", height: 52, fontSize: 15) {
              perm = "on"
              dismiss()
              store.flash("Notifikasi aktif")
            }
          }
        }.transition(.opacity)
      }
    }
  }
}

private struct ProfilePersonasSheet: View {
  @Environment(DemoStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    ProfileBareSheet {
      HStack(spacing: 8) {
        HStack(spacing: 8) {
          Text("DEMO").gl(11, .bold, em: 0.06).padding(.horizontal, 8).frame(height: 24)
            .background(GLTheme.butter, in: Capsule())
          Text("Ganti persona").gl(22, .bold, em: -0.02)
        }
        Spacer(minLength: 0)
        Button { dismiss() } label: {
          GLIcon("xmark", size: 22).frame(width: 44, height: 44)
            .background(Color(hex: "ECEEEB"), in: Circle())
        }.buttonStyle(.plain).accessibilityLabel("Tutup")
      }
      Text("Hanya untuk menguji sudut pandang tiap anggota. Semua persona memakai data yang sama.")
        .gl(14).lineSpacing(2.5).foregroundStyle(GLTheme.text3).padding(.top, -6)
      VStack(spacing: 8) {
        ForEach(profilePersonas, id: \.id) { persona in
          if let user = store.user(persona.id), !user.email.isEmpty {
            let on = store.currentUserID == persona.id
            Button {
              guard !on else { return }
              store.switchPersona(persona.id)
              dismiss()
              store.flash("Demo: sekarang melihat sebagai " + user.name, .info)
            } label: {
              HStack(spacing: 12) {
                GLAvatar(user: user, size: 40, fontSize: 13)
                VStack(alignment: .leading, spacing: 0) {
                  Text(user.name).gl(16, .semibold)
                  Text(persona.role).gl(13).foregroundStyle(GLTheme.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if on { Text("Aktif").gl(13, .bold) }
              }
              .padding(.vertical, 8).padding(.leading, 8).padding(.trailing, 14).frame(minHeight: 56)
              .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
              .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                  .strokeBorder(on ? GLTheme.ink : GLTheme.border, lineWidth: 1.5))
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
            .accessibilityIdentifier("switch-persona-\(persona.id)")
          }
        }
      }
    }
  }
}

private struct ProfileDeleteSheet: View {
  @Environment(DemoStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var step = 1
  @State private var text = ""
  @State private var error: String?
  @State private var busy = false
  /// Prototype rule: groups I coordinate that still have other members.
  private var blockers: [GLGroup] {
    store.myGroups.filter {
      $0.coordinatorID == store.currentUserID && (!store.isCloudMode || $0.memberIDs.count > 1)
    }
  }
  private var hasActiveAssignments: Bool {
    store.tasks.contains {
      $0.status != .done && ($0.assigneeID == store.currentUserID || $0.reviewerID == store.currentUserID)
    }
  }
  var body: some View {
    GLSheet("Hapus akun") {
      if step == 1 {
        VStack(alignment: .leading, spacing: 12) {
          VStack(alignment: .leading, spacing: 10) {
            line("trash", store.isCloudMode ? "Akun login dan profil di server akan dihapus permanen." : "Ini simulasi penghapusan akun demo, bukan akun server.")
            line(
              "clock.arrow.circlepath",
              "Hasil kerja dan pesanmu di grup tetap ada, ditampilkan sebagai “Pengguna terhapus”.")
            line("arrow.left.arrow.right", "Alihkan peran pelaksana/reviewer pada semua tugas yang belum selesai terlebih dahulu, termasuk di proyek arsip. Tidak ada pengalihan otomatis.")
            if store.isCloudMode {
              line("person.crop.circle.badge.minus", "Jika kamu satu-satunya anggota, grup kehilangan akses anggota dan undangannya dinonaktifkan. Riwayat kerja tetap disimpan tanpa identitas akunmu.")
            }
          }
          .padding(.vertical, 16).padding(.horizontal, 18).frame(maxWidth: .infinity, alignment: .leading)
          .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
          if !blockers.isEmpty {
            GLNotice(
              text: "Serahkan peran koordinator dulu di: "
                + blockers.map(\.name).joined(separator: ", ") + ".",
              icon: "person.badge.shield.checkmark")
          }
          if hasActiveAssignments {
            GLNotice(text: "Masih ada tugas yang belum selesai dengan kamu sebagai pelaksana atau reviewer. Minta koordinator membuka kembali proyek bila perlu, lalu alihkan tugasnya.", icon: "checklist")
          }
          if let error { GLFormError(text: error) }
          ProfileFilledButton(
            title: "Lanjutkan", background: blockers.isEmpty && !hasActiveAssignments ? GLTheme.ink : Color(hex: "B4B8BC")
          ) {
            if !blockers.isEmpty {
              error = "Serahkan peran koordinator dulu sebelum menghapus akun."
            } else if hasActiveAssignments {
              error = "Alihkan semua tugas aktif dan peran reviewer sebelum menghapus akun."
            } else {
              error = nil
              withAnimation(.easeOut(duration: 0.2)) { step = 2 }
            }
          }
        }
      } else {
        VStack(alignment: .leading, spacing: 12) {
          (Text("Ketik ") + Text("HAPUS").bold() + Text(" untuk konfirmasi.")).gl(15)
          TextField("", text: $text).gl(17, .semibold, em: 0.08)
            .textInputAutocapitalization(.characters).autocorrectionDisabled()
            .glInput(height: 52).accessibilityLabel("Ketik HAPUS")
          if !store.isCloudMode {
            ProfileDashedNote(
              text:
                "Simulasi: hanya data demo lokal yang berubah. Tidak ada data server yang dihapus. Pakai “Reset data demo” untuk mengembalikan."
            )
          }
          if let error { GLFormError(text: error) }
          ProfileFilledButton(
            title: busy ? "Menghapus…" : store.isCloudMode ? "Hapus akun" : "Hapus akun (simulasi)",
            background: GLTheme.danger, busy: busy
          ) { delete() }
          .accessibilityIdentifier("confirm-delete-account")
        }.transition(.opacity)
      }
    }
  }
  private func line(_ icon: String, _ text: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      GLIcon(icon, size: 20)
      Text(text).gl(15).lineSpacing(4.5).fixedSize(horizontal: false, vertical: true)
    }
  }
  private func delete() {
    guard text.trimmingCharacters(in: .whitespaces).uppercased() == "HAPUS" else {
      error = "Ketik HAPUS untuk konfirmasi."
      return
    }
    let cloud = store.isCloudMode
    busy = true
    Task {
      defer { busy = false }
      do {
        try await store.deleteAccount()
        dismiss()
        store.flash(
          cloud
            ? "Akun dihapus."
            : "Simulasi: akun dihapus dari data demo lokal. Tidak ada data server yang dihapus.", .info)
      } catch { self.error = error.localizedDescription }
    }
  }
}

/// Prototype `sheetPrivacy`; also opened from Welcome.
struct ProfilePrivacySheet: View {
  @Environment(DemoStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    ProfileBareSheet {
      Text("Privasi & data").gl(22, .bold, em: -0.02)
      VStack(alignment: .leading, spacing: 10) {
        Text("GROUPLY memakai nama dan identitas login untuk akunmu. Persona demo terpisah dari akun server.")
        Text("Proyek, tugas, dan pesan hanya terlihat oleh anggota grup terkait.")
        if store.isCloudMode {
          Text("Laporan dan isi pesan yang dilaporkan dapat ditinjau operator berwenang. Blokir menyembunyikan pesan untukmu, bukan mengeluarkan anggota atau menghentikan tugas bersama.")
          Text("Penghapusan akun menghapus identitas login dan profil. Pesan, hasil kerja, dan review bersama tetap disimpan tanpa identitas akun; hapus informasi pribadi dalam kontribusi sebelum membagikannya. Kebijakan retensi untuk rilis publik belum disahkan.")
        }
        // Prototype: "…di memori browser saja." — adapted for the native demo.
        Text(store.isCloudMode ? "Data akun ini tersimpan di Supabase. Sesi login disimpan aman di Keychain." : "Data demo disimpan di perangkat ini saja.").foregroundStyle(GLTheme.secondary)
      }
      .gl(15).lineSpacing(4.5)
      .padding(.vertical, 16).padding(.horizontal, 18).frame(maxWidth: .infinity, alignment: .leading)
      .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
      ProfileFilledButton(title: "Mengerti") { dismiss() }
    }
  }
}
