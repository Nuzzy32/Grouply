import 'package:flutter/material.dart';

/// Mirrors `GLTheme` in Grouply/Core/DesignSystem.swift.
abstract final class GLTheme {
  static bool dark = false;

  static Color get background => Color(dark ? 0xFF121314 : 0xFFF8F9F7);
  static Color get surface => Color(dark ? 0xFF1C1E20 : 0xFFFFFFFF);
  static Color get ink => Color(dark ? 0xFFECEDEE : 0xFF202124);
  static Color get onInk => Color(dark ? 0xFF1A1B1D : 0xFFFFFFFF);
  static Color get secondary => Color(dark ? 0xFFA3A8AD : 0xFF62676B);
  static Color get text2 => Color(dark ? 0xFFC2C6CA : 0xFF4D5155);
  static Color get text3 => Color(dark ? 0xFFD5D8DB : 0xFF3C4043);
  static Color get muted => Color(dark ? 0xFF222527 : 0xFFF0F3F1);
  static Color get border => Color(dark ? 0xFF2E3134 : 0xFFE8E9E7);
  static Color get chip => Color(dark ? 0xFF26292B : 0xFFECEEEB);
  static Color get raised => Color(dark ? 0xFF2E3134 : 0xFFFFFFFF);
  static Color get placeholder => Color(dark ? 0xFF868C93 : 0xFF9AA0A6);
  static Color get disabled => Color(dark ? 0xFF4A4F53 : 0xFFC4C7C5);
  static Color get faint => Color(dark ? 0xFF5B6166 : 0xFFB4B8BC);
  static Color get hairline => Color(dark ? 0xFF3A3E42 : 0xFFD5D8DB);
  static Color get tertiary => Color(dark ? 0xFF9AA0A6 : 0xFF80868B);
  static Color get lavender => Color(dark ? 0xFF3A3354 : 0xFFDED2FF);
  static Color get mint => Color(dark ? 0xFF1F3D2B : 0xFFC9F2D6);
  static Color get sky => Color(dark ? 0xFF1E3442 : 0xFFD8EAF4);
  static Color get butter => Color(dark ? 0xFF413720 : 0xFFF9E9BE);
  static Color get coral => Color(dark ? 0xFF47282B : 0xFFF6CED1);
  static Color get danger => Color(dark ? 0xFFFF8A80 : 0xFFA8231B);
  static Color get success => Color(dark ? 0xFF6FCF97 : 0xFF1E7A43);
  static Color get link => Color(dark ? 0xFF8AB4F8 : 0xFF1F4F86);

  static ThemeData get data {
    final base = ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      // Match the SwiftUI client on every platform: iOS push/swipe-back and no ripples.
      platform: TargetPlatform.iOS,
      scaffoldBackgroundColor: background,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      colorScheme: ColorScheme.fromSeed(
        brightness: dark ? Brightness.dark : Brightness.light,
        seedColor: ink,
        surface: background,
        primary: ink,
        onPrimary: onInk,
        error: danger,
      ),
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: ink,
        selectionColor: lavender,
        selectionHandleColor: ink,
      ),
      dividerTheme: DividerThemeData(color: border, space: 1),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
    );
  }
}
