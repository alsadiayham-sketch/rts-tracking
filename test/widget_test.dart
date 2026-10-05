import 'package:flutter_test/flutter_test.dart';

import 'package:rts_tracking/main.dart';

void main() {
  testWidgets('RTS Tracking shows the owner dashboard', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const RtsTrackingApp());
    await tester.pumpAndSettle();

    expect(find.text('RTS Tracking'), findsOneWidget);
    expect(find.text('RTS Business'), findsOneWidget);
    expect(find.text('Business overview'), findsOneWidget);
  });
}
