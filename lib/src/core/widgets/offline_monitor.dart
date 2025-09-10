import 'package:flutter/material.dart';
import 'package:flutter_offline/flutter_offline.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:toastification/toastification.dart';

/// Global connectivity monitor that shows brief toasts on offline/online state changes.
///
/// Offline: show for up to 5 seconds, once per transition.
/// Online: show for 3 seconds, once per transition.
class OfflineMonitor extends StatefulWidget {
  const OfflineMonitor({super.key, required this.child});
  final Widget child;

  @override
  State<OfflineMonitor> createState() => _OfflineMonitorState();
}

class _OfflineMonitorState extends State<OfflineMonitor> {
  bool? _lastConnected;
  @override
  Widget build(BuildContext context) {
    return OfflineBuilder(
      connectivityBuilder: (context, connectivity, child) {
        final connected = connectivity != ConnectivityResult.none;
        if (_lastConnected == null) {
          _lastConnected = connected;
        } else if (_lastConnected != connected) {
          _lastConnected = connected;
          // Fire a toast on transition
          WidgetsBinding.instance.addPostFrameCallback((_) {
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
          });
        }
        return child;
      },
      builder: (context) => widget.child,
    );
  }
}
