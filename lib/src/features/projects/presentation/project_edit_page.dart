import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
 import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import '../../projects/data/project_repository.dart';
import '../../../services/storage_service.dart';
import 'package:toastification/toastification.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import '../../../shared/data/blocks_provider.dart';
import '../../../shared/widgets/date_form_field.dart';
import '../domain/project.dart';
import '../../../shared/navigation/unsaved_changes_guard.dart';
import '../../../shared/widgets/attachment_button.dart';

class ProjectEditorPage extends ConsumerStatefulWidget {
  final String projectId;
  const ProjectEditorPage({super.key, required this.projectId});

  @override
  ConsumerState<ProjectEditorPage> createState() => _ProjectEditPageState();
}

class _ProjectEditPageState extends ConsumerState<ProjectEditorPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _desc = TextEditingController();
  
  // Dirty tracking uses ValueNotifier to avoid rebuilding the whole page on each keystroke
  final ValueNotifier<bool> _dirtyN = ValueNotifier<bool>(false);
  String? _blockId;
  String? _villageId;
  ProjectStatus _status = ProjectStatus.in_progress;
  int _phase = 0;
  bool _saving = false;
  bool _dirty = false;
  bool _suppressDirty = false;
  bool _seeded = false;
  // Owner edit gating
  String _ownerId = '';
  bool _ownerEditMode = false;
  // Section expand/collapse
  bool _expPrelim = false;
  bool _expSanc = false;
  bool _expAllot = false;
  bool _expWork = false;
  Future<void>? _loadFuture;

  // Location & photos
  GeoPoint? _location;
  final _photoUrls = <String>[];
  // Bounding box for Chhattisgarh (approx): lat 17.78 to 24.1, lon 80.22 to 84.4
  static const _cgMinLat = 17.78;
  static const _cgMaxLat = 24.10;
  static const _cgMinLng = 80.22;
  static const _cgMaxLng = 84.40;

  // Section 1: Preliminary
  final _sarpanchName = TextEditingController();
  final _sarpanchMobile = TextEditingController();
  final _gramPanchayat = TextEditingController();
  final _secretaryName = TextEditingController();
  final _secretaryMobile = TextEditingController();
  final _subEngineerName = TextEditingController();
  final _subEngineerMobile = TextEditingController();

  // Section 2: Sanction & Compliance
  final _sanctionDeptId = TextEditingController();
  final _sanctionDeptName = TextEditingController();
  final _techApprovalNo = TextEditingController();
  final _techApprovalDate = TextEditingController(); // YYYY-MM-DD
  final _adminApprovalNo = TextEditingController();
  final _adminApprovalDate = TextEditingController(); // YYYY-MM-DD
  final _schemeId = TextEditingController();
  final _schemeName = TextEditingController();
  final _itemId = TextEditingController();
  final _itemName = TextEditingController();
  final _planHeadId = TextEditingController();
  final _planHeadName = TextEditingController();
  final _approvedAmount = TextEditingController();
  final _approvalDocs = <String>[];

  // Section 3: Allotment Details
  final _inst1Amount = TextEditingController();
  final _inst1Date = TextEditingController();
  final _inst1RecvAmount = TextEditingController();
  final _inst1RecvDate = TextEditingController();
  final _inst2Amount = TextEditingController();
  final _inst2Date = TextEditingController();
  final _inst2RecvAmount = TextEditingController();
  final _inst2RecvDate = TextEditingController();
  final _inst3Amount = TextEditingController();
  final _inst3Date = TextEditingController();
  final _inst3RecvAmount = TextEditingController();
  final _inst3RecvDate = TextEditingController();
  final _bankId = TextEditingController();
  final _bankName = TextEditingController();
  final _bankAccount = TextEditingController();
  final _bankBranch = TextEditingController();
  final _bankIfsc = TextEditingController();

  // Section 4: Work Description
  final _workStartDate = TextEditingController();
  final _workEndDate = TextEditingController();
  WorkStage? _workStage;
  ApramStatus? _apramStatus;
  final _mbUrls = <String>[];
  final _testUrls = <String>[];
  final _workReportUrls = <String>[];
  final _certificateUrls = <String>[];

  // Cross-field helpers: parse amounts and validate installment totals vs Approved Amount
  double? _parseMoney(String s) {
    final v = s.trim();
    if (v.isEmpty) return null;
    final d = double.tryParse(v.replaceAll(',', ''));
    return d;
  }

  String? _sumValidationMessage() {
    final ap = _parseMoney(_approvedAmount.text);
    if (ap == null) return null; // can't compare if Approved not set
    final i1 = _parseMoney(_inst1Amount.text) ?? 0.0;
    final i2 = _parseMoney(_inst2Amount.text) ?? 0.0;
    final i3 = _parseMoney(_inst3Amount.text) ?? 0.0;
    final sum = i1 + i2 + i3;
    if (sum > ap + 1e-9) {
      // Format using Indian digit grouping for clarity
      final sumInt = sum.floor();
      final apInt = ap.floor();
      return 'Installments total ₹${_indianGrouping(sumInt)} exceeds Approved ₹${_indianGrouping(apInt)}';
    }
    return null;
  }

  Future<bool> _confirmDisclaimer() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm and proceed'),
        content: const Text(
          'I confirm the information provided is accurate to the best of my knowledge. '
          'Submitting false or misleading data may lead to rejection or action. '
          'Your changes will be recorded with timestamp.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('I understand')),
        ],
      ),
    );
    return res == true;
  }

  @override
  void initState() {
    super.initState();
    // Register global unsaved-changes guard so sidebar/tab navigations prompt too
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final guard = ref.read(unsavedChangesGuardProvider);
      guard.register(() async {
        if (!_dirty || _saving) return true;
        return await _onWillPop();
      });
    });
    void mark() {
      if (!_suppressDirty) {
        _dirty = true;
        _dirtyN.value = true;
      }
    }
    for (final c in [
      _name,
      _desc,
      _sarpanchName,
      _sarpanchMobile,
      _gramPanchayat,
      _secretaryName,
      _secretaryMobile,
      _subEngineerName,
      _subEngineerMobile,
      _sanctionDeptId,
      _sanctionDeptName,
      _techApprovalNo,
      _techApprovalDate,
      _adminApprovalNo,
      _adminApprovalDate,
      _schemeId,
      _schemeName,
      _itemId,
      _itemName,
      _planHeadId,
      _planHeadName,
      _approvedAmount,
      _inst1Amount,
      _inst1Date,
      _inst1RecvAmount,
      _inst1RecvDate,
      _inst2Amount,
      _inst2Date,
      _inst2RecvAmount,
      _inst2RecvDate,
      _inst3Amount,
      _inst3Date,
      _inst3RecvAmount,
      _inst3RecvDate,
      _bankId,
      _bankName,
      _bankAccount,
      _bankBranch,
      _bankIfsc,
      _workStartDate,
  _workEndDate,
    ]) {
      c.addListener(mark);
    }
  // Load once from server and seed controllers outside build
  _loadFuture = _resetFromServer();
  }

  Future<void> _resetFromServer() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('projects').doc(widget.projectId).get();
      if (!snap.exists) return;
      final data = (snap.data() ?? <String, dynamic>{});
  _applyData(data);
    } catch (_) {
      // ignore
    }
  }

  void _applyData(Map<String, dynamic> data) {
    setState(() {
      _suppressDirty = true;
      _name.text = (data['name'] as String?) ?? '';
      _desc.text = (data['description'] as String?) ?? '';
  _ownerId = (data['ownerId'] as String?) ?? '';
      _blockId = (data['blockId'] as String?);
      if (_blockId == 'magarload') _blockId = 'magarlod';
      _villageId = (data['villageId'] as String?);
      final s = data['status'] as String?;
      if (s != null) {
        final safe = s == 'draft' ? 'in_progress' : s;
        _status = ProjectStatus.values.firstWhere((e) => e.name == safe, orElse: () => ProjectStatus.in_progress);
      }
      _phase = ((data['phase'] as num?)?.toInt() ?? 0);
  _location = data['location'] as GeoPoint?;

      final prelim = (data['preliminaryDescription'] as Map<String, dynamic>?) ?? const {};
      _sarpanchName.text = (prelim['sarpanchName'] as String?) ?? '';
      _sarpanchMobile.text = (prelim['sarpanchMobile'] as String?) ?? '';
      _gramPanchayat.text = (prelim['gramPanchayat'] as String?) ?? '';
      _secretaryName.text = (prelim['secretaryName'] as String?) ?? '';
      _secretaryMobile.text = (prelim['secretaryMobile'] as String?) ?? '';
      _subEngineerName.text = (prelim['subEngineerName'] as String?) ?? '';
      _subEngineerMobile.text = (prelim['subEngineerMobile'] as String?) ?? '';

      final sanc = (data['sanctionCompliance'] as Map<String, dynamic>?) ?? const {};
      _sanctionDeptId.text = (sanc['sanctioningDepartmentId'] as String?) ?? '';
      _sanctionDeptName.text = (sanc['sanctioningDepartmentName'] as String?) ?? '';
      _techApprovalNo.text = (sanc['technicalApprovalNo'] as String?) ?? '';
      final ta = sanc['technicalApprovalDate'];
      _techApprovalDate.text = ta is Timestamp ? _fmt(ta.toDate()) : '';
      _adminApprovalNo.text = (sanc['adminApprovalNo'] as String?) ?? '';
      final aa = sanc['adminApprovalDate'];
      _adminApprovalDate.text = aa is Timestamp ? _fmt(aa.toDate()) : '';
      _schemeId.text = (sanc['schemeId'] as String?) ?? '';
      _schemeName.text = (sanc['schemeName'] as String?) ?? '';
      _itemId.text = (sanc['itemId'] as String?) ?? '';
      _itemName.text = (sanc['itemName'] as String?) ?? '';
      _planHeadId.text = (sanc['planHeadId'] as String?) ?? '';
      _planHeadName.text = (sanc['planHeadName'] as String?) ?? '';
      _approvedAmount.text = (sanc['approvedAmount'] is num) ? (sanc['approvedAmount']).toString() : '';
      _approvalDocs
        ..clear()
        ..addAll(((sanc['approvalDocumentUrls'] as List?) ?? const []).whereType<String>());

      void setInst(Map<String, dynamic>? m, TextEditingController a, TextEditingController d, TextEditingController ra, TextEditingController rd) {
        final mm = m ?? const {};
        a.text = (mm['amount'] is num) ? (mm['amount']).toString() : '';
        d.text = (mm['date'] is Timestamp) ? _fmt((mm['date'] as Timestamp).toDate()) : '';
        ra.text = (mm['receivedAmount'] is num) ? (mm['receivedAmount']).toString() : '';
        rd.text = (mm['receivedDate'] is Timestamp) ? _fmt((mm['receivedDate'] as Timestamp).toDate()) : '';
      }
      final allot = (data['allotmentDetails'] as Map<String, dynamic>?) ?? const {};
      setInst(allot['installment1'] as Map<String, dynamic>?, _inst1Amount, _inst1Date, _inst1RecvAmount, _inst1RecvDate);
      setInst(allot['installment2'] as Map<String, dynamic>?, _inst2Amount, _inst2Date, _inst2RecvAmount, _inst2RecvDate);
      setInst(allot['installment3'] as Map<String, dynamic>?, _inst3Amount, _inst3Date, _inst3RecvAmount, _inst3RecvDate);
      final bank = (allot['bankDetails'] as Map<String, dynamic>?) ?? const {};
      _bankId.text = (bank['bankId'] as String?) ?? '';
      _bankName.text = (bank['bankName'] as String?) ?? '';
      _bankAccount.text = (bank['accountNumber'] as String?) ?? '';
      _bankBranch.text = (bank['branch'] as String?) ?? '';
      _bankIfsc.text = (bank['ifsc'] as String?) ?? '';

      final work = (data['workDescription'] as Map<String, dynamic>?) ?? const {};
      _workStartDate.text = (work['startDate'] is Timestamp) ? _fmt((work['startDate'] as Timestamp).toDate()) : '';
  _workEndDate.text = (work['endDate'] is Timestamp) ? _fmt((work['endDate'] as Timestamp).toDate()) : '';
      final ss = work['stage'] as String?;
      _workStage = ss != null ? WorkStage.values.firstWhere((e) => e.name == ss, orElse: () => WorkStage.layout) : null;
      final as = work['apramStatus'] as String?;
      _apramStatus = as != null ? ApramStatus.values.firstWhere((e) => e.name == as, orElse: () => ApramStatus.incomplete) : null;
      _mbUrls..clear()..addAll(((work['measurementBookUrls'] as List?) ?? const []).whereType<String>());
      _testUrls..clear()..addAll(((work['testReportUrls'] as List?) ?? const []).whereType<String>());
      _workReportUrls..clear()..addAll(((work['workReportUrls'] as List?) ?? const []).whereType<String>());
      _certificateUrls..clear()..addAll(((work['certificateUrls'] as List?) ?? const []).whereType<String>());

      // Media
      _photoUrls
        ..clear()
        ..addAll(((data['photoUrls'] as List?) ?? const []).whereType<String>());

      _dirty = false;
      _suppressDirty = false;
  _seeded = true;
    });
  }

  Future<bool> _onWillPop() async {
    if (!_dirty || _saving) return true;
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children:[const Icon(CupertinoIcons.exclamationmark_triangle, color: Colors.amber), const SizedBox(width: 8), const Text('Discard changes?')]),
        content: const Text('You have unsaved edits. This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Keep editing')),
          FilledButton.icon(onPressed: () => Navigator.of(ctx).pop(true), icon: const Icon(CupertinoIcons.trash), label: const Text('Discard')),
        ],
      ),
    );
    return res == true;
  }

  // Permissions + pickers
  Future<void> _useMyLocation() async {
    try {
      LocationPermission p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p == LocationPermission.deniedForever || p == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Location permission denied'),
              action: SnackBarAction(
                label: 'Settings',
                onPressed: () {
                  openAppSettings();
                },
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
      final pos = await Geolocator.getCurrentPosition().timeout(const Duration(seconds: 12));
      final lat = pos.latitude, lng = pos.longitude;
      if (!_isInChhattisgarh(lat, lng)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a location within Chhattisgarh.')));
        }
        return;
      }
      setState(() { _location = GeoPoint(lat, lng); _dirty = true; });
    } on TimeoutException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location timed out. Try again.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Location failed: $e')));
    }
  }

  Future<void> _pickOnMap() async {
    ll.LatLng? picked = _location == null ? null : ll.LatLng(_location!.latitude, _location!.longitude);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        ll.LatLng center = picked ?? const ll.LatLng(20.5937, 78.9629); // India approx
        return StatefulBuilder(builder: (context, setS) {
          return Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.6,
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: center,
                      initialZoom: 12,
                      cameraConstraint: CameraConstraint.contain(bounds: LatLngBounds.fromPoints([
                        const ll.LatLng(6.0, 68.0), // SW India approx
                        const ll.LatLng(36.0, 97.5), // NE India approx
                      ])),
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom,
                      ),
                      onPositionChanged: (pos, hasGesture) {
                        // Soft guard present via cameraConstraint; no-op here to appease lints
                      },
                      onTap: (tapPos, latLng) {
                        if (_isInChhattisgarh(latLng.latitude, latLng.longitude)) {
                          setS(() => picked = latLng);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pick a point within Chhattisgarh.')));
                        }
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                        subdomains: const ['a','b','c','d'],
                        userAgentPackageName: 'com.example.nirmadapp',
                      ),
                      const RichAttributionWidget(
                        attributions: [
                          TextSourceAttribution('© OpenStreetMap contributors'),
                          TextSourceAttribution('© CARTO'),
                        ],
                        alignment: AttributionAlignment.bottomRight,
                      ),
                      if (picked != null)
                        MarkerLayer(markers: [
                          Marker(point: picked!, child: const Icon(CupertinoIcons.map_pin, color: Colors.red, size: 28)),
                        ]),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                  const Spacer(),
                  FilledButton(onPressed: picked == null ? null : () { Navigator.pop(context, picked); }, child: const Text('Use location')),
                ]),
              ],
            ),
          );
        });
      },
    ).then((value) {
      if (value is ll.LatLng) {
        if (_isInChhattisgarh(value.latitude, value.longitude)) {
          setState(() { _location = GeoPoint(value.latitude, value.longitude); _dirty = true; });
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selected location is outside Chhattisgarh.')));
          }
        }
      }
    });
  }

  bool _isInChhattisgarh(double lat, double lng) {
    return lat >= _cgMinLat && lat <= _cgMaxLat && lng >= _cgMinLng && lng <= _cgMaxLng;
  }

  // Resolve storage paths to public URLs if needed
  Future<String?> _resolvePublic(String url) async {
    if (url.startsWith('http')) return url;
    try {
      final storage = ref.read(storageServiceProvider);
      return await storage.getDownloadURL(url);
    } catch (_) {
      return null;
    }
  }

  // _launch removed: we now preview in-app and use DownloadButton for saving/opening.

  @override
  void dispose() {
  // Clear global guard if this page registered it
  try { ref.read(unsavedChangesGuardProvider).clear(); } catch (_) {}
    _name.dispose();
    _desc.dispose();
  _sarpanchName.dispose();
  _sarpanchMobile.dispose();
  _gramPanchayat.dispose();
  _secretaryName.dispose();
  _secretaryMobile.dispose();
  _subEngineerName.dispose();
  _subEngineerMobile.dispose();
  _sanctionDeptId.dispose();
  _sanctionDeptName.dispose();
  _techApprovalNo.dispose();
  _techApprovalDate.dispose();
  _adminApprovalNo.dispose();
  _adminApprovalDate.dispose();
  _schemeId.dispose();
  _schemeName.dispose();
  _itemId.dispose();
  _itemName.dispose();
  _planHeadId.dispose();
  _planHeadName.dispose();
  _approvedAmount.dispose();
  _inst1Amount.dispose();
  _inst1Date.dispose();
  _inst1RecvAmount.dispose();
  _inst1RecvDate.dispose();
  _inst2Amount.dispose();
  _inst2Date.dispose();
  _inst2RecvAmount.dispose();
  _inst2RecvDate.dispose();
  _inst3Amount.dispose();
  _inst3Date.dispose();
  _inst3RecvAmount.dispose();
  _inst3RecvDate.dispose();
  _bankId.dispose();
  _bankName.dispose();
  _bankAccount.dispose();
  _bankBranch.dispose();
  _bankIfsc.dispose();
  _workStartDate.dispose();
  _workEndDate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
  final user = ref.watch(authStateProvider).value;
  final isDevAdmin = user?.role == UserRole.devAdmin;
  final isSuper = user?.role == UserRole.superNodal;
  final isSub = user?.role == UserRole.subNodal;
  final isNodal = user != null && (isSuper == true || isSub == true);
  // Only Dev Admin can edit basic details. Nodal roles are read-only for basics.
  final canEditAll = (isDevAdmin == true);
  final canEditLimited = isNodal; // may edit certain non-basic fields (e.g., stage/description)
    final blocks = ref.watch(blocksListProvider);
  final isOwner = user != null && user.role == UserRole.projectOwner && user.uid == _ownerId;
  final fieldsAll = canEditAll && !_saving;
    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final ok = await _onWillPop();
        if (ok && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
      appBar: AppBar(
  title: const Text('Edit Project (परियोजना संपादित करें)'),
        actions: [
          if (isOwner) ...[
            Row(children:[
              const Text('Edit mode'),
              const SizedBox(width: 8),
              Switch(
                value: _ownerEditMode,
                onChanged: _saving ? null : (v) async {
                  if (v && !_ownerEditMode) {
                    final ok = await _confirmDisclaimer();
                    if (!ok) return;
                  }
                  setState(() => _ownerEditMode = v);
                },
              ),
              const SizedBox(width: 8),
            ]),
          ],
          TextButton.icon(
            onPressed: _saving ? null : () async {
              if (_dirty) {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Reset changes?'),
                    content: const Text('Reload last saved data and discard your edits?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Reset')),
                    ],
                  ),
                );
                if (ok != true) return;
              }
              await _resetFromServer();
            },
            icon: const Icon(CupertinoIcons.arrow_counterclockwise),
            label: const Text('Reset'),
          ),
        ],
      ),
      body: Stack(children:[
        FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snap) {
          if (!_seeded) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            // Not found or failed: show minimal fallback
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(CupertinoIcons.exclamationmark_triangle, size: 32),
                  const SizedBox(height: 12),
                  const Text('Failed to load project or it was removed.'),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: () => Navigator.maybePop(context), child: const Text('Back')),
                ],
              ),
            );
          }
          // owner gating handled via _ownerEditMode and isOwner flags
          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Card(
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        children: [
                          TextFormField(
                            textAlignVertical: TextAlignVertical.center,
                            controller: _name,
                            decoration: _reqDecoration('Project name (परियोजना का नाम)', const Icon(CupertinoIcons.doc_text)),
                            textCapitalization: TextCapitalization.sentences,
                            inputFormatters: [
                              // Match create form pattern and limit
                              FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z0-9\s\-\,\./\u0900-\u097F]")),
                              LengthLimitingTextInputFormatter(80),
                            ],
                            validator: canEditAll
                                ? (v) {
                                    final t = (v ?? '').trim();
                                    if (t.isEmpty) return 'Required';
                                    if (t.length < 3) return 'Enter at least 3 characters';
                                    return null;
                                  }
                                : null,
                            enabled: fieldsAll,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            textAlignVertical: TextAlignVertical.center,
                            controller: _desc,
                            decoration: const InputDecoration(
                              labelText: 'Description (विवरण)',
                              prefixIcon: Icon(CupertinoIcons.text_justify),
                            ),
                            maxLines: 3,
                            enabled: ((isDevAdmin) || isNodal || (isOwner && _ownerEditMode)) && !_saving,
                            onChanged: (_) {
                              _dirty = true;
                              _dirtyN.value = true;
                            },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: blocks.any((label) => label.toLowerCase().trim() == _blockId) ? _blockId : null,
                            isExpanded: true,
                            decoration: _reqDecoration('Block (ब्लॉक)', const Icon(CupertinoIcons.map_pin_ellipse)),
                            items: [
                              ...blocks.map((label) {
                                final id = label.toLowerCase().trim();
                                return DropdownMenuItem(value: id, child: Text(label));
                              }),
                            ],
                            validator: canEditAll ? (v) => (v == null || v.isEmpty) ? 'Select Block' : null : null,
                            onChanged: fieldsAll
                                ? (v) {
                                    _blockId = v;
                                    _dirty = true;
                                    _dirtyN.value = true;
                                    setState(() {}); // local rebuild for field value
                                  }
                                : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            textAlignVertical: TextAlignVertical.center,
                            initialValue: _villageId,
                            onChanged: (v) { _villageId = v; _dirty = true; _dirtyN.value = true; },
                            decoration: _reqDecoration('Village (गाँव)', const Icon(CupertinoIcons.house_alt)),
                            textCapitalization: TextCapitalization.words,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z\s\-\.\u0900-\u097F]")),
                              LengthLimitingTextInputFormatter(60),
                            ],
                            validator: canEditAll ? (v) => (v == null || v.trim().isEmpty) ? 'Enter Village' : null : null,
                            enabled: fieldsAll,
                          ),
                          const SizedBox(height: 12),
                          if ((isDevAdmin == true) || (isOwner && _ownerEditMode))
                            DropdownButtonFormField<ProjectStatus>(
                              value: _status,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Status (स्थिति)',
                                prefixIcon: Icon(CupertinoIcons.flag),
                              ),
                              items: [
                                ...ProjectStatus.values.map((s) => DropdownMenuItem(value: s, child: Text(s.name)))
                              ],
                              onChanged: !_saving
                                  ? (v) {
                                      _status = v ?? _status;
                                      _dirty = true;
                                      _dirtyN.value = true;
                                      setState(() {});
                                    }
                                  : null,
                            )
                          else
                            InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Status (स्थिति)',
                                prefixIcon: Icon(CupertinoIcons.flag),
                              ),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(_status.name, style: Theme.of(context).textTheme.bodyMedium),
                              ),
                            ),
                          const SizedBox(height: 12),
                          TextFormField(
                            textAlignVertical: TextAlignVertical.center,
                            initialValue: '$_phase',
                            enabled: false, // computed automatically
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Financial Phase (auto) (वित्तीय चरण)',
                              prefixIcon: Icon(CupertinoIcons.number_circle),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Photos section with view/download and max 5 uploads
                  const SizedBox(height: 8),
                  _sectionTitle(context, 'Photos (फ़ोटो)'),
                  Card(
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (_photoUrls.isEmpty)
                          Text('No photos', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF9A9A9A))),
                        if (_photoUrls.isNotEmpty)
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _photoUrls.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 6),
                            itemBuilder: (context, i) {
                              final p = _photoUrls[i];
                              return Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ListTile(
                                  dense: true,
                                  leading: const Icon(CupertinoIcons.photo_on_rectangle),
                                  title: Text(p, overflow: TextOverflow.ellipsis),
                                  trailing: Wrap(spacing: 4, children: [
                                    FutureBuilder<String?>(
                                      future: _resolvePublic(p),
                                      builder: (context, snap) {
                                        final url = snap.data;
                                        if (url == null) return const SizedBox.shrink();
                                        final name = p.split('/').last;
                                        return AttachmentButton(
                                          resolveUrl: () async => url,
                                          fileName: name,
                                          showPreview: false,
                                        );
                                      },
                                    ),
                                    if (fieldsAll)
                                      IconButton(
                                        tooltip: 'Remove',
                                        icon: const Icon(CupertinoIcons.trash, color: Color(0xFFe55353)),
                                        onPressed: () {
                                          setState(() { _photoUrls.removeAt(i); _dirty = true; _dirtyN.value = true; });
                                        },
                                      ),
                                  ]),
                                ),
                              );
                            },
                          ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(spacing: 8, children: [
                            FilledButton.icon(
                              onPressed: !fieldsAll ? null : () async {
                                if (_photoUrls.length >= 5) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Maximum 5 photos')));
                                  return;
                                }
                                final res = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true, type: FileType.image);
                                if (res == null || res.files.isEmpty) return;
                                int remaining = 5 - _photoUrls.length;
                                // Filter selected files to allowed types/size and limit count
                                final selected = <PlatformFile>[];
                                for (final f in res.files) {
                                  if (remaining <= 0) break;
                                  final bytes = f.bytes; if (bytes == null) { continue; }
                                  final ext = (f.name.split('.').last.toLowerCase());
                                  if (!{'jpg','jpeg','png','heic','heif'}.contains(ext)) { continue; }
                                  if (bytes.length > StorageService.maxPhotoBytes) { continue; }
                                  selected.add(f);
                                  remaining--;
                                }
                                if (selected.isEmpty) return;

                                String _mimeFor(String name) {
                                  final lower = name.toLowerCase();
                                  if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
                                  if (lower.endsWith('.png')) return 'image/png';
                                  if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
                                  return 'application/octet-stream';
                                }

                                final items = [
                                  for (final f in selected)
                                    {
                                      'name': f.name,
                                      'progress': 0.0,
                                      'status': 'Queued',
                                      'error': null,
                                      'path': null,
                                    }
                                ];
                                bool done = false;
                                int settled = 0;
                                await showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (_) => StatefulBuilder(builder: (ctx, setS) {
                                    void _start() {
                                      // Start all uploads in parallel (<= 5) using StorageService for consistent metadata and progress
                                      final storage = ref.read(storageServiceProvider);
                                      for (int i = 0; i < items.length; i++) {
                                        final entry = items[i];
                                        final f = selected[i];
                                        final bytes = f.bytes!;
                                        final path = 'projects/${widget.projectId}/photos/${DateTime.now().millisecondsSinceEpoch}_${f.name}';
                                        setS(() { entry['status'] = 'Uploading…'; entry['progress'] = 0.01; });
                                        storage.uploadWithAdapter(
                                          path: path,
                                          bytes: bytes,
                                          fileName: f.name,
                                          contentType: _mimeFor(f.name),
                                          onProgress: (p) {
                                            setS(() { entry['progress'] = p.clamp(0, 1); });
                                          },
                                        ).then((_) {
                                          setS(() { entry['status'] = 'Done'; entry['progress'] = 1.0; entry['path'] = path; });
                                        }).catchError((e) {
                                          setS(() { entry['status'] = 'Failed'; entry['error'] = e.toString(); });
                                        }).whenComplete(() {
                                          settled++;
                                          if (settled >= items.length) setS(() { done = true; });
                                        });
                                      }
                                    }

                                    // Kick off after first build
                                    WidgetsBinding.instance.addPostFrameCallback((_) { if (!done) _start(); });

                                    return AlertDialog(
                                      title: const Text('Uploading photos'),
                                      content: SizedBox(
                                        width: 380,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            ...items.map((e) => Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 6),
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(e['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
                                                  const SizedBox(height: 6),
                                                  LinearProgressIndicator(value: (e['progress'] as double?) == 0.0 ? null : e['progress'] as double?),
                                                  const SizedBox(height: 2),
                                                  Row(children:[
                                                    Expanded(child: Text(e['status'] as String)),
                                                    // Cancel disabled for adapter-based uploads
                                                    if (e['error'] != null) Tooltip(message: e['error'] as String, child: const Icon(CupertinoIcons.exclamationmark_triangle, color: Colors.amber, size: 18)),
                                                  ])
                                                ],
                                              ),
                                            )),
                                          ],
                                        ),
                                      ),
                                      actions: [
                                        TextButton(onPressed: done ? () { Navigator.of(ctx).pop(); } : null, child: const Text('Close')),
                                      ],
                                    );
                                  }),
                                );
                                // Collect successful uploads
                                final added = <String>[];
                                for (final e in items) {
                                  final path = e['path'] as String?;
                                  if (path != null) added.add(path);
                                }
                                if (added.isNotEmpty) {
                                  setState(() { _photoUrls.addAll(added); _dirty = true; _dirtyN.value = true; });
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Uploaded ${added.length} photo(s)')));
                                  }
                                }
                              },
                              icon: const Icon(CupertinoIcons.photo_on_rectangle),
                              label: const Text('Upload Photos'),
                            ),
                            Text('Max 5. Currently: ${_photoUrls.length}', style: Theme.of(context).textTheme.bodySmall),
                          ]),
                        ),
                      ]),
                    ),
                  ),

                  const SizedBox(height: 8),
                  _sectionTitle(context, 'Location (स्थान)'),
                  Card(
                    elevation: 0,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (_location != null)
                          SizedBox(
                            height: 180,
                            child: FlutterMap(
                              options: MapOptions(
                                initialCenter: ll.LatLng(_location!.latitude, _location!.longitude),
                                initialZoom: 14,
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                                  subdomains: const ['a','b','c','d'],
                                  userAgentPackageName: 'com.example.nirmadapp',
                                ),
                                const RichAttributionWidget(
                                  attributions: [
                                    TextSourceAttribution('© OpenStreetMap contributors'),
                                    TextSourceAttribution('© CARTO'),
                                  ],
                                  alignment: AttributionAlignment.bottomRight,
                                ),
                                MarkerLayer(markers: [
                                  Marker(point: ll.LatLng(_location!.latitude, _location!.longitude), child: const Icon(CupertinoIcons.location_solid, color: Colors.red, size: 28)),
                                ]),
                              ],
                            ),
                          )
                        else
                          const Text('No location set'),
                        const SizedBox(height: 12),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          FilledButton.icon(
                            onPressed: fieldsAll ? _useMyLocation : null,
                            icon: const Icon(CupertinoIcons.location),
                            label: const Text('Use my location'),
                          ),
                          OutlinedButton.icon(
                            onPressed: fieldsAll ? _pickOnMap : null,
                            icon: const Icon(CupertinoIcons.map_pin_ellipse),
                            label: const Text('Pick on map'),
                          ),
                        ]),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Section 1: Preliminary Description
                  ExpansionTile(
                    initiallyExpanded: _expPrelim,
                    onExpansionChanged: (v) => setState(() => _expPrelim = v),
                    leading: const CircleAvatar(
                      radius: 12,
                      child: Center(child: Text('1', style: TextStyle(height: 1))),
                    ),
                    title: const Text('Preliminary Description (प्राथमिक विवरण)'),
                    children: [
                      Card(
                        elevation: 0,
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            children: [
                              _row2(
                                TextFormField(
                                  controller: _sarpanchName,
                                  enabled: fieldsAll,
                                  textCapitalization: TextCapitalization.words,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z\s\-\.\u0900-\u097F]")),
                                    LengthLimitingTextInputFormatter(60),
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: 'Sarpanch name (सरपंच का नाम)',
                                    prefixIcon: Icon(CupertinoIcons.person_crop_circle),
                                  ),
                                  validator: canEditAll ? (v)=> (v==null||v.trim().isEmpty)?'Required':null : null,
                                ),
                                TextFormField(
                                  controller: _sarpanchMobile,
                                  enabled: fieldsAll,
                                  keyboardType: TextInputType.phone,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(10),
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: 'Sarpanch mobile (मोबाइल)',
                                    prefixIcon: Icon(CupertinoIcons.phone),
                                  ),
                                  validator: (v) {
                                    final s = (v ?? '').trim();
                                    if (s.isEmpty) return '10 digits';
                                    return RegExp(r'^\d{10}$').hasMatch(s) ? null : '10 digits';
                                  },
                                ),
                              ),
                              const SizedBox(height: 12),
                              _row2(
                                TextFormField(
                                  controller: _gramPanchayat,
                                  enabled: fieldsAll,
                                  textCapitalization: TextCapitalization.words,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z\s\-\.\u0900-\u097F]")),
                                    LengthLimitingTextInputFormatter(60),
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: 'Gram Panchayat (ग्राम पंचायत)',
                                    prefixIcon: Icon(CupertinoIcons.building_2_fill),
                                  ),
                                  validator: canEditAll ? (v)=> (v==null||v.trim().isEmpty)?'Required':null : null,
                                ),
                                TextFormField(
                                  controller: _secretaryName,
                                  enabled: fieldsAll,
                                  textCapitalization: TextCapitalization.words,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z\s\-\.\u0900-\u097F]")),
                                    LengthLimitingTextInputFormatter(60),
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: 'Secretary name (सचिव का नाम)',
                                    prefixIcon: Icon(CupertinoIcons.person_2_square_stack),
                                  ),
                                  validator: canEditAll ? (v)=> (v==null||v.trim().isEmpty)?'Required':null : null,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _row2(
                                TextFormField(
                                  controller: _secretaryMobile,
                                  enabled: fieldsAll,
                                  keyboardType: TextInputType.phone,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(10),
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: 'Secretary mobile (मोबाइल)',
                                    prefixIcon: Icon(CupertinoIcons.phone),
                                  ),
                                  validator: (v) {
                                    final s = (v ?? '').trim();
                                    if (s.isEmpty) return '10 digits';
                                    return RegExp(r'^\d{10}$').hasMatch(s) ? null : '10 digits';
                                  },
                                ),
                                TextFormField(
                                  controller: _subEngineerName,
                                  enabled: fieldsAll,
                                  textCapitalization: TextCapitalization.words,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z\s\-\.\u0900-\u097F]")),
                                    LengthLimitingTextInputFormatter(60),
                                  ],
                                  decoration: const InputDecoration(
                                    labelText: 'Sub-Engineer name (उप अभियंता का नाम)',
                                    prefixIcon: Icon(CupertinoIcons.person_crop_square),
                                  ),
                                  validator: canEditAll ? (v)=> (v==null||v.trim().isEmpty)?'Required':null : null,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: SizedBox(
                                  width: 360,
                                  child: TextFormField(
                                      textAlignVertical: TextAlignVertical.center,
                                    controller: _subEngineerMobile,
                                    enabled: fieldsAll,
                                    keyboardType: TextInputType.phone,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(10),
                                    ],
                                    decoration: const InputDecoration(
                                      labelText: 'Sub-Engineer mobile (मोबाइल)',
                                      prefixIcon: Icon(CupertinoIcons.phone),
                                    ),
                                    validator: (v) {
                                      final s = (v ?? '').trim();
                                      if (s.isEmpty) return '10 digits';
                                      return RegExp(r'^\d{10}$').hasMatch(s) ? null : '10 digits';
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                    ),
                    ),
                    ],
                  ),

                  const SizedBox(height: 8),
                  ExpansionTile(
                    initiallyExpanded: _expSanc,
                    onExpansionChanged: (v) => setState(() => _expSanc = v),
                    leading: const CircleAvatar(radius: 12, child: Center(child: Text('2', style: TextStyle(height: 1)))),
                    title: const Text('Sanction & Compliance (स्वीकृति एवं अनुपालन)'),
                    children: [
                      Card(
                        elevation: 0,
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(children: [
                        _row2(
                          TextFormField(textAlignVertical: TextAlignVertical.center, controller: _sanctionDeptId, enabled: fieldsAll, decoration: const InputDecoration(labelText: 'Sanctioning Dept. ID (विभाग आईडी)', prefixIcon: Icon(CupertinoIcons.number_square))),
                          TextFormField(textAlignVertical: TextAlignVertical.center, controller: _sanctionDeptName, enabled: fieldsAll, decoration: const InputDecoration(labelText: 'Sanctioning Dept. Name (विभाग का नाम)', prefixIcon: Icon(CupertinoIcons.briefcase)) ),
                        ),
                        const SizedBox(height: 12),
                        _row2(
                          TextFormField(textAlignVertical: TextAlignVertical.center, controller: _schemeId, enabled: fieldsAll, decoration: const InputDecoration(labelText: 'Scheme ID (योजना आईडी)', prefixIcon: Icon(CupertinoIcons.number)) ),
                          TextFormField(textAlignVertical: TextAlignVertical.center, controller: _schemeName, enabled: fieldsAll, decoration: const InputDecoration(labelText: 'Scheme Name (योजना नाम)', prefixIcon: Icon(CupertinoIcons.cube_box)) ),
                        ),
                        const SizedBox(height: 12),
                        _row2(
                          TextFormField(textAlignVertical: TextAlignVertical.center, controller: _itemId, enabled: fieldsAll, decoration: const InputDecoration(labelText: 'Item ID (आइटम आईडी)', prefixIcon: Icon(CupertinoIcons.number)) ),
                          TextFormField(
                            textAlignVertical: TextAlignVertical.center,
                            controller: _itemName,
                            enabled: fieldsAll,
                            textCapitalization: TextCapitalization.sentences,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z0-9\s\-\,\./\u0900-\u097F]")),
                              LengthLimitingTextInputFormatter(120),
                            ],
                            decoration: const InputDecoration(labelText: 'Item Name (Work Name) (कार्य का नाम)', prefixIcon: Icon(CupertinoIcons.list_bullet)),
                            validator: canEditAll ? (v) => (v==null||v.trim().isEmpty) ? 'Enter Work Name' : null : null,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _row2(
                          TextFormField(textAlignVertical: TextAlignVertical.center, controller: _planHeadId, enabled: fieldsAll, decoration: const InputDecoration(labelText: 'Plan Head ID', prefixIcon: Icon(CupertinoIcons.number)) ),
                          TextFormField(
                            textAlignVertical: TextAlignVertical.center,
                            controller: _planHeadName,
                            enabled: fieldsAll,
                            textCapitalization: TextCapitalization.words,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z0-9\s\-\,\./\u0900-\u097F]")),
                              LengthLimitingTextInputFormatter(60),
                            ],
                            decoration: const InputDecoration(labelText: 'Plan Head Name (मद का नाम)', prefixIcon: Icon(CupertinoIcons.doc_richtext)),
                            validator: canEditAll ? (v) => (v==null||v.trim().isEmpty) ? 'Enter Plan Head' : null : null,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _row2(
                          TextFormField(
                            textAlignVertical: TextAlignVertical.center,
                            controller: _techApprovalNo,
                            enabled: fieldsAll,
                            decoration: const InputDecoration(labelText: 'Technical Approval No. (तकनीकी स्वीकृति क्रमांक)', prefixIcon: Icon(CupertinoIcons.number)),
                            validator: canEditAll ? (v)=> (v==null||v.trim().isEmpty)?'Enter Technical Approval No.' : null : null,
                          ),
                          DateFormField(
                            controller: _techApprovalDate,
                            label: 'Technical Approval Date (तकनीकी स्वीकृति तिथि)',
                            validator: (v){
                              final s=(v??'').trim();
                              if (canEditAll && s.isEmpty) return 'Required';
                              if (s.isEmpty) return null;
                              final re = RegExp(r'^\d{4}-\d{2}-\d{2}$');
                              if (!re.hasMatch(s)) return 'Use YYYY-MM-DD';
                              try { DateTime.parse(s); } catch (_) { return 'Invalid date'; }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        _row2(
                          TextFormField(
                            textAlignVertical: TextAlignVertical.center,
                            controller: _adminApprovalNo,
                            enabled: fieldsAll,
                            decoration: const InputDecoration(labelText: 'Admin Approval No. (प्रशासनिक स्वीकृति क्रमांक)', prefixIcon: Icon(CupertinoIcons.number)),
                            validator: canEditAll ? (v)=> (v==null||v.trim().isEmpty)?'Enter Admin Approval No.' : null : null,
                          ),
                          DateFormField(
                            controller: _adminApprovalDate,
                            label: 'Admin Approval Date (प्रशासनिक स्वीकृति तिथि)',
                            validator: (v){
                              final s=(v??'').trim();
                              if (canEditAll && s.isEmpty) return 'Required';
                              if (s.isEmpty) return null;
                              final re = RegExp(r'^\d{4}-\d{2}-\d{2}$');
                              if (!re.hasMatch(s)) return 'Use YYYY-MM-DD';
                              try { DateTime.parse(s); } catch (_) { return 'Invalid date'; }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: 260,
                            child: TextFormField(
                              textAlignVertical: TextAlignVertical.center,
                              controller: _approvedAmount,
                              enabled: fieldsAll,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r"[0-9,\.]")),
                                LengthLimitingTextInputFormatter(18),
                              ],
                              decoration: const InputDecoration(labelText: 'Approved Amount (स्वीकृत राशि)', prefixIcon: Icon(Icons.currency_rupee)),
                              autovalidateMode: AutovalidateMode.onUserInteraction,
                              validator: (v) {
                                const maxRupees = 500000000; // 50 crores
                                final s=(v??'').trim();
                                if (canEditAll && s.isEmpty) return 'Required';
                                if (s.isEmpty) return null;
                                final norm = s.replaceAll(',', '');
                                final d = double.tryParse(norm);
                                if (d == null) return 'Enter valid amount';
                                if (d > maxRupees) return 'Max ₹50,00,00,000 (50 crores)';
                                final sumErr = _sumValidationMessage();
                                if (sumErr != null) return sumErr;
                                return null;
                              },
                            ),
                          ),
                        ),
                        if (_approvedAmount.text.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(_inrHelper(_approvedAmount.text.trim()) ?? '', style: Theme.of(context).textTheme.labelSmall),
                          ),
                        const SizedBox(height: 12),
                        _UrlListEditor(
                          title: 'Approval Documents (URLs)',
                          enabled: fieldsAll,
                          values: _approvalDocs,
                          minItems: 1,
                          resolveUrl: (v) async {
                            if (v.startsWith('http')) return v;
                            final storage = ref.read(storageServiceProvider);
                            return await storage.getDownloadURL(v);
                          },
                          onChanged: (list) {
                            _approvalDocs
                              ..clear()
                              ..addAll(list);
                            _dirty = true; _dirtyN.value = true;
                            setState(() {});
                          },
                          trailing: fieldsAll ? _UploadButton(
                            label: 'Upload',
                            onPickAndUpload: (bytes, name) async {
                              final storage = ref.read(storageServiceProvider);
                              final path = 'projects/${widget.projectId}/docs/${DateTime.now().millisecondsSinceEpoch}_$name';
                              await storage.uploadBytes(path: path, bytes: bytes);
                              _approvalDocs.add(path); _dirty = true; _dirtyN.value = true; if (mounted) setState(() {});
                            },
                          ) : null,
                        ),
                      ]),
                    ),
                    ),
                    ],
                  ),

                  const SizedBox(height: 8),
  ExpansionTile(
                    initiallyExpanded: _expAllot,
                    onExpansionChanged: (v) => setState(() => _expAllot = v),
                    leading: const CircleAvatar(radius: 12, child: Center(child: Text('3', style: TextStyle(height: 1)))),
                    title: const Text('Allotment Details (आवंटन)'),
                    children: [
                      Card(
                        elevation: 0,
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
  Text('Installment 1 (किस्त 1)', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
  _row3(
                          TextFormField(
                            textAlignVertical: TextAlignVertical.center,
                            controller: _inst1Amount,
                            enabled: fieldsAll,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r"[0-9,\.]")), LengthLimitingTextInputFormatter(18)],
                            decoration: const InputDecoration(labelText: 'Amount (राशि)', prefixIcon: Icon(Icons.currency_rupee)),
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            validator: (v) {
                              const maxRupees = 500000000; // 50 crores
                              final s=(v??'').trim(); if (s.isEmpty) return null;
                              final d = double.tryParse(s.replaceAll(',', ''));
                              if (d == null) return 'Enter valid amount';
                              if (d > maxRupees) return 'Max ₹50,00,00,000';
                              final sumErr = _sumValidationMessage();
                              if (sumErr != null) return sumErr;
                              return null;
                            },
                          ),
                          DateFormField(controller: _inst1Date, label: 'Date'),
  TextFormField(
    textAlignVertical: TextAlignVertical.center,
    controller: _inst1RecvAmount,
    enabled: fieldsAll,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r"[0-9,\.]")), LengthLimitingTextInputFormatter(18)],
    decoration: const InputDecoration(labelText: 'Received Amount (प्राप्त राशि)', prefixIcon: Icon(Icons.currency_rupee)),
    validator: (v) {
      const maxRupees = 500000000;
      final s=(v??'').trim(); if (s.isEmpty) return null;
      final d = double.tryParse(s.replaceAll(',', ''));
      if (d == null) return 'Enter valid amount';
      if (d > maxRupees) return 'Max ₹50,00,00,000';
      return null;
    },
  ),
                        ),
                        const SizedBox(height: 8),
                        if (_inst1Amount.text.trim().isNotEmpty || _inst1RecvAmount.text.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4.0),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              if (_inst1Amount.text.trim().isNotEmpty)
                                Text(_inrHelper(_inst1Amount.text.trim()) ?? '', style: Theme.of(context).textTheme.labelSmall),
                              if (_inst1RecvAmount.text.trim().isNotEmpty)
                                Text('Received: ${_inrHelper(_inst1RecvAmount.text.trim()) ?? ''}', style: Theme.of(context).textTheme.labelSmall),
                            ]),
                          ),
                        Align(alignment: Alignment.centerLeft, child: SizedBox(width: 220, child: DateFormField(controller: _inst1RecvDate, label: 'Received Date (प्राप्त तिथि)'))),

                        const SizedBox(height: 16),
                        Text('Installment 2 (किस्त 2)', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        _row3(
                          TextFormField(
                            textAlignVertical: TextAlignVertical.center,
                            controller: _inst2Amount,
                            enabled: fieldsAll,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r"[0-9,\.]")), LengthLimitingTextInputFormatter(18)],
                            decoration: const InputDecoration(labelText: 'Amount (राशि)', prefixIcon: Icon(Icons.currency_rupee)),
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            validator: (v) {
                              const maxRupees = 500000000;
                              final s=(v??'').trim(); if (s.isEmpty) return null;
                              final d = double.tryParse(s.replaceAll(',', ''));
                              if (d == null) return 'Enter valid amount';
                              if (d > maxRupees) return 'Max ₹50,00,00,000';
                              final sumErr = _sumValidationMessage();
                              if (sumErr != null) return sumErr;
                              return null;
                            },
                          ),
                          DateFormField(controller: _inst2Date, label: 'Date'),
                          TextFormField(
                            textAlignVertical: TextAlignVertical.center,
                            controller: _inst2RecvAmount,
                            enabled: fieldsAll,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r"[0-9,\.]")), LengthLimitingTextInputFormatter(18)],
                            decoration: const InputDecoration(labelText: 'Received Amount (प्राप्त राशि)', prefixIcon: Icon(Icons.currency_rupee)),
                            validator: (v) {
                              const maxRupees = 500000000;
                              final s=(v??'').trim(); if (s.isEmpty) return null;
                              final d = double.tryParse(s.replaceAll(',', ''));
                              if (d == null) return 'Enter valid amount';
                              if (d > maxRupees) return 'Max ₹50,00,00,000';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_inst2Amount.text.trim().isNotEmpty || _inst2RecvAmount.text.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4.0),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              if (_inst2Amount.text.trim().isNotEmpty)
                                Text(_inrHelper(_inst2Amount.text.trim()) ?? '', style: Theme.of(context).textTheme.labelSmall),
                              if (_inst2RecvAmount.text.trim().isNotEmpty)
                                Text('Received: ${_inrHelper(_inst2RecvAmount.text.trim()) ?? ''}', style: Theme.of(context).textTheme.labelSmall),
                            ]),
                          ),
                        Align(alignment: Alignment.centerLeft, child: SizedBox(width: 220, child: DateFormField(controller: _inst2RecvDate, label: 'Received Date (प्राप्त तिथि)'))),

                        const SizedBox(height: 16),
                        Text('Installment 3 (किस्त 3)', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        _row3(
                          TextFormField(
                            textAlignVertical: TextAlignVertical.center,
                            controller: _inst3Amount,
                            enabled: fieldsAll,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r"[0-9,\.]")), LengthLimitingTextInputFormatter(18)],
                            decoration: const InputDecoration(labelText: 'Amount (राशि)', prefixIcon: Icon(Icons.currency_rupee)),
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                            validator: (v) {
                              const maxRupees = 500000000;
                              final s=(v??'').trim(); if (s.isEmpty) return null;
                              final d = double.tryParse(s.replaceAll(',', ''));
                              if (d == null) return 'Enter valid amount';
                              if (d > maxRupees) return 'Max ₹50,00,00,000';
                              final sumErr = _sumValidationMessage();
                              if (sumErr != null) return sumErr;
                              return null;
                            },
                          ),
                          DateFormField(controller: _inst3Date, label: 'Date'),
                          TextFormField(
                            textAlignVertical: TextAlignVertical.center,
                            controller: _inst3RecvAmount,
                            enabled: fieldsAll,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r"[0-9,\.]")), LengthLimitingTextInputFormatter(18)],
                            decoration: const InputDecoration(labelText: 'Received Amount (प्राप्त राशि)', prefixIcon: Icon(Icons.currency_rupee)),
                            validator: (v) {
                              const maxRupees = 500000000;
                              final s=(v??'').trim(); if (s.isEmpty) return null;
                              final d = double.tryParse(s.replaceAll(',', ''));
                              if (d == null) return 'Enter valid amount';
                              if (d > maxRupees) return 'Max ₹50,00,00,000';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_inst3Amount.text.trim().isNotEmpty || _inst3RecvAmount.text.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4.0),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              if (_inst3Amount.text.trim().isNotEmpty)
                                Text(_inrHelper(_inst3Amount.text.trim()) ?? '', style: Theme.of(context).textTheme.labelSmall),
                              if (_inst3RecvAmount.text.trim().isNotEmpty)
                                Text('Received: ${_inrHelper(_inst3RecvAmount.text.trim()) ?? ''}', style: Theme.of(context).textTheme.labelSmall),
                            ]),
                          ),
                        Align(alignment: Alignment.centerLeft, child: SizedBox(width: 220, child: DateFormField(controller: _inst3RecvDate, label: 'Received Date (प्राप्त तिथि)'))),

                        const SizedBox(height: 16),
                        Text('Bank Details (बैंक विवरण)', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        _row2(
                          TextFormField(textAlignVertical: TextAlignVertical.center, controller: _bankId, enabled: fieldsAll, decoration: const InputDecoration(labelText: 'Bank ID (बैंक आईडी)', prefixIcon: Icon(CupertinoIcons.number)) ),
                          TextFormField(textAlignVertical: TextAlignVertical.center, controller: _bankName, enabled: fieldsAll, decoration: const InputDecoration(labelText: 'Bank Name (बैंक का नाम)', prefixIcon: Icon(CupertinoIcons.building_2_fill)) ),
                        ),
                        const SizedBox(height: 12),
                        _row3(
                          TextFormField(
                            textAlignVertical: TextAlignVertical.center,
                            controller: _bankAccount,
                            enabled: fieldsAll,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(labelText: 'Account Number (खाता संख्या)', prefixIcon: Icon(CupertinoIcons.creditcard)),
                            validator: canEditAll ? (v){ final s=(v??'').trim(); if(s.isEmpty) return 'Enter Account Number'; if(s.length<6) return 'Too short'; return null; } : null,
                          ),
                          TextFormField(textAlignVertical: TextAlignVertical.center, controller: _bankBranch, enabled: fieldsAll, decoration: const InputDecoration(labelText: 'Branch (शाखा)', prefixIcon: Icon(CupertinoIcons.building_2_fill)) ),
                          TextFormField(
                            textAlignVertical: TextAlignVertical.center,
                            controller: _bankIfsc,
                            enabled: fieldsAll,
                            decoration: const InputDecoration(labelText: 'IFSC (आईएफएससी)', prefixIcon: Icon(CupertinoIcons.number)),
                            inputFormatters: [LengthLimitingTextInputFormatter(11)],
                            onChanged: (_) {
                              final t = _bankIfsc.text.toUpperCase();
                              if (_bankIfsc.text != t) {
                                final sel = _bankIfsc.selection;
                                _bankIfsc.value = TextEditingValue(text: t, selection: sel);
                              }
                            },
                            validator: canEditAll ? (v){ final s=(v??'').trim(); if(s.isEmpty) return 'Enter IFSC'; if(s.length!=11) return '11 characters'; return null; } : null,
                          ),
                        ),
                      ]),
                    ),
                    ),
                    ],
                  ),

                  const SizedBox(height: 8),
                  ExpansionTile(
                    initiallyExpanded: _expWork,
                    onExpansionChanged: (v) => setState(() => _expWork = v),
                    leading: const CircleAvatar(radius: 12, child: Center(child: Text('4', style: TextStyle(height: 1)))),
                    title: const Text('Work Description (कार्य विवरण)'),
                    children: [
                      Card(
                        elevation: 0,
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(children: [
                        _row3(
                          DateFormField(
                            controller: _workStartDate,
                            label: 'Start Date (आरंभ तिथि)',
                            enabled: fieldsAll,
                            lastDate: (() {
                              try {
                                final s = _workEndDate.text.trim();
                                if (s.isEmpty) return null;
                                return DateTime.parse(s);
                              } catch (_) { return null; }
                            })(),
                            validator: (v) {
                              final s = (v ?? '').trim();
                              if (s.isEmpty) return null; // optional in edit unless enforcing elsewhere
                              final re = RegExp(r'^\d{4}-\d{2}-\d{2}$');
                              if (!re.hasMatch(s)) return 'Use YYYY-MM-DD';
                              DateTime d;
                              try { d = DateTime.parse(s); } catch (_) { return 'Invalid date'; }
                              final se = _workEndDate.text.trim();
                              if (se.isNotEmpty) {
                                try { final e = DateTime.parse(se); if (d.isAfter(e)) return 'Start must be on or before End'; } catch (_) {}
                              }
                              return null;
                            },
                          ),
                          DateFormField(
                            controller: _workEndDate,
                            label: 'End Date (समाप्ति तिथि)',
                            enabled: fieldsAll,
                            firstDate: (() {
                              try {
                                final s = _workStartDate.text.trim();
                                if (s.isEmpty) return null;
                                return DateTime.parse(s);
                              } catch (_) { return null; }
                            })(),
                            validator: (v) {
                              final s = (v ?? '').trim();
                              if (s.isEmpty) return null; // optional in edit
                              final re = RegExp(r'^\d{4}-\d{2}-\d{2}$');
                              if (!re.hasMatch(s)) return 'Use YYYY-MM-DD';
                              DateTime e;
                              try { e = DateTime.parse(s); } catch (_) { return 'Invalid date'; }
                              final ss = _workStartDate.text.trim();
                              if (ss.isNotEmpty) {
                                try { final d = DateTime.parse(ss); if (e.isBefore(d)) return 'End must be on or after Start'; } catch (_) {}
                              }
                              return null;
                            },
                          ),
                          DropdownButtonFormField<WorkStage?>(
                            value: _workStage,
                            decoration: const InputDecoration(labelText: 'Stage (चरण)'),
                            isExpanded: true,
                            items: [
                              const DropdownMenuItem(value: null, child: Text('Not set')),
                              ...WorkStage.values.map((e) => DropdownMenuItem(value: e, child: Text(e.name)))
                            ],
                            onChanged: _saving
                                ? null
                                : ((isDevAdmin == true || isNodal || (isOwner && _ownerEditMode))
                                    ? (v) {
                                        _workStage = v;
                                        _dirty = true;
                                        _dirtyN.value = true;
                                        setState(() {});
                                      }
                                    : null),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: 360,
                            child: DropdownButtonFormField<ApramStatus?>(
                              value: _apramStatus,
                              decoration: const InputDecoration(labelText: 'Apram status (एप्राम स्थिति)'),
                              isExpanded: true,
                              items: [
                                const DropdownMenuItem(value: null, child: Text('Not set')),
                                ...ApramStatus.values.map((e) => DropdownMenuItem(value: e, child: Text(e.name)))
                              ],
                              onChanged: fieldsAll
                                  ? (v) {
                                      _apramStatus = v;
                                      _dirty = true;
                                      _dirtyN.value = true;
                                      setState(() {});
                                    }
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _UrlListEditor(
                          title: 'Measurement Books (URLs)',
                          enabled: fieldsAll,
                          values: _mbUrls,
                          resolveUrl: (v) async { if (v.startsWith('http')) return v; final s = ref.read(storageServiceProvider); return await s.getDownloadURL(v); },
                          onChanged: (v) { _mbUrls..clear()..addAll(v); _dirty = true; _dirtyN.value = true; setState(() {}); },
                          trailing: fieldsAll ? _UploadButton(label: 'Upload', onPickAndUpload: (bytes, name) async {
                            final storage = ref.read(storageServiceProvider);
                            final path = 'projects/${widget.projectId}/docs/${DateTime.now().millisecondsSinceEpoch}_$name';
                            await storage.uploadBytes(path: path, bytes: bytes);
                            _mbUrls.add(path); _dirty = true; _dirtyN.value = true; if (mounted) setState(() {});
                          }) : null,
                        ),
                        const SizedBox(height: 12),
                        _UrlListEditor(
                          title: 'Test Reports (URLs)',
                          enabled: fieldsAll,
                          values: _testUrls,
                          resolveUrl: (v) async { if (v.startsWith('http')) return v; final s = ref.read(storageServiceProvider); return await s.getDownloadURL(v); },
                          onChanged: (v) { _testUrls..clear()..addAll(v); _dirty = true; _dirtyN.value = true; setState(() {}); },
                          trailing: fieldsAll ? _UploadButton(label: 'Upload', onPickAndUpload: (bytes, name) async {
                            final storage = ref.read(storageServiceProvider);
                            final path = 'projects/${widget.projectId}/docs/${DateTime.now().millisecondsSinceEpoch}_$name';
                            await storage.uploadBytes(path: path, bytes: bytes);
                            _testUrls.add(path); _dirty = true; _dirtyN.value = true; if (mounted) setState(() {});
                          }) : null,
                        ),
                        const SizedBox(height: 12),
                        _UrlListEditor(
                          title: 'Work Reports (URLs)',
                          enabled: fieldsAll,
                          values: _workReportUrls,
                          resolveUrl: (v) async { if (v.startsWith('http')) return v; final s = ref.read(storageServiceProvider); return await s.getDownloadURL(v); },
                          onChanged: (v) { _workReportUrls..clear()..addAll(v); _dirty = true; _dirtyN.value = true; setState(() {}); },
                          trailing: fieldsAll ? _UploadButton(label: 'Upload', onPickAndUpload: (bytes, name) async {
                            final storage = ref.read(storageServiceProvider);
                            final path = 'projects/${widget.projectId}/docs/${DateTime.now().millisecondsSinceEpoch}_$name';
                            await storage.uploadBytes(path: path, bytes: bytes);
                            _workReportUrls.add(path); _dirty = true; _dirtyN.value = true; if (mounted) setState(() {});
                          }) : null,
                        ),
                        const SizedBox(height: 12),
                        _UrlListEditor(
                          title: 'Certificates (URLs)',
                          enabled: fieldsAll,
                          values: _certificateUrls,
                          resolveUrl: (v) async { if (v.startsWith('http')) return v; final s = ref.read(storageServiceProvider); return await s.getDownloadURL(v); },
                          onChanged: (v) { _certificateUrls..clear()..addAll(v); _dirty = true; _dirtyN.value = true; setState(() {}); },
                          trailing: fieldsAll ? _UploadButton(label: 'Upload', onPickAndUpload: (bytes, name) async {
                            final storage = ref.read(storageServiceProvider);
                            final path = 'projects/${widget.projectId}/docs/${DateTime.now().millisecondsSinceEpoch}_$name';
                            await storage.uploadBytes(path: path, bytes: bytes);
                            _certificateUrls.add(path); _dirty = true; _dirtyN.value = true; if (mounted) setState(() {});
                          }) : null,
                        ),
                      ]),
                    ),
                    ),
                    ],
                  ),
                  const SizedBox(height: 64),
                ],
              ),
            ),
          );
        },
      ),
      if (_saving)
        Positioned.fill(
          child: Container(
            color: Colors.black.withOpacity(0.12),
            child: const Center(child: CircularProgressIndicator()),
          ),
        ),
      ]),
      floatingActionButton: ValueListenableBuilder<bool>(
        valueListenable: _dirtyN,
        builder: (context, isDirty, _) => (_saving || isDirty)
            ? FloatingActionButton.extended(
              tooltip: _saving ? 'Saving…' : 'Save',
              onPressed: _saving || !_dirty
                  ? null
                  : () async {
                      if (!(_form.currentState?.validate() ?? false)) return;
                      // Check connectivity before attempting to save
                      final statuses = await Connectivity().checkConnectivity().catchError((_) => <ConnectivityResult>[]);
                      if (statuses.isEmpty || statuses.every((s) => s == ConnectivityResult.none)) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You are offline. Please try again when back online.')));
                        }
                        return;
                      }
                      // Ensure required docs parity: at least 1 approval document
                      if (canEditAll && _approvalDocs.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Admin approval document required')));
                        return;
                      }
                      // Owners must enable edit mode
                      if (isOwner && !_ownerEditMode && !canEditAll && !canEditLimited) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enable Edit mode to save changes')));
                        return;
                      }
                      // Confirmation for nodal officers and non-admin roles
                      if (isNodal || !canEditAll) {
                        final ok = await _confirmDisclaimer();
                        if (!ok) return;
                      }
                      FocusScope.of(context).unfocus();
                      setState(() => _saving = true);
                      try {
                                final update = <String, dynamic>{
                                  'updatedAt': FieldValue.serverTimestamp(),
                                };
                                // Top-level fields
                                if (canEditAll) {
                                  update.addAll({
                                    'name': _name.text.trim(),
                                    'blockId': _blockId,
                                    'villageId': _villageId,
                                    'location': _location,
                                    'photoUrls': _photoUrls,
                                  });
                                }
                                if (isDevAdmin || (isOwner && _ownerEditMode)) {
                                  update.addAll({'status': _status.name});
                                }
                                // Description can be updated by dev_admin, nodal, or owner in edit mode
                                if ((isOwner && _ownerEditMode) || isDevAdmin || isNodal) {
                                  update['description'] = _desc.text.trim();
                                }

                                if (canEditAll) {
                                  // Helpers
                                  DateTime? _parseDate(String s) { try { if (s.trim().isEmpty) return null; return DateTime.parse(s.trim()); } catch (_) { return null; } }
                                  num? _parseNum(String s) {
                                    const maxRupees = 500000000; // 50 crores
                                    final v = s.trim(); if (v.isEmpty) return null;
                                    final d = double.tryParse(v.replaceAll(',', ''));
                                    if (d == null) return null;
                                    final clamped = d.clamp(0, maxRupees).toDouble();
                                    return clamped;
                                  }

                                  // Preliminary
                                  final prelim = {
                                    'sarpanchName': _sarpanchName.text.trim().isEmpty ? null : _sarpanchName.text.trim(),
                                    'sarpanchMobile': _sarpanchMobile.text.trim().isEmpty ? null : _sarpanchMobile.text.trim(),
                                    'gramPanchayat': _gramPanchayat.text.trim().isEmpty ? null : _gramPanchayat.text.trim(),
                                    'secretaryName': _secretaryName.text.trim().isEmpty ? null : _secretaryName.text.trim(),
                                    'secretaryMobile': _secretaryMobile.text.trim().isEmpty ? null : _secretaryMobile.text.trim(),
                                    'subEngineerName': _subEngineerName.text.trim().isEmpty ? null : _subEngineerName.text.trim(),
                                    'subEngineerMobile': _subEngineerMobile.text.trim().isEmpty ? null : _subEngineerMobile.text.trim(),
                                  }..removeWhere((k, v) => v == null);
                                  if (prelim.isNotEmpty) update['preliminaryDescription'] = prelim;

                                  // Sanction & Compliance
                                  final sanc = {
                                    'sanctioningDepartmentId': _sanctionDeptId.text.trim().isEmpty ? null : _sanctionDeptId.text.trim(),
                                    'sanctioningDepartmentName': _sanctionDeptName.text.trim().isEmpty ? null : _sanctionDeptName.text.trim(),
                                    'technicalApprovalNo': _techApprovalNo.text.trim().isEmpty ? null : _techApprovalNo.text.trim(),
                                    'technicalApprovalDate': _parseDate(_techApprovalDate.text),
                                    'adminApprovalNo': _adminApprovalNo.text.trim().isEmpty ? null : _adminApprovalNo.text.trim(),
                                    'adminApprovalDate': _parseDate(_adminApprovalDate.text),
                                    'schemeId': _schemeId.text.trim().isEmpty ? null : _schemeId.text.trim(),
                                    'schemeName': _schemeName.text.trim().isEmpty ? null : _schemeName.text.trim(),
                                    'itemId': _itemId.text.trim().isEmpty ? null : _itemId.text.trim(),
                                    'itemName': _itemName.text.trim().isEmpty ? null : _itemName.text.trim(),
                                    'planHeadId': _planHeadId.text.trim().isEmpty ? null : _planHeadId.text.trim(),
                                    'planHeadName': _planHeadName.text.trim().isEmpty ? null : _planHeadName.text.trim(),
                                    'approvedAmount': _parseNum(_approvedAmount.text),
                                    'approvalDocumentUrls': _approvalDocs,
                                  }..removeWhere((k, v) => v == null);
                                  if (sanc.isNotEmpty) update['sanctionCompliance'] = sanc;

                                  // Allotment
                                  Map<String, dynamic> mkInst(TextEditingController a, TextEditingController d, TextEditingController ra, TextEditingController rd) => {
                                        'amount': _parseNum(a.text),
                                        'date': _parseDate(d.text),
                                        'receivedAmount': _parseNum(ra.text),
                                        'receivedDate': _parseDate(rd.text),
                                      }..removeWhere((k, v) => v == null);
                                  final allotment = <String, dynamic>{
                                    'installment1': mkInst(_inst1Amount, _inst1Date, _inst1RecvAmount, _inst1RecvDate),
                                    'installment2': mkInst(_inst2Amount, _inst2Date, _inst2RecvAmount, _inst2RecvDate),
                                    'installment3': mkInst(_inst3Amount, _inst3Date, _inst3RecvAmount, _inst3RecvDate),
                                    'bankDetails': {
                                      'bankId': _bankId.text.trim().isEmpty ? null : _bankId.text.trim(),
                                      'bankName': _bankName.text.trim().isEmpty ? null : _bankName.text.trim(),
                                      'accountNumber': _bankAccount.text.trim().isEmpty ? null : _bankAccount.text.trim(),
                                      'branch': _bankBranch.text.trim().isEmpty ? null : _bankBranch.text.trim(),
                                      'ifsc': _bankIfsc.text.trim().isEmpty ? null : _bankIfsc.text.trim(),
                                    }..removeWhere((k, v) => v == null),
                                  };
                                  // Remove empty maps inside allotment
                                  allotment.removeWhere((k, v) => (v as Map).isEmpty);
                                  if (allotment.isNotEmpty) update['allotmentDetails'] = allotment;

                                  // Compute Financial Phase (0..3) based on received installments
                                  int computePhase() {
                                    int phase = 0;
                                    num? r1 = _parseNum(_inst1RecvAmount.text);
                                    num? r2 = _parseNum(_inst2RecvAmount.text);
                                    num? r3 = _parseNum(_inst3RecvAmount.text);
                                    if ((r1 ?? 0) > 0) phase = 1;
                                    if ((r2 ?? 0) > 0) phase = 2;
                                    if ((r3 ?? 0) > 0) phase = 3;
                                    return phase;
                                  }
                                  update['phase'] = computePhase();

                                  // Work
                                  final work = {
                                    'startDate': _parseDate(_workStartDate.text),
                                    'endDate': _parseDate(_workEndDate.text),
                                    'stage': _workStage?.name,
                                    'apramStatus': _apramStatus?.name,
                                    'measurementBookUrls': _mbUrls,
                                    'testReportUrls': _testUrls,
                                    'workReportUrls': _workReportUrls,
                                    'certificateUrls': _certificateUrls,
                                  }..removeWhere((k, v) => v == null);
                                  final hasAnyWork = work['startDate'] != null || work['stage'] != null || work['apramStatus'] != null || _mbUrls.isNotEmpty || _testUrls.isNotEmpty || _workReportUrls.isNotEmpty || _certificateUrls.isNotEmpty;
                                  if (hasAnyWork) update['workDescription'] = work;
                                }

                                // Stage can be updated by dev_admin, nodal, or owner in edit mode even when not editing all
                                if ((isDevAdmin || isNodal || (isOwner && _ownerEditMode)) && _workStage != null) {
                                  update['workDescription.stage'] = _workStage!.name;
                                }

                                await db.collection('projects').doc(widget.projectId).update(update);
            if (!mounted) return;
                                toastification.show(
                                  context: context,
                                  type: ToastificationType.success,
                                  style: ToastificationStyle.fillColored,
                                  title: const Text('Project updated'),
                                  autoCloseDuration: const Duration(seconds: 2),
                                  showProgressBar: false,
                                );
            _dirty = false; _dirtyN.value = false; if (mounted) setState(() {});
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
                              } finally {
                                if (mounted) setState(() => _saving = false);
                              }
                    },
              icon: _saving ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)) : const Icon(CupertinoIcons.floppy_disk),
              label: Text(_saving ? 'Saving…' : 'Save'),
            )
            : const SizedBox.shrink(),
  ),
    ));
  }
}

Widget _sectionTitle(BuildContext context, String title) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 6.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
    );

// Responsive field rows: stack on narrow screens to avoid RenderFlex overflows
Widget _row2(Widget a, Widget b) => LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      if (w < 640) {
        return Column(children: [a, const SizedBox(height: 12), b]);
      }
      return Row(children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)]);
    });
Widget _row3(Widget a, Widget b, Widget c) => LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth;
      if (w < 720) {
        return Column(children: [a, const SizedBox(height: 12), b, const SizedBox(height: 12), c]);
      } else if (w < 1024) {
        return Column(children: [Row(children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)]), const SizedBox(height: 12), c]);
      }
      return Row(children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b), const SizedBox(width: 12), Expanded(child: c)]);
    });

String _fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class _UrlListEditor extends StatefulWidget {
  final String title;
  final bool enabled;
  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final Widget? trailing; // optional trailing action (e.g., Upload)
  final int minItems; // minimum number of items required (restrict deletion)
  final Future<String?> Function(String url)? resolveUrl; // to resolve storage paths
  const _UrlListEditor({required this.title, required this.enabled, required this.values, required this.onChanged, this.trailing, this.minItems = 0, this.resolveUrl});

  @override
  State<_UrlListEditor> createState() => _UrlListEditorState();
}

class _UrlListEditorState extends State<_UrlListEditor> {
  final _ctrl = TextEditingController();
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.values;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LayoutBuilder(builder: (context, c) {
        final narrow = c.maxWidth < 560;
        final title = Expanded(child: Text(widget.title + (widget.minItems > 0 ? ' *' : ''), style: Theme.of(context).textTheme.titleSmall));
        final addField = ConstrainedBox(
          constraints: BoxConstraints(maxWidth: narrow ? c.maxWidth : 300),
          child: TextField(controller: _ctrl, decoration: const InputDecoration(hintText: 'https:// or gs:// path')),
        );
        final addBtn = FilledButton.icon(
          onPressed: () {
            final v = _ctrl.text.trim();
            if (v.isEmpty) return;
            final uri = Uri.tryParse(v);
            if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a public http(s) link')));
              return;
            }
            setState(() {
              list.add(v);
              _ctrl.clear();
            });
            widget.onChanged(list);
          },
          icon: const Icon(CupertinoIcons.link),
          label: const Text('Add'),
        );

        if (!widget.enabled) {
          return Row(children: [title]);
        }

        if (widget.minItems > 0) {
          // Required group: hide manual Add link; show only trailing action (e.g., Upload)
          if (narrow) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [title]),
              const SizedBox(height: 8),
              if (widget.trailing != null) Align(alignment: Alignment.centerLeft, child: widget.trailing!),
            ]);
          }
          return Row(children: [title, if (widget.trailing != null) widget.trailing!]);
        }

        // Optional group: show add field + button; on narrow stack vertically to avoid overflows
        if (narrow) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [title]),
            const SizedBox(height: 8),
            addField,
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [addBtn, if (widget.trailing != null) widget.trailing!]),
          ]);
        }
        return Row(children: [title, addField, const SizedBox(width: 8), addBtn, if (widget.trailing != null) ...[const SizedBox(width: 8), widget.trailing!]]);
      }),
      const SizedBox(height: 8),
      if (list.isEmpty)
        Text('No items', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF9A9A9A))),
      if (list.isNotEmpty)
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (context, i) {
            final item = list[i];
            final icon = _iconFor(item);
            final canDelete = widget.enabled && list.length > widget.minItems;
            return Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListTile(
                dense: true,
                leading: Icon(icon, color: _colorFor(item)),
                title: Text(item, overflow: TextOverflow.ellipsis),
                trailing: Wrap(spacing: 4, children: [
                  AttachmentButton(
                    resolveUrl: () async => await _resolve(item) ?? item,
                    fileName: _fileNameFor(item),
                    showPreview: false,
                  ),
                  if (canDelete)
                    IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(CupertinoIcons.trash, color: Color(0xFFe55353)),
                      onPressed: () {
                        setState(() { list.removeAt(i); });
                        widget.onChanged(list);
                      },
                    ),
                ]),
              ),
            );
          },
        ),
    ]);
  }

  Future<String?> _resolve(String url) async {
    if (widget.resolveUrl != null) return await widget.resolveUrl!(url);
    return url;
  }

  IconData _iconFor(String url) {
    final u = url.toLowerCase();
    if (u.endsWith('.pdf')) return CupertinoIcons.doc_richtext;
    if (u.endsWith('.jpg') || u.endsWith('.jpeg') || u.endsWith('.png') || u.endsWith('.heic') || u.endsWith('.heif')) return CupertinoIcons.photo_on_rectangle;
    if (u.endsWith('.xls') || u.endsWith('.xlsx') || u.endsWith('.csv')) return CupertinoIcons.table;
    if (u.endsWith('.doc') || u.endsWith('.docx')) return CupertinoIcons.doc_text;
    return CupertinoIcons.link;
  }

  Color _colorFor(String url) {
    final u = url.toLowerCase();
    if (u.endsWith('.pdf')) return const Color(0xFFE55353); // red
    if (u.endsWith('.jpg') || u.endsWith('.jpeg') || u.endsWith('.png') || u.endsWith('.heic') || u.endsWith('.heif')) return const Color(0xFF6366F1); // indigo
    if (u.endsWith('.xls') || u.endsWith('.xlsx') || u.endsWith('.csv')) return const Color(0xFF2EB85C); // green
    if (u.endsWith('.doc') || u.endsWith('.docx')) return const Color(0xFF0EA5E9); // sky blue
    return const Color(0xFF9A9A9A);
  }

  String _fileNameFor(String url) {
    final idx = url.lastIndexOf('/');
    if (idx >= 0 && idx < url.length - 1) return url.substring(idx + 1);
    return url;
  }
}

class _UploadButton extends StatelessWidget {
  final String label;
  final Future<void> Function(List<int> bytes, String name) onPickAndUpload;
  const _UploadButton({required this.label, required this.onPickAndUpload});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () async {
        try {
          final res = await FilePicker.platform.pickFiles(
            type: FileType.custom,
            withData: true,
            allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx', 'xls', 'xlsx'],
          );
          if (res == null || res.files.isEmpty) return;
          final f = res.files.first;
          final bytes = f.bytes;
          if (bytes == null) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No file data')));
            return;
          }
          if (bytes.length > StorageService.maxDocBytes) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File too large')));
            return;
          }
          await onPickAndUpload(bytes, f.name);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Uploaded')));
          }
        } catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
        }
      },
      icon: const Icon(CupertinoIcons.cloud_upload),
      label: Text(label),
    );
  }
}

// Removed _PhotosGrid: editor now shows attachments as icons only (no image streaming)

// End state class helpers

// Helper to build required-field labels
InputDecoration _reqDecoration(String label, Icon prefix) => InputDecoration(
      label: RichText(text: TextSpan(text: label, style: const TextStyle(color: Colors.grey), children: const [TextSpan(text: ' *', style: TextStyle(color: Colors.red))])),
      prefixIcon: prefix,
    );

// INR helpers: numeric formatting + pronunciation (English words)
String? _inrHelper(String s) {
  final norm = s.replaceAll(',', '').trim();
  final d = double.tryParse(norm);
  if (d == null) return null;
  final intR = d.floor();
  return '₹${_indianGrouping(intR)} (${_rupeesInWords(intR)})';
}

String _indianGrouping(int value) {
  final str = value.toString();
  if (str.length <= 3) return str;
  final last3 = str.substring(str.length - 3);
  String rest = str.substring(0, str.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(',')},$last3';
}

String _rupeesInWords(int n) {
  if (n == 0) return 'zero rupees';
  String two(int x) {
    const ones = ['zero','one','two','three','four','five','six','seven','eight','nine','ten','eleven','twelve','thirteen','fourteen','fifteen','sixteen','seventeen','eighteen','nineteen'];
    const tens = ['', '', 'twenty','thirty','forty','fifty','sixty','seventy','eighty','ninety'];
    if (x < 20) return ones[x];
    final t = x ~/ 10, o = x % 10;
    return tens[t] + (o > 0 ? '-${ones[o]}' : '');
  }
  String three(int x) {
    final h = x ~/ 100; final r = x % 100;
    if (h == 0) return two(r);
    final head = '${two(h)} hundred';
    if (r == 0) return head;
    return '$head ${two(r)}';
  }
  final crore = n ~/ 10000000;
  final lakh = (n % 10000000) ~/ 100000;
  final thousand = (n % 100000) ~/ 1000;
  final hundred = n % 1000;
  final parts = <String>[];
  if (crore > 0) parts.add('${crore < 100 ? two(crore) : three(crore)} crore');
  if (lakh > 0) parts.add('${two(lakh)} lakh');
  if (thousand > 0) parts.add('${two(thousand)} thousand');
  if (hundred > 0) parts.add(three(hundred));
  return parts.join(' ') + ' rupees';
}

