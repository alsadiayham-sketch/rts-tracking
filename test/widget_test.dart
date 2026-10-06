import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rts_tracking/main.dart';
import 'package:rts_tracking/tracking_data.dart';

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

  testWidgets('live mode requires login and locks to the authenticated mode', (
    WidgetTester tester,
  ) async {
    final api = _FakeOwnerApi(
      loginSession: const OwnerSession(
        token: 'clinic-token',
        mode: TrackingMode.clinic,
        displayName: 'Dr Ada',
      ),
      dashboard: _clinicDashboard,
    );
    final store = _MemoryOwnerSessionStore();

    await tester.pumpWidget(RtsTrackingApp(api: api, sessionStore: store));
    await tester.pumpAndSettle();

    expect(find.text('Owner sign in'), findsOneWidget);
    expect(find.text('Clinic overview'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('owner-username')),
      'clinic-owner',
    );
    await tester.enterText(find.byKey(const Key('owner-password')), 'secret');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(api.lastUsername, 'clinic-owner');
    expect(api.lastPassword, 'secret');
    expect(find.text('Clinic overview'), findsOneWidget);
    expect(find.byType(SegmentedButton<TrackingMode>), findsNothing);
    expect(find.textContaining('RTS Clinic · Dr Ada'), findsOneWidget);
    expect(api.requestedModes, [TrackingMode.clinic]);
    expect(api.dashboardTokens, ['clinic-token']);
    expect(store.session?.mode, TrackingMode.clinic);
  });

  testWidgets('logout clears the secure session and returns to login', (
    WidgetTester tester,
  ) async {
    final api = _FakeOwnerApi(
      loginSession: const OwnerSession(
        token: 'business-token',
        mode: TrackingMode.business,
      ),
      dashboard: _businessDashboard,
    );
    final store = _MemoryOwnerSessionStore();

    await tester.pumpWidget(RtsTrackingApp(api: api, sessionStore: store));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('owner-username')), 'owner');
    await tester.enterText(find.byKey(const Key('owner-password')), 'password');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Owner sign in'), findsOneWidget);
    expect(store.session, isNull);
    expect(store.clearCount, 1);
  });

  testWidgets(
    'unauthorized dashboard response clears restored authentication',
    (WidgetTester tester) async {
      final store = _MemoryOwnerSessionStore(
        const OwnerSession(token: 'expired-token', mode: TrackingMode.business),
      );
      final api = _FakeOwnerApi(
        loginSession: const OwnerSession(
          token: 'unused',
          mode: TrackingMode.business,
        ),
        dashboard: _businessDashboard,
        rejectDashboard: true,
      );

      await tester.pumpWidget(RtsTrackingApp(api: api, sessionStore: store));
      await tester.pumpAndSettle();

      expect(find.text('Owner sign in'), findsOneWidget);
      expect(find.text('Your session expired. Sign in again.'), findsOneWidget);
      expect(store.session, isNull);
      expect(store.clearCount, 1);
      expect(api.dashboardTokens, ['expired-token']);
    },
  );
}

class _MemoryOwnerSessionStore implements OwnerSessionStore {
  _MemoryOwnerSessionStore([this.session]);

  OwnerSession? session;
  int clearCount = 0;

  @override
  Future<void> clear() async {
    clearCount += 1;
    session = null;
  }

  @override
  Future<OwnerSession?> read() async => session;

  @override
  Future<void> write(OwnerSession session) async {
    this.session = session;
  }
}

class _FakeOwnerApi extends OwnerApi {
  _FakeOwnerApi({
    required this.loginSession,
    required this.dashboard,
    this.rejectDashboard = false,
  }) : super(baseUrl: Uri.parse('https://api.example.com'));

  final OwnerSession loginSession;
  final DashboardSnapshot dashboard;
  final bool rejectDashboard;
  final List<TrackingMode> requestedModes = [];
  final List<String?> dashboardTokens = [];
  String? lastUsername;
  String? lastPassword;

  @override
  Future<OwnerSession> login(String username, String password) async {
    lastUsername = username;
    lastPassword = password;
    return loginSession;
  }

  @override
  Future<DashboardSnapshot> getDashboard(
    TrackingMode mode, {
    String? authToken,
  }) async {
    requestedModes.add(mode);
    dashboardTokens.add(authToken);
    if (rejectDashboard) throw const AuthRequiredException();
    return dashboard;
  }
}

const _businessDashboard = DashboardSnapshot(
  mode: TrackingMode.business,
  metrics: [
    DashboardMetric(key: 'salesToday', label: 'Sales today', value: '10'),
  ],
  sites: [],
  alerts: [],
  synchronizedLabel: 'Now',
  isDemo: false,
);

const _clinicDashboard = DashboardSnapshot(
  mode: TrackingMode.clinic,
  metrics: [
    DashboardMetric(
      key: 'appointmentsToday',
      label: 'Appointments',
      value: '8',
    ),
  ],
  sites: [],
  alerts: [],
  synchronizedLabel: 'Now',
  isDemo: false,
);
