import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:toastification/toastification.dart';

/// Global connectivity monitor using connectivity_plus.
/// - Shows a non-intrusive offline banner when there is no network.
/// - Emits toasts when going offline/online.
class OfflineMonitor extends StatefulWidget {
  const OfflineMonitor({super.key, required this.child});
  final Widget child;

  @override
  State<OfflineMonitor> createState() => _OfflineMonitorState();
}

class _OfflineMonitorState extends State<OfflineMonitor> {
  late final Connectivity _conn;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _offline = false;
  bool? _lastConnected;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _conn = Connectivity();
    _init();
  }

  Future<void> _init() async {
    try {
      final initial = await _conn.checkConnectivity();
      _applyStatus(initial);
    } catch (_) {}
    _sub = _conn.onConnectivityChanged.listen((results) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 700), () => _applyStatus(results));
    });
  }

  void _applyStatus(List<ConnectivityResult> results) {
    final connected = results.any((r) => r != ConnectivityResult.none);
    if (_lastConnected == null) {
      _lastConnected = connected;
    } else if (_lastConnected != connected) {
      _lastConnected = connected;
      if (!mounted) return;
      if (connected) {
        toastification.show(
          context: context,
          type: ToastificationType.success,
          style: ToastificationStyle.fillColored,
          autoCloseDuration: const Duration(seconds: 3),
          title: const Text('Back online'),
          description: const Text('Connectivity restored.'),
          showProgressBar: false,
        );
      } else {
        toastification.show(
          context: context,
          type: ToastificationType.warning,
          style: ToastificationStyle.fillColored,
          autoCloseDuration: const Duration(seconds: 5),
          title: const Text('You are offline'),
          description: const Text('Some actions will queue until online.'),
          showProgressBar: true,
        );
      }
    }
    if (mounted) setState(() => _offline = !connected);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        // Offline floating banner
        Positioned(
          left: 12,
          right: 12,
          bottom: 12 + MediaQuery.of(context).viewInsets.bottom,
          child: IgnorePointer(
            ignoring: !_offline,
            child: AnimatedOpacity(
              opacity: _offline ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: _OfflineBanner(),
            ),
          ),
        ),
      ],
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: cs.errorContainer.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.error.withValues(alpha: 0.3)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.wifi_off_rounded, color: cs.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'You’re offline — changes will sync when connected',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
