import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:nirmadapp/src/shared/widgets/hybrid_tooltip.dart';

// Default Chhattisgarh bounding box (approx)
const _cgMinLat = 17.78;
const _cgMaxLat = 24.10;
const _cgMinLng = 80.22;
const _cgMaxLng = 84.40;
final LatLngBounds _cgBounds = LatLngBounds.fromPoints(const [
  LatLng(_cgMinLat, _cgMinLng),
  LatLng(_cgMaxLat, _cgMaxLng),
]);

/// A reusable map widget for consistent map behavior across the app.
/// - Uses a single light tile source (OSM) with production-friendly defaults
/// - Removes dark mode switching
/// - Disables retina tiles to avoid 404s and failed tile loads on some providers
/// - Exposes configurable interaction flags to ensure drag works on Android/Web
/// - Supports optional marker and tap handling
/// - Optional info icon overlay with a tooltip for consistent instructions
class AppMap extends StatelessWidget {
  const AppMap({
    super.key,
    required this.initialCenter,
    this.initialZoom = 14,
    this.minZoom = 8,
    this.maxZoom = 19,
    this.flags,
    this.onTap,
    this.marker,
    this.controller,
    this.cameraBounds,
    this.showAttribution = false,
    this.infoMessage,
    this.infoAlignment = Alignment.bottomRight,
  });

  final LatLng initialCenter;
  final double initialZoom;
  final double minZoom;
  final double maxZoom;
  final int? flags;
  final void Function(TapPosition, LatLng)? onTap;
  final LatLng? marker;
  final MapController? controller;
  final LatLngBounds? cameraBounds;
  final bool showAttribution;

  /// If provided, an info icon will be overlaid on the map with this tooltip message
  final String? infoMessage;

  /// Where to place the info icon overlay within the map
  final Alignment infoAlignment;

  @override
  Widget build(BuildContext context) {
    final int resolvedFlags = flags ??
        (InteractiveFlag.drag |
            InteractiveFlag.pinchZoom |
            InteractiveFlag.doubleTapZoom |
            InteractiveFlag.scrollWheelZoom) &
            ~InteractiveFlag.flingAnimation; // more stable on mobile/web

    final map = FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: initialCenter,
        initialZoom: initialZoom,
        minZoom: minZoom,
        maxZoom: maxZoom,
        interactionOptions: InteractionOptions(flags: resolvedFlags),
        cameraConstraint: CameraConstraint.contain(
          bounds: cameraBounds ?? _cgBounds,
        ),
        onTap: onTap,
      ),
      children: [
        // Single light tile source (OSM) with non-retina tiles + built-in caching
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.nirmadapp',
          maxZoom: 19,
          retinaMode: false,
          tileProvider: NetworkTileProvider(
            cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(),
          ),
          errorTileCallback: (tile, error, stackTrace) {
            // Avoid throwing, just log in debug to prevent noisy console
            debugPrint('Tile load error: $error');
          },
        ),
        if (showAttribution)
          const RichAttributionWidget(
            attributions: [
              TextSourceAttribution('© OpenStreetMap contributors'),
            ],
            alignment: AttributionAlignment.bottomRight,
          ),
        if (marker != null)
          MarkerLayer(
            markers: [
              Marker(
                point: marker!,
                width: 40,
                height: 40,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.location_on,
                  color: Colors.redAccent,
                  size: 36,
                ),
              ),
            ],
          ),
      ],
    );

    if (infoMessage == null || infoMessage!.isEmpty) {
      return map;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        map,
        Align(
          alignment: infoAlignment,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: HybridTooltip(
              message: infoMessage!,
              child: const Icon(Icons.info_outline, size: 16, color: Colors.grey),
            ),
          ),
        ),
      ],
    );
  }
}