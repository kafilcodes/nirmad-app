// typed_data not needed; foundation import provides Uint8List in Flutter context

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:toastification/toastification.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/data/auth_repository.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
// Removed pickers: photo upload disabled; generated avatars are used by default
// Cached image replaced by hash_cached_image in avatar
// import 'package:image/image.dart' as img; // kept as reference if re-enabling uploads later
// Removed external avatar libs; using simple initials-only avatar
// Upload avatar using official Firebase Storage SDK for a fixed path
import '../../../core/logging/app_logger.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormBuilderState>();
  bool _saving = false;
  bool _editing = false;
  bool _dirty = false;
  bool _requireAllFields = false; // First-time completion requires all fields
  final Set<String> _alwaysRequired = const {'displayName', 'phone'}; // minimal mandatory fields after first-time
  Map<String, dynamic> _initialValues = const {};
  // Local draft autosave
  Map<String, dynamic> _draft = {};
  int _viewGen = 0; // bump to animate a single smooth transition after save
  // markers (not currently used in UI but kept for potential restore banners)
  // DateTime _lastChange = DateTime.now();
  // bool _restoring = true;
  // Debounce timer
  Timer? _saveDebounce;
  StreamSubscription<fb.User?>? _authSub;

  @override
  void initState() {
    super.initState();
    _load();
    // Keep the disabled email field in sync with the live auth user
    _authSub = fb.FirebaseAuth.instance.userChanges().listen((u) {
      final email = (u?.email ?? '').trim();
      if (email.isEmpty) return;
      // Only patch email field; avoid unnecessary rebuilds
      final currentEmail = (_initialValues['email'] as String?)?.trim() ?? '';
      if (email == currentEmail) return;
      _initialValues = Map<String, dynamic>.from(_initialValues)..['email'] = email;
      _formKey.currentState?.patchValue({'email': email});
      // No setState here to avoid double refresh; form field updates itself
    });
  }

  Future<void> _load() async {
    final u = fb.FirebaseAuth.instance.currentUser;
    final uid = u?.uid;
    if (uid == null) return;
    // Read Firestore doc; do not bail out if it fails
    Map<String, dynamic> server = const {};
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      server = doc.data() ?? {};
    } catch (e) {
      AppLogger.i.i('Profile load Firestore error: $e');
    }
  // Compose initial values from server fields with auth fallback
    Map<String, dynamic> initial = {
      'displayName': (server['displayName'] as String?) ?? (u?.displayName ?? ''),
      'email': u?.email ?? '',
      'phone': (server['phone'] as String?) ?? '',
      'whatsapp': (server['whatsapp'] as String?) ?? '',
      'aadhar': (server['aadhar'] as String?) ?? '',
      'dob': (server['dob'] is Timestamp) ? (server['dob'] as Timestamp).toDate() : null,
      'gender': (server['gender'] as String?) ?? '',
      'occupation': (server['occupation'] as String?) ?? '',
      'address': (server['address'] as String?) ?? '',
    };
  // Determine if this is first-time completion (no data in Firestore)
  final isFirstTime = server.isEmpty;
    // Merge local draft (if any)
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('profile_draft');
      if (raw != null && raw.isNotEmpty) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        _draft = map;
        if (_draft['dob'] is String && (_draft['dob'] as String).isNotEmpty) {
          try { initial['dob'] = DateTime.parse(_draft['dob']); } catch (_) {}
        }
        for (final k in _draft.keys) {
          if (k == 'dob') continue;
          initial[k] = _draft[k];
        }
      }
    } catch (e) {
      AppLogger.i.i('Profile load draft error: $e');
    }
  // Photo URL no longer used; generated avatar is shown
    // Apply to form now regardless
    if (mounted) {
      // Determine if core fields are all missing/empty in Firestore
      final coreKeys = ['displayName','phone','whatsapp','aadhar','dob','gender','occupation','address'];
      bool allCoreMissing = true;
      for (final k in coreKeys) {
        final v = server[k];
        if (v is String && v.trim().isNotEmpty) { allCoreMissing = false; break; }
        if (v is Timestamp) { allCoreMissing = false; break; }
      }
      setState(() {
        _initialValues = initial;
        _editing = isFirstTime || allCoreMissing; // auto-enable editing if first-time or core empty
        _requireAllFields = isFirstTime || allCoreMissing;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _formKey.currentState?.patchValue(initial);
      });
    }
  }

  // Avatar upload path removed in favor of generated avatars

  // Removed legacy mobile picker callback; we use themed picker sheet instead

  Future<void> _save() async {
    final uid = fb.FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final st = _formKey.currentState;
    if (st == null) return;
    if (!st.saveAndValidate()) {
      toastification.show(
        context: context,
        title: const Text('Please fix the highlighted fields'),
        type: ToastificationType.warning,
        style: ToastificationStyle.fillColored,
        autoCloseDuration: const Duration(seconds: 3),
        showProgressBar: false,
        icon: const Icon(Icons.error_outline),
      );
      return;
    }
    if (mounted) setState(() => _saving = true);
    try {
      final values = Map<String, dynamic>.from(st.value);
      final displayName = (values['displayName'] as String? ?? '').trim();
      final phone = (values['phone'] as String? ?? '').trim();
      final whatsapp = (values['whatsapp'] as String? ?? '').trim();
      final aadhar = (values['aadhar'] as String? ?? '').trim();
      final gender = (values['gender'] as String? ?? '').trim();
      final occupation = (values['occupation'] as String? ?? '').trim();
      final address = (values['address'] as String? ?? '').trim();
      final dob = values['dob'] is DateTime ? values['dob'] as DateTime : null;

      final data = <String, dynamic>{
        'displayName': displayName,
        'phone': phone,
        'whatsapp': whatsapp,
        'aadhar': aadhar,
        if (dob != null) 'dob': Timestamp.fromDate(dob),
        'gender': gender,
        'occupation': occupation,
        'address': address,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  await FirebaseFirestore.instance.collection('users').doc(uid).set(data, SetOptions(merge: true));

      // Update FirebaseAuth displayName for consistency across widgets
      if (displayName.isNotEmpty && displayName != (fb.FirebaseAuth.instance.currentUser?.displayName ?? '')) {
        await fb.FirebaseAuth.instance.currentUser?.updateDisplayName(displayName);
      }

  // No global provider invalidation here to avoid double refresh; unified
  // profile provider listens to Firestore and will update the UI.

      // Clear local draft on successful save
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('profile_draft');
      } catch (_) {}

      if (!mounted) return;
      toastification.show(
        context: context,
        title: const Text('Profile updated'),
        type: ToastificationType.success,
        style: ToastificationStyle.fillColored,
        autoCloseDuration: const Duration(seconds: 3),
        showProgressBar: false,
        icon: const Icon(Icons.check_circle),
      );
      // Update initial values and reset edit state (single smooth transition)
      setState(() {
        _initialValues = {
          'displayName': displayName,
          'email': fb.FirebaseAuth.instance.currentUser?.email ?? '',
          'phone': phone,
          'whatsapp': whatsapp,
          'aadhar': aadhar,
          if (dob != null) 'dob': dob,
          'gender': gender,
          'occupation': occupation,
          'address': address,
        };
        _editing = false;
        _dirty = false;
        _requireAllFields = false;
        _viewGen++;
      });
    } catch (e) {
      if (!mounted) return;
      toastification.show(
        context: context,
        title: const Text('Update failed'),
        description: Text('$e'),
        type: ToastificationType.error,
        style: ToastificationStyle.fillColored,
        autoCloseDuration: const Duration(seconds: 4),
        showProgressBar: true,
        icon: const Icon(Icons.error_outline),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
  _saveDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Consumer(builder: (context, ref, _) {
                    final prof = ref.watch(currentUserProfileProvider);
                    final liveUser = fb.FirebaseAuth.instance.currentUser;
                    final displayName = (prof?.displayName ?? liveUser?.displayName ?? '').trim();
                    final email = (prof?.email ?? liveUser?.email ?? '').trim();
                    final displayLabel = displayName.isNotEmpty ? displayName : (email.split('@').first);
                    return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                      InkWell(
                        borderRadius: const BorderRadius.all(Radius.circular(64)),
                        // Disable photo upload per request; rely on generated avatar
                        onTap: null,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                          SizedBox(
                            width: 128,
                            height: 128,
                            child: Consumer(builder: (context, ref, _) {
                              final display = displayLabel;
                              final first = (display.isNotEmpty ? display[0] : (email.isNotEmpty ? email[0] : '?')).toUpperCase();
                              final cs = Theme.of(context).colorScheme;
                              return CircleAvatar(
                                radius: 64,
                                backgroundColor: cs.primary,
                                child: Text(
                                  first,
                                  textAlign: TextAlign.center,
                                  textHeightBehavior: const TextHeightBehavior(
                                    applyHeightToFirstAscent: true,
                                    applyHeightToLastDescent: true,
                                    leadingDistribution: TextLeadingDistribution.even,
                                  ),
                                  style: TextStyle(
                                    fontSize: 48,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onPrimary,
                                    height: 1.0,
                                    leadingDistribution: TextLeadingDistribution.even,
                                    textBaseline: TextBaseline.alphabetic,
                                  ),
                                ),
                              );
                            }),
                          ),
                          // Edit/Lock icon overlay
                          Positioned(
                            right: 8,
                            bottom: 8,
                            child: IconButton.filledTonal(
                              onPressed: _saving
                                  ? null
                                  : () {
                                      setState(() {
                                        _editing = !_editing;
                                        if (!_editing) {
                                          _formKey.currentState?.reset();
                                          _formKey.currentState?.patchValue(_initialValues);
                                          _dirty = false;
                                        }
                                      });
                                    },
                              icon: Icon(_editing ? CupertinoIcons.lock : CupertinoIcons.pencil),
                              tooltip: _editing ? 'Lock' : 'Edit',
                            ),
                          ),
                          if (_saving)
              ClipOval(
                              child: Container(
                                width: 128,
                                height: 128,
                color: Colors.black.withValues(alpha: 0.25),
                                child: const Center(
                                  child: SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: CircularProgressIndicator(strokeWidth: 2.6),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(CupertinoIcons.person, size: 16),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              displayLabel.isNotEmpty ? displayLabel : 'Your Profile',
                              style: Theme.of(context).textTheme.titleLarge,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(CupertinoIcons.mail, size: 14),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              email.isNotEmpty ? email : '-',
                              style: Theme.of(context).textTheme.bodySmall,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                        ],
            );
          }),
                ),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  child: Card(
                    key: ValueKey('form-$_viewGen'),
                  clipBehavior: Clip.antiAlias,
                  elevation: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: FormBuilder(
                      key: _formKey,
                      initialValue: _initialValues,
                      autovalidateMode: _editing ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
                      onChanged: () {
                        // Debounced local autosave of form values
                        _saveDebounce?.cancel();
                        _saveDebounce = Timer(const Duration(milliseconds: 600), () async {
                          final state = _formKey.currentState;
                          if (state == null) return;
                          state.save();
                          final val = Map<String, dynamic>.from(state.value);
                          // Serialize DateTime to ISO string
                          if (val['dob'] is DateTime) {
                            val['dob'] = (val['dob'] as DateTime).toIso8601String();
                          }
                          try {
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString('profile_draft', jsonEncode(val));
                          } catch (_) {}
                        });
                        // Update dirty state
                        final current = Map<String, dynamic>.from(_formKey.currentState?.value ?? {});
                        setState(() {
                          _dirty = _hasChanges(current, _initialValues);
                        });
                      },
                      child: LayoutBuilder(builder: (context, c) {
                        final isWide = c.maxWidth > 640;
                        final col = isWide ? 2 : 1;
                        final gap = 16.0;
                        final fieldWidth = isWide ? (c.maxWidth - gap) / col : c.maxWidth;
                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            SizedBox(
                              width: fieldWidth,
                              child: FormBuilderTextField(
                                name: 'displayName',
                                enabled: _editing,
                                decoration: const InputDecoration(
                                  labelText: 'Display name',
                                  prefixIcon: Icon(CupertinoIcons.person),
                                ),
                                validator: FormBuilderValidators.compose([
                  (val) => _isFieldRequired('displayName') && (val == null || val.trim().isEmpty)
                    ? 'This field is required'
                    : null,
                                  FormBuilderValidators.minLength(2),
                                ]),
                              ),
                            ),
                            SizedBox(
                              width: fieldWidth,
                              child: FormBuilderTextField(
                                name: 'email',
                                enabled: false,
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                  prefixIcon: Icon(CupertinoIcons.at),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: fieldWidth,
                              child: FormBuilderTextField(
                                name: 'phone',
                                enabled: _editing,
                                decoration: const InputDecoration(
                                  labelText: 'Phone (India)',
                                  prefixText: '+91 ',
                                  prefixIcon: Icon(CupertinoIcons.phone),
                                ),
                                validator: FormBuilderValidators.compose([
                                  (val) => _isFieldRequired('phone') && (val == null || val.trim().isEmpty)
                                      ? 'This field is required'
                                      : null,
                                  FormBuilderValidators.match(RegExp(r'^[6-9]\d{9}$'), errorText: 'Enter 10-digit Indian mobile'),
                                  (val) {
                                    if (val == null || val.trim().isEmpty) return null; // optional
                                    final s = val.trim();
                                    if (s.length != 10) return 'Must be 10 digits';
                                    return null;
                                  },
                                ]),
                                keyboardType: TextInputType.phone,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(10),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: fieldWidth,
                              child: FormBuilderTextField(
                                name: 'whatsapp',
                                enabled: _editing,
                                decoration: InputDecoration(
                                  labelText: 'WhatsApp (India)',
                                  prefixText: '+91 ',
                                  prefixIcon: const Icon(CupertinoIcons.chat_bubble_text),
                                  suffixIcon: const Padding(
                                    padding: EdgeInsets.only(right: 8.0, left:8.0, top: 8.0, bottom: 8.0),
                                    child: FaIcon(FontAwesomeIcons.whatsapp, size: 20, color: Color(0xFF25D366)),
                                  ),
                                  suffixIconConstraints: const BoxConstraints(minHeight: 24, minWidth: 24),
                                ),
                                validator: FormBuilderValidators.compose([
                                  if (_requireAllFields)
                                    (val) => (val == null || val.trim().isEmpty) ? 'This field is required' : null,
                                  FormBuilderValidators.match(RegExp(r'^(?:[6-9]\d{9})?$'), errorText: 'Enter 10-digit Indian WhatsApp'),
                                  (val) {
                                    if (val == null || val.trim().isEmpty) return null; // optional
                                    final s = val.trim();
                                    if (s.length != 10) return 'Must be 10 digits';
                                    return null;
                                  },
                                ]),
                                keyboardType: TextInputType.phone,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(10),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: fieldWidth,
                              child: FormBuilderTextField(
                                name: 'aadhar',
                                enabled: _editing,
                                decoration: const InputDecoration(
                                  labelText: 'Aadhaar Number',
                                  prefixIcon: Icon(CupertinoIcons.person_crop_square),
                                ),
                                validator: FormBuilderValidators.compose([
                                  if (_requireAllFields)
                                    (val) => (val == null || val.trim().isEmpty) ? 'This field is required' : null,
                                  FormBuilderValidators.match(RegExp(r'^(?:\d{12})?$'), errorText: 'Enter 12-digit Aadhaar'),
                                ]),
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(12),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: fieldWidth,
                              child: FormBuilderDateTimePicker(
                                name: 'dob',
                                enabled: _editing,
                                inputType: InputType.date,
                                decoration: const InputDecoration(
                                  labelText: 'Date of birth',
                                  prefixIcon: Icon(CupertinoIcons.calendar),
                                ),
                                lastDate: DateTime.now(),
                                initialDate: DateTime(2000, 1, 1),
                                validator: (val) {
                                  if (val == null) return _isFieldRequired('dob') || _requireAllFields ? 'This field is required' : null;
                                  final now = DateTime.now();
                                  final eighteen = DateTime(now.year - 18, now.month, now.day);
                                  if (val.isAfter(eighteen)) {
                                    return 'Must be at least 18 years old';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            SizedBox(
                              width: fieldWidth,
                              child: FormBuilderDropdown<String>(
                                name: 'gender',
                                enabled: _editing,
                                decoration: const InputDecoration(
                                  labelText: 'Gender',
                                  prefixIcon: Icon(CupertinoIcons.person_2),
                                ),
                                isExpanded: true,
                                items: const [
                                  DropdownMenuItem(value: 'Male', child: Text('Male')),
                                  DropdownMenuItem(value: 'Female', child: Text('Female')),
                                  DropdownMenuItem(value: 'Non-binary', child: Text('Non-binary')),
                                  DropdownMenuItem(value: 'Prefer not to say', child: Text('Prefer not to say')),
                                ],
                                validator: (val) => (_isFieldRequired('gender') || _requireAllFields) && (val == null || val.isEmpty)
                                    ? 'This field is required'
                                    : null,
                              ),
                            ),
                            SizedBox(
                              width: fieldWidth,
                              child: FormBuilderTextField(
                                name: 'occupation',
                                enabled: _editing,
                                decoration: const InputDecoration(
                                  labelText: 'Occupation',
                                  prefixIcon: Icon(CupertinoIcons.briefcase),
                                ),
                                validator: (val) => _requireAllFields && (val == null || val.trim().isEmpty)
                                    ? 'This field is required'
                                    : null,
                              ),
                            ),
                            SizedBox(
                              width: c.maxWidth,
                              child: FormBuilderTextField(
                                name: 'address',
                                maxLines: 3,
                                enabled: _editing,
                                decoration: const InputDecoration(
                                  labelText: 'Address',
                                  prefixIcon: Icon(CupertinoIcons.house),
                                ),
                                validator: (val) => (_isFieldRequired('address') || _requireAllFields) && (val == null || val.trim().isEmpty)
                                    ? 'This field is required'
                                    : null,
                              ),
                            ),
                          ],
                        );
                      }),
                    ),
                  ),
                ),
                ),
                const SizedBox(height: 12),
                Align(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_editing)
                        OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () {
                                  setState(() {
                                    _formKey.currentState?.reset();
                                    _formKey.currentState?.patchValue(_initialValues);
                                    _dirty = false;
                                    _editing = false;
                                  });
                                },
                          child: const Text('Cancel'),
                        ),
                      if (_editing) const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: _saving || !_editing || !_dirty || !(_formKey.currentState?.isValid ?? false)
                            ? null
                            : _save,
                        icon: _saving
                            ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(CupertinoIcons.checkmark_alt),
                        label: Text(_saving ? 'Saving…' : 'Save changes'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _hasChanges(Map<String, dynamic> a, Map<String, dynamic> b) {
    bool eq(dynamic v1, dynamic v2) {
      if (v1 is DateTime && v2 is DateTime) {
        return v1.toIso8601String() == v2.toIso8601String();
      }
      return (v1 ?? '') == (v2 ?? '');
    }
    const keys = [
      'displayName', 'phone', 'whatsapp', 'aadhar', 'dob', 'gender', 'occupation', 'address'
    ];
    for (final k in keys) {
      if (!eq(a[k], b[k])) return true;
    }
    return false;
  }

  bool _isFieldRequired(String name) => _requireAllFields || _alwaysRequired.contains(name);

  // Picked bytes handler removed

  // Photo picking bottom sheet removed per new requirement
}
// Theme & language toggles are in the sidebar footer

// Removed local wrappers; using avatar_better_pro + hash_cached_image packages
