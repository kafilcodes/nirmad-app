import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/data/auth_repository.dart';
import 'package:go_router/go_router.dart';
import 'app_sidebar.dart';

/// AppShell is a reusable scaffold that renders a SidebarX-based navigation
/// and a top app bar with an optional title and actions. Use it across pages
/// for a consistent production-ready layout.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.body, this.title, this.initialIndex, this.onSelect});
  final Widget body;
  final String? title;
  final int? initialIndex;
  final void Function(int index)? onSelect;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;
  bool _sidebarOpen = true;
  bool _autoManageSidebar = true;

  @override
  void initState() {
    super.initState();
  _index = widget.initialIndex ?? 0;
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.read(authRepositoryProvider);
    final screenW = MediaQuery.of(context).size.width;
    final overlaySidebar = screenW < 900; // overlay on phones/tablets
    final desiredOpen = !overlaySidebar; // open by default on wide screens
    if (_autoManageSidebar && _sidebarOpen != desiredOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _sidebarOpen = desiredOpen);
      });
    }

    return Scaffold(
      body: Stack(
        children: [
          Row(
            children: [
              if (!overlaySidebar) ...[
                SizedBox(
                  width: 256,
                  child: AppSidebar(
                    selectedIndex: _index,
                    onSelect: (i) {
                      setState(() => _index = i);
                      widget.onSelect?.call(i);
                    },
                  ),
                ),
                VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
              ],
              Expanded(
                child: Column(
                  children: [
                    SizedBox(
                      height: 56,
                      child: Row(children: [
                        if (overlaySidebar)
                          IconButton(
                            icon: const Icon(CupertinoIcons.bars),
                            onPressed: () => setState(() {
                              _sidebarOpen = true;
                              _autoManageSidebar = false;
                            }),
                            tooltip: 'Menu',
                          )
                        else
                          const SizedBox(width: 12),
                        if (widget.title != null)
                          Expanded(
                            child: Text(
                              widget.title!,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                        else
                          const Spacer(),
                        IconButton(
                          onPressed: () async {
                            await auth.signOut();
                            if (context.mounted) context.go('/');
                          },
                          icon: const Icon(CupertinoIcons.square_arrow_right),
                          tooltip: 'Sign out',
                        ),
                      ]),
                    ),
                    Divider(height: 1, color: Theme.of(context).dividerColor),
                    Expanded(child: widget.body),
                  ],
                ),
              ),
            ],
          ),

          // Backdrop below, overlayed sidebar above for correct hit testing
          if (overlaySidebar && _sidebarOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _sidebarOpen = false),
                child: Container(color: Colors.black26),
              ),
            ),
          if (overlaySidebar)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              top: 0,
              bottom: 0,
              left: _sidebarOpen ? 0 : -300,
              width: 280,
              child: Material(
                elevation: 8,
                color: Theme.of(context).colorScheme.surface,
                child: SafeArea(
                  child: AppSidebar(
                    selectedIndex: _index,
                    onSelect: (i) {
                      setState(() {
                        _index = i;
                        _sidebarOpen = false; // close on selection
                        _autoManageSidebar = false;
                      });
                      widget.onSelect?.call(i);
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
