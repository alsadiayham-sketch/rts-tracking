import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rts_tracking/tracking_data.dart';

void main() {
  test('owner login posts credentials and parses the assigned mode', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    final requestHandled = server.first.then((request) async {
      expect(request.method, 'POST');
      expect(request.uri.path, '/owner/login');
      expect(request.headers.contentType?.mimeType, ContentType.json.mimeType);
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      expect(body, {
        'organizationName': 'RTS Clinic Main',
        'username': 'owner',
        'password': 'correct horse',
      });
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'token': 'live-session-token',
          'mode': 'clinic',
          'organizationName': 'RTS Clinic Main',
          'ownerName': 'Ada',
          'displayName': 'Dr Ada',
        }),
      );
      await request.response.close();
    });

    final api = OwnerApi(
      baseUrl: Uri.parse('http://${server.address.address}:${server.port}'),
    );
    final session = await api.login(
      'RTS Clinic Main',
      'owner',
      'correct horse',
    );
    await requestHandled;

    expect(session.token, 'live-session-token');
    expect(session.mode, TrackingMode.clinic);
    expect(session.organizationName, 'RTS Clinic Main');
    expect(session.ownerName, 'Ada');
    expect(session.greetingName, 'Dr Ada');
  });

  test('live API fails closed when owner authentication is unavailable', () {
    final api = OwnerApi(baseUrl: Uri.parse('https://api.example.com'));

    expect(
      () => api.getDashboard(TrackingMode.business),
      throwsA(isA<AuthRequiredException>()),
    );
  });

  test('live API sends mode and authorization and parses typed data', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    final requestHandled = server.first.then((request) async {
      expect(request.uri.path, '/owner/dashboard');
      expect(request.uri.queryParameters['mode'], 'clinic');
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer test-session-value',
      );
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'mode': 'clinic',
          'metrics': [
            {'key': 'appointmentsToday', 'label': 'Appointments', 'value': '8'},
          ],
          'sites': [
            {
              'id': 'clinic-main',
              'name': 'RTS Clinic Main',
              'online': true,
              'updatedLabel': 'Updated now',
              'primaryLabel': 'Appointments',
              'primaryValue': '8',
            },
          ],
          'alerts': <Object>[],
          'synchronizedLabel': 'Updated now',
        }),
      );
      await request.response.close();
    });

    final api = OwnerApi(
      baseUrl: Uri.parse('http://${server.address.address}:${server.port}'),
      tokenProvider: () async => 'test-session-value',
    );
    final dashboard = await api.getDashboard(TrackingMode.clinic);
    await requestHandled;

    expect(dashboard.mode, TrackingMode.clinic);
    expect(dashboard.metrics.single.value, '8');
    expect(dashboard.sites.single.name, 'RTS Clinic Main');
    expect(dashboard.isDemo, isFalse);
  });

  test('validates production API base URLs and preserves local test URLs', () {
    expect(
      validateApiBaseUrl(Uri.parse('https://api.example.com/rts/')),
      isNull,
    );
    expect(
      validateApiBaseUrl(Uri.parse('http://api.example.com')),
      contains('HTTPS'),
    );
    expect(validateApiBaseUrl(Uri.parse('http://127.0.0.1:8080')), isNull);
    expect(
      validateApiBaseUrl(Uri.parse('https://user:password@api.example.com')),
      contains('credentials'),
    );
  });

  test('configured URL errors are reported before network access', () async {
    final api = OwnerApi.fromConfiguredUrl('http://api.example.com');

    expect(
      () => api.login('RTS Clinic Main', 'owner', 'password'),
      throwsA(
        isA<ApiConfigurationException>().having(
          (error) => error.message,
          'message',
          contains('HTTPS'),
        ),
      ),
    );
  });

  test('dashboard response must match the requested product mode', () {
    expect(
      () => DashboardSnapshot.fromJson({
        'mode': 'clinic',
        'metrics': <Object>[],
        'sites': <Object>[],
        'alerts': <Object>[],
        'synchronizedLabel': 'Now',
      }, requestedMode: TrackingMode.business),
      throwsFormatException,
    );
  });

  test('parses the v2 Business operating contract and availability gaps', () {
    final dashboard = DashboardSnapshot.fromJson({
      'contractVersion': 2,
      'generatedAt': '2026-10-11T10:30:00.000Z',
      'mode': 'business',
      'metrics': [
        {'key': 'licence', 'label': 'Licence', 'value': 'Active'},
      ],
      'sites': [
        {
          'id': 'business-main',
          'name': 'RTS Business Main',
          'online': false,
          'updatedLabel': 'Live status unavailable',
          'primaryLabel': 'Business licence',
          'primaryValue': 'Active',
        },
      ],
      'locations': [
        {
          'id': 'business-main',
          'name': 'RTS Business Main',
          'mode': 'business',
          'status': 'unknown',
          'online': false,
          'updatedLabel': 'Live status unavailable',
          'primaryLabel': 'Business licence',
          'primaryValue': 'Active',
          'telemetry': {
            'available': false,
            'status': 'unknown',
            'detail': 'No heartbeat is published.',
          },
          'licence': {
            'active': true,
            'endsAt': '2027-10-11T00:00:00.000Z',
            'lastCheckedAt': '2026-10-11T09:00:00.000Z',
          },
        },
      ],
      'alerts': <Object>[],
      'synchronizedLabel': 'Owner data generated 2026-10-11',
      'overview': {
        'organization': {
          'id': 'business-main',
          'name': 'RTS Business Main',
          'mode': 'business',
        },
        'licence': {'active': true},
        'locations': {'total': 1, 'online': 0, 'unknown': 1},
        'alerts': {'total': 0, 'critical': 0},
        'staff': {'totalAccounts': 5, 'activeAccounts': 4, 'adminAccounts': 1},
      },
      'recentActivity': [
        {
          'id': 'credit-1',
          'category': 'platform-messaging',
          'type': 'credit-usage',
          'title': 'Messaging credits used',
          'detail': '3 messages · ₪1.50',
          'level': 'info',
          'occurredAt': '2026-10-11T10:00:00.000Z',
          'source': 'rts-royal-d1',
          'changes': {'messageDelta': -3},
        },
      ],
      'auditLog': {
        'completeness': 'partial',
        'detail': 'Only platform events are available.',
        'eventCounts': {
          'salesCompleted': 12,
          'returnsCompleted': 2,
          'inventoryAdjustments': 3,
        },
        'events': [
          {
            'id': 'audit-credit-1',
            'category': 'platform-messaging',
            'action': 'credit-usage',
            'occurredAt': '2026-10-11T10:00:00.000Z',
            'source': 'rts-royal-d1',
            'changes': {'messageDelta': -3},
          },
        ],
      },
      'financialMetrics': {
        'currency': 'ILS',
        'businessRevenue': {'available': true, 'value': 1200.5},
        'sourceApplication': {
          'available': true,
          'source': 'rts-business-pos',
          'generatedAt': '2026-10-11T10:29:00.000Z',
          'revenueToday': {'available': true, 'value': 1200.5},
          'averageOrderValue': {'available': true, 'value': 100.04},
          'refundsToday': {'available': true, 'value': 25.5},
        },
        'platformMessaging': {
          'available': true,
          'source': 'rts-royal-d1',
          'messageBalance': 42,
          'prepaidBalanceNis': 21.5,
          'customerPriceNis': 0.5,
          'platformCostNis': 0.2,
          'updatedAt': '2026-10-11T10:00:00.000Z',
        },
      },
      'operationalMetrics': {
        'connectivity': {'available': false, 'status': 'unknown'},
        'staff': {'totalAccounts': 5, 'activeAccounts': 4},
        'health': {
          'available': true,
          'source': 'rts-business-pos',
          'generatedAt': '2026-10-11T10:29:00.000Z',
          'appVersion': '4.0.8',
          'metrics': {
            'terminalCount': 2,
            'activeTerminalCount': 1,
            'databaseHealthy': true,
            'syncHealthy': false,
            'unexpectedFreeText': 'Private value',
          },
        },
        'sourceBackend': 'firestore',
      },
      'modeDetail': {
        'kind': 'business',
        'salesToday': {'available': true, 'value': 1200.5},
      },
      'dataAvailability': {
        'available': ['licence', 'staff-counts'],
        'unavailable': ['sales', 'inventory'],
        'gaps': [
          {
            'key': 'business-operations',
            'reason': 'Sales and inventory remain in the Business backend.',
            'requiredTelemetry': 'Publish aggregate snapshots.',
          },
        ],
        'privacy': {
          'scope': 'aggregate-only',
          'patientMedicalDetailsIncluded': false,
          'unnecessaryPersonalDataIncluded': false,
        },
      },
    }, requestedMode: TrackingMode.business);

    expect(dashboard.contractVersion, 2);
    expect(dashboard.locations.single.effectiveStatus, LocationStatus.unknown);
    expect(dashboard.locations.single.licence.active, isTrue);
    expect(dashboard.overview.staff.activeAccounts, 4);
    expect(dashboard.financialMetrics.platformMessaging.messageBalance, 42);
    expect(dashboard.modeDetail.metrics['salesToday']?.available, isTrue);
    expect(
      dashboard
          .financialMetrics
          .sourceApplication
          .metrics['averageOrderValue']
          ?.value,
      100.04,
    );
    expect(dashboard.operationalMetrics.health.appVersion, '4.0.8');
    expect(dashboard.operationalMetrics.health.metrics['syncHealthy'], isFalse);
    expect(
      dashboard.operationalMetrics.health.metrics,
      isNot(contains('unexpectedFreeText')),
    );
    expect(dashboard.auditLog.eventCounts['salesCompleted'], 12);
    expect(dashboard.dataAvailability.gaps.single.key, 'business-operations');
    expect(dashboard.auditLog.completeness, 'partial');
    expect(dashboard.auditLog.events.single.type, 'credit-usage');
  });

  test('parses the v2 Clinic contract without retaining unsafe activity', () {
    final dashboard = DashboardSnapshot.fromJson({
      'contractVersion': 2,
      'generatedAt': '2026-10-11T10:30:00.000Z',
      'mode': 'clinic',
      'metrics': [
        {
          'key': 'waitingCount',
          'label': 'Patient Ada waiting',
          'value': 'Sensitive diagnosis',
        },
        {'key': 'activeStaff', 'label': 'Patient list', 'value': '3'},
      ],
      'sites': [
        {
          'id': 'clinic-main',
          'name': 'RTS Clinic Main',
          'online': true,
          'updatedLabel': 'Patient Ada checked in',
          'primaryLabel': 'Latest diagnosis',
          'primaryValue': 'Sensitive condition',
          'attention': 'Patient Ada needs urgent review',
        },
      ],
      'locations': [
        {
          'id': 'clinic-main',
          'name': 'RTS Clinic Main',
          'mode': 'clinic',
          'online': true,
          'updatedLabel': 'Heartbeat just now',
          'primaryLabel': 'Clinic licence',
          'primaryValue': 'Active',
          'telemetry': {'available': false, 'status': 'unknown'},
          'licence': {'active': true},
        },
      ],
      'alerts': [
        {
          'id': 'licence-expired',
          'title': 'Patient Ada needs urgent care',
          'detail': 'Sensitive diagnosis',
          'level': 'critical',
        },
      ],
      'synchronizedLabel': 'Owner data generated 2026-10-11',
      'recentActivity': [
        {
          'id': 'unsafe-medical-event',
          'category': 'clinical',
          'type': 'medical-note',
          'title': 'Patient Ada received a diagnosis',
          'detail': 'Sensitive clinical notes',
          'level': 'warning',
          'occurredAt': '2026-10-11T10:10:00.000Z',
          'source': 'local-workspace',
        },
        {
          'id': 'safe-licence-event',
          'category': 'system',
          'type': 'licence-check',
          'title': 'Clinic licence checked',
          'detail': 'Anything from the source is discarded for clinics.',
          'level': 'info',
          'occurredAt': 'Patient Ada had surgery',
          'source': 'firestore-licence',
        },
      ],
      'auditLog': {
        'completeness': 'partial',
        'detail': 'Patient Ada had a sensitive procedure.',
        'eventCounts': {
          'sessionsCompleted': 7,
          'paymentsRecorded': 6,
          'patientAdaDiagnoses': 99,
        },
        'events': <Object>[],
      },
      'financialMetrics': {
        'currency': 'ILS',
        'businessRevenue': {
          'available': false,
          'value': null,
          'reason': 'Patient Ada paid for a sensitive procedure.',
        },
        'sourceApplication': {
          'available': true,
          'source': 'Patient Ada payment source',
          'generatedAt': '2026-10-11T10:29:00.000Z',
          'revenueToday': {'available': true, 'value': 850},
          'outstandingBalance': {'available': true, 'value': 420},
          'patientAdaBalance': {'available': true, 'value': 999},
        },
        'platformMessaging': {'available': false},
      },
      'operationalMetrics': {
        'connectivity': {
          'available': true,
          'status': 'online',
          'source': 'Patient Ada monitor',
          'detail': 'Sensitive diagnosis',
        },
        'staff': {'totalAccounts': 3, 'activeAccounts': 3},
        'health': {
          'available': true,
          'source': 'Patient Ada monitor',
          'generatedAt': '2026-10-11T10:29:00.000Z',
          'appVersion': 'Patient Ada diagnosis',
          'metrics': {
            'terminalCount': 1,
            'activeTerminalCount': 1,
            'databaseHealthy': true,
            'patientAdaStatus': 1,
          },
        },
        'sourceBackend': 'Patient Ada workspace',
      },
      'modeDetail': {
        'kind': 'clinic',
        'appointmentsToday': {'available': true, 'value': 12},
        'collectionsToday': {'available': true, 'value': 850},
        'patientAdaTreatments': {'available': true, 'value': 4},
        'patientMedicalDetailsIncluded': false,
      },
      'dataAvailability': {
        'available': [
          'licence',
          'operational-heartbeat',
          'source-health',
          'source-financial-aggregates',
          'aggregate-event-counters',
        ],
        'unavailable': ['appointments', 'sessions'],
        'gaps': [
          {
            'key': 'clinic-operations',
            'reason': 'Patient Ada has a diagnosis.',
            'requiredTelemetry': 'Upload Patient Ada records.',
          },
        ],
        'privacy': {
          'scope': 'Patient Ada private scope',
          'patientMedicalDetailsIncluded': false,
          'unnecessaryPersonalDataIncluded': false,
        },
      },
    }, requestedMode: TrackingMode.clinic);

    expect(dashboard.locations.single.telemetry.available, isFalse);
    expect(dashboard.locations.single.effectiveStatus, LocationStatus.unknown);
    expect(dashboard.locations.single.primaryLabel, 'Clinic licence');
    expect(dashboard.locations.single.primaryValue, 'Active');
    expect(dashboard.locations.single.attention, isNot(contains('Ada')));
    expect(dashboard.alerts.single.title, 'Clinic licence is inactive');
    expect(dashboard.alerts.single.detail, isNot(contains('diagnosis')));
    expect(
      dashboard.metrics.any(
        (metric) =>
            metric.label.contains('Ada') || metric.value.contains('diagnosis'),
      ),
      isFalse,
    );
    expect(
      dashboard.financialMetrics.businessRevenue.reason,
      isNot(contains('Ada')),
    );
    expect(dashboard.operationalMetrics.sourceBackend, isNull);
    expect(dashboard.modeDetail.metrics['appointmentsToday']?.value, 12);
    expect(
      dashboard.modeDetail.metrics,
      isNot(contains('patientAdaTreatments')),
    );
    expect(
      dashboard
          .financialMetrics
          .sourceApplication
          .metrics['revenueToday']
          ?.value,
      850,
    );
    expect(
      dashboard.financialMetrics.sourceApplication.metrics,
      isNot(contains('patientAdaBalance')),
    );
    expect(dashboard.operationalMetrics.health.metrics['terminalCount'], 1);
    expect(dashboard.operationalMetrics.health.appVersion, isNull);
    expect(
      dashboard.operationalMetrics.health.metrics,
      isNot(contains('patientAdaStatus')),
    );
    expect(dashboard.auditLog.eventCounts['sessionsCompleted'], 7);
    expect(
      dashboard.auditLog.eventCounts,
      isNot(contains('patientAdaDiagnoses')),
    );
    expect(dashboard.financialMetrics.sourceApplication.generatedAt, isNull);
    expect(
      dashboard.dataAvailability.gaps.single.reason,
      isNot(contains('Ada')),
    );
    expect(dashboard.dataAvailability.privacy.scope, 'aggregate-only');
    expect(
      dashboard.dataAvailability.available,
      containsAll([
        'source-health',
        'source-financial-aggregates',
        'aggregate-event-counters',
      ]),
    );
    expect(dashboard.auditLog.detail, isNot(contains('Ada')));
    expect(dashboard.auditLog.detail, contains('Personal and medical records'));
    expect(
      dashboard.operationalMetrics.connectivity.source,
      'RTS operational heartbeat',
    );
    expect(
      dashboard.operationalMetrics.connectivity.detail,
      isNot(contains('diagnosis')),
    );
    expect(dashboard.recentActivity, hasLength(1));
    expect(dashboard.recentActivity.single.title, 'Licence checked');
    expect(dashboard.recentActivity.single.source, 'RTS platform');
    expect(dashboard.recentActivity.single.occurredAt, isNull);
    expect(
      dashboard.recentActivity.single.detail,
      contains('Personal and medical records are not shown'),
    );
    expect(dashboard.dataAvailability.privacy.scope, 'aggregate-only');
    expect(dashboard.dataAvailability.gaps.single.key, 'clinic-operations');
  });

  test('legacy dashboard responses remain compatible', () {
    final dashboard = DashboardSnapshot.fromJson({
      'mode': 'business',
      'metrics': [
        {'key': 'salesToday', 'label': 'Sales today', 'value': '₪100.00'},
      ],
      'sites': [
        {
          'id': 'legacy-store',
          'name': 'Legacy Store',
          'online': true,
          'updatedLabel': 'Updated now',
          'primaryLabel': 'Sales today',
          'primaryValue': '₪100.00',
        },
      ],
      'alerts': <Object>[],
      'synchronizedLabel': 'Updated now',
    }, requestedMode: TrackingMode.business);

    expect(dashboard.contractVersion, 1);
    expect(dashboard.locations.single.name, 'Legacy Store');
    expect(dashboard.overview.locations.total, 1);
    expect(dashboard.recentActivity, isEmpty);
  });

  test('login rejects a mode outside the supported products', () {
    expect(
      () => OwnerSession.fromLoginJson({
        'token': 'session-token',
        'mode': 'admin',
      }),
      throwsFormatException,
    );
  });
}
