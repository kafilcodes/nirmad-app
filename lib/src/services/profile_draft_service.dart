import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileDraftService {
  static const String _draftKey = 'profile_draft';

  final SharedPreferences _prefs;

  ProfileDraftService(this._prefs);

  Future<void> saveDraft(Map<String, dynamic> draftData) async {
    try {
      final jsonData = jsonEncode(draftData);
      await _prefs.setString(_draftKey, jsonData);
    } catch (_) {
      // ignore malformed data
    }
  }

  Map<String, dynamic>? loadDraft() {
    final jsonData = _prefs.getString(_draftKey);
    if (jsonData == null) return null;
    try {
      return jsonDecode(jsonData) as Map<String, dynamic>;
    } catch (_) {
      clearDraft();
      return null;
    }
  }

  Future<void> clearDraft() async {
    await _prefs.remove(_draftKey);
  }

  bool hasDraft() => _prefs.containsKey(_draftKey);
}
