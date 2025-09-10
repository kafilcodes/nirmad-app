import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class UnsavedChangesGuard extends ChangeNotifier {
  Future<bool> Function()? _confirm;

  Future<bool> confirm() async {
    if (_confirm == null) return true;
    return await _confirm!.call();
  }

  void register(Future<bool> Function()? fn) {
    _confirm = fn;
    notifyListeners();
  }

  void clear() {
    _confirm = null;
    notifyListeners();
  }
}

final unsavedChangesGuardProvider = ChangeNotifierProvider<UnsavedChangesGuard>((ref) => UnsavedChangesGuard());
