import 'package:flutter_test/flutter_test.dart';
import 'package:rts_tracking/api_configuration.dart';
import 'package:rts_tracking/tracking_data.dart';

void main() {
  test('missing build configuration remains fail closed', () {
    final api = OwnerApi.fromConfiguredUrl(resolveApiBaseUrl('   '));

    expect(api.baseUrl, isNull);
    expect(
      api.configurationError,
      'No live API endpoint is configured. Set RTS_API_BASE_URL.',
    );
  });

  test('a build-time API endpoint is trimmed and used', () {
    expect(
      resolveApiBaseUrl(' https://staging.example.com/rts/ '),
      'https://staging.example.com/rts/',
    );
  });
}
