import 'package:flutter/material.dart';

import '../../app/app_store.dart';
import '../../core/units/formatters.dart';
import '../../models/run_activity.dart';
import '../../services/navigation_monitor.dart';
import '../map/trail_map.dart';

class RecordScreen extends StatelessWidget {
  const RecordScreen({super.key, required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final activity = store.activeActivity;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Record activity'),
        actions: [
          IconButton(
            tooltip: 'Alerts',
            icon: const Icon(Icons.notifications_active_outlined),
            onPressed: () => _showAlertSettings(context, store),
          ),
        ],
      ),
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
          child: TrailMap(
            store: store,
            route: store.selectedRoute,
            routes: store.routes,
            showControls: true,
          ),
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
            routes: store.routes,
            track: activity.samples.map((sample) => sample.latLng).toList(),
            showControls: true,
          ),
        ),
        if (store.navStatus.offRoute || store.navStatus.junctionAhead != null)
          _NavBanner(status: store.navStatus),
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

void _showAlertSettings(BuildContext context, AppStore store) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => AlertSettingsSheet(store: store),
  );
}

class _NavBanner extends StatelessWidget {
  const _NavBanner({required this.status});

  final NavStatus status;

  @override
  Widget build(BuildContext context) {
    final offRoute = status.offRoute;
    final scheme = Theme.of(context).colorScheme;
    final color = offRoute ? scheme.error : scheme.tertiary;
    final distance = status.distanceToRouteMeters;
    final IconData icon;
    final String text;
    if (offRoute) {
      icon = Icons.wrong_location;
      text = distance != null
          ? 'Off route \u2022 ${distance.round()} m away'
          : 'Off route';
    } else {
      final turn = status.junctionTurn;
      icon = switch (turn) {
        TurnDirection.left => Icons.turn_left,
        TurnDirection.right => Icons.turn_right,
        TurnDirection.straight => Icons.straight,
        null => Icons.fork_right,
      };
      final junctionDistance = status.junctionDistanceMeters;
      final lead = junctionDistance != null
          ? 'Junction in ${junctionDistance.round()} m'
          : 'Junction ahead';
      final guidance = switch (turn) {
        TurnDirection.left => 'keep left',
        TurnDirection.right => 'keep right',
        TurnDirection.straight => 'continue straight',
        null => null,
      };
      text = guidance != null ? '$lead \u2022 $guidance' : lead;
    }
    return Material(
      color: color.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AlertSettingsSheet extends StatefulWidget {
  const AlertSettingsSheet({super.key, required this.store});

  final AppStore store;

  @override
  State<AlertSettingsSheet> createState() => _AlertSettingsSheetState();
}

class _AlertSettingsSheetState extends State<AlertSettingsSheet> {
  late NavAlertConfig _config = widget.store.navAlertConfig;
  NavAlert? _previewing;

  Future<void> _preview(NavAlert alert) async {
    setState(() => _previewing = alert);
    final result = await widget.store.previewNavigationAlert(
      alert,
      config: _config,
    );
    if (!mounted) return;
    setState(() => _previewing = null);

    final String? message;
    if (_config.feedbackMode.usesVoice && !result.voiceSpoken) {
      message = result.tonePlayed
          ? 'Voice is unavailable. The alert tone played instead.'
          : 'Voice is unavailable. Install an English system voice.';
    } else if (_config.feedbackMode != NavFeedbackMode.hapticsOnly &&
        !result.audioPlayed) {
      message = 'Alert audio could not play. Check the media volume.';
    } else {
      message = null;
    }
    if (message != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Live alerts',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<NavFeedbackMode>(
                key: const ValueKey('nav-feedback-mode'),
                initialValue: _config.feedbackMode,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Alert output',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.volume_up_outlined),
                ),
                items:
                    const [
                          NavFeedbackMode.toneAndVoice,
                          NavFeedbackMode.voice,
                          NavFeedbackMode.tones,
                          NavFeedbackMode.hapticsOnly,
                        ]
                        .map(
                          (mode) => DropdownMenuItem(
                            value: mode,
                            child: Text(_feedbackLabel(mode)),
                          ),
                        )
                        .toList(growable: false),
                onChanged: (mode) {
                  if (mode == null) return;
                  setState(
                    () => _config = _config.copyWith(feedbackMode: mode),
                  );
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Test alerts',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('test-off-route-alert'),
                      onPressed: _previewing == null
                          ? () => _preview(NavAlert.offRoute)
                          : null,
                      icon: _previewing == NavAlert.offRoute
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wrong_location_outlined),
                      label: const Text('Off route'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('test-junction-alert'),
                      onPressed: _previewing == null
                          ? () => _preview(NavAlert.junction)
                          : null,
                      icon: _previewing == NavAlert.junction
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.turn_left),
                      label: const Text('Junction'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _config.offRouteEnabled,
                onChanged: (value) => setState(
                  () => _config = _config.copyWith(offRouteEnabled: value),
                ),
                title: const Text('Off-route alert'),
              ),
              ListTile(
                enabled: _config.offRouteEnabled,
                title: Text(
                  'Off-route distance: ${_config.offRouteMeters.round()} m',
                ),
                subtitle: Slider(
                  min: 10,
                  max: 100,
                  divisions: 18,
                  value: _config.offRouteMeters.clamp(10.0, 100.0).toDouble(),
                  label: '${_config.offRouteMeters.round()} m',
                  onChanged: _config.offRouteEnabled
                      ? (value) => setState(
                          () =>
                              _config = _config.copyWith(offRouteMeters: value),
                        )
                      : null,
                ),
              ),
              ListTile(
                enabled: _config.offRouteEnabled,
                title: Text(
                  'Confirm over ${_config.offRoutePersistence} GPS fixes',
                ),
                subtitle: Slider(
                  min: 1,
                  max: 10,
                  divisions: 9,
                  value: _config.offRoutePersistence.clamp(1, 10).toDouble(),
                  label: '${_config.offRoutePersistence}',
                  onChanged: _config.offRouteEnabled
                      ? (value) => setState(
                          () => _config = _config.copyWith(
                            offRoutePersistence: value.round(),
                          ),
                        )
                      : null,
                ),
              ),
              const Divider(),
              SwitchListTile(
                value: _config.junctionEnabled,
                onChanged: (value) => setState(
                  () => _config = _config.copyWith(junctionEnabled: value),
                ),
                title: const Text('Junction alert'),
              ),
              ListTile(
                enabled: _config.junctionEnabled,
                title: Text(
                  'Junction distance: ${_config.junctionMeters.round()} m',
                ),
                subtitle: Slider(
                  min: 10,
                  max: 100,
                  divisions: 18,
                  value: _config.junctionMeters.clamp(10.0, 100.0).toDouble(),
                  label: '${_config.junctionMeters.round()} m',
                  onChanged: _config.junctionEnabled
                      ? (value) => setState(
                          () =>
                              _config = _config.copyWith(junctionMeters: value),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () async {
                  await widget.store.setNavAlertConfig(_config);
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('Save alerts'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _feedbackLabel(NavFeedbackMode mode) => switch (mode) {
  NavFeedbackMode.toneAndVoice => 'Tone + voice',
  NavFeedbackMode.voice => 'Voice',
  NavFeedbackMode.tones => 'Tones',
  NavFeedbackMode.hapticsOnly => 'Haptics only',
};

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
