import 'dart:async';

import 'package:flutter/material.dart';

import '../features/about/app_version_dialogs.dart';
import '../features/activities/activities_screen.dart';
import '../features/map/map_screen.dart';
import '../features/offline_maps/offline_maps_screen.dart';
import '../features/recording/record_screen.dart';
import '../features/routes/routes_screen.dart';
import '../services/tile_store.dart';
import 'app_store.dart';

class TrailRunnerApp extends StatelessWidget {
  const TrailRunnerApp({super.key, required this.store, this.initialIndex = 0});

  final AppStore store;
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RunTiyul',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF246B3B),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: const CardThemeData(
          margin: EdgeInsets.symmetric(vertical: 6),
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6CBF84),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: AppShell(store: store, initialIndex: initialIndex),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.store, this.initialIndex = 0});

  final AppStore store;
  final int initialIndex;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  late var _index = widget.initialIndex;
  var _versionDialogScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_showPendingVersionUpdate());
    });
  }

  Future<void> _showPendingVersionUpdate() async {
    final previousVersion = widget.store.previousAppVersion;
    if (!mounted || _versionDialogScheduled || previousVersion == null) return;
    _versionDialogScheduled = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AppUpdatedDialog(
        currentVersion: widget.store.appVersion,
        previousVersion: previousVersion,
      ),
    );
    if (!mounted) return;
    await widget.store.acknowledgeAppUpdate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning to the foreground: resume any download the OS interrupted while
    // the app was backgrounded.
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.store.resumeInterruptedDownloads());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final pages = [
          MapScreen(store: widget.store),
          RoutesScreen(
            store: widget.store,
            onShowMap: () => setState(() => _index = 0),
            onStart: () => setState(() => _index = 2),
          ),
          RecordScreen(store: widget.store),
          ActivitiesScreen(store: widget.store),
          OfflineMapsScreen(
            store: widget.store,
            onPreview: (area) {
              widget.store.focusOfflineArea(area);
              unawaited(widget.store.setMapTileMode(MapTileMode.offline));
              setState(() => _index = 0);
            },
          ),
        ];
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                if (widget.store.errorMessage != null)
                  MaterialBanner(
                    content: Text(widget.store.errorMessage!),
                    actions: [
                      TextButton(
                        onPressed: widget.store.clearError,
                        child: const Text('Dismiss'),
                      ),
                    ],
                  ),
                Expanded(
                  child: widget.store.loading
                      ? const Center(child: CircularProgressIndicator())
                      : pages[_index],
                ),
              ],
            ),
          ),
          bottomNavigationBar: TrailNavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (value) => setState(() => _index = value),
          ),
        );
      },
    );
  }
}

class TrailNavigationBar extends StatelessWidget {
  const TrailNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.map_outlined),
          selectedIcon: Icon(Icons.map),
          label: 'Map',
        ),
        NavigationDestination(
          icon: Icon(Icons.route_outlined),
          selectedIcon: Icon(Icons.route),
          label: 'Routes',
        ),
        NavigationDestination(
          icon: Icon(Icons.fiber_manual_record_outlined),
          selectedIcon: Icon(Icons.fiber_manual_record),
          label: 'Record',
        ),
        NavigationDestination(
          icon: Icon(Icons.history),
          selectedIcon: Icon(Icons.history_toggle_off),
          label: 'Activities',
        ),
        NavigationDestination(
          icon: Icon(Icons.offline_pin_outlined),
          selectedIcon: Icon(Icons.offline_pin),
          label: 'Offline',
        ),
      ],
    );
  }
}
