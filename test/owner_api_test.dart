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
      expect(body, {'username': 'owner', 'password': 'correct horse'});
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'token': 'live-session-token',
          'mode': 'clinic',
          'ownerName': 'Ada',
          'displayName': 'Dr Ada',
        }),
      );
      await request.response.close();
    });

    final api = OwnerApi(
      baseUrl: Uri.parse('http://${server.address.address}:${server.port}'),
    );
    final session = await api.login('owner', 'correct horse');
    await requestHandled;

    expect(session.token, 'live-session-token');
    expect(session.mode, TrackingMode.clinic);
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
        startsWith('Bearer '),
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
