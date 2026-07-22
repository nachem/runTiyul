import 'package:flutter/material.dart';

import '../../services/app_version_service.dart';

class AppUpdatedDialog extends StatelessWidget {
  const AppUpdatedDialog({
    super.key,
    required this.currentVersion,
    required this.previousVersion,
  });

  final AppVersionInfo currentVersion;
  final String previousVersion;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.system_update_alt),
      title: const Text('RunTiyul was updated'),
      content: Text(
        'Version ${currentVersion.displayLabel} is installed. The previous '
        'version was $previousVersion.\n\nYour routes, activities, settings, '
        'and offline maps remain on this device.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class RunTiyulAboutButton extends StatelessWidget {
  const RunTiyulAboutButton({super.key, required this.version});

  final AppVersionInfo version;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'About RunTiyul',
      onPressed: () => showAboutDialog(
        context: context,
        applicationName: version.appName,
        applicationVersion: version.displayLabel,
        applicationIcon: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(
            'assets/branding/app_icon.png',
            width: 52,
            height: 52,
          ),
        ),
        applicationLegalese: 'Copyright (c) 2026 Bernoulli Software',
        children: const [
          Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text(
              'Offline-first route planning, navigation, activity recording, '
              'and map storage for trail runners.',
            ),
          ),
        ],
      ),
      icon: const Icon(Icons.info_outline),
    );
  }
}
