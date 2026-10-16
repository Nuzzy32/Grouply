import SwiftUI

enum GLTheme {
  static let background = Color(hex: "F8F9F7")
  static let ink = Color(hex: "202124")
  static let secondary = Color(hex: "62676B")
  static let muted = Color(hex: "F0F3F1")
  static let border = Color(hex: "E8E9E7")
  static let lavender = Color(hex: "DED2FF")
  static let mint = Color(hex: "C9F2D6")
  static let sky = Color(hex: "D8EAF4")
  static let butter = Color(hex: "F9E9BE")
  static let coral = Color(hex: "F6CED1")
}

extension Color {
  init(hex: String) {
    let value =
      UInt64(hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), radix: 16) ?? 0
    self.init(
      .sRGB, red: Double((value >> 16) & 255) / 255,
      green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
  }
}

extension View {
  func glCard(_ color: Color = .white) -> some View {
    padding(18).frame(maxWidth: .infinity, alignment: .leading)
      .background(color, in: RoundedRectangle(cornerRadius: 24))
  }
  func glScreen() -> some View {
    background(GLTheme.background).foregroundStyle(GLTheme.ink)
      .toolbarBackground(GLTheme.background, for: .navigationBar)
  }
}

struct GLCard<Content: View>: View {
  let content: Content
  init(@ViewBuilder content: () -> Content) { self.content = content() }
  var body: some View { content.glCard() }
}

struct GLPrimaryButton: View {
  let title: String
  var systemImage: String? = nil
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        if let systemImage { Image(systemName: systemImage) }
        Text(title).fontWeight(.semibold)
      }.frame(maxWidth: .infinity).frame(minHeight: 52)
    }.buttonStyle(GLButtonStyle())
  }
}

struct GLButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.foregroundStyle(.white)
      .background(GLTheme.ink.opacity(isEnabled ? 1 : 0.35), in: RoundedRectangle(cornerRadius: 18))
      .opacity(configuration.isPressed ? 0.72 : 1)
  }
}

struct GLAvatar: View {
  let user: GLUser?
  var size: CGFloat = 36
  var body: some View {
    Text(String(user?.name.prefix(2) ?? "??").uppercased())
      .font(.system(.caption, design: .rounded, weight: .bold))
      .frame(width: size, height: size)
      .background(Color(hex: user?.tint ?? "DED2FF"), in: Circle())
      .accessibilityLabel(user?.name ?? "Anggota")
  }
}

extension TaskStatus {
  var tint: Color {
    switch self {
    case .todo: return GLTheme.butter
    case .inProgress: return GLTheme.sky
    case .inReview: return GLTheme.lavender
    case .needsRevision: return GLTheme.coral
    case .done: return GLTheme.mint
    }
  }
}

struct GLStatusChip: View {
  let status: TaskStatus
  var body: some View {
    Label(status.label, systemImage: status.icon)
      .font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 7)
      .background(status.tint, in: Capsule()).fixedSize(horizontal: false, vertical: true)
  }
}

struct GLNotice: View {
  let text: String
  var color: Color = GLTheme.butter
  var body: some View {
    Label {
      Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
    } icon: {
      Image(systemName: "info.circle")
    }
    .glCard(color)
  }
}

struct GLEmptyState: View {
  let title: String
  let message: String
  let systemImage: String
  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: systemImage).font(.largeTitle).padding(18)
        .background(GLTheme.mint, in: RoundedRectangle(cornerRadius: 20))
      Text(title).font(.title3.bold())
      Text(message).font(.subheadline).foregroundStyle(GLTheme.secondary)
    }.multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(24).glCard()
  }
}

struct GLSectionHeading: View {
  let title: String
  var body: some View {
    Text(title).font(.title3.bold()).frame(maxWidth: .infinity, alignment: .leading)
  }
}

enum GLFormat {
  static func date(_ date: Date) -> String {
    date.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "id_ID")))
  }
  static func deadline(_ date: Date, now: Date = .now) -> String {
    let days =
      Calendar.current.dateComponents(
        [.day], from: Calendar.current.startOfDay(for: now),
        to: Calendar.current.startOfDay(for: date)
      ).day ?? 0
    if days == 0 { return "Hari ini" }
    if days == 1 { return "Besok" }
    return date < now ? "Terlambat · \(self.date(date))" : self.date(date)
  }
}
