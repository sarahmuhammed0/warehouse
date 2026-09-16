import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Theme state (architecture §4/§24) — in-memory only for now. Settings
/// isn't built yet, so there's nowhere to persist a user's choice; when it
/// is, this Notifier's `setMode` is the one method it calls, and nothing
/// else in the app changes. Defaults to following the OS.
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void setMode(ThemeMode mode) => state = mode;

  void toggle() {
    state = switch (state) {
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.light,
      ThemeMode.system => ThemeMode.light,
    };
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);
