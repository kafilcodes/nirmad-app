import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/data/auth_repository.dart';
import '../../projects/data/project_repository.dart';
import 'project_edit_page.dart';
import '../../projects/presentation/project_detail_page.dart';
import '../../../core/widgets/branding_footer.dart';

class OwnerHomePage extends ConsumerWidget {
  const OwnerHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.read(authRepositoryProvider);
    final projectsAsync = ref.watch(ownerProjectsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Projects'),
        actions: [
          IconButton(
            onPressed: () => auth.signOut(),
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
          )
        ],
      ),
      body: projectsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (projects) {
          if (projects.isEmpty) {
            return const Center(child: Text('No projects yet'));
          }
          return ListView.separated(
            itemCount: projects.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final p = projects[index];
              return ListTile(
                title: Text(p.name),
                subtitle: Text('#${p.id} • ${p.status.name} • Phase ${p.phase}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProjectDetailPage(project: p))),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProjectEditPage()));
          ref.invalidate(ownerProjectsProvider);
        },
        child: const Icon(Icons.add),
      ),
  bottomNavigationBar: const BrandingFooter(),
    );
  }
}
