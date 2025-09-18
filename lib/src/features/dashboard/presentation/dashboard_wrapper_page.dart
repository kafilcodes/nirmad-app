import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/app_user.dart';
import 'nodal_dashboard_page.dart';
import '../../admin/presentation/prod_admin_dashboard_page.dart';
import '../../../shared/ui/progress.dart';

class DashboardWrapperPage extends ConsumerWidget {
  const DashboardWrapperPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(authStateProvider);
    if (!userAsync.hasValue) {
      return const Scaffold(body: Center(child: AppLoadingIndicator()));
    }
    final user = userAsync.value;
    if (user == null) {
      return const Scaffold(body: Center(child: AppLoadingIndicator()));
    }
    final isAdmin = user.role == UserRole.devAdmin;
    return isAdmin ? const ProdAdminDashboardPage() : const NodalDashboardPage();
  }
}
