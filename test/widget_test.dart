import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rts_tracking/main.dart';
import 'package:rts_tracking/tracking_data.dart';

void main() {
  testWidgets('demo operating view exposes all five exception-led tabs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const RtsTrackingApp(requireAuthentication: false));
    await tester.pumpAndSettle();

    expect(find.text('RTS Tracking'), findsOneWidget);
    expect(find.text('Today'), findsWidgets);
    expect(find.text('Decisions to make'), findsOneWidget);
    expect(find.text('Business performance'), findsOneWidget);
    expect(find.text('Financial position'), findsOneWidget);
    expect(find.text('System and account health'), findsOneWidget);
    expect(find.text('Damaged units today'), findsOneWidget);
    expect(find.text('Demo data'), findsOneWidget);
    expect(find.text('Not available yet'), findsOneWidget);

    await _selectTab(tester, 'Locations');
    expect(find.byKey(const Key('location-search')), findsOneWidget);
    expect(find.text('Offline / Unknown'), findsOneWidget);
    expect(find.text('Snapshot freshness'), findsOneWidget);

    await _selectTab(tester, 'Activity');
    expect(find.text('Aggregate activity totals'), findsOneWidget);
    expect(find.text('Completed sales'), findsOneWidget);
    expect(find.byKey(const Key('activity-search')), findsOneWidget);
    expect(find.text('Timeline'), findsOneWidget);

    await _selectTab(tester, 'Alerts');
    expect(find.text('Action order'), findsOneWidget);
    expect(find.textContaining('Impact:'), findsWidgets);
    expect(find.textContaining('Action:'), findsWidgets);

    await _selectTab(tester, 'More');
    expect(find.text('Security'), findsOneWidget);
    expect(find.text('Data sources and availability'), findsOneWidget);
    expect(find.text('Refresh behavior'), findsOneWidget);
  });

  testWidgets('demo mode adapts to clinic aggregate-only language', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const RtsTrackingApp(requireAuthentication: false));
    await tester.pumpAndSettle();

    await tester.tap(find.text('RTS Clinic'));
    await tester.pumpAndSettle();

    expect(find.text('Aggregate waiting count'), findsOneWidget);
    expect(find.text('Clinic operations'), findsOneWidget);
    expect(find.text('Outstanding insurance'), findsWidgets);
    expect(find.text('Open sessions'), findsOneWidget);
    expect(find.text('Sales today'), findsNothing);

    await _selectTab(tester, 'Activity');
    expect(find.text('Aggregate-only activity'), findsOneWidget);
    expect(
      find.textContaining('patient names, medical notes, files, diagnoses'),
      findsOneWidget,
    );
  });

  testWidgets('a location opens an operational detail sheet', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const RtsTrackingApp(requireAuthentication: false));
    await tester.pumpAndSettle();

    await _selectTab(tester, 'Locations');
    final warehouse = find.text('RTS Business Warehouse');
    await tester.drag(
      find.byKey(const Key('tracking-scroll-view')),
      const Offset(0, -520),
    );
    await tester.pumpAndSettle();
    await tester.tap(warehouse);
    await tester.pumpAndSettle();

    expect(find.text('Location details'), findsOneWidget);
    expect(find.text('Status and freshness'), findsOneWidget);
    expect(find.text('Licence and access'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Portfolio context'),
      420,
      scrollable: find.descendant(
        of: find.byKey(const Key('location-details-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Portfolio context'), findsOneWidget);
    expect(find.text('Shown on Today'), findsOneWidget);
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
        child: RtsTrackingApp(requireAuthentication: false),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Today'), findsWidgets);
  });

  testWidgets('release-style startup requires login instead of demo mode', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      RtsTrackingApp(
        api: OwnerApi(),
        requireAuthentication: true,
        sessionStore: _MemoryOwnerSessionStore(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Owner sign in'), findsOneWidget);
    expect(find.byKey(const Key('rts-login-logo')), findsOneWidget);
    expect(find.text('Demo data'), findsNothing);
  });

  testWidgets(
    'live mode locks the server-assigned product and clinic privacy',
    (WidgetTester tester) async {
      final api = _FakeOwnerApi(
        loginSession: const OwnerSession(
          token: 'clinic-token',
          mode: TrackingMode.clinic,
          organizationName: 'RTS Clinic Main',
          displayName: 'Dr Ada',
        ),
        dashboard: _clinicDashboard,
      );
      final store = _MemoryOwnerSessionStore();

      await tester.pumpWidget(RtsTrackingApp(api: api, sessionStore: store));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('owner-organization')),
        'RTS Clinic Main',
      );
      await tester.enterText(
        find.byKey(const Key('owner-username')),
        'clinic-owner',
      );
      await tester.enterText(find.byKey(const Key('owner-password')), 'secret');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Today'), findsWidgets);
      expect(find.text('RTS Clinic · Dr Ada'), findsOneWidget);
      expect(find.text('RTS Business'), findsNothing);
      expect(api.requestedModes, [TrackingMode.clinic]);
      expect(api.dashboardTokens, ['clinic-token']);
      expect(store.session?.mode, TrackingMode.clinic);

      await _selectTab(tester, 'More');
      expect(find.text('Server-assigned RTS Clinic'), findsOneWidget);
      expect(
        find.textContaining('patient names, medical notes, files, diagnoses'),
        findsOneWidget,
      );
    },
  );

  testWidgets('logout clears the secure session and returns to login', (
    WidgetTester tester,
  ) async {
    final api = _FakeOwnerApi(
      loginSession: const OwnerSession(
        token: 'business-token',
        mode: TrackingMode.business,
        organizationName: 'RTS Business Main',
      ),
      dashboard: _businessDashboard,
    );
    final store = _MemoryOwnerSessionStore();

    await tester.pumpWidget(RtsTrackingApp(api: api, sessionStore: store));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('owner-organization')),
      'RTS Business Main',
    );
    await tester.enterText(find.byKey(const Key('owner-username')), 'owner');
    await tester.enterText(find.byKey(const Key('owner-password')), 'password');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    await _selectTab(tester, 'More');
    await tester.drag(
      find.byKey(const Key('tracking-scroll-view')),
      const Offset(0, -260),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sign-out-button')));
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
          organizationName: 'RTS Business Main',
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

Future<void> _selectTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
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

  @override
  Future<OwnerSession> login(
    String organizationName,
    String username,
    String password,
  ) async => loginSession;

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
  metrics: [DashboardMetric(key: 'licence', label: 'Licence', value: 'Active')],
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
      label: 'Scheduled today',
      value: '8',
    ),
  ],
  sites: [],
  alerts: [],
  synchronizedLabel: 'Now',
  dataAvailability: DataAvailability(
    privacy: PrivacyScope(
      scope: 'aggregate-only',
      patientMedicalDetailsIncluded: false,
    ),
  ),
  isDemo: false,
);
