import SwiftUI

struct ProfileView: View {
  @Environment(DemoStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @AppStorage("grouply.local.deadline") private var deadline = true
  @AppStorage("grouply.local.review") private var review = true
  @AppStorage("grouply.local.chat") private var chat = false
  @State private var name = ""
  @State private var error: String?
  @State private var confirmation: String?
  var body: some View {
    @Bindable var store = store
    Form {
      if let persistenceError = store.persistenceError {
        Section {
          Label(persistenceError, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
        }
      }
      Section {
        HStack(spacing: 16) {
          GLAvatar(user: store.currentUser, size: 60)
          VStack(alignment: .leading, spacing: 4) {
            Text(store.currentUser?.name ?? "Tamu").font(.title2.bold())
            Text(store.currentUser?.email ?? "").font(.caption).foregroundStyle(GLTheme.secondary)
          }
        }.padding(.vertical, 8)
        TextField("Nama tampilan", text: $name)
        Button("Simpan nama") { perform { try store.updateProfile(name: name) } }
      } header: {
        Text("Profil")
      }
      Section {
        Toggle("Pengingat deadline", isOn: $deadline)
        Toggle("Review dan revisi", isOn: $review)
        Toggle("Pesan grup", isOn: $chat)
      } header: {
        Text("Contoh preferensi notifikasi")
      } footer: {
        Text(
          "Pengaturan contoh tersimpan lokal dan belum memicu pengingat. Notifikasi perangkat dan push server belum terhubung."
        )
      }
      Section("Akun diblokir") {
        if store.blockedUserIDs.isEmpty {
          Text("Belum ada akun diblokir").foregroundStyle(GLTheme.secondary)
        }
        ForEach(store.blockedUserIDs, id: \.self) { id in
          HStack {
            GLAvatar(user: store.user(id))
            Text(store.user(id)?.name ?? "Pengguna")
            Spacer()
            Button("Buka blokir") { store.unblockUser(id) }
          }
        }
      }
      Section {
        Picker(
          "Lihat sebagai",
          selection: Binding(
            get: { store.currentUserID ?? "u1" },
            set: {
              store.switchPersona($0)
              name = store.currentUser?.name ?? ""
            })
        ) {
          ForEach(store.users.filter { !$0.email.isEmpty }) { user in Text(user.name).tag(user.id) }
        }
        Toggle("Majukan waktu 8 hari", isOn: $store.advanceDemoTime)
        Toggle("Simulasi offline", isOn: $store.simulatedOffline)
        Toggle("Simulasi pesan gagal", isOn: $store.simulateSendFailure)
        Button("Reset semua data demo", role: .destructive) { confirmation = "reset" }
      } header: {
        Text("Panel demo lokal")
      } footer: {
        Text(
          "Persona dan data hanya untuk pengujian. Tidak ada sesi Apple, akun server, atau sinkronisasi antarperangkat."
        )
      }
      Section {
        Button("Keluar", role: .destructive) { confirmation = "signout" }
        Button("Hapus akun demo", role: .destructive) { confirmation = "delete" }
      } footer: {
        Text(
          "Penghapusan akun hanya memengaruhi data demo lokal. Selesaikan atau alihkan tanggung jawab aktif terlebih dahulu."
        )
      }
      Section {
        Text("GROUPLY · Native iOS demo\nSoft Future · Prototype v3.1").font(.caption)
          .foregroundStyle(GLTheme.secondary)
      }
    }.navigationTitle("Pengaturan")
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Selesai") { dismiss() } } }
      .onAppear { name = store.currentUser?.name ?? "" }
      .confirmationDialog(
        confirmation == "reset"
          ? "Reset data demo?"
          : confirmation == "delete" ? "Hapus akun demo?" : "Keluar dari GROUPLY?",
        isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }),
        titleVisibility: .visible
      ) {
        Button(
          confirmation == "reset" ? "Reset" : confirmation == "delete" ? "Hapus akun" : "Keluar",
          role: .destructive
        ) {
          let action = confirmation
          confirmation = nil
          perform {
            if action == "reset" {
              store.reset()
              name = store.currentUser?.name ?? ""
            } else if action == "delete" {
              try store.deleteAccount()
              dismiss()
            } else {
              store.signOut()
              dismiss()
            }
          }
        }
      } message: {
        Text(
          confirmation == "reset"
            ? "Semua perubahan demo akan kembali ke data awal."
            : confirmation == "delete"
              ? "Data identitas lokal akan dihapus. Riwayat bersama dapat tetap tersedia dengan identitas anonim."
              : "Kamu dapat masuk kembali melalui persona demo.")
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
