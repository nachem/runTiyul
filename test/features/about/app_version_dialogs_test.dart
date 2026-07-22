import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trail_runner/features/about/app_version_dialogs.dart';
import 'package:trail_runner/services/app_version_service.dart';

const _version = AppVersionInfo(
  appName: 'RunTiyul',
  packageName: 'com.bernoulli.trailrunner.trail_runner',
  version: '1.2.1',
  buildNumber: '6',
);

void main() {
  testWidgets('update dialog identifies the old and installed versions', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppUpdatedDialog(
            currentVersion: _version,
            previousVersion: '1.2.0+5',
          ),
        ),
      ),
    );

    expect(find.text('RunTiyul was updated'), findsOneWidget);
    expect(find.textContaining('1.2.1 (build 6)'), findsOneWidget);
    expect(find.textContaining('1.2.0+5'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('about button displays the installed version', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: RunTiyulAboutButton(version: _version)),
      ),
    );

    await tester.tap(find.byTooltip('About RunTiyul'));
    await tester.pumpAndSettle();

    expect(find.text('RunTiyul'), findsWidgets);
    expect(find.text('1.2.1 (build 6)'), findsOneWidget);
  });
}
