import SwiftUI

// Values mirror the v3.1 prototype ("Grouply App.dc.html") one-to-one; pt == CSS px.
// Each token pairs the light value with its dark-mode value (docs/DARK_THEME.md).
enum GLTheme {
  static let background = Color(light: "F8F9F7", dark: "121314")
  static let surface = Color(light: "FFFFFF", dark: "1C1E20")
  /// Small floating controls (shadowed pills/circles) that must stand out from the screen.
  static let raised = Color(light: "FFFFFF", dark: "2E3134")
  static let ink = Color(light: "202124", dark: "ECEDEE")
  static let onInk = Color(light: "FFFFFF", dark: "1A1B1D")
  static let secondary = Color(light: "62676B", dark: "A3A8AD")
  static let text2 = Color(light: "4D5155", dark: "C2C6CA")
  static let text3 = Color(light: "3C4043", dark: "D5D8DB")
  static let muted = Color(light: "F0F3F1", dark: "222527")
  static let border = Color(light: "E8E9E7", dark: "2E3134")
  static let chip = Color(light: "ECEEEB", dark: "26292B")
  static let placeholder = Color(light: "9AA0A6", dark: "868C93")
  static let disabled = Color(light: "C4C7C5", dark: "4A4F53")
  static let faint = Color(light: "B4B8BC", dark: "5B6166")
  static let hairline = Color(light: "D5D8DB", dark: "3A3E42")
  static let tertiary = Color(light: "80868B", dark: "9AA0A6")
  static let lavender = Color(light: "DED2FF", dark: "3A3354")
  static let mint = Color(light: "C9F2D6", dark: "1F3D2B")
  static let sky = Color(light: "D8EAF4", dark: "1E3442")
  static let butter = Color(light: "F9E9BE", dark: "413720")
  static let coral = Color(light: "F6CED1", dark: "47282B")
  static let danger = Color(light: "A8231B", dark: "FF8A80")
  static let link = Color(light: "1F4F86", dark: "8AB4F8")
  // Floating tab bar: ink capsule in light mode, raised dark capsule in dark mode
  // (inverting ink would make it the brightest thing on screen).
  static let tabBar = Color(light: "202124", dark: "2A2D30")
  static let tabActive = Color(light: "FFFFFF", dark: "ECEDEE")
  static let tabActiveInk = Color(hex: "202124")
  static let tabInactive = Color(light: "FFFFFF", dark: "ECEDEE").opacity(0.78)
}

extension Color {
  init(hex: String) {
    let value =
      UInt64(hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted), radix: 16) ?? 0
    self.init(
      .sRGB, red: Double((value >> 16) & 255) / 255,
      green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
  }
  /// Data-driven pastel (user/group `tint`, status chips): the light value as stored, and in dark mode
  /// the matching dark pastel from docs/DARK_THEME.md, or a 28% mix into `surface` for any other hex.
  init(tint hex: String) {
    let key = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).uppercased()
    let known = ["DED2FF": "3A3354", "C9F2D6": "1F3D2B", "D8EAF4": "1E3442", "F9E9BE": "413720",
                 "F6CED1": "47282B", "ECEEEB": "26292B", "FFFFFF": "1C1E20"]
    if let dark = known[key] { self.init(light: key, dark: dark); return }
    let v = UInt64(key, radix: 16) ?? 0
    let mix = { (c: UInt64, base: Double) in String(format: "%02X", Int(Double(c & 255) * 0.28 + base * 0.72)) }
    self.init(light: key, dark: mix(v >> 16, 0x1C) + mix(v >> 8, 0x1E) + mix(v, 0x20))
  }
  /// Resolves per trait collection, so it follows the system appearance.
  init(light: String, dark: String) {
    self.init(
      UIColor { $0.userInterfaceStyle == .dark ? UIColor(Color(hex: dark)) : UIColor(Color(hex: light)) })
  }
}

/// Fixed prototype size at the default text size, still scaling with Dynamic Type.
private struct GLScaledFont: ViewModifier {
  @ScaledMetric private var size: CGFloat
  let weight: Font.Weight
  init(size: CGFloat, weight: Font.Weight) {
    _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    self.weight = weight
  }
  func body(content: Content) -> some View { content.font(.system(size: size, weight: weight)) }
}

extension View {
  /// `em` is CSS letter-spacing in em units.
  func gl(_ size: CGFloat, _ weight: Font.Weight = .regular, em: CGFloat = 0) -> some View {
    modifier(GLScaledFont(size: size, weight: weight)).tracking(size * em)
  }
  /// White surface used by the prototype's cards.
  func glSurface(_ radius: CGFloat = 24, _ color: Color = GLTheme.surface) -> some View {
    background {
      RoundedRectangle(cornerRadius: radius, style: .continuous).fill(color)
        .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
    }
  }
  func glCard(_ color: Color = GLTheme.surface) -> some View {
    padding(18).frame(maxWidth: .infinity, alignment: .leading)
      .background(color, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
  }
  func glScreen() -> some View {
    background(GLTheme.background).foregroundStyle(GLTheme.ink)
      .toolbarBackground(GLTheme.background, for: .navigationBar)
  }
}

/// SF Symbol sized like a Material Symbols glyph of the same CSS font-size.
struct GLIcon: View {
  let name: String
  var size: CGFloat = 20
  var weight: Font.Weight = .regular
  init(_ name: String, size: CGFloat = 20, weight: Font.Weight = .regular) {
    self.name = name
    self.size = size
    self.weight = weight
  }
  var body: some View {
    Image(systemName: name).font(.system(size: size * 0.78, weight: weight))
      .frame(width: size, height: size).accessibilityHidden(true)
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
        if let systemImage { GLIcon(systemImage, size: 22) }
        Text(title).gl(17, .semibold)
      }.frame(maxWidth: .infinity).frame(minHeight: 58)
    }.buttonStyle(GLButtonStyle())
  }
}

struct GLButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  var radius: CGFloat = 20
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.foregroundStyle(GLTheme.onInk)
      .background(
        GLTheme.ink.opacity(isEnabled ? 1 : 0.35),
        in: RoundedRectangle(cornerRadius: radius, style: .continuous)
      )
      .scaleEffect(configuration.isPressed ? 0.98 : 1)
  }
}

/// Opacity feedback the prototype uses on list rows (`style-active="opacity:.6"`).
struct GLRowButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.contentShape(Rectangle()).opacity(configuration.isPressed ? 0.6 : 1)
  }
}

/// Scale feedback the prototype uses on cards (`transform:scale(.98)`).
struct GLCardButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.contentShape(Rectangle()).scaleEffect(configuration.isPressed ? 0.98 : 1)
      .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
  }
}

struct GLAvatar: View {
  let user: GLUser?
  var size: CGFloat = 36
  var fontSize: CGFloat? = nil
  var body: some View {
    Text(String(user?.name.prefix(2) ?? "??").uppercased())
      .gl(fontSize ?? (size <= 32 ? 11 : size <= 40 ? 13 : 15), .bold)
      .frame(width: size, height: size)
      .background(Color(tint: user?.tint ?? "DED2FF"), in: Circle())
      .accessibilityLabel(user?.name ?? "Anggota")
  }
}

/// Pill used for status, role and info chips. `outlined` = inset 1.5px ink ring.
struct GLChip: View {
  let label: String
  var icon: String? = nil
  var background: Color = GLTheme.muted
  var foreground: Color = GLTheme.ink
  var outlined = false
  var height: CGFloat = 28
  var fontSize: CGFloat = 13
  var iconSize: CGFloat = 16
  var body: some View {
    HStack(spacing: icon == nil ? 0 : (height <= 24 ? 3 : 4)) {
      if let icon { GLIcon(icon, size: iconSize) }
      Text(label).gl(fontSize, .semibold).lineLimit(1)
    }
    .padding(.leading, icon == nil ? 10 : (height <= 24 ? 6 : 8))
    .padding(.trailing, icon == nil ? 10 : (height <= 24 ? 9 : 11))
    .frame(minHeight: height)
    .foregroundStyle(foreground)
    .background(background, in: Capsule())
    .overlay { if outlined { Capsule().strokeBorder(GLTheme.ink, lineWidth: 1.5) } }
  }
}

/// Dark rounded counter used in section headers.
struct GLCountBadge: View {
  let count: Int
  var size: CGFloat = 30
  var body: some View {
    Text("\(count)").gl(size >= 30 ? 14 : 12, .bold).foregroundStyle(GLTheme.onInk)
      .padding(.horizontal, size >= 30 ? 9 : 7).frame(minWidth: size, minHeight: size)
      .background(GLTheme.ink, in: Capsule())
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
  var large = false
  var body: some View {
    GLChip(
      label: status.label, icon: status.icon, background: status.tint, height: large ? 30 : 28)
  }
}

struct GLNotice: View {
  let text: String
  var color: Color = GLTheme.butter
  var icon = "info.circle"
  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      GLIcon(icon, size: 20)
      Text(text).gl(14).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
    }
    .padding(.vertical, 12).padding(.horizontal, 14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(color, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
}

/// Centered empty state card (white, radius 28).
struct GLEmptyState: View {
  let title: String
  let message: String
  let systemImage: String
  var tint: Color = GLTheme.mint
  var body: some View {
    VStack(spacing: 10) {
      GLIcon(systemImage, size: 28).frame(width: 56, height: 56)
        .background(tint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
      Text(title).gl(19, .bold)
      Text(message).gl(15).lineSpacing(4).foregroundStyle(GLTheme.secondary)
    }.multilineTextAlignment(.center).frame(maxWidth: .infinity)
      .padding(.vertical, 28).padding(.horizontal, 22)
      .background(GLTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
  }
}

/// Section title (21/700) with an optional trailing "… >" link.
struct GLSectionHeading: View {
  let title: String
  var actionTitle: String? = nil
  var action: (() -> Void)? = nil
  var body: some View {
    HStack(spacing: 8) {
      Text(title).gl(21, .bold, em: -0.02)
      Spacer(minLength: 0)
      if let actionTitle, let action {
        Button(action: action) {
          HStack(spacing: 2) {
            Text(actionTitle).gl(15, .semibold)
            GLIcon("chevron.right", size: 20, weight: .semibold)
          }.padding(.leading, 12).padding(.trailing, 4).frame(height: 44)
        }.buttonStyle(.plain)
      }
    }
  }
}

enum GLFormat {
  static let months = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"]
  static let weekdays = ["Min", "Sen", "Sel", "Rab", "Kam", "Jum", "Sab"]
  private static var cal: Calendar { Calendar.current }
  /// "16 Okt"
  static func date(_ date: Date) -> String {
    "\(cal.component(.day, from: date)) \(months[cal.component(.month, from: date) - 1])"
  }
  /// "Sab"
  static func weekday(_ date: Date) -> String { weekdays[cal.component(.weekday, from: date) - 1] }
  /// "19:02"
  static func time(_ date: Date) -> String {
    String(format: "%02d:%02d", cal.component(.hour, from: date), cal.component(.minute, from: date))
  }
  private static func dayOffset(_ date: Date, from now: Date) -> Int {
    cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
  }
  static func isOverdue(_ date: Date, status: TaskStatus, now: Date) -> Bool {
    status != .done && date < now
  }
  /// Matches the prototype's `dueInfo` label.
  static func due(_ date: Date, status: TaskStatus, now: Date) -> String {
    if isOverdue(date, status: status, now: now) { return "Terlambat · " + self.date(date) }
    let n = dayOffset(date, from: now)
    if n == 0 { return "Hari ini, " + time(date) }
    if n == 1 { return "Besok, " + time(date) }
    if n < 7 { return weekday(date) + ", " + time(date) }
    return self.date(date)
  }
  static func isSoon(_ date: Date, status: TaskStatus, now: Date) -> Bool {
    !isOverdue(date, status: status, now: now) && dayOffset(date, from: now) <= 2 && status != .done
  }
  /// "19:02" today, "Kemarin", otherwise "14 Okt" (chat list preview).
  static func chatStamp(_ date: Date, now: Date) -> String {
    switch dayOffset(date, from: now) {
    case 0: return time(date)
    case -1: return "Kemarin"
    default: return self.date(date)
    }
  }
  static func deadline(_ date: Date, now: Date = .now) -> String {
    due(date, status: .todo, now: now)
  }
}

extension GLFormat {
  /// Activity time: "08:40" today, "Kemarin", otherwise "Sel, 13 Okt".
  static func activityStamp(_ date: Date, now: Date) -> String {
    let n =
      Calendar.current.dateComponents(
        [.day], from: Calendar.current.startOfDay(for: now),
        to: Calendar.current.startOfDay(for: date)
      ).day ?? 0
    if n == 0 { return time(date) }
    if n == -1 { return "Kemarin" }
    return weekday(date) + ", " + self.date(date)
  }
}

// MARK: - Detail screens

/// Custom detail header: 44pt white back circle, centered 17/600 title, optional trailing.
struct GLDetailHeader<Trailing: View>: View {
  let title: String
  @ViewBuilder var trailing: Trailing
  @Environment(\.dismiss) private var dismiss
  init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
    self.title = title
    self.trailing = trailing()
  }
  var body: some View {
    HStack {
      GLCircleButton(icon: "arrow.left", label: "Kembali", iconSize: 24) { dismiss() }
      Spacer(minLength: 8)
      Text(title).gl(17, .semibold).lineLimit(1)
      Spacer(minLength: 8)
      ZStack { Color.clear.frame(width: 44, height: 44); trailing }
    }
  }
}

/// 44pt white circular icon button with the prototype's hairline shadow.
struct GLCircleButton: View {
  let icon: String
  let label: String
  var iconSize: CGFloat = 22
  var background: Color = GLTheme.surface
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      GLIcon(icon, size: iconSize).frame(width: 44, height: 44)
        .background {
          Circle().fill(background).shadow(color: .black.opacity(0.06), radius: 1, y: 1)
        }
    }.buttonStyle(.plain).accessibilityLabel(label)
  }
}

extension View {
  /// Detail screens draw their own header; keep the system bar hidden but swipe-back alive.
  func glDetailScreen() -> some View {
    glScreen().toolbar(.hidden, for: .navigationBar)
  }
}

/// Re-enables the interactive pop gesture while the navigation bar is hidden.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
  override open func viewDidLoad() {
    super.viewDidLoad()
    interactivePopGestureRecognizer?.delegate = self
  }
  public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    viewControllers.count > 1
  }
}

// MARK: - Bottom sheets

/// Prototype bottom sheet: #F8F9F7, 32pt top corners, 38×5 handle, 22/700 title + close button,
/// 16pt gaps, 20pt side padding. Height fits its content.
struct GLSheet<Content: View>: View {
  let title: String
  var subtitle: String? = nil
  @ViewBuilder var content: Content
  @Environment(\.dismiss) private var dismiss
  @State private var height: CGFloat = 400
  init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
    self.title = title
    self.subtitle = subtitle
    self.content = content()
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Capsule().fill(GLTheme.disabled).frame(width: 38, height: 5)
          .frame(maxWidth: .infinity)
        HStack(spacing: 8) {
          Text(title).gl(22, .bold, em: -0.02)
          Spacer(minLength: 0)
          Button { dismiss() } label: {
            GLIcon("xmark", size: 22).frame(width: 44, height: 44)
              .background(GLTheme.chip, in: Circle())
          }.buttonStyle(.plain).accessibilityLabel("Tutup")
        }
        if let subtitle {
          Text(subtitle).gl(15).lineSpacing(3).foregroundStyle(GLTheme.text3).padding(.top, -8)
        }
        content
      }
      .padding(.top, 10).padding(.horizontal, 20).padding(.bottom, 34)
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

/// Labeled field: 14/600 label (+ red asterisk), white 16pt-radius box with E8E9E7 border.
struct GLField<Field: View>: View {
  let label: String
  var required = false
  var trailing: String? = nil
  @ViewBuilder var field: Field
  init(
    _ label: String, required: Bool = false, trailing: String? = nil,
    @ViewBuilder field: () -> Field
  ) {
    self.label = label
    self.required = required
    self.trailing = trailing
    self.field = field()
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        (Text(label) + Text(required ? " *" : "").foregroundColor(GLTheme.danger)).gl(14, .semibold)
        Spacer(minLength: 0)
        if let trailing { Text(trailing).gl(13).foregroundStyle(GLTheme.secondary) }
      }
      field
    }
  }
}

extension View {
  /// Input box styling (`height:50px;border-radius:16px;border:1px solid #E8E9E7`).
  func glInput(height: CGFloat? = 50, radius: CGFloat = 16) -> some View {
    padding(.horizontal, 16).padding(.vertical, height == nil ? 14 : 0)
      .frame(minHeight: height, alignment: .leading)
      .background(GLTheme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(GLTheme.border))
  }
}

/// Inline form error (coral, 16pt radius, 14/500).
struct GLFormError: View {
  let text: String
  var body: some View {
    HStack(spacing: 8) {
      GLIcon("exclamationmark.circle", size: 18)
      Text(text).gl(14, .medium).fixedSize(horizontal: false, vertical: true)
    }
    .padding(.vertical, 12).padding(.horizontal, 14).frame(maxWidth: .infinity, alignment: .leading)
    .background(GLTheme.coral, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .accessibilityElement(children: .combine)
  }
}

/// Sheet submit button: 56pt, radius 20, 17/600, spinner while busy.
struct GLSubmitButton: View {
  let title: String
  var busy = false
  var background: Color = GLTheme.ink
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        if busy { ProgressView().tint(GLTheme.onInk) }
        Text(title).gl(17, .semibold)
      }.frame(maxWidth: .infinity).frame(height: 56).foregroundStyle(GLTheme.onInk)
        .background(background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .opacity(busy ? 0.6 : 1)
    }.buttonStyle(.plain).disabled(busy)
  }
}

/// Outlined button (`border:1.5px solid #202124`).
struct GLOutlineButton: View {
  let title: String
  var icon: String? = nil
  var height: CGFloat = 48
  var radius: CGFloat = 16
  var fontSize: CGFloat = 15
  let action: () -> Void
  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        if let icon { GLIcon(icon, size: 19) }
        Text(title).gl(fontSize, .semibold)
      }.frame(maxWidth: .infinity).frame(height: height)
        .overlay(
          RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(
            GLTheme.ink, lineWidth: 1.5)
        ).contentShape(Rectangle())
    }.buttonStyle(.plain)
  }
}

// MARK: - Confirm dialog & toast

struct GLConfirmation: Identifiable {
  let id = UUID()
  var title: String
  var text: String
  var ok: String
  var destructive = false
  /// Info dialogs have a single button.
  var info = false
  var run: () -> Void = {}
}

extension View {
  /// Prototype confirm dialog: dimmed backdrop, white 28pt card, Batal + action buttons.
  func glConfirm(_ item: Binding<GLConfirmation?>) -> some View {
    overlay {
      if let c = item.wrappedValue {
        ZStack {
          Color(red: 20 / 255, green: 22 / 255, blue: 24 / 255).opacity(0.4).ignoresSafeArea()
            .onTapGesture { item.wrappedValue = nil }
          VStack(alignment: .leading, spacing: 12) {
            Text(c.title).gl(19, .bold, em: -0.01)
            Text(c.text).gl(15).lineSpacing(4).foregroundStyle(GLTheme.text3)
            HStack(spacing: 10) {
              if !c.info {
                Button { item.wrappedValue = nil } label: {
                  Text("Batal").gl(15, .semibold).frame(maxWidth: .infinity).frame(height: 50)
                    .background(GLTheme.chip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }.buttonStyle(.plain)
              }
              Button {
                item.wrappedValue = nil
                c.run()
              } label: {
                Text(c.ok).gl(15, .semibold).foregroundStyle(GLTheme.onInk).frame(maxWidth: .infinity)
                  .frame(height: 50)
                  .background(
                    c.destructive ? GLTheme.danger : GLTheme.ink,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
              }.buttonStyle(.plain)
            }.padding(.top, 6)
          }
          .foregroundStyle(GLTheme.ink).padding(22).frame(maxWidth: 340, alignment: .leading)
          .background(GLTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
          .padding(28).accessibilityAddTraits(.isModal)
        }.transition(.opacity)
      }
    }.animation(.easeOut(duration: 0.15), value: item.wrappedValue?.id)
  }
}

enum GLToastKind { case ok, info, err }

struct GLToastView: View {
  let text: String
  let kind: GLToastKind
  var body: some View {
    HStack(spacing: 8) {
      GLIcon(
        kind == .err ? "exclamationmark.circle" : kind == .info ? "info.circle" : "checkmark.circle",
        size: 19
      ).foregroundStyle(kind == .err ? GLTheme.coral : kind == .info ? GLTheme.sky : GLTheme.mint)
      Text(text).gl(14, .medium).lineSpacing(2)
    }
    .foregroundStyle(GLTheme.onInk).padding(.vertical, 12).padding(.horizontal, 16)
    .background(GLTheme.ink, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .shadow(color: .black.opacity(0.4), radius: 15, y: 12)
    .padding(.horizontal, 16).accessibilityAddTraits(.updatesFrequently)
  }
}

/// Prototype `isDenied` screen (lost access to a group/project/task).
struct GLAccessDenied: View {
  var text =
    "Konten ini milik grup yang tidak kamu ikuti, atau sudah dihapus. Minta kode undangan ke koordinatornya untuk bergabung."
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        GLCircleButton(icon: "arrow.left", label: "Kembali", iconSize: 24) { dismiss() }
        VStack(spacing: 10) {
          GLIcon("lock", size: 30).frame(width: 60, height: 60)
            .background(GLTheme.coral, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
          Text("Kamu tidak punya akses").gl(19, .bold)
          Text(text).gl(15).lineSpacing(4).foregroundStyle(GLTheme.secondary)
        }.multilineTextAlignment(.center).frame(maxWidth: .infinity)
          .padding(.vertical, 28).padding(.horizontal, 22)
          .background(GLTheme.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
      }.padding(.horizontal, 20).padding(.top, 10)
    }.glDetailScreen()
  }
}
