import 'package:flutter/material.dart';

import '../../app/app_store.dart';
import '../offline_maps/offline_maps_screen.dart';
import 'trail_map.dart';

class MapScreen extends StatelessWidget {
  const MapScreen({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final offlineArea = store.focusedOfflineArea;
    return Stack(
      children: [
        TrailMap(
          key: ValueKey(
            'main-map-${offlineArea?.id}-${offlineArea?.updatedAt.millisecondsSinceEpoch}',
          ),
          store: store,
          route: store.selectedRoute,
          routes: store.routes,
          selection: offlineArea?.bounds,
          initialCenter: offlineArea?.bounds.center,
          initialZoom: offlineArea?.minZoom.toDouble(),
          showControls: true,
          controlsTop: 104,
          autoFit: true,
        ),
        Positioned(
          top: 16,
          left: 16,
          right: 16,
          child: Card(
            child: ListTile(
              leading: Icon(
                offlineArea == null ? Icons.terrain : Icons.offline_pin,
              ),
              title: Text(
                offlineArea?.name ??
                    store.selectedRoute?.name ??
                    'Explore trails',
              ),
              subtitle: Text(
                offlineArea != null
                    ? 'Offline bounds • zoom ${offlineArea.minZoom}-${offlineArea.maxZoom}'
                    : store.selectedRoute == null
                    ? 'Select a saved route to show it here.'
                    : 'Selected route is ready for recording.',
              ),
              trailing: offlineArea == null
                  ? null
                  : Wrap(
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
