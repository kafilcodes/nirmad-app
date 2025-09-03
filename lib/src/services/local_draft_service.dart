import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalDraftService {
  static const String _draftKey = 'project_creation_draft';
  
  final SharedPreferences _prefs;
  
  LocalDraftService(this._prefs);
  
  /// Save draft data to local storage
  Future<void> saveDraft(Map<String, dynamic> draftData) async {
    final jsonData = jsonEncode(draftData);
    await _prefs.setString(_draftKey, jsonData);
  }
  
  /// Load draft data from local storage
  Map<String, dynamic>? loadDraft() {
    final jsonData = _prefs.getString(_draftKey);
    if (jsonData == null) return null;
    
    try {
      return jsonDecode(jsonData) as Map<String, dynamic>;
    } catch (e) {
      // If decode fails, return null and clear corrupted data
      clearDraft();
      return null;
    }
  }
  
  /// Clear draft data from local storage
  Future<void> clearDraft() async {
    await _prefs.remove(_draftKey);
  }
  
  /// Check if draft exists
  bool hasDraft() {
    return _prefs.containsKey(_draftKey);
  }
}