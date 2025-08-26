import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/data/auth_repository.dart';
import 'nodal_dashboard_list_page.dart';
import 'metrics_tiles.dart';
import '../../../core/widgets/branding_footer.dart';

class NodalDashboardPage extends ConsumerWidget {
  const NodalDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.read(authRepositoryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
  actions: [
          IconButton(
            onPressed: () => auth.signOut(),
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
          )
        ],
      ),
      body: const Column(
        children: [
          Padding(
            padding: EdgeInsets.all(8.0),
            child: MetricsTiles(),
          ),
          Expanded(child: NodalDashboardListPage()),
        ],
      ),
  bottomNavigationBar: const BrandingFooter(),
    );
  }
}
