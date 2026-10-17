import 'package:flutter/material.dart';

/// Mirrors `GLTheme` in Grouply/Core/DesignSystem.swift.
abstract final class GLTheme {
  static const background = Color(0xFFF8F9F7);
  static const ink = Color(0xFF202124);
  static const secondary = Color(0xFF62676B);
  static const text2 = Color(0xFF4D5155);
  static const text3 = Color(0xFF3C4043);
  static const muted = Color(0xFFF0F3F1);
  static const border = Color(0xFFE8E9E7);
  static const lavender = Color(0xFFDED2FF);
  static const mint = Color(0xFFC9F2D6);
  static const sky = Color(0xFFD8EAF4);
  static const butter = Color(0xFFF9E9BE);
  static const coral = Color(0xFFF6CED1);
  static const danger = Color(0xFFA8231B);

  static ThemeData get data {
    final base = ThemeData(
      useMaterial3: true,
      // Match the SwiftUI client on every platform: iOS push/swipe-back and no ripples.
      platform: TargetPlatform.iOS,
      scaffoldBackgroundColor: background,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      splashColor: Colors.transparent,
      colorScheme: ColorScheme.fromSeed(
        seedColor: ink,
        surface: background,
        primary: ink,
        onPrimary: Colors.white,
        error: danger,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: ink,
        selectionColor: lavender,
        selectionHandleColor: ink,
      ),
      dividerTheme: const DividerThemeData(color: border, space: 1),
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
    );
  }
}
