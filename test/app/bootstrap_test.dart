import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trail_runner/main.dart';

void main() {
  testWidgets('startup failure is retryable without an uncaught exception', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      AppBootstrap(
        createStore: () async {
          attempts++;
          throw StateError('Storage unavailable');
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('RunTiyul could not start'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
  });
}
