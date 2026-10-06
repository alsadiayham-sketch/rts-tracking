import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

class AuthRequiredException implements Exception {
  const AuthRequiredException();

  @override
  String toString() => 'Owner authentication is required.';
}

class OwnerApi {
  OwnerApi({
    this.baseUrl,
    this.tokenProvider,
    HttpClientFactory? clientFactory,
    this.requestTimeout = const Duration(seconds: 12),
  }) : _clientFactory = clientFactory ?? HttpClient.new;

  final Uri? baseUrl;
  final AuthTokenProvider? tokenProvider;
  final HttpClientFactory _clientFactory;
  final Duration requestTimeout;

  bool get isDemo => baseUrl == null;

  Future<DashboardSnapshot> getDashboard(TrackingMode mode) async {
    if (baseUrl == null) return _demoDashboard(mode);

    final token = await tokenProvider?.call();
    if (token == null || token.trim().isEmpty) {
      throw const AuthRequiredException();
    }

    final endpoint = baseUrl!.resolve('/owner/dashboard');
    final uri = endpoint.replace(
      queryParameters: {...endpoint.queryParameters, 'mode': mode.apiValue},
    );
    final client = _clientFactory();
    try {
      final request = await client.getUrl(uri).timeout(requestTimeout);
      request.headers
        ..set(HttpHeaders.acceptHeader, ContentType.json.mimeType)
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
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
        throw HttpException(
          'Dashboard request failed: ${response.statusCode}',
          uri: uri,
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Dashboard response must be an object');
      }
      return DashboardSnapshot.fromJson(decoded, requestedMode: mode);
    } finally {
      client.close(force: true);
    }
  }

  DashboardSnapshot _demoDashboard(TrackingMode mode) {
    return switch (mode) {
      TrackingMode.business => const DashboardSnapshot(
        mode: TrackingMode.business,
        metrics: [
          DashboardMetric(
            key: 'salesToday',
            label: 'Sales today',
            value: '₪18,420',
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
            primaryValue: '₪9,840',
          ),
          SiteSnapshot(
            id: 'business-mall',
            name: 'RTS Business Mall',
            online: true,
            updatedLabel: 'Updated 2 min ago',
            primaryLabel: 'Sales today',
            primaryValue: '₪8,580',
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

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string');
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
