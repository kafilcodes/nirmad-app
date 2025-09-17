import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:nirmadapp/src/shared/widgets/required_label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:nirmadapp/src/shared/widgets/app_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:nirmadapp/src/features/auth/data/auth_repository.dart';
import 'package:nirmadapp/src/shared/utils/amount_in_words.dart';
import 'package:nirmadapp/src/features/projects/data/project_repository.dart';
import 'package:nirmadapp/src/features/projects/domain/project.dart';
import 'package:nirmadapp/src/shared/utils/date_parse.dart';
import 'package:nirmadapp/src/shared/widgets/scroll_safe_dialog.dart';
import 'package:flutter/services.dart';
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
  // Stepper header state and anchors
  int _activeStep = 0;
  final _commentStepKey = GlobalKey();
  final _stageStepKey = GlobalKey();
  final _installmentsStepKey = GlobalKey();
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

  // Media
  final _photos = <String>[];
  final _docs = <String>[];

  // Location
  double? _lat;
  double? _lng;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _commentController = TextEditingController(text: _comment ?? '');
    // Preselect current project stage if available
    try {
      _stage = widget.project.workDescription.stage;
    } catch (_) {}
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _scrollToKey(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        alignment: 0.05,
      );
    }
  }

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
      if (_photos.length >= 3) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Maximum 3 photos per update')));
        }
        return;
      }
      if (kIsWeb) {
        // On web, use FilePicker with bytes and enforce 5 MB limit; store as-is
        final res = await FilePicker.platform.pickFiles(withData: true, type: FileType.image);
        final f = res?.files.single;
        if (f == null || f.bytes == null) return;
        if (f.size > 5 * 1024 * 1024) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image must be ≤ 5 MB')));
          return;
        }
        final ext = (f.extension ?? 'jpg').toLowerCase();
        final contentType = ext == 'png' ? 'image/png' : 'image/jpeg';
        final ts = DateTime.now().millisecondsSinceEpoch;
        final name = (f.name.isNotEmpty ? f.name : 'photo.$ext');
        final fullPath = 'projects/${widget.project.id}/photos/${ts}_$name';
        await ref.read(storageServiceProvider).uploadWithAdapter(path: fullPath, bytes: f.bytes!, fileName: name, contentType: contentType);
        if (!mounted) return;
        setState(() => _photos.add(fullPath));
      } else {
        final picker = ImagePicker();
        // No client-side compression; store as-is
        final img = await picker.pickImage(source: ImageSource.camera);
        if (img == null) return;
        final file = File(img.path);
        final size = await file.length();
        if (size > 5 * 1024 * 1024) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Image must be ≤ 5 MB')));
          return;
        }
        final path = await ref.read(storageServiceProvider).uploadProjectPhoto(projectId: widget.project.id, file: file);
        if (!mounted) return;
        setState(() {
          if (_photos.length < 3) {
            _photos.add(path);
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _pickDoc() async {
    try {
      if (_docs.isNotEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Only 1 PDF allowed')));
        return;
      }
      final res = await FilePicker.platform.pickFiles(withData: kIsWeb, type: FileType.custom, allowedExtensions: const ['pdf']);
      if (res == null) return;
      final f = res.files.single;
      String storagePath;
      if (kIsWeb) {
        final bytes = f.bytes;
        if (bytes == null) return;
        if (bytes.length > 20 * 1024 * 1024) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF must be ≤ 20 MB')));
          return;
        }
        final name = (f.name.isNotEmpty ? f.name : 'document').toLowerCase();
        const contentType = 'application/pdf';
        final ts = DateTime.now().millisecondsSinceEpoch;
        final fullPath = 'projects/${widget.project.id}/docs/${ts}_$name';
        await ref.read(storageServiceProvider).uploadWithAdapter(
          path: fullPath,
          bytes: bytes,
          fileName: name,
          contentType: contentType,
        );
        storagePath = fullPath;
      } else {
        final filePath = f.path;
        if (filePath == null) return;
        final file = File(filePath);
        final size = await file.length();
        if (size > 20 * 1024 * 1024) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF must be ≤ 20 MB')));
          return;
        }
        storagePath = await ref.read(storageServiceProvider).uploadProjectDoc(projectId: widget.project.id, file: file);
      }
      if (!mounted) return;
      setState(() => _docs.add(storagePath));
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
    setState(() => _locating = true);
    try {
      final perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Location permission denied'),
              action: SnackBarAction(
                label: 'Settings',
                onPressed: () { openAppSettings(); },
              ),
            ),
          );
        }
        return;
      }
      final serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Turn on device location services to continue.')),
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.best));
      if (!mounted) return;
      setState(() => _locating = false);

      final lat = pos.latitude;
      final lng = pos.longitude;
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) {
          final cs = Theme.of(ctx).colorScheme;
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        Icon(CupertinoIcons.location_solid, color: cs.primary),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Confirm your current location', style: Theme.of(ctx).textTheme.titleMedium)),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.all(Radius.circular(8)),
                      child: AppMap(
                        initialCenter: LatLng(lat, lng),
                        initialZoom: 16,
                        minZoom: 8,
                        maxZoom: 19,
                        flags: (InteractiveFlag.drag | InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom | InteractiveFlag.scrollWheelZoom),
                        marker: LatLng(lat, lng),
                        showAttribution: false,
                        cameraBounds: LatLngBounds.fromPoints(const [
                          LatLng(-85.0, -180.0), // SW world
                          LatLng(85.0, 180.0),   // NE world
                        ]),
                        infoMessage: 'Map is locked to your current location for confirmation.',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
                    child: Row(
                      children: [
                        Text('(${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)})', style: Theme.of(ctx).textTheme.bodySmall),
                        const Spacer(),
                        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          icon: const Icon(CupertinoIcons.plus_app),
                          label: const Text('Attach'),
                        ),
                      ],
                    ),
                  )
                ],
              ),
            ),
          );
        },
      );
      if (confirmed == true && mounted) {
        setState(() {
          _lat = lat;
          _lng = lng;
        });
       }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to get location')));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
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
    final hasContent = payload.isNotEmpty || (_comment?.trim().isNotEmpty == true) || _photos.isNotEmpty || _docs.isNotEmpty || (_lat != null && _lng != null);
    if (!hasContent) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nothing to submit')));
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
      // Soft prompt if submitting without location
      if (_lat == null || _lng == null) {
        if (!mounted) return;
        final proceed = await showScrollSafeDialog<bool>(
          context: context,
          builder: (ctx) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Submit without location?', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              const Text('Including your current location helps nodal officers verify work. You can still proceed without it.'),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Add location')),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Proceed')),
                ],
              ),
            ],
          ),
        );
        if (proceed != true) return;
      }
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

      // Batch all writes for atomicity and fewer roundtrips
      final batch = db.batch();

      // 1) Project update doc (audit trail)
      final updateRef = db.collection('projects').doc(widget.project.id).collection('updates').doc();
      batch.set(updateRef, {
        'type': 'details',
        'payload': payload,
        'comment': _comment,
        'photos': _photos,
        'documents': _docs,
        'updatedBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        if (_lat != null && _lng != null) 'location': {'lat': _lat, 'lng': _lng},
      });

      // 2) Global notification for nodals
      final notifRef = db.collection('updates').doc();
      batch.set(notifRef, {
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

      // 3) Inline project doc update always (request flow removed)
      if (payload.isNotEmpty) {
        final projRef = db.collection('projects').doc(widget.project.id);
        final data = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
        if (payload['stage'] != null) {
          data['workDescription'] = {
            'stage': payload['stage'],
          };
        }
        Map<String, dynamic> instMerge(String key) {
          final v = payload[key] as Map<String, dynamic>?;
          if (v == null || v.isEmpty) return {};
          return {'allotmentDetails': {key: v}};
        }
        data.addAll(instMerge('installment1'));
        data.addAll(instMerge('installment2'));
        data.addAll(instMerge('installment3'));
        batch.set(projRef, data, SetOptions(merge: true));
      }

      await batch.commit();

      if (!mounted) return;
      Navigator.of(context).pop(true);
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

      return Form(
        key: _formKey,
        child: ListView(
          physics: const ClampingScrollPhysics(), // Better mobile scrolling
          padding: const EdgeInsets.all(16), // Increased padding for mobile
          children: [
            // Native Flutter Stepper for consistency
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Stepper(
                type: StepperType.vertical,
                currentStep: _activeStep,
                onStepTapped: (i) {
                  setState(() => _activeStep = i);
                  final keys = [_commentStepKey, _stageStepKey, _installmentsStepKey];
                  if (i >= 0 && i < keys.length) _scrollToKey(keys[i]);
                },
                controlsBuilder: (context, details) {
                  return const SizedBox.shrink(); // No controls needed
                },
                steps: const [
                  Step(
                    title: Text('Comment'),
                    content: SizedBox.shrink(),
                  ),
                  Step(
                    title: Text('Stage'),
                    content: SizedBox.shrink(),
                  ),
                  Step(
                    title: Text('Installments'),
                    content: SizedBox.shrink(),
                  ),
                ],
              ),
            ),
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
                        Expanded(child: KeyedSubtree(key: _commentStepKey, child: sectionTitle(CupertinoIcons.chat_bubble_text, 'Comment'))),
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
                        decoration: const InputDecoration(
                          labelText: 'Comment',
                          prefixIcon: Icon(CupertinoIcons.chat_bubble),
                        ),
                        minLines: 1,
                        maxLines: 6,
                        onChanged: _onCommentChanged,
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
                        Expanded(child: KeyedSubtree(key: _stageStepKey, child: sectionTitle(CupertinoIcons.settings, 'Work Stage'))),
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
                        decoration: const InputDecoration(
                          label: RequiredLabel('Work Stage'),
                          prefixIcon: Icon(CupertinoIcons.cube_box),
                        ),
                        initialValue: _stage ?? project.workDescription.stage,
                        items: allowedStages(project.workDescription.stage).map((e) => DropdownMenuItem(
                              value: e,
                              child: Row(children: [
                                Icon(_stageIcon(e), size: 18),
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
                        Expanded(child: KeyedSubtree(key: _installmentsStepKey, child: sectionTitle(CupertinoIcons.creditcard, 'Installments'))),
                        TextButton.icon(
                          onPressed: () => setState(() => _showInstallments = !_showInstallments),
                          icon: Icon(_showInstallments ? CupertinoIcons.chevron_down : CupertinoIcons.chevron_right, size: 16),
                          label: Text(_showInstallments ? 'Collapse' : 'Expand'),
                        ),
                      ],
                    ),
                    if (_showInstallments) ...[
                      const SizedBox(height: 16), // Increased spacing for mobile
                      _installmentEditor(context, project, 1, project.allotmentDetails.installment1),
                      const SizedBox(height: 8),
                      _installmentEditor(context, project, 2, project.allotmentDetails.installment2),
                      const SizedBox(height: 8),
                      _installmentEditor(context, project, 3, project.allotmentDetails.installment3),
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
                        Expanded(child: Text('Attachments & Location', style: Theme.of(context).textTheme.titleMedium)),
                        TextButton.icon(
                          onPressed: () => setState(() => _showAttach = !_showAttach),
                          icon: Icon(_showAttach ? CupertinoIcons.chevron_down : CupertinoIcons.chevron_right, size: 16),
                          label: Text(_showAttach ? 'Collapse' : 'Expand'),
                        ),
                      ],
                    ),
                    if (_showAttach) ...[
                      sectionTitle(CupertinoIcons.paperclip, 'Attachments & Location'),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        FilledButton.icon(onPressed: _pickPhoto, icon: const Icon(CupertinoIcons.camera), label: const Text('Add Photos')),
                        FilledButton.icon(onPressed: _pickDoc, icon: const Icon(CupertinoIcons.doc), label: const Text('Add PDF')),
                        FilledButton.icon(onPressed: _locating ? null : _openLocationSheet, icon: const Icon(CupertinoIcons.location), label: Text(_locating ? 'Loading…' : 'Use location')),
                      ]),
                      const SizedBox(height: 10),
                      if (_photos.isNotEmpty) ...[
                        Text('Photos', style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _photos.map((p) {
                            final name = p.split('/').last;
                            return Chip(
                              avatar: const Icon(CupertinoIcons.camera),
                              label: Text(name, overflow: TextOverflow.ellipsis),
                              onDeleted: () => setState(() => _photos.remove(p)),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (_docs.isNotEmpty) ...[
                        Text('Documents', style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _docs.map((p) {
                            final name = p.split('/').last;
                            return Chip(
                              avatar: const Icon(CupertinoIcons.doc_text),
                              label: Text(name, overflow: TextOverflow.ellipsis),
                              onDeleted: () => setState(() => _docs.remove(p)),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Row(children: [
                        Icon(CupertinoIcons.location_solid, size: 18, color: cs.primary),
                        const SizedBox(width: 6),
                        Expanded(child: Text(_lat == null || _lng == null ? 'No location attached' : 'Location attached (${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)})')),
                      ]),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(CupertinoIcons.paperplane),
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
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('projects').doc(widget.project.id).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && snap.data == null) {
          if (widget.embedded) {
            return const Center(child: CircularProgressIndicator());
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
            body: const Center(child: CircularProgressIndicator()),
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
  const _DateField({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: now.subtract(const Duration(days: 365)),
          lastDate: now.add(const Duration(days: 365)),
        );
        onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, prefixIcon: const Icon(CupertinoIcons.calendar)),
        child: Text(value == null ? '-' : fmtYmd(value!.toLocal())),
      ),
    );
  }
}

// Installment editor tile with lock/disable when already received
extension on _ProjectUpdateFormPageState {
  Widget _installmentEditor(BuildContext context, Project project, int n, Installment? inst) {
    return StatefulBuilder(builder: (context, sbSetState) {
      final received = (inst?.receivedAmount ?? 0) > 0;
      final lockIcon = received ? const Icon(CupertinoIcons.lock_fill, size: 16) : const SizedBox.shrink();
      final title = 'Installment $n';
      final amtStr = inst?.amount == null ? null : _fmtMoneyInr(inst!.amount);
      final amtLine = amtStr == null ? null : '$amtStr  •  ${_rupeesInWords((inst!.amount ?? 0).round())}';
      final hintStyle = Theme.of(context).textTheme.labelSmall;

      InputDecoration moneyDecoration(String label, String? value) => InputDecoration(
            labelText: label,
            prefixIcon: const Icon(Icons.currency_rupee),
            helperText: (() {
              final raw = value?.trim();
              final num? parsed = raw == null || raw.isEmpty ? null : num.tryParse(raw);
              if (parsed == null) return null;
              return '${_fmtMoneyInr(parsed)}  (${_rupeesInWords(parsed.round())})';
            })(),
          );

      final disabled = received;
      final row1 = Row(children: [
        Expanded(
          child: TextFormField(
            textAlignVertical: TextAlignVertical.center,
            enabled: !disabled,
            decoration: moneyDecoration('Amount', _iAmt[n]),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r"[0-9\.]")),
              LengthLimitingTextInputFormatter(18),
            ],
            onChanged: (v) {
              // Enforce ₹50 crores max
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
            onChanged: disabled
                ? (_) {}
                : (d) {
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
            enabled: !disabled,
            decoration: moneyDecoration('Received Amount', _iRecAmt[n]),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r"[0-9\.]")),
              LengthLimitingTextInputFormatter(18),
            ],
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
            onChanged: disabled
                ? (_) {}
                : (d) {
                    _iRecDate[n] = d;
                    sbSetState(() {});
                  },
          ),
        ),
      ]);

      return Container(
        decoration: BoxDecoration(
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
            if (received) ...[
              const SizedBox(width: 6),
              Chip(avatar: const Icon(CupertinoIcons.check_mark, size: 14), label: const Text('Received'), visualDensity: VisualDensity.compact),
            ],
            const Spacer(),
            lockIcon,
          ]),
          if (amtLine != null) Padding(padding: const EdgeInsets.only(top: 4, left: 2), child: Text(amtLine, style: hintStyle)),
          const SizedBox(height: 8),
          row1,
          const SizedBox(height: 8),
          row2,
        ]),
      );
    });
  }
}
