import AuthenticationServices
import SwiftUI

struct BackendLoginView: View {
  @Environment(DemoStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme
  @State private var email = ""
  @State private var password = ""
  @State private var nonce: AppleSignInNonce?
  @State private var error: String?
  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text("Kerja bareng, di akunmu sendiri.").font(.title2.bold())
          Text("Data grup dan tugas disimpan di Supabase. Akun ini terpisah dari persona demo.")
            .font(.subheadline).foregroundStyle(GLTheme.secondary)
        }
        if store.backendConfigured {
          Section {
            SignInWithAppleButton(.signIn) { request in
              do {
                let value = try AppleSignInNonce()
                nonce = value
                request.nonce = value.hashed
                request.requestedScopes = [.fullName, .email]
              } catch { self.error = error.localizedDescription }
            } onCompletion: { result in
              Task {
                defer { nonce = nil }
                do {
                  guard
                    let credential = try result.get().credential
                      as? ASAuthorizationAppleIDCredential,
                    let token = credential.identityToken,
                    let idToken = String(data: token, encoding: .utf8), let nonce
                  else {
                    throw DemoError(message: "Identitas Apple belum tersedia. Coba lagi.")
                  }
                  let name = credential.fullName.map {
                    PersonNameComponentsFormatter().string(from: $0)
                  }
                  try await store.connectApple(idToken: idToken, nonce: nonce.raw, fullName: name)
                  dismiss()
                } catch let authError as ASAuthorizationError where authError.code == .canceled {
                } catch { self.error = error.localizedDescription }
              }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black).frame(height: 54)
            Text(
              "Memerlukan capability Sign in with Apple dan provider Apple yang dikonfigurasi pada proyek Supabase."
            )
            .font(.caption).foregroundStyle(GLTheme.secondary)
          }
          #if DEBUG
            Section {
              TextField("Email akun pengujian", text: $email).keyboardType(.emailAddress)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("backend-email")
              SecureField("Kata sandi", text: $password).accessibilityIdentifier("backend-password")
              GLPrimaryButton(title: "Masuk ke Server", systemImage: "arrow.right") {
                Task {
                  do {
                    try await store.connectBackend(email: email, password: password)
                    password = ""
                    dismiss()
                  } catch { self.error = error.localizedDescription }
                }
              }.disabled(email.isEmpty || password.isEmpty).accessibilityIdentifier(
                "backend-signin")
            } header: {
              Text("Akun pengujian · Debug")
            } footer: {
              Text(
                "Untuk uji dua akun lokal. Ini memakai Supabase Auth sungguhan, bukan pergantian persona. Jalankan scripts/backend_local.py untuk menyiapkan akun lokal."
              )
            }
          #endif
        } else {
          Section {
            GLNotice(
              text:
                "Konfigurasi server belum tersedia. Ikuti docs/BACKEND_SETUP.md, lalu build ulang aplikasinya."
            )
          }
        }
        if let error {
          Section {
            Text(error).foregroundStyle(.red).accessibilityIdentifier("backend-login-error")
          }
        }
      }
      .scrollContentBackground(.hidden).glScreen().navigationTitle("Masuk Akun")
      .navigationBarTitleDisplayMode(.inline)
      .disabled(store.isBusy)
      .overlay {
        if store.isBusy {
          ProgressView("Menghubungkan akun…").padding(20).background(
            .regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
      }
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Batal") { dismiss() }.disabled(store.isBusy)
        }
      }
      .interactiveDismissDisabled(store.isBusy)
    }
  }
}
