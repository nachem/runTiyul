import 'package:flutter/material.dart';

import '../../app/app_store.dart';
import '../../models/offline_area.dart';
import '../about/app_version_dialogs.dart';
import '../offline_maps/offline_maps_screen.dart';
import 'trail_map.dart';

/// A stable widget-key identity for the focused offline-area preview. It
/// intentionally excludes download progress (`completedTiles`, `actualBytes`,
/// `status`, and `updatedAt`), so previewing an area while it is still
/// downloading does not change the key on every downloaded tile. A changing key
/// tears down and recreates the whole map — and its controls — many times per
/// second, which leaves the viewer on a gray screen with no map or controls.
/// The key still changes when a different area is shown or its geometry (bounds
/// or zoom range) is edited, so the camera re-centers when it should.
@visibleForTesting
String offlineAreaMapKey(OfflineArea? area) {
  if (area == null) return 'main-map-none';
  final bounds = area.bounds;
  return 'main-map-${area.id}-${area.minZoom}-${area.maxZoom}-'
      '${bounds.north},${bounds.south},${bounds.east},${bounds.west}';
}

class MapScreen extends StatelessWidget {
  const MapScreen({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final offlineArea = store.focusedOfflineArea;
    return Stack(
      children: [
        TrailMap(
          key: ValueKey(offlineAreaMapKey(offlineArea)),
          store: store,
          route: store.selectedRoute,
          routes: store.routes,
          selection: offlineArea?.bounds,
          initialCenter: offlineArea?.bounds.center,
          initialZoom: offlineArea?.minZoom.toDouble(),
          showControls: true,
          controlsTop: offlineArea == null ? 16 : 104,
          autoFit: true,
        ),
        Positioned(
          top: offlineArea == null ? 16 : 104,
          left: 16,
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            elevation: 2,
            shape: const CircleBorder(),
            child: RunTiyulAboutButton(version: store.appVersion),
          ),
        ),
        if (offlineArea != null)
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
              child: ListTile(
                leading: const Icon(Icons.offline_pin),
                title: Text(offlineArea.name),
                subtitle: Text(
                  'Offline bounds • zoom '
                  '${offlineArea.minZoom}-${offlineArea.maxZoom}',
                ),
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => OfflineAreaEditor(
                            store: store,
                            area: offlineArea,
                          ),
                        ),
                      ),
                      tooltip: 'Edit offline bounds',
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      onPressed: () => store.focusOfflineArea(null),
                      tooltip: 'Close offline preview',
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
