import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController extends StateNotifier<ThemeMode> {
  ThemeController(this._prefs) : super(ThemeMode.light) {
    _load();
  }

  final SharedPreferences _prefs;

  static const _key = 'theme_mode';

  void _load() {
    final v = _prefs.getString(_key);
    switch (v) {
      case 'light':
        state = ThemeMode.light;
        break;
      case 'dark':
        state = ThemeMode.dark;
        break;
      default:
        state = ThemeMode.light; // default to light if unset
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await _prefs.setString(_key, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'light', // treat system as light to avoid OS-driven changes
    });
  }

  Future<void> toggle() async {
  final next = state == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    await setMode(next);
  }
}

final themeControllerProvider = StateNotifierProvider<ThemeController, ThemeMode>((ref) {
  throw UnimplementedError('themeControllerProvider overridden at runtime');
});
