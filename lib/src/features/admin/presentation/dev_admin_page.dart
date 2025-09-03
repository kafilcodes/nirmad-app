import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/functions_service.dart';
import '../../../shared/ui/toast.dart';

class DevAdminPage extends ConsumerStatefulWidget {
  const DevAdminPage({super.key});

  @override
  ConsumerState<DevAdminPage> createState() => _DevAdminPageState();
}

class _DevAdminPageState extends ConsumerState<DevAdminPage> {
  final _emailCtrl = TextEditingController();
  final _blocksCtrl = TextEditingController();
  String _role = 'project_owner';
  bool _busy = false;
  final _ownersCtrl = TextEditingController(text: '5');
  final _nodalsCtrl = TextEditingController(text: '2');
  final _domainCtrl = TextEditingController(text: 'example.com');

  @override
  void dispose() {
    _emailCtrl.dispose();
    _blocksCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dev Admin Tools')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Assign Role & Blocks to User (by email)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'User email', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Role:'),
                const SizedBox(width: 12),
                Flexible(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _role,
                    items: const [
                      DropdownMenuItem(value: 'super_nodal', child: Text('Super Nodal')),
                      DropdownMenuItem(value: 'sub_nodal', child: Text('Sub Nodal')),
                      DropdownMenuItem(value: 'project_owner', child: Text('Project Owner')),
                      DropdownMenuItem(value: 'dev_admin', child: Text('Dev Admin')),
                    ],
                    onChanged: (v) => setState(() => _role = v ?? _role),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _blocksCtrl,
              decoration: const InputDecoration(
                labelText: 'Blocks (comma separated, for sub_nodal)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _assign,
              icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(CupertinoIcons.check_mark),
              label: const Text('Set Claims'),
            ),
            const Divider(height: 32),
            const Text('Seed Test Accounts', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(children: [
              Flexible(child: TextField(controller: _ownersCtrl, decoration: const InputDecoration(labelText: 'Owners', border: OutlineInputBorder()))),
              const SizedBox(width: 8),
              Flexible(child: TextField(controller: _nodalsCtrl, decoration: const InputDecoration(labelText: 'Nodals', border: OutlineInputBorder()))),
            ]),
            const SizedBox(height: 12),
            TextField(controller: _domainCtrl, decoration: const InputDecoration(labelText: 'Email domain', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _seed,
              icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(CupertinoIcons.person_crop_circle_badge_plus),
              label: const Text('Create Test Users'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _assign() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
  showToast(context, 'Email is required', icon: CupertinoIcons.exclamationmark_triangle, error: true);
      return;
    }
    final blocks = _blocksCtrl.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    setState(() => _busy = true);
    try {
      await ref.read(functionsServiceProvider).setUserClaims(email: email, role: _role, blocks: blocks.isEmpty ? null : blocks);
  if (!mounted) return; showToast(context, 'Claims updated', icon: CupertinoIcons.checkmark_seal);
    } catch (e) {
  if (!mounted) return; showToast(context, 'Failed: $e', icon: CupertinoIcons.exclamationmark_triangle, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _seed() async {
    setState(() => _busy = true);
    try {
      final owners = int.tryParse(_ownersCtrl.text.trim()) ?? 0;
      final nodals = int.tryParse(_nodalsCtrl.text.trim()) ?? 0;
      final domain = _domainCtrl.text.trim().isEmpty ? 'example.com' : _domainCtrl.text.trim();
      final blocks = _blocksCtrl.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
  final svc = ref.read(functionsServiceProvider);
  await svc.seedTestUsers(owners: owners, nodals: nodals, domain: domain, blockIds: blocks.isEmpty ? null : blocks);
  if (!mounted) return; showToast(context, 'Seeding requested. Check Firebase Auth for new users.', icon: CupertinoIcons.person_2);
    } catch (e) {
  if (!mounted) return; showToast(context, 'Seeding failed: $e', icon: CupertinoIcons.exclamationmark_triangle, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
