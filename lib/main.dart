import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AppBootstrap(createStore: AppStore.create));
}

/// APP-003/HIS-003: initialization errors must leave a retryable screen rather
/// than an unhandled pre-runApp future or permanent launch splash. No reset or
/// deletion of the user's local database is attempted.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({required this.createStore, super.key});

  final Future<AppStore> Function() createStore;

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  late Future<AppStore> _store;

  @override
  void initState() {
    super.initState();
    _startLoading();
  }

  void _startLoading() {
    _store = Future<AppStore>.sync(widget.createStore);
    // A retry can fail before the next frame subscribes FutureBuilder. Attach
    // an error listener immediately; FutureBuilder still displays the error.
    _store.ignore();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<AppStore>(
    future: _store,
    builder: (context, snapshot) {
      if (snapshot.hasData) return TrailRunnerApp(store: snapshot.requireData);
      return MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: snapshot.hasError
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('RunTiyul could not start'),
                          const SizedBox(height: 12),
                          const Text(
                            'Local storage or a device service is unavailable. '
                            'Your saved data has not been reset. Check available '
                            'storage, then retry. Do not uninstall to troubleshoot.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: () => setState(_startLoading),
                            child: const Text('Retry'),
                          ),
                        ],
                      )
                    : const CircularProgressIndicator(),
              ),
            ),
          ),
        ),
      );
    },
  );
}
