import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:nirmadapp/src/shared/widgets/required_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
// import 'package:permission_handler/permission_handler.dart'; // removed unused
import 'package:image_picker/image_picker.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:nirmadapp/src/shared/widgets/app_map.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:nirmadapp/src/services/draft_media_store.dart';
import 'package:nirmadapp/src/utils/image_utils.dart' as image_utils;

import 'package:nirmadapp/src/features/auth/data/auth_repository.dart';
import 'package:nirmadapp/src/shared/utils/amount_in_words.dart';
import 'package:nirmadapp/src/features/projects/data/project_repository.dart';
import 'package:nirmadapp/src/features/projects/domain/project.dart';
import 'package:nirmadapp/src/shared/utils/date_parse.dart';
import 'package:nirmadapp/src/shared/widgets/scroll_safe_dialog.dart';
import 'package:flutter/services.dart';
import '../../../shared/ui/progress.dart';
// Removed unused imports: app_wizard_stepper and section_controller

class ProjectUpdateFormPage extends ConsumerStatefulWidget {
  final Project project;
  final bool embedded; // when true, render content without Scaffold/AppBar for embedding in tabs
  const ProjectUpdateFormPage({super.key, required this.project, this.embedded = false});

  @override
  ConsumerState<ProjectUpdateFormPage> createState() => _ProjectUpdateFormPageState();
}

class _ProjectUpdateFormPageState extends ConsumerState<ProjectUpdateFormPage> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  // Collapsible toggles
  bool _showComment = true;
  bool _showStage = true;
  bool _showInstallments = true;
  bool _showAttach = true;

  // Basic fields
  String? _comment;
  WorkStage? _stage;
  late final TextEditingController _commentController;
  int _commentWords = 0;

  // Installments
  final _iAmt = <int, String?>{1: null, 2: null, 3: null};
  final _iDate = <int, DateTime?>{1: null, 2: null, 3: null};
  final _iRecAmt = <int, String?>{1: null, 2: null, 3: null};
  final _iRecDate = <int, DateTime?>{1: null, 2: null, 3: null};
  final Set<int> _activeNewInstallments = <int>{};

  // Media
  final _photos = <String>[];
  final _docs = <String>[];
  final Map<String, double> _uploadingPhotos = {};
  final Map<String, double> _uploadingDocs = {};
  DraftMediaStore? _mediaStore;

  // Location
  double? _lat;
  double? _lng;
  String? _locMethod; // 'gps' or 'manual'
  bool _locating = false;
  bool _mapAllowed = false; // show Pick on Map only after auto-location fails or permission denied

  @override
  void initState() {
    super.initState();
    _commentController = TextEditingController(text: _comment ?? '');
    try { _stage = widget.project.workDescription.stage; } catch (_) {}
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // initialize draft media store lazily
      final s = ref.read(draftMediaStoreProvider);
      await s.init();
      if (!mounted) return;
      setState(() { _mediaStore = s; });
      // Kick off location flow if absent
      if (_lat == null && _lng == null) {
        await _openLocationSheet();
      }
    });
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  // removed _scrollToKey helper as stepper is removed

  int _countWords(String s) {
    final t = s.trim();
    if (t.isEmpty) return 0;
    return t.split(RegExp(r"\s+")).where((e) => e.isNotEmpty).length;
  }

  String _firstWords(String s, int n) {
    final words = s.trim().split(RegExp(r"\s+")).where((e) => e.isNotEmpty).toList();
    if (words.length <= n) return s.trim();
    return words.take(n).join(' ');
  }

  void _onCommentChanged(String v) {
    final w = _countWords(v);
    if (w <= 100) {
      setState(() {
        _commentWords = w;
        _comment = v;
      });
    } else {
      final trimmed = _firstWords(v, 100);
      // Update controller text and place cursor at end
      _commentController.text = trimmed;
      _commentController.selection = TextSelection.fromPosition(TextPosition(offset: _commentController.text.length));
      setState(() {
        _commentWords = 100;
        _comment = trimmed;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Max 100 words allowed')));
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final existing = _mediaStore?.list(category: 'work_photo').length ?? 0;
      final uploading = _uploadingPhotos.length;
      if (existing + uploading >= 5) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Maximum 5 photos per update')));
        }
        return;
      }
      if (kIsWeb) {
        final res = await FilePicker.platform.pickFiles(withData: true, type: FileType.image);
        final f = res?.files.single;
        if (f == null || f.bytes == null) return;
        if (f.size > 3 * 1024 * 1024) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image must be ≤ 3 MB')));
          return;
        }
        await _mediaStore?.addFromPlatformFile(
          f,
          category: 'work_photo',
          maxBytes: 3 * 1024 * 1024,
        );
        if (!mounted) return;
        setState(() {});
      } else {
        final picker = ImagePicker();
        final img = await picker.pickImage(source: ImageSource.camera);
        if (img == null) return;
        final file = File(img.path);
        final size = await file.length();
        if (size > 3 * 1024 * 1024) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image must be ≤ 3 MB')));
          return;
        }
        await _mediaStore?.addFromXFile(
          img,
          category: 'work_photo',
          maxBytes: 3 * 1024 * 1024,
        );
        if (!mounted) return;
        setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _pickDoc() async {
    try {
      final existingDocs = _mediaStore?.list(category: 'work_doc').length ?? 0;
      if (existingDocs + _uploadingDocs.length >= 1) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Only 1 PDF allowed')));
        return;
      }
      final res = await FilePicker.platform.pickFiles(withData: kIsWeb, type: FileType.custom, allowedExtensions: const ['pdf']);
      if (res == null) return;
      final f = res.files.single;
      if (kIsWeb) {
        final bytes = f.bytes;
        if (bytes == null) return;
        if (bytes.length > 10 * 1024 * 1024) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF must be ≤ 10 MB')));
          return;
        }
        await _mediaStore?.addFromPlatformFile(
          f,
          category: 'work_doc',
          maxBytes: 10 * 1024 * 1024,
        );
        if (!mounted) return;
        setState(() {});
      } else {
        if (f.size > 10 * 1024 * 1024) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF must be ≤ 10 MB')));
          return;
        }
        await _mediaStore?.addFromPlatformFile(
          f,
          category: 'work_doc',
          maxBytes: 10 * 1024 * 1024,
        );
        if (!mounted) return;
        setState(() {});
      }
    } catch (_) {}
  }

  // Stage icon helper for dropdown items
  IconData _stageIcon(WorkStage s) {
    switch (s) {
      case WorkStage.layout:
        return CupertinoIcons.map;
      case WorkStage.plinth:
        return Icons.foundation; // Material icon
      case WorkStage.lintel:
        return Icons.architecture; // Material icon
      case WorkStage.finishing:
        return Icons.brush; // Material icon
      case WorkStage.completed:
        return CupertinoIcons.check_mark_circled;
    }
  }

  // Opens a non-editable map centered on current user location for confirmation
  Future<void> _openLocationSheet() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      // Request permission if needed
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permission denied. Please pick location on map.')));
        }
        setState(() => _mapAllowed = true);
        await _openPickOnMapSheet();
        return;
      }
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Turn on device location services or pick location on map.')));
        }
        setState(() => _mapAllowed = true);
        await _openPickOnMapSheet();
        return;
      }
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.best));
      if (!mounted) return;
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _locMethod = 'gps';
        _mapAllowed = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to get current location. Please pick on map.')));
      }
      setState(() => _mapAllowed = true);
      await _openPickOnMapSheet();
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  // Bounding box for Chhattisgarh (approx): lat 17.78 to 24.1, lon 80.22 to 84.4
  // NOTE: Duplicates removed below. See single definition further down with _openPickOnMapSheet.

  // Bounding box for Chhattisgarh (approx): lat 17.78 to 24.1, lon 80.22 to 84.4
  static const _cgMinLat = 17.78;
  static const _cgMaxLat = 24.10;
  static const _cgMinLng = 80.22;
  static const _cgMaxLng = 84.40;
  bool _isInChhattisgarh(double lat, double lng) => lat >= _cgMinLat && lat <= _cgMaxLat && lng >= _cgMinLng && lng <= _cgMaxLng;

  Future<void> _openPickOnMapSheet() async {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    LatLng? picked = (_lat != null && _lng != null) ? LatLng(_lat!, _lng!) : null;
    // Prefer project location as center when available
    final projLoc = widget.project.location;
    LatLng center = picked ?? (projLoc != null ? LatLng(projLoc.latitude, projLoc.longitude) : const LatLng(20.7072, 81.5480)); // Default: Dhamtari

    final value = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setS) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    const Icon(CupertinoIcons.map_pin),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Pick on map', style: Theme.of(ctx).textTheme.titleMedium)),
                  ]),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 260,
                    child: AppMap(
                      initialCenter: center,
                      minZoom: 6,
                      maxZoom: 18,
                      marker: picked,
                      cameraBounds: LatLngBounds.fromPoints(const [
                        LatLng(_cgMinLat, _cgMinLng),
                        LatLng(_cgMaxLat, _cgMaxLng),
                      ]),
                      onTap: (tapPos, latLng) {
                        if (_isInChhattisgarh(latLng.latitude, latLng.longitude)) {
                          setS(() => picked = latLng);
                        } else {
                          messenger.showSnackBar(const SnackBar(content: Text('Please select a location within Chhattisgarh.')));
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: picked == null ? null : () => Navigator.pop(ctx, picked),
                    child: const Text('Use location'),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );

    if (!mounted) return;
    if (value is LatLng) {
      if (_isInChhattisgarh(value.latitude, value.longitude)) {
        setState(() {
          _lat = value.latitude;
          _lng = value.longitude;
          _locMethod = 'manual';
        });
      } else {
        messenger.showSnackBar(const SnackBar(content: Text('Selected location is outside Chhattisgarh.')));
      }
    }
  }

  Future<bool> _confirmDisclaimer({required String roleKey}) async {
    // Skip for dev admin
    if (roleKey == 'dev_admin') return true;
    final accepted = await showScrollSafeDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Confirm and proceed', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          const Text(
            'I confirm the information provided is accurate to the best of my knowledge. '
            'Submitting false or misleading data may lead to rejection or action. '
            'Your update will be recorded with timestamp and may include your location.',
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              const SizedBox(width: 8),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('I understand')),
            ],
          ),
        ],
      ),
    );
    return accepted == true;
  }

  // INR formatting helpers (consistent with Details page)
  String _fmtMoneyInr(num? n) {
    final v = (n ?? 0).toDouble();
    String s = v.toStringAsFixed(0);
    String head = s.length > 3 ? s.substring(0, s.length - 3) : '';
    String tail = s.length > 3 ? s.substring(s.length - 3) : s;
    if (head.isNotEmpty) {
      final parts = <String>[];
      while (head.length > 2) {
        parts.insert(0, head.substring(head.length - 2));
        head = head.substring(0, head.length - 2);
      }
      if (head.isNotEmpty) parts.insert(0, head);
      s = '${parts.join(',')},$tail';
    } else {
      s = tail;
    }
    return '₹$s';
  }

  String _rupeesInWords(int n) {
    return AmountInWords.toRupees(n);
  }

  // Old implementation kept previously for reference is removed to avoid unused_element lint

  Map<String, dynamic> _buildPayload() {
    final payload = <String, dynamic>{};
    if (_stage != null) payload['stage'] = _stage!.name;
    Map<String, dynamic> inst(int n) {
      final amt = _iAmt[n];
      final dt = _iDate[n];
      final ramt = _iRecAmt[n];
      final rdt = _iRecDate[n];
      return {
        if (amt != null && amt.trim().isNotEmpty) 'amount': num.tryParse(amt.trim()),
        if (dt != null) 'date': Timestamp.fromDate(dt),
        if (ramt != null && ramt.trim().isNotEmpty) 'receivedAmount': num.tryParse(ramt.trim()),
        if (rdt != null) 'receivedDate': Timestamp.fromDate(rdt),
      }..removeWhere((k, v) => v == null);
    }
    final i1 = inst(1);
    final i2 = inst(2);
    final i3 = inst(3);
    if (i1.isNotEmpty) payload['installment1'] = i1;
    if (i2.isNotEmpty) payload['installment2'] = i2;
    if (i3.isNotEmpty) payload['installment3'] = i3;
    return payload;
  }

  Future<void> _save() async {
    if (_saving) return;
    // Ensure comment is required even if section is collapsed
    if (_comment == null || _comment!.trim().isEmpty) {
      setState(() => _showComment = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Comment is required')));
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }
    // Check connectivity before attempting network writes
  final statuses = await Connectivity().checkConnectivity().catchError((_) => <ConnectivityResult>[]);
  if (statuses.isEmpty || statuses.every((s) => s == ConnectivityResult.none)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You are offline. Please try again when back online.')));
      }
      return;
    }
  final payload = _buildPayload();
    // Comment + photo + location required; payload may be empty
    if (!(_comment?.trim().isNotEmpty == true)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please add a comment')));
      }
      return;
    }
    // Enforce media/location gating
    if (!(_mediaStore?.list(category: 'work_photo').isNotEmpty ?? false)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attach at least 1 photo')));
      }
      return;
    }
    if (_lat == null || _lng == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please attach your current location')));
      }
      return;
    }
    setState(() => _saving = true);
  try {
  // Re-check connectivity just before commit in case state changed
  final statuses2 = await Connectivity().checkConnectivity().catchError((_) => <ConnectivityResult>[]);
  if (statuses2.isEmpty || statuses2.every((s) => s == ConnectivityResult.none)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connection lost. Please retry when online.')));
        }
        return;
      }
  final user = await ref.read(authRepositoryProvider).currentUser();
      if (user == null) return;
  // Require explicit confirmation for non-admin roles
  final ok = await _confirmDisclaimer(roleKey: user.role.key);
  if (!ok) return;
      // Removed soft prompt: location is required by gating above
      final db = FirebaseFirestore.instance;
      // Re-read project to lock down installments already received
      final snap = await db.collection('projects').doc(widget.project.id).get();
      if (snap.exists) {
        bool received(String key) {
          final ad = (snap.data()?['allotmentDetails'] as Map<String, dynamic>?) ?? const {};
          final inst = (ad[key] as Map<String, dynamic>?) ?? const {};
          final ra = inst['receivedAmount'];
          if (ra is num) return ra > 0;
          return false;
        }
        for (final k in ['installment1', 'installment2', 'installment3']) {
          if (received(k)) payload.remove(k);
        }
      }

      // Validate installment totals vs budget
      try {
        final data = snap.data();
        final sc = (data?['sanctionCompliance'] as Map<String, dynamic>?) ?? const {};
        final budgetNum = sc['approvedAmount'];
        final double budget = budgetNum is num ? budgetNum.toDouble() : 0.0;
        if (budget > 0) {
          num readDbAmt(String key) {
            final ad = (data?['allotmentDetails'] as Map<String, dynamic>?) ?? const {};
            final inst = (ad[key] as Map<String, dynamic>?) ?? const {};
            final a = inst['amount'];
            return a is num ? a : 0;
          }
          num readPayloadAmt(String key) {
            final m = (payload[key] as Map<String, dynamic>?) ?? const {};
            final a = m['amount'];
            return a is num ? a : 0;
          }
          final total = (['installment1','installment2','installment3']).fold<num>(0, (acc, key) {
            final pa = readPayloadAmt(key);
            if (pa > 0) return acc + pa;
            return acc + readDbAmt(key);
          }).toDouble();
          if (total > budget) {
            if (mounted) {
              final over = total - budget;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Installments exceed budget by ${_fmtMoneyInr(over)}. Please adjust amounts.')));
            }
            setState(() => _saving = false);
            return;
          }
        }
      } catch (_) {
        // If budget cannot be read, skip this validation to avoid blocking user.
      }

      // Upload local-first media from DraftMediaStore
      final storage = ref.read(storageServiceProvider);
      final workPhotos = _mediaStore?.list(category: 'work_photo') ?? const <DraftMediaItem>[];
      final workDocs = _mediaStore?.list(category: 'work_doc') ?? const <DraftMediaItem>[];
      bool anyFailure = false;
      // photos
      for (final it in workPhotos) {
        final ts = DateTime.now().millisecondsSinceEpoch;
        final dest = 'projects/${widget.project.id}/photos/${ts}_${_safeName(it.name)}';
        try {
          final isJpeg = it.contentType.toLowerCase().startsWith('image/jpeg');
          final bytes = isJpeg ? image_utils.ImageUtils.compressJpeg(it.bytes, maxWidth: 1600, maxHeight: 1600, quality: 80) : it.bytes;
          setState(() { _uploadingPhotos[it.name] = 0.0; });
          await storage.uploadWithAdapter(
            path: dest,
            bytes: bytes,
            contentType: it.contentType,
            fileName: it.name,
            onProgress: (v) { if (mounted) setState(() { _uploadingPhotos[it.name] = v; }); },
          );
          if (!mounted) return;
          setState(() {
            _uploadingPhotos.remove(it.name);
            _photos.add(dest);
          });
        } catch (e) {
          anyFailure = true;
          if (mounted) {
            setState(() { _uploadingPhotos.remove(it.name); });
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to upload photo ${it.name}')));
          }
        }
      }
      // documents
      for (final it in workDocs) {
        final ts = DateTime.now().millisecondsSinceEpoch;
        final dest = 'projects/${widget.project.id}/docs/${ts}_${_safeName(it.name)}';
        try {
          setState(() { _uploadingDocs[it.name] = 0.0; });
          await storage.uploadWithAdapter(
            path: dest,
            bytes: it.bytes,
            contentType: it.contentType,
            fileName: it.name,
            onProgress: (v) { if (mounted) setState(() { _uploadingDocs[it.name] = v; }); },
          );
          if (!mounted) return;
          setState(() {
            _uploadingDocs.remove(it.name);
            _docs.add(dest);
          });
        } catch (e) {
          anyFailure = true;
          if (mounted) {
            setState(() { _uploadingDocs.remove(it.name); });
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to upload document ${it.name}')));
          }
        }
      }
      if (anyFailure) {
        // Abort save if any upload failed
        return;
      }

      // Transactional write with server-side validation for installments
      final projRef = db.collection('projects').doc(widget.project.id);
      final updateRef = projRef.collection('updates').doc();
      final notifRef = db.collection('updates').doc();

      try {
        await db.runTransaction((tx) async {
          final docSnap = await tx.get(projRef);
          final existing = docSnap.data() ?? const {};
          final ad = (existing['allotmentDetails'] as Map<String, dynamic>?) ?? const {};

          bool dbReceived(String key) {
            final inst = (ad[key] as Map<String, dynamic>?) ?? const {};
            final ra = inst['receivedAmount'];
            return ra is num && ra > 0;
          }

          Map<String, dynamic>? sanitize(String key) {
            if (dbReceived(key)) return null; // freeze installments already received
            final incoming = (payload[key] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v));
            if (incoming == null || incoming.isEmpty) return null;
            final dbInst = (ad[key] as Map<String, dynamic>?) ?? const {};
            final num? dbAmt = dbInst['amount'] is num ? dbInst['amount'] as num : null;
            // Strip amount change if predefined in DB
            if (dbAmt != null && dbAmt > 0) {
              incoming.remove('amount');
            }
            final num? newAmt = incoming['amount'] is num ? incoming['amount'] as num : null;
            final num? effectiveAmt = newAmt ?? dbAmt;
            final num? recAmt = incoming['receivedAmount'] is num ? incoming['receivedAmount'] as num : null;
            if (recAmt != null) {
              if (effectiveAmt == null || effectiveAmt <= 0) {
                throw StateError('Received amount requires a defined installment amount');
              }
              if (recAmt > effectiveAmt) {
                throw StateError('Received amount cannot exceed defined amount');
              }
            }
            return incoming;
          }

          final s1 = sanitize('installment1');
          final s2 = sanitize('installment2');
          final s3 = sanitize('installment3');

          final projUpdate = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
          if (payload['stage'] != null) {
            projUpdate['workDescription'] = {'stage': payload['stage']};
          }
          Map<String, dynamic> instMerge(String key, Map<String, dynamic>? v) {
            if (v == null || v.isEmpty) return {};
            return {'allotmentDetails': {key: v}};
          }
          projUpdate.addAll(instMerge('installment1', s1));
          projUpdate.addAll(instMerge('installment2', s2));
          projUpdate.addAll(instMerge('installment3', s3));

          // 1) Audit trail update doc
          tx.set(updateRef, {
            'type': 'details',
            'payload': {
              if (payload['stage'] != null) 'stage': payload['stage'],
              if (s1 != null && s1.isNotEmpty) 'installment1': s1,
              if (s2 != null && s2.isNotEmpty) 'installment2': s2,
              if (s3 != null && s3.isNotEmpty) 'installment3': s3,
            },
            'comment': _comment,
            'photos': _photos,
            'documents': _docs,
            'updatedBy': user.uid,
            'createdAt': FieldValue.serverTimestamp(),
            if (_lat != null && _lng != null) 'location': {'lat': _lat, 'lng': _lng},
            if (_locMethod != null) 'locationMethod': _locMethod,
          });

          // 2) Global notification
          tx.set(notifRef, {
            'type': 'status',
            'title': 'Project updated',
            'body': (_comment?.trim().isNotEmpty == true) ? _comment : 'Project fields updated',
            'projectId': widget.project.id,
            'projectName': widget.project.name,
            'ownerId': widget.project.ownerId,
            'blockId': widget.project.blockId,
            'targetRoles': ['super_nodal', 'sub_nodal'],
            'readBy': <String>[],
            'createdAt': FieldValue.serverTimestamp(),
            'updateId': updateRef.id,
          });

          // 3) Inline project doc update (merge)
          tx.set(projRef, projUpdate, SetOptions(merge: true));
        });
      } on StateError catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('StateError: ', ''))));
        }
        setState(() => _saving = false);
        return;
      } on FirebaseException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Failed to save. Please retry.')));
        }
        setState(() => _saving = false);
        return;
      }
      // NOTE: Legacy batch write block removed. Using Firestore transaction above for atomic validation and writes.

      // Clear local drafts after successful commit
      await _mediaStore?.removeByCategory('work_photo');
      await _mediaStore?.removeByCategory('work_doc');

      // Reset local form state to fresh
      setState(() {
        _comment = null;
        _stage = null;
        _lat = null;
        _lng = null;
        _locMethod = null;
        _photos.clear();
        _docs.clear();
        _activeNewInstallments.clear();
        for (final n in [1,2,3]) {
          _iAmt[n] = null;
          _iDate[n] = null;
          _iRecAmt[n] = null;
          _iRecDate[n] = null;
        }
      });

      if (!mounted) return;
      // Success dialog with countdown then redirect
      final dest = (user.role.key == 'owner') ? '/owner' : '/dashboard';
      int secs = 3;
      Timer? t;
      final result = await showScrollSafeDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return StatefulBuilder(builder: (ctx, setS) {
            t ??= Timer.periodic(const Duration(seconds: 1), (_) {
              if (secs <= 1) {
                t?.cancel();
                if (Navigator.of(ctx).canPop()) {
                  Navigator.of(ctx).pop(true);
                }
              } else {
                setS(() => secs -= 1);
              }
            });
            final cs = Theme.of(ctx).colorScheme;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle, color: cs.primary),
                    const SizedBox(width: 8),
                    const Text('Update submitted', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Redirecting in $secs…'),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        t?.cancel();
                        if (Navigator.of(ctx).canPop()) {
                          Navigator.of(ctx).pop(true);
                        }
                      },
                      child: const Text('Go now'),
                    ),
                  ],
                ),
              ],
            );
          });
        },
      );
      t?.cancel();
      if (!mounted) return;
      if (result == true) {
        context.go(dest);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Live project stream to sync installment state in real-time
    Widget contentBuilder(Project project) {
      final cs = Theme.of(context).colorScheme;
      Widget sectionTitle(IconData icon, String title) => Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(children: [Icon(icon, size: 18, color: cs.primary), const SizedBox(width: 6), Text(title, style: Theme.of(context).textTheme.titleMedium)]),
          );

      // Helper to compute allowed stage options: current and next only
      List<WorkStage> allowedStages(WorkStage? current) {
        final values = WorkStage.values;
        if (current == null) return [values.first];
        if (current == WorkStage.completed) return [WorkStage.completed];
        final idx = values.indexOf(current);
        final next = values[(idx + 1).clamp(0, values.length - 1)];
         // include current and next
         return {current, next}.toList();
      }

      // Compute gating state
      final hasComment = (_comment?.trim().length ?? 0) >= 5;
      final hasPhoto = (_mediaStore?.list(category: 'work_photo').isNotEmpty ?? false);
      final hasLocation = _lat != null && _lng != null;
      final hasUploads = _uploadingPhotos.isNotEmpty || _uploadingDocs.isNotEmpty;
      final canSubmit = hasComment && hasPhoto && hasLocation && !_saving && !hasUploads;
      final isBusy = _saving || hasUploads;

      return Stack(
        children: [
          AbsorbPointer(
            absorbing: isBusy,
            child: Form(
              key: _formKey,
               child: ListView(
                 physics: const ClampingScrollPhysics(), // Better mobile scrolling
                 padding: const EdgeInsets.all(16), // Increased padding for mobile
                 children: [
            // Stepper removed: Single-page flow
            const SizedBox.shrink(),
            // Comment
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: sectionTitle(CupertinoIcons.chat_bubble_text, 'Comment')),
                        TextButton.icon(
                          onPressed: () => setState(() => _showComment = !_showComment),
                          icon: Icon(_showComment ? CupertinoIcons.chevron_down : CupertinoIcons.chevron_right, size: 16),
                          label: Text(_showComment ? 'Collapse' : 'Expand'),
                        ),
                      ],
                    ),
                    if (_showComment) ...[
                      const SizedBox(height: 16), // Increased spacing for mobile
                      TextFormField(
                        textAlignVertical: TextAlignVertical.center,
                        controller: _commentController,
                        decoration: InputDecoration(
                          label: const RequiredLabel('Comment'),
                          prefixIcon: const Icon(CupertinoIcons.chat_bubble),
                          suffixIcon: ((_comment?.trim().length ?? 0) >= 5)
                              ? const Icon(CupertinoIcons.checkmark_circle_fill, color: Colors.green)
                              : null,
                        ),
                        minLines: 3,
                        maxLines: 6,
                        onChanged: _onCommentChanged,
                        validator: (v) {
                          final t = v?.trim() ?? '';
                          if (t.isEmpty) return 'Comment is required';
                          if (t.length < 5) return 'Comment must be at least 5 characters.';
                          return null;
                        },
                      ),
                      const SizedBox(height: 4),
                      Text('$_commentWords/100 words', style: Theme.of(context).textTheme.labelSmall),
                    ]
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16), // Better spacing between sections
            // Stage
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: sectionTitle(CupertinoIcons.settings, 'Work Stage')),
                        TextButton.icon(
                          onPressed: () => setState(() => _showStage = !_showStage),
                          icon: Icon(_showStage ? CupertinoIcons.chevron_down : CupertinoIcons.chevron_right, size: 16),
                          label: Text(_showStage ? 'Collapse' : 'Expand'),
                        ),
                      ],
                    ),
                    if (_showStage) ...[
                      const SizedBox(height: 16), // Increased spacing for mobile
                      DropdownButtonFormField<WorkStage>(
                        decoration: InputDecoration(
                          label: const RequiredLabel('Work Stage'),
                          prefixIcon: const Icon(CupertinoIcons.cube_box),
                          suffixIcon: ((_stage ?? project.workDescription.stage) != null)
                              ? const Icon(CupertinoIcons.checkmark_circle_fill, color: Colors.green)
                              : null,
                        ),
                        initialValue: _stage ?? project.workDescription.stage,
                        items: allowedStages(project.workDescription.stage).map((e) => DropdownMenuItem(
                              value: e,
                              enabled: true,
                              child: Row(children: [
                                Icon(_stageIcon(e), size: 18, color: Theme.of(context).colorScheme.primary),
                                const SizedBox(width: 8),
                                Text(e.name),
                              ]),
                            )).toList(),
                        onChanged: (v) => setState(() => _stage = v),
                        validator: (v) => v == null ? 'This field is required' : null,
                      ),
                    ]
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16), // Better spacing between sections
            // Installments
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: sectionTitle(CupertinoIcons.creditcard, 'Installments')),
                        TextButton.icon(
                          onPressed: () => setState(() => _showInstallments = !_showInstallments),
                          icon: Icon(_showInstallments ? CupertinoIcons.chevron_down : CupertinoIcons.chevron_right, size: 16),
                          label: Text(_showInstallments ? 'Collapse' : 'Expand'),
                        ),
                      ],
                    ),
                    if (_showInstallments) ...[
                      const SizedBox(height: 16), // Increased spacing for mobile
                      const SizedBox(height: 8),
                      ...() {
                        final widgets = <Widget>[];
                        final insts = {
                          1: project.allotmentDetails.installment1,
                          2: project.allotmentDetails.installment2,
                          3: project.allotmentDetails.installment3,
                        };
                        for (var n = 1; n <= 3; n++) {
                          final inst = insts[n];
                          if (inst != null) {
                            if ((inst.receivedAmount ?? 0) > 0) {
                              widgets.add(_installmentSummary(context, n, inst));
                            } else {
                              widgets.add(_installmentEditor(context, project, n, inst));
                            }
                            widgets.add(const SizedBox(height: 8));
                          } else if (_activeNewInstallments.contains(n)) {
                            widgets.add(_installmentEditor(context, project, n, null));
                            widgets.add(const SizedBox(height: 8));
                          }
                        }
                        if (widgets.isNotEmpty) widgets.removeLast();
                        return widgets;
                      }(),
                      const SizedBox(height: 8),
                      Builder(builder: (ctx) {
                        final insts = {
                          1: project.allotmentDetails.installment1,
                          2: project.allotmentDetails.installment2,
                          3: project.allotmentDetails.installment3,
                        };
                        final missing = [1, 2, 3].where((n) => insts[n] == null && !_activeNewInstallments.contains(n)).toList();
                        if (missing.isEmpty) return const SizedBox.shrink();
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final n in missing)
                                OutlinedButton.icon(
                                  onPressed: () => setState(() => _activeNewInstallments.add(n)),
                                  icon: const Icon(CupertinoIcons.add_circled),
                                  label: Text('Add Installment $n'),
                                ),
                            ],
                          ),
                        );
                      }),
                    ]
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16), // Better spacing between sections
            // Attachments & Location
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(CupertinoIcons.paperclip, size: 18, color: cs.primary),
                        const SizedBox(width: 6),
                        Expanded(child: RequiredLabel('Attachments & Location', style: Theme.of(context).textTheme.titleMedium)),
                        TextButton.icon(
                          onPressed: () => setState(() => _showAttach = !_showAttach),
                          icon: Icon(_showAttach ? CupertinoIcons.chevron_down : CupertinoIcons.chevron_right, size: 16),
                          label: Text(_showAttach ? 'Collapse' : 'Expand'),
                        ),
                      ],
                    ),
                    if (_showAttach) ...[
                      
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        FilledButton.icon(
                          onPressed: _pickPhoto,
                          icon: const Icon(CupertinoIcons.camera),
                          label: Row(children: [
                            const Text('Add Photos'),
                            if ((_mediaStore?.list(category: 'work_photo').isNotEmpty ?? false)) ...[
                              const SizedBox(width: 6),
                              const Icon(CupertinoIcons.check_mark_circled_solid, size: 16, color: Colors.green),
                            ],
                          ]),
                        ),
                        FilledButton.icon(
                          onPressed: _pickDoc,
                          icon: const Icon(CupertinoIcons.doc),
                          label: Row(children: [
                            const Text('Add PDF'),
                            if ((_mediaStore?.list(category: 'work_doc').isNotEmpty ?? false)) ...[
                              const SizedBox(width: 6),
                              const Icon(CupertinoIcons.check_mark_circled_solid, size: 16, color: Colors.green),
                            ],
                          ]),
                        ),
                        FilledButton.icon(
                          onPressed: _locating || _saving || hasUploads ? null : _openLocationSheet,
                          icon: const Icon(CupertinoIcons.location),
                          label: Row(children: [
                            Text(_locating ? 'Loading…' : 'Use current location (वर्तमान स्थान)'),
                            if (_lat != null && _lng != null && _locMethod == 'gps') ...[
                              const SizedBox(width: 6),
                              const Icon(CupertinoIcons.check_mark_circled_solid, size: 16, color: Colors.green),
                            ],
                          ]),
                        ),
                        if (_mapAllowed || _locMethod == 'manual')
                          FilledButton.icon(
                            onPressed: (_saving || hasUploads) ? null : _openPickOnMapSheet,
                            icon: const Icon(CupertinoIcons.map_pin),
                            label: Row(children: [
                              const Text('Pick on map (मानचित्र पर चुनें)'),
                              if (_lat != null && _lng != null && _locMethod == 'manual') ...[
                                const SizedBox(width: 6),
                                const Icon(CupertinoIcons.check_mark_circled_solid, size: 16, color: Colors.green),
                              ],
                            ]),
                          ),
                      ]),
                      const SizedBox(height: 6),
                      Text('Max 3 photos (≤ 3 MB each). Optional 1 PDF (≤ 10 MB).', style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 4),
                      Text('At least 1 photo is required.', style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 10),
                      if ((_mediaStore?.list(category: 'work_photo').isNotEmpty ?? false)) ...[
                        Text('Photos', style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: (_mediaStore?.list(category: 'work_photo') ?? const <DraftMediaItem>[]).expand((it) {
                            final name = it.name;
                            final prog = _uploadingPhotos[name];
                            return [
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Chip(
                                    avatar: const Icon(CupertinoIcons.photo),
                                    label: Text(name, overflow: TextOverflow.ellipsis),
                                    onDeleted: () async {
                                      await _mediaStore?.remove(it.id);
                                      if (mounted) setState(() {});
                                    },
                                  ),
                                  if (prog != null) ...[
                                    SizedBox(
                                      width: 160,
                                      child: LinearProgressIndicator(value: prog, minHeight: 4),
                                    ),
                                    const SizedBox(height: 2),
                                    Text('${(prog * 100).toStringAsFixed(0)}%', style: Theme.of(context).textTheme.labelSmall),
                                  ],
                                ],
                              ),
                            ];
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if ((_mediaStore?.list(category: 'work_doc').isNotEmpty ?? false)) ...[
                        Text('Documents', style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: (_mediaStore?.list(category: 'work_doc') ?? const <DraftMediaItem>[]).expand((it) {
                            final name = it.name;
                            final prog = _uploadingDocs[name];
                            return [
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Chip(
                                    avatar: const Icon(CupertinoIcons.doc_text),
                                    label: Text(name, overflow: TextOverflow.ellipsis),
                                    onDeleted: () async {
                                      await _mediaStore?.remove(it.id);
                                      if (mounted) setState(() {});
                                    },
                                  ),
                                  if (prog != null) ...[
                                    SizedBox(
                                      width: 200,
                                      child: LinearProgressIndicator(value: prog, minHeight: 4),
                                    ),
                                    const SizedBox(height: 2),
                                    Text('${(prog * 100).toStringAsFixed(0)}%', style: Theme.of(context).textTheme.labelSmall),
                                  ],
                                ],
                              ),
                            ];
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Row(children: [
                        Icon(CupertinoIcons.location_solid, size: 18, color: cs.primary),
                        const SizedBox(width: 6),
                        Expanded(child: Text(_lat == null || _lng == null ? 'No location attached' : 'Location attached (${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)})')),
                      ]),
                      if (_lat != null && _lng != null) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 120,
                          child: AbsorbPointer(
                            absorbing: true,
                            child: AppMap(
                              initialCenter: LatLng(_lat!, _lng!),
                              minZoom: 13,
                              maxZoom: 18,
                              marker: LatLng(_lat!, _lng!),
                              infoMessage: _locMethod == null ? null : 'Location: ${_locMethod == 'gps' ? 'current location' : 'picked on map'}',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),
            if (!canSubmit) ...[
              Row(
                children: [
                  Icon(CupertinoIcons.info, size: 18, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'To submit, please: ${[
                        if (!hasComment) 'add a comment',
                        if (!hasPhoto) 'attach at least 1 photo',
                        if (!hasLocation) 'add your location',
                        if (hasUploads) 'wait for uploads to finish',
                      ].join(', ')}.',
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            FilledButton.icon(
              onPressed: canSubmit ? (_saving ? null : _save) : null,
              icon: _saving ? const SizedBox.square(dimension: 16, child: AppLoadingIndicator(strokeWidth: 2)) : const Icon(CupertinoIcons.paperplane),
              label: const Text('Submit Update'),
              style: FilledButton.styleFrom(
                alignment: Alignment.center,
                textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                      height: 1.0,
                      leadingDistribution: TextLeadingDistribution.even,
                      textBaseline: TextBaseline.alphabetic,
                    ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
    if (isBusy)
      Positioned.fill(
        child: Container(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox.square(dimension: 36, child: AppLoadingIndicator()),
                const SizedBox(height: 12),
                Builder(builder: (_) {
                  final total = (_uploadingPhotos.length + _uploadingDocs.length).clamp(1, 999);
                  final sum = _uploadingPhotos.values.fold<double>(0, (a, b) => a + b) + _uploadingDocs.values.fold<double>(0, (a, b) => a + b);
                  final avg = total > 0 ? (sum / total).clamp(0.0, 1.0) : 0.0;
                  final hasAny = _uploadingPhotos.isNotEmpty || _uploadingDocs.isNotEmpty;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(hasAny ? 'Uploading attachments… ${(avg * 100).toStringAsFixed(0)}%' : 'Saving…'),
                      if (hasAny) ...[
                        const SizedBox(height: 8),
                        SizedBox(width: 220, child: LinearProgressIndicator(value: avg, minHeight: 6)),
                      ],
                    ],
                  );
                }),
              ],
            ),
          ),
        ),
      ),
  ],
);
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('projects').doc(widget.project.id).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && snap.data == null) {
          if (widget.embedded) {
            return const Center(child: AppLoadingIndicator(variant: AppLoadingVariant.page));
          }
          return Scaffold(
            appBar: AppBar(
              leading: IconButton(
                tooltip: 'Back',
                icon: const Icon(CupertinoIcons.back),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              title: const Text('Update Project'),
            ),
            body: const Center(child: AppLoadingIndicator(variant: AppLoadingVariant.page)),
          );
        }

        final project = (snap.data != null && snap.data!.data() != null)
            ? Project.fromDoc(snap.data!)
            : widget.project;

        final body = contentBuilder(project);
        if (widget.embedded) return body;

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: 'Back',
              icon: const Icon(CupertinoIcons.back),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: const Text('Update Project'),
          ),
          body: body,
        );
      },
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool enabled;
  final Widget? suffixIcon;
  const _DateField({required this.label, required this.value, required this.onChanged, this.enabled = true, this.suffixIcon});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled
          ? () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: value ?? now,
                firstDate: now.subtract(const Duration(days: 365)),
                lastDate: now.add(const Duration(days: 365)),
              );
              onChanged(picked);
            }
          : null,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(CupertinoIcons.calendar),
          enabled: enabled,
          suffixIcon: suffixIcon,
        ),
        child: Text(value == null ? '-' : fmtYmd(value!.toLocal())),
      ),
    );
  }
}

// Installment editor tile with lock/disable when already received
extension on _ProjectUpdateFormPageState {
  bool _hasInstallmentData(Installment? i) {
    if (i == null) return false;
    final a = i.amount ?? 0;
    final ra = i.receivedAmount ?? 0;
    return (a > 0) || (ra > 0) || i.date != null || i.receivedDate != null;
  }

  Widget _installmentSummary(BuildContext context, int n, Installment inst) {
    final cs = Theme.of(context).colorScheme;
    final title = 'Installment $n';
    final amount = inst.amount;
    final rAmt = inst.receivedAmount;
    final rDate = inst.receivedDate;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(CupertinoIcons.creditcard, size: 18),
          const SizedBox(width: 6),
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(width: 6),
          Icon(CupertinoIcons.check_mark_circled_solid, size: 14, color: cs.primary),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          const Icon(CupertinoIcons.money_dollar_circle, size: 16),
          const SizedBox(width: 6),
          Expanded(child: Text('Amount: ${amount == null ? '-' : _fmtMoneyInr(amount)}')),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          const Icon(CupertinoIcons.money_dollar, size: 16),
          const SizedBox(width: 6),
          Expanded(child: Text('Received: ${rAmt == null ? '-' : _fmtMoneyInr(rAmt)}')),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          const Icon(CupertinoIcons.calendar, size: 16),
          const SizedBox(width: 6),
          Expanded(child: Text('Received on: ${rDate == null ? '-' : fmtYmd(rDate.toLocal())}')),
        ]),
      ]),
    );
  }

  Widget _installmentEditor(BuildContext context, Project project, int n, Installment? inst) {
    return StatefulBuilder(builder: (context, sbSetState) {
      final received = (inst?.receivedAmount ?? 0) > 0;
      if (received) {
        return _installmentSummary(context, n, inst!);
      }
      final isPredefined = (inst?.amount ?? 0) > 0;
      final title = 'Installment $n';

      InputDecoration moneyDecoration(String label, String? value) {
        final raw = value?.trim();
        final num? parsed = raw == null || raw.isEmpty ? null : num.tryParse(raw);
        final helper = parsed == null ? null : '${_fmtMoneyInr(parsed)}  (${_rupeesInWords(parsed.round())})';
        final isValid = parsed != null && parsed > 0 && parsed <= 500000000;
        return InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.currency_rupee),
          helperText: helper,
          suffixIcon: isValid ? const Icon(CupertinoIcons.checkmark_circle_fill, color: Colors.green) : null,
        );
      }

      final row1 = Row(children: [
        Expanded(
          child: TextFormField(
            textAlignVertical: TextAlignVertical.center,
            enabled: !isPredefined, // Task 1: hide/disable amount when predefined
            decoration: moneyDecoration('Amount', _iAmt[n]),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r"[0-9\.]")),
              LengthLimitingTextInputFormatter(18),
            ],
            onChanged: (v) {
              final parsed = double.tryParse(v.trim());
              if (parsed != null && parsed > 500000000) {
                _iAmt[n] = '500000000';
              } else {
                _iAmt[n] = v;
              }
              sbSetState(() {});
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _DateField(
            label: 'Date',
            value: _iDate[n],
            enabled: !isPredefined, // Task 1: hide/disable declaration date when predefined
            suffixIcon: _iDate[n] != null ? const Icon(CupertinoIcons.checkmark_circle_fill, color: Colors.green) : null,
            onChanged: (d) {
              _iDate[n] = d;
              sbSetState(() {});
            },
          ),
        ),
      ]);

      final row2 = Row(children: [
        Expanded(
          child: TextFormField(
            textAlignVertical: TextAlignVertical.center,
            enabled: true,
            decoration: moneyDecoration('Received Amount', _iRecAmt[n]),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r"[0-9\.]")),
              LengthLimitingTextInputFormatter(18),
            ],
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: (v) {
              const maxRupees = 500000000;
              final s = (v ?? '').trim(); if (s.isEmpty) return null;
              final val = double.tryParse(s);
              if (val == null) return 'Enter valid amount';
              if (val > maxRupees) return 'Max ₹50,00,00,000';
              double? maxAmt;
              if (isPredefined) {
                maxAmt = (inst?.amount)?.toDouble();
              } else {
                final rawAmt = (_iAmt[n] ?? '').trim();
                maxAmt = double.tryParse(rawAmt);
              }
              if (maxAmt == null || maxAmt <= 0) return 'Define installment amount first';
              if (val > maxAmt) return 'Received cannot exceed amount (₹${_fmtMoneyInr(maxAmt)})';
              return null;
            },
            onChanged: (v) {
              final parsed = double.tryParse(v.trim());
              if (parsed != null && parsed > 500000000) {
                _iRecAmt[n] = '500000000';
              } else {
                _iRecAmt[n] = v;
              }
              sbSetState(() {});
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _DateField(
            label: 'Received Date',
            value: _iRecDate[n],
            enabled: (() {
              final s = (_iRecAmt[n] ?? '').trim();
              final v = double.tryParse(s);
              return v != null && v > 0;
            })(),
            suffixIcon: _iRecDate[n] != null ? const Icon(CupertinoIcons.checkmark_circle_fill, color: Colors.green) : null,
            onChanged: (d) {
              _iRecDate[n] = d;
              sbSetState(() {});
            },
          ),
        ),
      ]);

      // Safe removal controls for active new installments with no-orphan rule
      Widget header() {
        return Row(children: [
          const Icon(CupertinoIcons.creditcard, size: 18),
          const SizedBox(width: 6),
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
          if (inst == null)
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(CupertinoIcons.trash, size: 18),
              onPressed: () {
                // Block removal that would orphan a later installment
                final i2 = project.allotmentDetails.installment2;
                final i3 = project.allotmentDetails.installment3;
                // Removed unused has1 variable
                final has2 = _hasInstallmentData(i2) || _activeNewInstallments.contains(2);
                final has3 = _hasInstallmentData(i3) || _activeNewInstallments.contains(3);
                if ((n == 1 && (has2 || has3)) || (n == 2 && has3)) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Remove later installments first')));
                  return;
                }
                sbSetState(() {
                  _activeNewInstallments.remove(n);
                  _iAmt[n] = null; _iDate[n] = null; _iRecAmt[n] = null; _iRecDate[n] = null;
                });
              },
            ),
        ]);
      }

      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.4)),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          header(),
          const SizedBox(height: 8),
          if (!isPredefined) ...[
            row1,
            const SizedBox(height: 8),
          ],
          row2,
        ]),
      );
    });
  }
}
// ...
  // Helper to sanitize filenames for storage paths
  String _safeName(String input) {
    return input.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }
// ...
