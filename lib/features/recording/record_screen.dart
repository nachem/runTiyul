import 'package:flutter/material.dart';

import '../../app/app_store.dart';
import '../../core/units/formatters.dart';
import '../../models/run_activity.dart';
import '../map/trail_map.dart';

class RecordScreen extends StatelessWidget {
  const RecordScreen({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final activity = store.activeActivity;
    return Scaffold(
      appBar: AppBar(title: const Text('Record activity')),
      body: activity == null
          ? _ReadyToRecord(store: store)
          : _ActiveRecording(store: store, activity: activity),
    );
  }
}

class _ReadyToRecord extends StatelessWidget {
  const _ReadyToRecord({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: TrailMap(store: store, route: store.selectedRoute),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String?>(
                initialValue: store.selectedRoute?.id,
                decoration: const InputDecoration(
                  labelText: 'Route (optional)',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Free run')),
                  ...store.routes.map(
                    (route) => DropdownMenuItem(
                      value: route.id,
                      child: Text(route.name),
                    ),
                  ),
                ],
                onChanged: (id) => store.selectRoute(
                  store.routes.where((route) => route.id == id).firstOrNull,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Location is stored locally. Background recording requires the '
                'platform location permission and shows a persistent indicator.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: store.startActivity,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start run'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActiveRecording extends StatelessWidget {
  const _ActiveRecording({required this.store, required this.activity});

  final AppStore store;
  final RunActivity activity;

  @override
  Widget build(BuildContext context) {
    final route = store.routes
        .where((item) => item.id == activity.routeId)
        .firstOrNull;
    return Column(
      children: [
        Expanded(
          child: TrailMap(
            store: store,
            route: route,
            track: activity.samples.map((sample) => sample.latLng).toList(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  _Metric(
                    label: 'TIME',
                    value: formatDuration(activity.elapsed),
                  ),
                  _Metric(
                    label: 'DISTANCE',
                    value: formatDistance(activity.distanceMeters),
                  ),
                  _Metric(
                    label: 'PACE',
                    value: formatPace(
                      activity.distanceMeters,
                      activity.elapsed,
                    ),
                  ),
                  _Metric(
                    label: 'GAIN',
                    value: '${activity.elevationGainMeters.round()} m',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Discard activity?'),
                            content: const Text(
                              'The recorded track will be permanently deleted.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Keep'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Discard'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) await store.discardActivity();
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Discard'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: activity.status == ActivityStatus.recording
                          ? store.pauseActivity
                          : store.resumeActivity,
                      icon: Icon(
                        activity.status == ActivityStatus.recording
                            ? Icons.pause
                            : Icons.play_arrow,
                      ),
                      label: Text(
                        activity.status == ActivityStatus.recording
                            ? 'Pause'
                            : 'Resume',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: store.finishActivity,
                      icon: const Icon(Icons.stop),
                      label: const Text('Finish'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
