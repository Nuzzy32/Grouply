// Flutter port of Grouply/Core/DesignSystem.swift. Values mirror the SwiftUI
// implementation one-to-one (pt == logical px) so both clients look the same.
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/store.dart';
import '../theme.dart';

export '../theme.dart';

/// `Color(hex:)` — accepts "#DED2FF" or "DED2FF".
Color glTint(String? hex, [Color? fallback]) {
  final value = int.tryParse((hex ?? '').replaceAll('#', ''), radix: 16);
  if (value == null) return fallback ?? GLTheme.lavender;
  if (!GLTheme.dark) return Color(0xFF000000 | value);
  const mapped = <int, int>{
    0xDED2FF: 0x3A3354,
    0xC9F2D6: 0x1F3D2B,
    0xD8EAF4: 0x1E3442,
    0xF9E9BE: 0x413720,
    0xF6CED1: 0x47282B,
    0xECEEEB: 0x26292B,
    0xFFFFFF: 0x1C1E20,
  };
  final direct = mapped[value];
  if (direct != null) return Color(0xFF000000 | direct);
  // 28% of the stored hex over the dark surface 1C1E20, per channel (as Swift `Color(tint:)`).
  int mix(int channel, int base) => (channel * 0.28 + base * 0.72).floor();
  return Color.fromARGB(
    255,
    mix((value >> 16) & 0xFF, 0x1C),
    mix((value >> 8) & 0xFF, 0x1E),
    mix(value & 0xFF, 0x20),
  );
}

/// SwiftUI renders SF with Display optics from ~19pt and applies Apple's size-specific
/// tracking; Flutter does neither, so mirror both (HIG tracking table, pt).
final _tracking = <int, double>{
  // SF Pro Text
  11: 0.06, 12: 0, 13: -0.08, 14: -0.15, 15: -0.23, 16: -0.31, 17: -0.43,
  18: -0.44,
  // SF Pro Display
  19: 0.38, 20: 0.38, 22: 0.35, 28: 0.38, 34: 0.40,
};

double _sfTracking(double size) {
  final keys = _tracking.keys.toList();
  if (size <= keys.first) return _tracking[keys.first]!;
  if (size >= keys.last) return _tracking[keys.last]!;
  final hi = keys.firstWhere((k) => k >= size);
  final lo = keys.lastWhere((k) => k <= size);
  if (hi == lo) return _tracking[lo]!;
  final t = (size - lo) / (hi - lo);
  return _tracking[lo]! + (_tracking[hi]! - _tracking[lo]!) * t;
}

/// `.gl(size, weight, em:)` — SwiftUI `lineSpacing` is extra space between lines.
TextStyle gl(
  double size, [
  FontWeight weight = FontWeight.w400,
  double em = 0,
  Color? color,
  double lineSpacing = 0,
]) => TextStyle(
  // Resolves to SF on iOS; other platforms fall back to their system font.
  fontFamily: size >= 19 ? 'CupertinoSystemDisplay' : 'CupertinoSystemText',
  fontSize: size,
  fontWeight: weight,
  letterSpacing: size * em + _sfTracking(size),
  color: color,
  // SF line height is ~1.19×size in SwiftUI; Flutter's default metrics are taller.
  height: (size * 1.19 + lineSpacing) / size,
  leadingDistribution: TextLeadingDistribution.even,
);
const w400 = FontWeight.w400;
const w500 = FontWeight.w500;
const w600 = FontWeight.w600;
const w700 = FontWeight.w700;
const w800 = FontWeight.w800;

// SF Symbol name → glyph. Cupertino icons are the SF-style set; Material fills gaps.
final _symbols = <String, IconData>{
  'archivebox': CupertinoIcons.archivebox,
  'arrow.clockwise': CupertinoIcons.arrow_clockwise,
  'arrow.counterclockwise': CupertinoIcons.arrow_counterclockwise,
  'arrow.left': CupertinoIcons.arrow_left,
  'arrow.left.arrow.right': CupertinoIcons.arrow_right_arrow_left,
  'arrow.right': CupertinoIcons.arrow_right,
  'arrow.up': CupertinoIcons.arrow_up,
  'arrow.up.right.square': CupertinoIcons.arrow_up_right_square,
  'arrow.uturn.backward': CupertinoIcons.arrow_uturn_left,
  'arrow.triangle.2.circlepath': CupertinoIcons.arrow_2_circlepath,
  'bell': CupertinoIcons.bell,
  'bell.badge': CupertinoIcons.bell,
  'bolt': CupertinoIcons.bolt,
  'bubble.left': CupertinoIcons.bubble_left,
  'bubble.left.fill': CupertinoIcons.bubble_left_fill,
  'bubble.left.and.bubble.right': CupertinoIcons.bubble_left_bubble_right,
  'calendar': CupertinoIcons.calendar,
  'chart.xyaxis.line': CupertinoIcons.graph_square,
  'chart.bar': CupertinoIcons.chart_bar,
  'checklist': CupertinoIcons.square_list,
  'checkmark': CupertinoIcons.checkmark,
  'checkmark.circle': CupertinoIcons.checkmark_circle,
  'checkmark.circle.fill': CupertinoIcons.checkmark_circle_fill,
  'checkmark.shield': CupertinoIcons.checkmark_shield,
  'chevron.backward': CupertinoIcons.chevron_back,
  'chevron.right': CupertinoIcons.chevron_right,
  'circle': CupertinoIcons.circle,
  'circle.grid.2x2': CupertinoIcons.square_grid_2x2,
  'clock': CupertinoIcons.clock,
  'clock.arrow.circlepath': CupertinoIcons.clock,
  'clock.badge.xmark': Icons.timer_off_outlined,
  'cylinder.split.1x2': Icons.storage_outlined,
  'doc.on.doc': CupertinoIcons.doc_on_doc,
  'ellipsis': CupertinoIcons.ellipsis,
  'exclamationmark.circle': CupertinoIcons.exclamationmark_circle,
  'exclamationmark.triangle': CupertinoIcons.exclamationmark_triangle,
  'externaldrive.connected.to.line.below': CupertinoIcons.cloud,
  'eye': CupertinoIcons.eye,
  'eye.slash': CupertinoIcons.eye_slash,
  'flag': CupertinoIcons.flag,
  'flask': CupertinoIcons.lab_flask,
  'folder': CupertinoIcons.folder,
  'gearshape': CupertinoIcons.gear_alt,
  'hand.wave': CupertinoIcons.hand_raised,
  'house': CupertinoIcons.house,
  'house.fill': CupertinoIcons.house_fill,
  'hourglass': CupertinoIcons.hourglass,
  'icloud.slash': CupertinoIcons.wifi_slash,
  'info.circle': CupertinoIcons.info_circle,
  'iphone': CupertinoIcons.device_phone_portrait,
  'key': Icons.key_outlined,
  'largecircle.fill.circle': CupertinoIcons.smallcircle_fill_circle,
  'link': CupertinoIcons.link,
  'list.bullet.clipboard': CupertinoIcons.doc_on_clipboard,
  'lock': CupertinoIcons.lock,
  'magnifyingglass': CupertinoIcons.search,
  'nosign': CupertinoIcons.nosign,
  'pencil': CupertinoIcons.pencil,
  'person.2': CupertinoIcons.person_2,
  'person.2.fill': CupertinoIcons.person_2_fill,
  'person.3': CupertinoIcons.person_3,
  'person.3.fill': CupertinoIcons.person_3_fill,
  'person.badge.minus': CupertinoIcons.person_badge_minus,
  'person.badge.plus': CupertinoIcons.person_badge_plus,
  'person.badge.shield.checkmark':
      CupertinoIcons.person_crop_circle_badge_checkmark,
  'person.crop.circle.badge.minus':
      CupertinoIcons.person_crop_circle_badge_minus,
  'play.fill': CupertinoIcons.play_fill,
  'plus': CupertinoIcons.plus,
  'qrcode': CupertinoIcons.qrcode,
  'rectangle.portrait.and.arrow.right': CupertinoIcons.square_arrow_right,
  'square.and.arrow.up': CupertinoIcons.square_arrow_up,
  'square.and.pencil': CupertinoIcons.square_pencil,
  'trash': CupertinoIcons.trash,
  'tray.and.arrow.up': CupertinoIcons.tray_arrow_up,
  'wifi.slash': CupertinoIcons.wifi_slash,
  'xmark': CupertinoIcons.xmark,
};

// Cupertino draws these glyphs smaller than the SF Symbols they stand in for.
final _wide = {
  'person.2': 1.15,
  'person.2.fill': 1.15,
  'person.3': 1.35,
  'person.3.fill': 1.35,
};

IconData glSymbol(String name) =>
    _symbols[name] ??
    _symbols[name.replaceAll('.fill', '')] ??
    CupertinoIcons.circle;

/// `GLIcon` — SF Symbol drawn at 78% of its box, like the Swift version.
class GLIcon extends StatelessWidget {
  const GLIcon(this.name, {super.key, this.size = 20, this.color});
  final String name;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Icon(
          glSymbol(name),
          size: size * 0.78 * (_wide[name] ?? 1),
          color: color,
        ),
      ),
    ),
  );
}

/// Squircle-ish rounded rect, like `RoundedRectangle(style: .continuous)`.
ShapeBorder glShape(double radius) =>
    RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(radius));

/// `.background(color, in: RoundedRectangle(cornerRadius:))` (+ optional hairline shadow).
ShapeDecoration glBox(
  Color color,
  double radius, {
  bool shadow = false,
  Color? border,
  double borderWidth = 1,
}) => ShapeDecoration(
  color: color,
  shape: border == null
      ? glShape(radius)
      : RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: border, width: borderWidth),
        ),
  shadows: shadow
      ? [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ]
      : null,
);

/// `.glSurface(radius)` — white card with hairline shadow.
class GLSurface extends StatelessWidget {
  const GLSurface({
    super.key,
    required this.child,
    this.radius = 24,
    this.color,
    this.padding = EdgeInsets.zero,
  });
  final Widget child;
  final double radius;
  final Color? color;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: glBox(color ?? GLTheme.surface, radius, shadow: true),
    child: child,
  );
}

/// `.glCard(color)` — 18pt padding, radius 24, full width.
class GLCard extends StatelessWidget {
  const GLCard({super.key, required this.child, this.color});
  final Widget child;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.all(18),
    decoration: glBox(color ?? GLTheme.surface, 24),
    child: child,
  );
}

/// Press feedback without Material ripples: `GLRowButtonStyle` (opacity .6)
/// or `GLCardButtonStyle` (scale .98).
class GLTap extends StatefulWidget {
  const GLTap({
    super.key,
    required this.child,
    required this.onTap,
    this.scale = false,
    this.label,
  });
  const GLTap.card({
    super.key,
    required this.child,
    required this.onTap,
    this.label,
  }) : scale = true;
  final Widget child;
  final VoidCallback? onTap;
  final bool scale;
  final String? label;
  @override
  State<GLTap> createState() => _GLTapState();
}

class _GLTapState extends State<GLTap> {
  bool _down = false;
  void _set(bool value) {
    if (widget.onTap != null && value != _down) setState(() => _down = value);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: widget.onTap != null,
    label: widget.label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: widget.scale
          ? AnimatedScale(
              scale: _down ? 0.98 : 1,
              duration: Duration(milliseconds: 150),
              curve: Curves.easeOut,
              child: widget.child,
            )
          : Opacity(opacity: _down ? 0.6 : 1, child: widget.child),
    ),
  );
}

/// `GLButtonStyle` — ink fill, white label, scale .98 on press, 35% when disabled.
class GLInkButton extends StatelessWidget {
  const GLInkButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.radius = 20,
    this.height = 58,
    this.color,
  });
  final Widget child;
  final VoidCallback? onPressed;
  final double radius;
  final double height;
  final Color? color;
  @override
  Widget build(BuildContext context) => GLTap.card(
    onTap: onPressed,
    child: Container(
      constraints: BoxConstraints(minHeight: height),
      alignment: Alignment.center,
      decoration: glBox(
        onPressed == null
            ? (color ?? GLTheme.ink).withValues(alpha: 0.35)
            : (color ?? GLTheme.ink),
        radius,
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: GLTheme.onInk),
        child: IconTheme.merge(
          data: IconThemeData(color: GLTheme.onInk),
          child: child,
        ),
      ),
    ),
  );
}

/// `GLPrimaryButton` — 58pt ink button with optional icon.
class GLPrimaryButton extends StatelessWidget {
  const GLPrimaryButton({
    super.key,
    required this.title,
    required this.onPressed,
    this.icon,
  });
  final String title;
  final String? icon;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => GLInkButton(
    onPressed: onPressed,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[GLIcon(icon!, size: 22), SizedBox(width: 8)],
        Text(title, style: gl(17, w600)),
      ],
    ),
  );
}

String glInitials(String? name) {
  final value = (name ?? '??').characters.take(2).toString().toUpperCase();
  return value.isEmpty ? '??' : value;
}

/// `GLAvatar` — two-letter initials on the user's tint.
class GLAvatar extends StatelessWidget {
  const GLAvatar({
    super.key,
    required this.user,
    this.size = 36,
    this.fontSize,
  });
  final JsonMap? user;
  final double size;
  final double? fontSize;
  @override
  Widget build(BuildContext context) => Semantics(
    label: user?.text('name') ?? 'Anggota',
    child: ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: glTint(user?.text('tint')),
          shape: BoxShape.circle,
        ),
        child: Text(
          glInitials(user?.text('name')),
          textScaler: TextScaler.noScaling,
          style: gl(
            fontSize ?? (size <= 32 ? 11 : (size <= 40 ? 13 : 15)),
            w700,
            0,
            GLTheme.ink,
          ),
        ),
      ),
    ),
  );
}

/// `GLChip` — pill for status/role/info. `outlined` = 1.5pt ink ring.
class GLChip extends StatelessWidget {
  const GLChip({
    super.key,
    required this.label,
    this.icon,
    this.background,
    this.foreground,
    this.outlined = false,
    this.height = 28,
    this.fontSize = 13,
    this.iconSize = 16,
  });
  final String label;
  final String? icon;
  final Color? background;
  final Color? foreground;
  final bool outlined;
  final double height;
  final double fontSize;
  final double iconSize;
  @override
  Widget build(BuildContext context) {
    final small = height <= 24;
    return Container(
      constraints: BoxConstraints(minHeight: height),
      padding: EdgeInsets.only(
        left: icon == null ? 10 : (small ? 6 : 8),
        right: icon == null ? 10 : (small ? 9 : 11),
      ),
      decoration: ShapeDecoration(
        color: background,
        shape: StadiumBorder(
          side: outlined
              ? BorderSide(color: GLTheme.ink, width: 1.5)
              : BorderSide.none,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            GLIcon(icon!, size: iconSize, color: foreground),
            SizedBox(width: small ? 3 : 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: gl(fontSize, w600, 0, foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// `GLCountBadge` — dark counter in section headers.
class GLCountBadge extends StatelessWidget {
  const GLCountBadge({super.key, required this.count, this.size = 30});
  final int count;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(minWidth: size, minHeight: size),
    padding: EdgeInsets.symmetric(horizontal: size >= 30 ? 9 : 7),
    alignment: Alignment.center,
    decoration: ShapeDecoration(color: GLTheme.ink, shape: StadiumBorder()),
    child: Text(
      '$count',
      style: gl(size >= 30 ? 14 : 12, w700, 0, GLTheme.onInk),
    ),
  );
}

/// `TaskStatus` label / icon / tint, keyed by the raw status string.
abstract final class GLStatus {
  static final all = [
    'todo',
    'in_progress',
    'in_review',
    'needs_revision',
    'done',
  ];
  static String label(String status) => switch (status) {
    'todo' => 'Belum dimulai',
    'in_progress' => 'Sedang dikerjakan',
    'in_review' => 'Menunggu review',
    'needs_revision' => 'Perlu revisi',
    'done' => 'Selesai',
    _ => status,
  };
  static String icon(String status) => switch (status) {
    'todo' => 'circle',
    'in_progress' => 'arrow.triangle.2.circlepath',
    'in_review' => 'eye',
    'needs_revision' => 'arrow.uturn.backward',
    _ => 'checkmark.circle',
  };
  static Color tint(String status) => switch (status) {
    'todo' => GLTheme.butter,
    'in_progress' => GLTheme.sky,
    'in_review' => GLTheme.lavender,
    'needs_revision' => GLTheme.coral,
    _ => GLTheme.mint,
  };
}

class GLStatusChip extends StatelessWidget {
  const GLStatusChip({super.key, required this.status, this.large = false});
  final String status;
  final bool large;
  @override
  Widget build(BuildContext context) => GLChip(
    label: GLStatus.label(status),
    icon: GLStatus.icon(status),
    background: GLStatus.tint(status),
    height: large ? 30 : 28,
  );
}

/// `GLNotice` — tinted info box.
class GLNotice extends StatelessWidget {
  const GLNotice({
    super.key,
    required this.text,
    this.color,
    this.icon = 'info.circle',
  });
  final String text;
  final Color? color;
  final String icon;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 14),
    decoration: glBox(color ?? GLTheme.butter, 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GLIcon(icon, size: 20),
        SizedBox(width: 10),
        Expanded(child: Text(text, style: gl(14, w400, 0, null, 3))),
      ],
    ),
  );
}

/// `GLEmptyState` — centered white card, radius 28.
class GLEmptyState extends StatelessWidget {
  const GLEmptyState({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
    this.tint,
  });
  final String title;
  final String message;
  final String icon;
  final Color? tint;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(vertical: 28, horizontal: 22),
    decoration: glBox(GLTheme.surface, 28),
    child: Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: glBox(tint ?? GLTheme.mint, 20),
          child: GLIcon(icon, size: 28),
        ),
        SizedBox(height: 10),
        Text(title, textAlign: TextAlign.center, style: gl(19, w700)),
        SizedBox(height: 10),
        Text(
          message,
          textAlign: TextAlign.center,
          style: gl(15, w400, 0, GLTheme.secondary, 4),
        ),
      ],
    ),
  );
}

/// `GLSectionHeading` — 21/700 title with optional trailing "… >" link.
class GLSectionHeading extends StatelessWidget {
  const GLSectionHeading({
    super.key,
    required this.title,
    this.actionTitle,
    this.onAction,
  });
  final String title;
  final String? actionTitle;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(title, style: gl(21, w700, -0.02))),
      if (actionTitle != null && onAction != null)
        GLTap(
          onTap: onAction,
          child: Container(
            height: 44,
            padding: EdgeInsets.only(left: 12, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(actionTitle!, style: gl(15, w600)),
                SizedBox(width: 2),
                GLIcon('chevron.right', size: 20),
              ],
            ),
          ),
        ),
    ],
  );
}

/// `GLFormat` — Indonesian short dates matching the Swift helpers.
abstract final class GLFormat {
  static final months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', //
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
  ];
  static final monthsLong = [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', //
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
  ];
  static final weekdays = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
  static final weekdaysLong = [
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu',
  ];

  /// "16 Okt"
  static String date(DateTime value) {
    final d = value.toLocal();
    return '${d.day} ${months[d.month - 1]}';
  }

  /// "Jumat, 16 Oktober"
  static String longDate(DateTime value) {
    final d = value.toLocal();
    return '${weekdaysLong[d.weekday - 1]}, ${d.day} ${monthsLong[d.month - 1]}';
  }

  /// "Sab"
  static String weekday(DateTime value) =>
      weekdays[value.toLocal().weekday - 1];

  /// "19:02"
  static String time(DateTime value) {
    final d = value.toLocal();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  static int _dayOffset(DateTime value, DateTime now) {
    final a = value.toLocal(), b = now.toLocal();
    return DateTime(
      a.year,
      a.month,
      a.day,
    ).difference(DateTime(b.year, b.month, b.day)).inHours.divRound();
  }

  static bool isOverdue(DateTime value, String status, DateTime now) =>
      status != 'done' && value.isBefore(now);

  /// Prototype `dueInfo` label.
  static String due(DateTime value, String status, DateTime now) {
    if (isOverdue(value, status, now)) return 'Terlambat · ${date(value)}';
    final n = _dayOffset(value, now);
    if (n == 0) return 'Hari ini, ${time(value)}';
    if (n == 1) return 'Besok, ${time(value)}';
    if (n < 7) return '${weekday(value)}, ${time(value)}';
    return date(value);
  }

  static bool isSoon(DateTime value, String status, DateTime now) =>
      !isOverdue(value, status, now) &&
      _dayOffset(value, now) <= 2 &&
      status != 'done';

  /// "19:02" today, "Kemarin", otherwise "14 Okt".
  static String chatStamp(DateTime value, DateTime now) =>
      switch (_dayOffset(value, now)) {
        0 => time(value),
        -1 => 'Kemarin',
        _ => date(value),
      };

  static String deadline(DateTime value, DateTime now) =>
      due(value, 'todo', now);

  /// "08:40" today, "Kemarin", otherwise "Sel, 13 Okt".
  static String activityStamp(DateTime value, DateTime now) =>
      switch (_dayOffset(value, now)) {
        0 => time(value),
        -1 => 'Kemarin',
        _ => '${weekday(value)}, ${date(value)}',
      };
}

extension on int {
  // Day difference in hours → whole days (DST-safe rounding).
  int divRound() => (this / 24).round();
}

/// `GLCircleButton` — 44pt white circle icon button with hairline shadow.
class GLCircleButton extends StatelessWidget {
  const GLCircleButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconSize = 22,
    this.background,
  });
  final String icon;
  final String label;
  final double iconSize;
  final Color? background;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => GLTap(
    onTap: onTap,
    label: label,
    child: Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: background ?? GLTheme.raised,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: GLIcon(icon, size: iconSize),
    ),
  );
}

/// `GLDetailHeader` — back circle, centered 17/600 title, optional trailing.
class GLDetailHeader extends StatelessWidget {
  const GLDetailHeader(this.title, {super.key, this.trailing, this.onBack});
  final String title;
  final Widget? trailing;
  final VoidCallback? onBack;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      GLCircleButton(
        icon: 'arrow.left',
        label: 'Kembali',
        iconSize: 24,
        onTap: onBack ?? () => Navigator.of(context).maybePop(),
      ),
      SizedBox(width: 8),
      Expanded(
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: gl(17, w600),
        ),
      ),
      SizedBox(width: 8),
      SizedBox(width: 44, height: 44, child: Center(child: trailing)),
    ],
  );
}

/// `.glDetailScreen()` — background + safe area + custom header, scrolling body.
/// Content uses the Swift detail padding (20 horizontal, 10 top).
class GLDetailScaffold extends StatelessWidget {
  const GLDetailScaffold({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
    this.bottom,
    this.spacing = 16,
    this.onRefresh,
  });
  final String title;
  final List<Widget> children;
  final Widget? trailing;
  final Widget? bottom;
  final double spacing;
  final Future<void> Function()? onRefresh;
  @override
  Widget build(BuildContext context) {
    Widget list = ListView(
      physics: AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(20, 10, 20, 32),
      children: [
        GLDetailHeader(title, trailing: trailing),
        for (final child in children) ...[SizedBox(height: spacing), child],
      ],
    );
    if (onRefresh != null) {
      list = RefreshIndicator.adaptive(onRefresh: onRefresh!, child: list);
    }
    return Scaffold(
      backgroundColor: GLTheme.background,
      body: SafeArea(
        bottom: bottom == null,
        child: Column(
          children: [
            Expanded(child: list),
            ?bottom,
          ],
        ),
      ),
    );
  }
}

/// `GLSheet` — #F8F9F7, 32pt top corners, 38×5 handle, 22/700 title + close,
/// 16pt gaps, 20pt side padding; height fits content.
Future<T?> showGLSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required WidgetBuilder builder,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: GLTheme.background,
  barrierColor: GLTheme.scrim,
  shape: GLTheme.sheetShape,
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 10, 20, 34),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: GLTheme.ink),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 5,
                decoration: ShapeDecoration(
                  color: GLTheme.disabled,
                  shape: StadiumBorder(),
                ),
              ),
            ),
            SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: Text(title, style: gl(22, w700, -0.02))),
                SizedBox(width: 8),
                GLTap(
                  label: 'Tutup',
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: GLTheme.chip,
                      shape: BoxShape.circle,
                    ),
                    child: GLIcon('xmark', size: 22),
                  ),
                ),
              ],
            ),
            if (subtitle != null) ...[
              SizedBox(height: 8),
              Text(subtitle, style: gl(15, w400, 0, GLTheme.text3, 3)),
            ],
            SizedBox(height: 16),
            Builder(builder: builder),
          ],
        ),
      ),
    ),
  ),
);

/// `GLField` — 14/600 label (+ red asterisk) over a field.
class GLField extends StatelessWidget {
  const GLField(
    this.label, {
    super.key,
    required this.child,
    this.required = false,
    this.trailing,
  });
  final String label;
  final bool required;
  final String? trailing;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                text: label,
                children: [
                  if (required)
                    TextSpan(
                      text: ' *',
                      style: TextStyle(color: GLTheme.danger),
                    ),
                ],
              ),
              style: gl(14, w600),
            ),
          ),
          if (trailing != null)
            Text(trailing!, style: gl(13, w400, 0, GLTheme.secondary)),
        ],
      ),
      SizedBox(height: 6),
      child,
    ],
  );
}

/// `.glInput()` — white 16pt-radius box with #E8E9E7 border, 50pt tall.
InputDecoration glInputDecoration({String? hint, double radius = 16}) {
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecoration(
    hintText: hint,
    hintStyle: gl(16, w400, 0, GLTheme.placeholder),
    isDense: true,
    filled: true,
    fillColor: GLTheme.surface,
    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    border: border(GLTheme.border),
    enabledBorder: border(GLTheme.border),
    focusedBorder: border(GLTheme.ink, 1.5),
    errorBorder: border(GLTheme.danger),
    focusedErrorBorder: border(GLTheme.danger, 1.5),
    counterText: '',
  );
}

class GLTextField extends StatelessWidget {
  const GLTextField({
    super.key,
    required this.controller,
    this.hint,
    this.minLines = 1,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.obscureText = false,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.autofillHints,
    this.textCapitalization = TextCapitalization.none,
    this.semanticLabel,
  });
  final TextEditingController controller;
  final String? hint;
  final int minLines;
  final int maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final TextCapitalization textCapitalization;
  final String? semanticLabel;
  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel,
    textField: true,
    child: TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      obscureText: obscureText,
      autofocus: autofocus,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      textCapitalization: textCapitalization,
      cursorColor: GLTheme.ink,
      style: gl(16, w400, 0, GLTheme.ink),
      decoration: glInputDecoration(hint: hint),
    ),
  );
}

/// `GLFormError` — coral inline error.
class GLFormError extends StatelessWidget {
  const GLFormError(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: glBox(GLTheme.coral, 16),
      child: Row(
        children: [
          GLIcon('exclamationmark.circle', size: 18),
          SizedBox(width: 8),
          Expanded(child: Text(text, style: gl(14, w500))),
        ],
      ),
    ),
  );
}

/// `GLSubmitButton` — 56pt, radius 20, 17/600, spinner while busy.
class GLSubmitButton extends StatelessWidget {
  const GLSubmitButton({
    super.key,
    required this.title,
    required this.onPressed,
    this.busy = false,
    this.background,
  });
  final String title;
  final bool busy;
  final Color? background;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: !busy && onPressed != null,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: busy ? null : onPressed,
      child: Opacity(
        opacity: busy || onPressed == null ? 0.6 : 1,
        child: Container(
          height: 56,
          decoration: glBox(background ?? GLTheme.ink, 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy) ...[
                CupertinoActivityIndicator(color: GLTheme.onInk),
                SizedBox(width: 8),
              ],
              Text(title, style: gl(17, w600, 0, GLTheme.onInk)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// `GLOutlineButton` — 1.5pt ink border.
class GLOutlineButton extends StatelessWidget {
  const GLOutlineButton({
    super.key,
    required this.title,
    required this.onPressed,
    this.icon,
    this.height = 48,
    this.radius = 16,
    this.fontSize = 15,
  });
  final String title;
  final String? icon;
  final double height;
  final double radius;
  final double fontSize;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => GLTap(
    onTap: onPressed,
    child: Opacity(
      opacity: onPressed == null ? 0.35 : 1,
      child: Container(
        height: height,
        decoration: glBox(
          Colors.transparent,
          radius,
          border: GLTheme.ink,
          borderWidth: 1.5,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[GLIcon(icon!, size: 19), SizedBox(width: 6)],
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: gl(fontSize, w600),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// `glConfirm` — dimmed backdrop, white 28pt card, Batal + action buttons.
/// Resolves true when the action button is tapped. `info` shows one button.
Future<bool> showGLConfirm(
  BuildContext context, {
  required String title,
  required String text,
  required String ok,
  bool destructive = false,
  bool info = false,
}) async =>
    await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Tutup',
      barrierColor: GLTheme.dark ? GLTheme.scrim : Color(0x66141618),
      transitionDuration: Duration(milliseconds: 150),
      transitionBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
      pageBuilder: (context, _, _) => Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 340),
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                padding: EdgeInsets.all(22),
                decoration: glBox(
                  GLTheme.surface,
                  28,
                  border: GLTheme.overlayEdge,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: gl(19, w700, -0.01, GLTheme.ink)),
                    SizedBox(height: 12),
                    Text(text, style: gl(15, w400, 0, GLTheme.text3, 4)),
                    SizedBox(height: 18),
                    Row(
                      children: [
                        if (!info) ...[
                          Expanded(
                            child: _DialogButton(
                              title: 'Batal',
                              color: GLTheme.chip,
                              foreground: GLTheme.ink,
                              onTap: () => Navigator.of(context).pop(false),
                            ),
                          ),
                          SizedBox(width: 10),
                        ],
                        Expanded(
                          child: _DialogButton(
                            title: ok,
                            color: destructive ? GLTheme.danger : GLTheme.ink,
                            foreground: GLTheme.onInk,
                            onTap: () => Navigator.of(context).pop(true),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ) ??
    false;

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.title,
    required this.color,
    required this.foreground,
    required this.onTap,
  });
  final String title;
  final Color color;
  final Color foreground;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GLTap(
    onTap: onTap,
    child: Container(
      height: 50,
      alignment: Alignment.center,
      decoration: glBox(color, 16),
      child: Text(title, style: gl(15, w600, 0, foreground)),
    ),
  );
}

enum GLToastKind { ok, info, err }

OverlayEntry? _toast;
Timer? _toastTimer;

/// `GLToastView` at the top of the screen (store.flash in Swift).
void showGLToast(
  BuildContext context,
  String text, {
  GLToastKind kind = GLToastKind.ok,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _toastTimer?.cancel();
  _toast?.remove();
  final entry = OverlayEntry(
    builder: (context) => Positioned(
      left: 0,
      right: 0,
      top: MediaQuery.paddingOf(context).top + 4,
      child: IgnorePointer(
        child: Center(
          child: GLToastView(text: text, kind: kind),
        ),
      ),
    ),
  );
  _toast = entry;
  overlay.insert(entry);
  _toastTimer = Timer(Duration(milliseconds: 2400), () {
    if (_toast == entry) _toast = null;
    entry.remove();
  });
}

class GLToastView extends StatelessWidget {
  const GLToastView({
    super.key,
    required this.text,
    this.kind = GLToastKind.ok,
  });
  final String text;
  final GLToastKind kind;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: ShapeDecoration(
            color: GLTheme.ink,
            shape: glShape(20),
            shadows: [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 30,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GLIcon(
                switch (kind) {
                  GLToastKind.err => 'exclamationmark.circle',
                  GLToastKind.info => 'info.circle',
                  GLToastKind.ok => 'checkmark.circle',
                },
                size: 19,
                color: switch (kind) {
                  GLToastKind.err => GLTheme.coral,
                  GLToastKind.info => GLTheme.sky,
                  GLToastKind.ok => GLTheme.mint,
                },
              ),
              SizedBox(width: 8),
              Flexible(
                child: Text(text, style: gl(14, w500, 0, GLTheme.onInk, 2)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// `GLAccessDenied` — lost access to a group/project/task.
class GLAccessDenied extends StatelessWidget {
  const GLAccessDenied({
    super.key,
    this.text =
        'Konten ini milik grup yang tidak kamu ikuti, atau sudah dihapus. Minta kode undangan ke koordinatornya untuk bergabung.',
  });
  final String text;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: GLTheme.background,
    body: SafeArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, 10, 20, 32),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: GLCircleButton(
              icon: 'arrow.left',
              label: 'Kembali',
              iconSize: 24,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          SizedBox(height: 20),
          GLEmptyState(
            title: 'Kamu tidak punya akses',
            message: text,
            icon: 'lock',
            tint: GLTheme.coral,
          ),
        ],
      ),
    ),
  );
}

/// Thin progress bar (ink on muted) used on project cards.
class GLProgressBar extends StatelessWidget {
  const GLProgressBar({super.key, required this.value, this.height = 6});
  final double value;
  final double height;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(height),
    child: SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: GLTheme.muted)),
          FractionallySizedBox(
            widthFactor: value.clamp(0, 1),
            child: ColoredBox(color: GLTheme.ink),
          ),
        ],
      ),
    ),
  );
}

/// 1pt divider line used between list rows.
class GLHairline extends StatelessWidget {
  const GLHairline({super.key, this.color});
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(height: 1, color: color);
}
