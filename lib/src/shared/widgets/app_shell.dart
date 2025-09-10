import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_sidebar.dart';
import '../navigation/unsaved_changes_guard.dart';

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
  bool _sidebarCollapsed = false; // desktop icon-only mode
  bool _sidebarHidden = false; // desktop fully hidden

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
  // final auth = ref.read(authRepositoryProvider); // logout moved to sidebar footer
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
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  width: _sidebarHidden ? 0 : (_sidebarCollapsed ? 72 : 256),
                  child: _sidebarHidden
                      ? const SizedBox.shrink()
                      : AppSidebar(
                    selectedIndex: _index,
                    onSelect: (i) async {
                      final guard = ref.read(unsavedChangesGuardProvider);
                      final ok = await guard.confirm();
                      if (!ok) return;
                      setState(() => _index = i);
                      widget.onSelect?.call(i);
                    },
                    collapsed: _sidebarCollapsed,
                  ),
                ),
                // Removed sidebar divider for a flat, seamless layout
                // (no visual separation between sidebar and content)
              ],
              Expanded(
                child: SafeArea(
                  top: true,
                  bottom: false,
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
                        else ...[
                          const SizedBox(width: 6),
                          Row(children: [
                            Tooltip(
                              message: _sidebarHidden ? 'Show sidebar' : 'Hide sidebar',
                              child: IconButton(
                                icon: Icon(_sidebarHidden ? Icons.menu : Icons.menu_open),
                                onPressed: () => setState(() => _sidebarHidden = !_sidebarHidden),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Tooltip(
                              message: _sidebarCollapsed ? 'Expand sidebar' : 'Collapse sidebar',
                              child: IconButton(
                                icon: Icon(_sidebarCollapsed ? CupertinoIcons.right_chevron : CupertinoIcons.left_chevron),
                                onPressed: () => setState(() => _sidebarCollapsed = !_sidebarCollapsed),
                              ),
                            ),
                          ]),
                          const SizedBox(width: 6),
                        ],
                        if (widget.title != null)
                          Expanded(
                            child: Text(
                              widget.title!,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                        else
                          const Spacer(),
                      ]),
                    ),
                    Divider(height: 1, color: Theme.of(context).dividerColor),
                    Expanded(child: widget.body),
                  ],
                  ),
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
                // Remove elevation to match the flat sidebar design
                elevation: 0,
                color: Theme.of(context).colorScheme.surface,
                child: SafeArea(
                  child: AppSidebar(
                    selectedIndex: _index,
                    onSelect: (i) async {
                      final guard = ref.read(unsavedChangesGuardProvider);
                      final ok = await guard.confirm();
                      if (!ok) return;
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
