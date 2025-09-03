import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/project_repository.dart';
import '../domain/project.dart';
import '../domain/project_update.dart';
import 'phase_update_stepper_page.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../services/functions_service.dart';
import '../../../core/widgets/branding_footer.dart';
import '../../../shared/ui/toast.dart';

class ProjectDetailPage extends ConsumerWidget {
  final Project project;
  const ProjectDetailPage({super.key, required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
  final updatesStream = ref.read(projectRepositoryProvider).watchUpdates(project.id);
    return Scaffold(
      appBar: AppBar(
        title: Text(project.name),
        actions: [
          IconButton(
            tooltip: 'Export ZIP',
            icon: const Icon(CupertinoIcons.arrow_down_doc),
              onPressed: () async {
                try {
                  if (!context.mounted) return;
                  showToast(context, 'Preparing export…', icon: CupertinoIcons.arrow_down_doc);
                  final url = await ref.read(functionsServiceProvider).exportProjectZip(project.id);
                  final uri = Uri.parse(url);
                  if (!context.mounted) return;
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    if (!context.mounted) return;
                    showToast(context, 'Download link: $url', icon: CupertinoIcons.link);
                  }
                } catch (e) {
                  if (!context.mounted) return;
                  showToast(context, 'Export failed: $e', icon: CupertinoIcons.exclamationmark_triangle, error: true);
                }
              },
          ),
        ],
  ),
      body: Column(
        children: [
          ListTile(
            title: Text('Status: ${project.status.name}'),
            subtitle: Text('Phase: ${project.phase}'),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder(
              stream: updatesStream,
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final updates = snapshot.data as List<ProjectUpdate>;
                if (updates.isEmpty) return const Center(child: Text('No updates yet'));
                return ListView.separated(
                  itemCount: updates.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final u = updates[index];
                    return ListTile(
                      title: Text('Phase ${u.phase}'),
                      subtitle: Text(u.comment ?? ''),
                      trailing: Text(u.createdAt.toLocal().toString().split('.').first),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
  bottomNavigationBar: const BrandingFooter(),
      floatingActionButton: project.status == ProjectStatus.completed
          ? null
          : FloatingActionButton(
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PhaseUpdateStepperPage(project: project)));
              },
              child: const Icon(CupertinoIcons.add),
            ),
    );
  }
}
