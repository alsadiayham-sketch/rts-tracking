import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rts_tracking/main.dart';

void main() {
  testWidgets('shows an explicit Business demo dashboard', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const RtsTrackingApp());
    await tester.pumpAndSettle();

    expect(find.text('RTS Tracking'), findsOneWidget);
    expect(find.text('Business overview'), findsOneWidget);
    expect(find.text('Sales today'), findsWidgets);
    expect(find.text('RTS Business Main Store'), findsOneWidget);
    expect(find.text('Demo data'), findsOneWidget);
  });

  testWidgets('adapts dashboard content for Clinic locations', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const RtsTrackingApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('RTS Clinic'));
    await tester.pumpAndSettle();

    expect(find.text('Clinic overview'), findsOneWidget);
    expect(find.text('Patients waiting'), findsOneWidget);
    expect(find.text('RTS Clinic North'), findsWidgets);
    expect(find.text('Sales today'), findsNothing);
  });

  testWidgets('bottom navigation exposes locations, alerts, and settings', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const RtsTrackingApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Locations'));
    await tester.pump();
    expect(find.text('Business stores'), findsOneWidget);
    expect(find.text('RTS Business Warehouse'), findsOneWidget);

    await tester.tap(find.text('Alerts'));
    await tester.pump();
    expect(find.text('RTS Business alerts'), findsOneWidget);
    expect(find.text('Warehouse is offline'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pump();
    expect(find.text('Authentication not connected'), findsOneWidget);
    expect(find.text('Connectivity behavior'), findsOneWidget);
  });

  testWidgets('supports a narrow viewport with 200 percent text scaling', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(2)),
        child: RtsTrackingApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Business overview'), findsOneWidget);
  });
}
