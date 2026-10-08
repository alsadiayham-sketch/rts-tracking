import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum TrackingMode { business, clinic }

extension TrackingModeDetails on TrackingMode {
  String get apiValue => name;

  String get displayName => switch (this) {
    TrackingMode.business => 'RTS Business',
    TrackingMode.clinic => 'RTS Clinic',
  };

  String get locationName => switch (this) {
    TrackingMode.business => 'store',
    TrackingMode.clinic => 'clinic',
  };

  String get locationNamePlural => switch (this) {
    TrackingMode.business => 'stores',
    TrackingMode.clinic => 'clinics',
  };
}

enum AlertLevel { info, warning, critical }

class DashboardMetric {
  const DashboardMetric({
    required this.key,
    required this.label,
    required this.value,
  });

  factory DashboardMetric.fromJson(Map<String, dynamic> json) {
    return DashboardMetric(
      key: _requiredString(json, 'key'),
      label: _requiredString(json, 'label'),
      value: _requiredString(json, 'value'),
    );
  }

  final String key;
  final String label;
  final String value;
}

class SiteSnapshot {
  const SiteSnapshot({
    required this.id,
    required this.name,
    required this.online,
    required this.updatedLabel,
    required this.primaryLabel,
    required this.primaryValue,
    this.attention,
  });

  factory SiteSnapshot.fromJson(Map<String, dynamic> json) {
    return SiteSnapshot(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      online: json['online'] == true,
      updatedLabel: _requiredString(json, 'updatedLabel'),
      primaryLabel: _requiredString(json, 'primaryLabel'),
      primaryValue: _requiredString(json, 'primaryValue'),
      attention: json['attention'] as String?,
    );
  }

  final String id;
  final String name;
  final bool online;
  final String updatedLabel;
  final String primaryLabel;
  final String primaryValue;
  final String? attention;
}

class TrackingAlert {
  const TrackingAlert({
    required this.id,
    required this.title,
    required this.detail,
    required this.level,
  });

  factory TrackingAlert.fromJson(Map<String, dynamic> json) {
    final levelName = _requiredString(json, 'level');
    return TrackingAlert(
      id: _requiredString(json, 'id'),
      title: _requiredString(json, 'title'),
      detail: _requiredString(json, 'detail'),
      level: AlertLevel.values.firstWhere(
        (level) => level.name == levelName,
        orElse: () => throw const FormatException('Unknown alert level'),
      ),
    );
  }

  final String id;
  final String title;
  final String detail;
  final AlertLevel level;
}

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.mode,
    required this.metrics,
    required this.sites,
    required this.alerts,
    required this.synchronizedLabel,
    required this.isDemo,
  });

  factory DashboardSnapshot.fromJson(
    Map<String, dynamic> json, {
    required TrackingMode requestedMode,
  }) {
    final responseMode = TrackingMode.values.firstWhere(
      (mode) => mode.apiValue == json['mode'],
      orElse: () => throw const FormatException('Unknown dashboard mode'),
    );
    if (responseMode != requestedMode) {
      throw const FormatException('Dashboard mode does not match request');
    }

    return DashboardSnapshot(
      mode: responseMode,
      metrics: _objectList(
        json,
        'metrics',
      ).map(DashboardMetric.fromJson).toList(growable: false),
      sites: _objectList(
        json,
        'sites',
      ).map(SiteSnapshot.fromJson).toList(growable: false),
      alerts: _objectList(
        json,
        'alerts',
      ).map(TrackingAlert.fromJson).toList(growable: false),
      synchronizedLabel: _requiredString(json, 'synchronizedLabel'),
      isDemo: false,
    );
  }

  final TrackingMode mode;
  final List<DashboardMetric> metrics;
  final List<SiteSnapshot> sites;
  final List<TrackingAlert> alerts;
  final String synchronizedLabel;
  final bool isDemo;

  int get onlineSites => sites.where((site) => site.online).length;
}

typedef AuthTokenProvider = Future<String?> Function();
typedef HttpClientFactory = HttpClient Function();

class OwnerSession {
  const OwnerSession({
    required this.token,
    required this.mode,
    this.organizationName,
    this.ownerName,
    this.displayName,
  });

  factory OwnerSession.fromLoginJson(Map<String, dynamic> json) {
    final modeName = _requiredString(json, 'mode');
    final mode = TrackingMode.values.firstWhere(
      (candidate) => candidate.apiValue == modeName,
      orElse: () => throw const FormatException('Unknown owner mode'),
    );
    return OwnerSession(
      token: _requiredString(json, 'token'),
      mode: mode,
      organizationName: _optionalString(json, 'organizationName'),
      ownerName: _optionalString(json, 'ownerName'),
      displayName: _optionalString(json, 'displayName'),
    );
  }

  final String token;
  final TrackingMode mode;
  final String? organizationName;
  final String? ownerName;
  final String? displayName;

  String get greetingName => displayName ?? ownerName ?? 'Owner';
}

abstract class OwnerSessionStore {
  Future<OwnerSession?> read();

  Future<void> write(OwnerSession session);

  Future<void> clear();
}

class SecureOwnerSessionStore implements OwnerSessionStore {
  SecureOwnerSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'owner_session_token';
  static const _modeKey = 'owner_session_mode';
  static const _organizationNameKey = 'owner_session_organization_name';
  static const _ownerNameKey = 'owner_session_owner_name';
  static const _displayNameKey = 'owner_session_display_name';

  final FlutterSecureStorage _storage;

  @override
  Future<OwnerSession?> read() async {
    final token = await _storage.read(key: _tokenKey);
    final modeName = await _storage.read(key: _modeKey);
    if (token == null ||
        token.trim().isEmpty ||
        !TrackingMode.values.any((mode) => mode.apiValue == modeName)) {
      await clear();
      return null;
    }
    return OwnerSession(
      token: token,
      mode: TrackingMode.values.firstWhere((mode) => mode.apiValue == modeName),
      organizationName: await _storage.read(key: _organizationNameKey),
      ownerName: await _storage.read(key: _ownerNameKey),
      displayName: await _storage.read(key: _displayNameKey),
    );
  }

  @override
  Future<void> write(OwnerSession session) async {
    await _storage.write(key: _tokenKey, value: session.token);
    await _storage.write(key: _modeKey, value: session.mode.apiValue);
    await _writeOptional(_organizationNameKey, session.organizationName);
    await _writeOptional(_ownerNameKey, session.ownerName);
    await _writeOptional(_displayNameKey, session.displayName);
  }

  Future<void> _writeOptional(String key, String? value) {
    if (value == null) return _storage.delete(key: key);
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _tokenKey),
      _storage.delete(key: _modeKey),
      _storage.delete(key: _organizationNameKey),
      _storage.delete(key: _ownerNameKey),
      _storage.delete(key: _displayNameKey),
    ]);
  }
}

class AuthRequiredException implements Exception {
  const AuthRequiredException();

  @override
  String toString() => 'Owner authentication is required.';
}

class ApiConfigurationException implements Exception {
  const ApiConfigurationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiConnectionException implements Exception {
  const ApiConnectionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ApiServerException implements Exception {
  const ApiServerException({required this.operation, required this.statusCode});

  final String operation;
  final int statusCode;

  @override
  String toString() => '$operation failed with HTTP $statusCode.';
}

class LoginRejectedException implements Exception {
  const LoginRejectedException();

  @override
  String toString() => 'The username or password is incorrect.';
}

class OwnerApi {
  OwnerApi({
    this.baseUrl,
    this.tokenProvider,
    HttpClientFactory? clientFactory,
    this.requestTimeout = const Duration(seconds: 12),
    String? configurationError,
  }) : _clientFactory = clientFactory ?? HttpClient.new,
       _configurationError = configurationError ?? validateApiBaseUrl(baseUrl);

  factory OwnerApi.fromConfiguredUrl(
    String configuredBaseUrl, {
    AuthTokenProvider? tokenProvider,
    HttpClientFactory? clientFactory,
    Duration requestTimeout = const Duration(seconds: 12),
  }) {
    final value = configuredBaseUrl.trim();
    if (value.isEmpty) {
      return OwnerApi(
        tokenProvider: tokenProvider,
        clientFactory: clientFactory,
        requestTimeout: requestTimeout,
        configurationError:
            'No live API endpoint is configured. Set RTS_API_BASE_URL.',
      );
    }
    final parsed = Uri.tryParse(value);
    if (parsed == null) {
      return OwnerApi(
        tokenProvider: tokenProvider,
        clientFactory: clientFactory,
        requestTimeout: requestTimeout,
        configurationError: 'RTS_API_BASE_URL is not a valid URL.',
      );
    }
    return OwnerApi(
      baseUrl: parsed,
      tokenProvider: tokenProvider,
      clientFactory: clientFactory,
      requestTimeout: requestTimeout,
    );
  }

  final Uri? baseUrl;
  final AuthTokenProvider? tokenProvider;
  final HttpClientFactory _clientFactory;
  final Duration requestTimeout;
  final String? _configurationError;

  bool get isDemo => baseUrl == null && _configurationError == null;

  String? get configurationError => _configurationError;

  Future<OwnerSession> login(
    String organizationName,
    String username,
    String password,
  ) async {
    _ensureConfigured();

    final endpoint = _endpoint('owner/login');
    final client = _clientFactory();
    try {
      final request = await client.postUrl(endpoint).timeout(requestTimeout);
      request.headers
        ..set(HttpHeaders.acceptHeader, ContentType.json.mimeType)
        ..contentType = ContentType.json;
      request.write(
        jsonEncode({
          'organizationName': organizationName,
          'username': username,
          'password': password,
        }),
      );
      final response = await request.close().timeout(requestTimeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(requestTimeout);
      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        throw const LoginRejectedException();
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiServerException(
          operation: 'Login request',
          statusCode: response.statusCode,
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Login response must be an object');
      }
      return OwnerSession.fromLoginJson(decoded);
    } on ApiServerException {
      rethrow;
    } on IOException catch (error) {
      throw ApiConnectionException('Could not reach the login service: $error');
    } on TimeoutException {
      throw const ApiConnectionException(
        'The login service did not respond before the request timed out.',
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<DashboardSnapshot> getDashboard(
    TrackingMode mode, {
    String? authToken,
  }) async {
    if (baseUrl == null && _configurationError == null) {
      return _demoDashboard(mode);
    }
    _ensureConfigured();

    final token = authToken ?? await tokenProvider?.call();
    if (token == null || token.trim().isEmpty) {
      throw const AuthRequiredException();
    }

    final endpoint = _endpoint('owner/dashboard');
    final uri = endpoint.replace(
      queryParameters: {...endpoint.queryParameters, 'mode': mode.apiValue},
    );
    final client = _clientFactory();
    try {
      final request = await client.getUrl(uri).timeout(requestTimeout);
      request.headers
        ..set(HttpHeaders.acceptHeader, ContentType.json.mimeType)
        ..set(HttpHeaders.authorizationHeader, 'Bearer ${token.trim()}');
      final response = await request.close().timeout(requestTimeout);
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(requestTimeout);
      if (response.statusCode == HttpStatus.unauthorized ||
          response.statusCode == HttpStatus.forbidden) {
        throw const AuthRequiredException();
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiServerException(
          operation: 'Dashboard request',
          statusCode: response.statusCode,
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Dashboard response must be an object');
      }
      return DashboardSnapshot.fromJson(decoded, requestedMode: mode);
    } on ApiServerException {
      rethrow;
    } on IOException catch (error) {
      throw ApiConnectionException(
        'Could not reach the dashboard service: $error',
      );
    } on TimeoutException {
      throw const ApiConnectionException(
        'The dashboard service did not respond before the request timed out.',
      );
    } finally {
      client.close(force: true);
    }
  }

  void _ensureConfigured() {
    final error = _configurationError;
    if (error != null) throw ApiConfigurationException(error);
    if (baseUrl == null) {
      throw const ApiConfigurationException(
        'No live API endpoint is configured. Set RTS_API_BASE_URL.',
      );
    }
  }

  Uri _endpoint(String path) {
    final base = baseUrl!;
    final basePath = base.path.isEmpty
        ? '/'
        : base.path.endsWith('/')
        ? base.path
        : '${base.path}/';
    return base.replace(path: basePath).resolve(path);
  }

  DashboardSnapshot _demoDashboard(TrackingMode mode) {
    return switch (mode) {
      TrackingMode.business => const DashboardSnapshot(
        mode: TrackingMode.business,
        metrics: [
          DashboardMetric(
            key: 'salesToday',
            label: 'Sales today',
            value: 'â‚ª18,420',
          ),
          DashboardMetric(
            key: 'ordersToday',
            label: 'Orders today',
            value: '146',
          ),
          DashboardMetric(
            key: 'storesOnline',
            label: 'Stores online',
            value: '2/3',
          ),
          DashboardMetric(
            key: 'stockAlerts',
            label: 'Stock alerts',
            value: '2',
          ),
        ],
        sites: [
          SiteSnapshot(
            id: 'business-main',
            name: 'RTS Business Main Store',
            online: true,
            updatedLabel: 'Updated just now',
            primaryLabel: 'Sales today',
            primaryValue: 'â‚ª9,840',
          ),
          SiteSnapshot(
            id: 'business-mall',
            name: 'RTS Business Mall',
            online: true,
            updatedLabel: 'Updated 2 min ago',
            primaryLabel: 'Sales today',
            primaryValue: 'â‚ª8,580',
            attention: '2 low-stock items',
          ),
          SiteSnapshot(
            id: 'business-warehouse',
            name: 'RTS Business Warehouse',
            online: false,
            updatedLabel: 'Last update 18 min ago',
            primaryLabel: 'Open stock tasks',
            primaryValue: '4',
            attention: 'Connection lost',
          ),
        ],
        alerts: [
          TrackingAlert(
            id: 'low-stock',
            title: '2 low-stock items need review',
            detail: 'RTS Business Mall',
            level: AlertLevel.warning,
          ),
          TrackingAlert(
            id: 'warehouse-offline',
            title: 'Warehouse is offline',
            detail: 'Last update 18 min ago',
            level: AlertLevel.critical,
          ),
        ],
        synchronizedLabel: 'Demo data generated locally',
        isDemo: true,
      ),
      TrackingMode.clinic => const DashboardSnapshot(
        mode: TrackingMode.clinic,
        metrics: [
          DashboardMetric(
            key: 'appointmentsToday',
            label: 'Appointments',
            value: '27',
          ),
          DashboardMetric(
            key: 'patientsWaiting',
            label: 'Patients waiting',
            value: '4',
          ),
          DashboardMetric(
            key: 'clinicsOnline',
            label: 'Clinics online',
            value: '2/3',
          ),
          DashboardMetric(key: 'followUps', label: 'Follow-ups', value: '2'),
        ],
        sites: [
          SiteSnapshot(
            id: 'clinic-main',
            name: 'RTS Clinic Main',
            online: true,
            updatedLabel: 'Updated just now',
            primaryLabel: 'Appointments today',
            primaryValue: '14',
          ),
          SiteSnapshot(
            id: 'clinic-north',
            name: 'RTS Clinic North',
            online: true,
            updatedLabel: 'Updated 1 min ago',
            primaryLabel: 'Appointments today',
            primaryValue: '13',
            attention: '4 patients waiting',
          ),
          SiteSnapshot(
            id: 'clinic-west',
            name: 'RTS Clinic West',
            online: false,
            updatedLabel: 'Last update 11 min ago',
            primaryLabel: 'Appointments today',
            primaryValue: '0',
            attention: 'Connection lost',
          ),
        ],
        alerts: [
          TrackingAlert(
            id: 'follow-ups',
            title: '2 appointment follow-ups need review',
            detail: 'RTS Clinic North',
            level: AlertLevel.warning,
          ),
          TrackingAlert(
            id: 'clinic-offline',
            title: 'West clinic is offline',
            detail: 'Last update 11 min ago',
            level: AlertLevel.critical,
          ),
        ],
        synchronizedLabel: 'Demo data generated locally',
        isDemo: true,
      ),
    };
  }
}

String? validateApiBaseUrl(Uri? uri) {
  if (uri == null) return null;
  if (!uri.isAbsolute || uri.host.isEmpty) {
    return 'RTS_API_BASE_URL must be an absolute URL with a host.';
  }
  if (uri.userInfo.isNotEmpty) {
    return 'RTS_API_BASE_URL must not include credentials.';
  }
  if (uri.query.isNotEmpty || uri.fragment.isNotEmpty) {
    return 'RTS_API_BASE_URL must not include a query or fragment.';
  }
  if (uri.scheme == 'https') return null;
  if (uri.scheme == 'http' && _isLocalHost(uri.host)) return null;
  return 'RTS_API_BASE_URL must use HTTPS for production endpoints.';
}

bool _isLocalHost(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1';
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string when provided');
  }
  return value;
}

List<Map<String, dynamic>> _objectList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List) {
    throw FormatException('$key must be a list');
  }
  return value
      .map((item) {
        if (item is! Map<String, dynamic>) {
          throw FormatException('$key entries must be objects');
        }
        return item;
      })
      .toList(growable: false);
}
