import 'package:flutter/material.dart';

import '../../app/app_store.dart';
import '../../core/units/formatters.dart';
import '../../models/run_activity.dart';
import '../map/trail_map.dart';

class ActivitiesScreen extends StatelessWidget {
  const ActivitiesScreen({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final completed = store.activities
        .where((activity) => activity.status == ActivityStatus.completed)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Activities')),
      body: completed.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.directions_run, size: 72),
                    SizedBox(height: 16),
                    Text('Finished runs will appear here.'),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: completed.length,
              itemBuilder: (context, index) {
                final activity = completed[index];
                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.directions_run),
                    ),
                    title: Text(
                      MaterialLocalizations.of(
                        context,
                      ).formatMediumDate(activity.startedAt.toLocal()),
                    ),
                    subtitle: Text(
                      '${formatDistance(activity.distanceMeters)}'
                      ' • ${formatDuration(activity.elapsed)}'
                      ' • ${formatPace(activity.distanceMeters, activity.elapsed)}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ActivityDetailScreen(
                          store: store,
                          activity: activity,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class ActivityDetailScreen extends StatelessWidget {
  const ActivityDetailScreen({
    super.key,
    required this.store,
    required this.activity,
  });

  final AppStore store;
  final RunActivity activity;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity details'),
        actions: [
          IconButton(
            onPressed: activity.samples.isEmpty
                ? null
                : () => store.exportActivity(activity),
            tooltip: 'Export GPX',
            icon: const Icon(Icons.ios_share),
          ),
          IconButton(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Delete activity?'),
                  content: const Text('The saved GPS track will be removed.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await store.deleteActivity(activity);
                if (context.mounted) Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: TrailMap(
              store: store,
              track: activity.samples.map((sample) => sample.latLng).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _Summary(
                  label: 'Distance',
                  value: formatDistance(activity.distanceMeters),
                ),
                _Summary(
                  label: 'Time',
                  value: formatDuration(activity.elapsed),
                ),
                _Summary(
                  label: 'Average pace',
                  value: formatPace(activity.distanceMeters, activity.elapsed),
                ),
                _Summary(
                  label: 'Elevation gain',
                  value: '${activity.elevationGainMeters.round()} m',
                ),
                _Summary(
                  label: 'GPS points',
                  value: '${activity.samples.length}',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        Text(value, style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }
}
