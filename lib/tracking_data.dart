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

extension AlertLevelDetails on AlertLevel {
  String get displayName => switch (this) {
    AlertLevel.info => 'Information',
    AlertLevel.warning => 'Warning',
    AlertLevel.critical => 'Critical',
  };

  int get severity => switch (this) {
    AlertLevel.critical => 0,
    AlertLevel.warning => 1,
    AlertLevel.info => 2,
  };
}

enum LocationStatus { online, offline, unknown }

extension LocationStatusDetails on LocationStatus {
  String get displayName => switch (this) {
    LocationStatus.online => 'Online',
    LocationStatus.offline => 'Offline',
    LocationStatus.unknown => 'Unknown',
  };
}

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

class LicenceInfo {
  const LicenceInfo({this.active, this.endsAt, this.lastCheckedAt});

  factory LicenceInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const LicenceInfo();
    return LicenceInfo(
      active: json['active'] is bool ? json['active'] as bool : null,
      endsAt: _optionalTimestamp(json, 'endsAt'),
      lastCheckedAt: _optionalTimestamp(json, 'lastCheckedAt'),
    );
  }

  final bool? active;
  final String? endsAt;
  final String? lastCheckedAt;
}

class ConnectivityInfo {
  const ConnectivityInfo({
    required this.available,
    required this.status,
    this.lastHeartbeatAt,
    this.source,
    this.detail,
  });

  const ConnectivityInfo.unavailable()
    : available = false,
      status = LocationStatus.unknown,
      lastHeartbeatAt = null,
      source = null,
      detail = null;

  factory ConnectivityInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ConnectivityInfo.unavailable();
    final available = json['available'] == true;
    return ConnectivityInfo(
      available: available,
      status: _locationStatus(json['status']),
      lastHeartbeatAt: _optionalTimestamp(json, 'lastHeartbeatAt'),
      source: _optionalString(json, 'source'),
      detail: _optionalString(json, 'detail'),
    );
  }

  final bool available;
  final LocationStatus status;
  final String? lastHeartbeatAt;
  final String? source;
  final String? detail;
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
    this.mode,
    this.status,
    this.telemetry = const ConnectivityInfo.unavailable(),
    this.licence = const LicenceInfo(),
  });

  factory SiteSnapshot.fromJson(Map<String, dynamic> json) {
    final online = json['online'] == true;
    final telemetry = ConnectivityInfo.fromJson(
      _optionalObject(json, 'telemetry'),
    );
    return SiteSnapshot(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      online: online,
      updatedLabel: _requiredString(json, 'updatedLabel'),
      primaryLabel: _requiredString(json, 'primaryLabel'),
      primaryValue: _requiredString(json, 'primaryValue'),
      attention: _optionalString(json, 'attention'),
      mode: _modeOrNull(json['mode']),
      status: json.containsKey('status')
          ? _locationStatus(json['status'])
          : (telemetry.available ? telemetry.status : null),
      telemetry: telemetry,
      licence: LicenceInfo.fromJson(_optionalObject(json, 'licence')),
    );
  }

  final String id;
  final String name;
  final bool online;
  final String updatedLabel;
  final String primaryLabel;
  final String primaryValue;
  final String? attention;
  final TrackingMode? mode;
  final LocationStatus? status;
  final ConnectivityInfo telemetry;
  final LicenceInfo licence;

  LocationStatus get effectiveStatus =>
      status ?? (online ? LocationStatus.online : LocationStatus.offline);

  bool get needsAttention =>
      effectiveStatus != LocationStatus.online || attention != null;
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
    final level = AlertLevel.values.where((value) => value.name == levelName);
    if (level.isEmpty) throw const FormatException('Unknown alert level');
    return TrackingAlert(
      id: _requiredString(json, 'id'),
      title: _requiredString(json, 'title'),
      detail: _requiredString(json, 'detail'),
      level: level.first,
    );
  }

  final String id;
  final String title;
  final String detail;
  final AlertLevel level;
}

class StaffSummary {
  const StaffSummary({
    this.totalAccounts,
    this.activeAccounts,
    this.adminAccounts,
  });

  factory StaffSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const StaffSummary();
    return StaffSummary(
      totalAccounts: _optionalInt(json, 'totalAccounts'),
      activeAccounts: _optionalInt(json, 'activeAccounts'),
      adminAccounts: _optionalInt(json, 'adminAccounts'),
    );
  }

  final int? totalAccounts;
  final int? activeAccounts;
  final int? adminAccounts;
}

class LocationOverview {
  const LocationOverview({this.total, this.online, this.unknown});

  factory LocationOverview.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const LocationOverview();
    return LocationOverview(
      total: _optionalInt(json, 'total'),
      online: _optionalInt(json, 'online'),
      unknown: _optionalInt(json, 'unknown'),
    );
  }

  final int? total;
  final int? online;
  final int? unknown;
}

class AlertOverview {
  const AlertOverview({this.total, this.critical});

  factory AlertOverview.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AlertOverview();
    return AlertOverview(
      total: _optionalInt(json, 'total'),
      critical: _optionalInt(json, 'critical'),
    );
  }

  final int? total;
  final int? critical;
}

class DashboardOverview {
  const DashboardOverview({
    this.organizationId,
    this.organizationName,
    this.licence = const LicenceInfo(),
    this.locations = const LocationOverview(),
    this.alerts = const AlertOverview(),
    this.staff = const StaffSummary(),
  });

  factory DashboardOverview.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DashboardOverview();
    final organization = _optionalObject(json, 'organization');
    return DashboardOverview(
      organizationId: organization == null
          ? null
          : _optionalString(organization, 'id'),
      organizationName: organization == null
          ? null
          : _optionalString(organization, 'name'),
      licence: LicenceInfo.fromJson(_optionalObject(json, 'licence')),
      locations: LocationOverview.fromJson(_optionalObject(json, 'locations')),
      alerts: AlertOverview.fromJson(_optionalObject(json, 'alerts')),
      staff: StaffSummary.fromJson(_optionalObject(json, 'staff')),
    );
  }

  factory DashboardOverview.fromLegacy(
    List<SiteSnapshot> sites,
    List<TrackingAlert> alerts,
  ) {
    return DashboardOverview(
      locations: LocationOverview(
        total: sites.length,
        online: sites.where((site) => site.online).length,
      ),
      alerts: AlertOverview(
        total: alerts.length,
        critical: alerts
            .where((alert) => alert.level == AlertLevel.critical)
            .length,
      ),
    );
  }

  final String? organizationId;
  final String? organizationName;
  final LicenceInfo licence;
  final LocationOverview locations;
  final AlertOverview alerts;
  final StaffSummary staff;
}

class AvailabilityValue {
  const AvailabilityValue({required this.available, this.value, this.reason});

  factory AvailabilityValue.fromJson(Map<String, dynamic> json) {
    return AvailabilityValue(
      available: json['available'] == true,
      value: json['value'],
      reason: _optionalString(json, 'reason'),
    );
  }

  final bool available;
  final Object? value;
  final String? reason;
}

class ModeDetail {
  const ModeDetail({
    required this.kind,
    required this.metrics,
    required this.patientMedicalDetailsIncluded,
  });

  factory ModeDetail.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const ModeDetail(
        kind: null,
        metrics: <String, AvailabilityValue>{},
        patientMedicalDetailsIncluded: false,
      );
    }

    final metrics = <String, AvailabilityValue>{};
    for (final entry in json.entries) {
      if (entry.key == 'kind' || entry.key == 'patientMedicalDetailsIncluded') {
        continue;
      }
      if (entry.value is Map<String, dynamic>) {
        final value = entry.value as Map<String, dynamic>;
        if (value.containsKey('available')) {
          metrics[entry.key] = AvailabilityValue.fromJson(value);
        }
      }
    }
    return ModeDetail(
      kind: _optionalString(json, 'kind'),
      metrics: Map.unmodifiable(metrics),
      patientMedicalDetailsIncluded:
          json['patientMedicalDetailsIncluded'] == true,
    );
  }

  final String? kind;
  final Map<String, AvailabilityValue> metrics;
  final bool patientMedicalDetailsIncluded;
}

class PlatformMessaging {
  const PlatformMessaging({
    required this.available,
    this.source,
    this.messageBalance,
    this.prepaidBalanceNis,
    this.customerPriceNis,
    this.platformCostNis,
    this.updatedAt,
  });

  factory PlatformMessaging.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const PlatformMessaging(available: false);
    return PlatformMessaging(
      available: json['available'] == true,
      source: _optionalString(json, 'source'),
      messageBalance: _optionalInt(json, 'messageBalance'),
      prepaidBalanceNis: _optionalDouble(json, 'prepaidBalanceNis'),
      customerPriceNis: _optionalDouble(json, 'customerPriceNis'),
      platformCostNis: _optionalDouble(json, 'platformCostNis'),
      updatedAt: _optionalTimestamp(json, 'updatedAt'),
    );
  }

  final bool available;
  final String? source;
  final int? messageBalance;
  final double? prepaidBalanceNis;
  final double? customerPriceNis;
  final double? platformCostNis;
  final String? updatedAt;
}

class FinancialMetrics {
  const FinancialMetrics({
    this.currency,
    this.businessRevenue = const AvailabilityValue(available: false),
    this.platformMessaging = const PlatformMessaging(available: false),
  });

  factory FinancialMetrics.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const FinancialMetrics();
    final revenue = _optionalObject(json, 'businessRevenue');
    return FinancialMetrics(
      currency: _optionalString(json, 'currency'),
      businessRevenue: revenue == null
          ? const AvailabilityValue(available: false)
          : AvailabilityValue.fromJson(revenue),
      platformMessaging: PlatformMessaging.fromJson(
        _optionalObject(json, 'platformMessaging'),
      ),
    );
  }

  final String? currency;
  final AvailabilityValue businessRevenue;
  final PlatformMessaging platformMessaging;
}

class OperationalMetrics {
  const OperationalMetrics({
    this.connectivity = const ConnectivityInfo.unavailable(),
    this.staff = const StaffSummary(),
    this.sourceBackend,
  });

  factory OperationalMetrics.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const OperationalMetrics();
    return OperationalMetrics(
      connectivity: ConnectivityInfo.fromJson(
        _optionalObject(json, 'connectivity'),
      ),
      staff: StaffSummary.fromJson(_optionalObject(json, 'staff')),
      sourceBackend: _optionalString(json, 'sourceBackend'),
    );
  }

  final ConnectivityInfo connectivity;
  final StaffSummary staff;
  final String? sourceBackend;
}

class DataGap {
  const DataGap({
    required this.key,
    required this.reason,
    required this.requiredTelemetry,
  });

  factory DataGap.fromJson(Map<String, dynamic> json) {
    return DataGap(
      key: _requiredString(json, 'key'),
      reason: _requiredString(json, 'reason'),
      requiredTelemetry: _requiredString(json, 'requiredTelemetry'),
    );
  }

  final String key;
  final String reason;
  final String requiredTelemetry;
}

class PrivacyScope {
  const PrivacyScope({
    this.scope,
    this.patientMedicalDetailsIncluded = false,
    this.unnecessaryPersonalDataIncluded = false,
  });

  factory PrivacyScope.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const PrivacyScope();
    return PrivacyScope(
      scope: _optionalString(json, 'scope'),
      patientMedicalDetailsIncluded:
          json['patientMedicalDetailsIncluded'] == true,
      unnecessaryPersonalDataIncluded:
          json['unnecessaryPersonalDataIncluded'] == true,
    );
  }

  final String? scope;
  final bool patientMedicalDetailsIncluded;
  final bool unnecessaryPersonalDataIncluded;
}

class DataAvailability {
  const DataAvailability({
    this.available = const [],
    this.unavailable = const [],
    this.gaps = const [],
    this.privacy = const PrivacyScope(),
  });

  factory DataAvailability.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DataAvailability();
    return DataAvailability(
      available: _stringList(json, 'available'),
      unavailable: _stringList(json, 'unavailable'),
      gaps: _objectListOrEmpty(
        json,
        'gaps',
      ).map(DataGap.fromJson).toList(growable: false),
      privacy: PrivacyScope.fromJson(_optionalObject(json, 'privacy')),
    );
  }

  final List<String> available;
  final List<String> unavailable;
  final List<DataGap> gaps;
  final PrivacyScope privacy;
}

class ActivityEvent {
  const ActivityEvent({
    required this.id,
    required this.category,
    required this.type,
    required this.title,
    required this.level,
    this.detail,
    this.occurredAt,
    this.source,
    this.changes = const {},
  });

  factory ActivityEvent.fromJson(Map<String, dynamic> json) {
    final type =
        _optionalString(json, 'type') ??
        _optionalString(json, 'action') ??
        'system-event';
    final title = _optionalString(json, 'title') ?? _activityTitle(type);
    return ActivityEvent(
      id: _requiredString(json, 'id'),
      category: _optionalString(json, 'category') ?? 'system',
      type: type,
      title: title,
      detail: _optionalString(json, 'detail'),
      level: _alertLevelOrInfo(_optionalString(json, 'level')),
      occurredAt: _optionalTimestamp(json, 'occurredAt'),
      source: _optionalString(json, 'source'),
      changes: _optionalObject(json, 'changes') ?? const {},
    );
  }

  static const _clinicSafeTypes = {
    'credit-allocation',
    'credit-usage',
    'licence-check',
    'licence-created',
  };

  final String id;
  final String category;
  final String type;
  final String title;
  final String? detail;
  final AlertLevel level;
  final String? occurredAt;
  final String? source;
  final Map<String, dynamic> changes;

  bool get isSafeForClinic => _clinicSafeTypes.contains(type);

  ActivityEvent privacySafeForClinic() {
    return ActivityEvent(
      id: id,
      category: category,
      type: type,
      title: _activityTitle(type),
      detail:
          'Aggregate-only operational activity. Personal and medical records are not shown.',
      level: level,
      occurredAt: occurredAt,
      source: 'RTS platform',
    );
  }
}

class AuditLog {
  const AuditLog({this.completeness, this.detail, this.events = const []});

  factory AuditLog.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AuditLog();
    return AuditLog(
      completeness: _optionalString(json, 'completeness'),
      detail: _optionalString(json, 'detail'),
      events: _objectListOrEmpty(
        json,
        'events',
      ).map(ActivityEvent.fromJson).toList(growable: false),
    );
  }

  final String? completeness;
  final String? detail;
  final List<ActivityEvent> events;

  AuditLog withEvents(List<ActivityEvent> value) {
    return AuditLog(completeness: completeness, detail: detail, events: value);
  }
}

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.mode,
    required this.metrics,
    required this.sites,
    required this.alerts,
    required this.synchronizedLabel,
    required this.isDemo,
    this.contractVersion = 1,
    this.generatedAt,
    this.overview = const DashboardOverview(),
    this.locations = const [],
    this.recentActivity = const [],
    this.auditLog = const AuditLog(),
    this.financialMetrics = const FinancialMetrics(),
    this.operationalMetrics = const OperationalMetrics(),
    this.modeDetail = const ModeDetail(
      kind: null,
      metrics: <String, AvailabilityValue>{},
      patientMedicalDetailsIncluded: false,
    ),
    this.dataAvailability = const DataAvailability(),
  });

  factory DashboardSnapshot.fromJson(
    Map<String, dynamic> json, {
    required TrackingMode requestedMode,
  }) {
    final responseMode = _modeOrNull(json['mode']);
    if (responseMode == null) {
      throw const FormatException('Unknown dashboard mode');
    }
    if (responseMode != requestedMode) {
      throw const FormatException('Dashboard mode does not match request');
    }

    final parsedSites = _objectList(
      json,
      'sites',
    ).map(SiteSnapshot.fromJson).toList(growable: false);
    final locationsJson = _objectListOrEmpty(json, 'locations');
    final parsedLocations = locationsJson.isEmpty
        ? parsedSites
        : locationsJson.map(SiteSnapshot.fromJson).toList(growable: false);
    final parsedAlerts = _objectList(
      json,
      'alerts',
    ).map(TrackingAlert.fromJson).toList(growable: false);
    final contractVersion = _optionalInt(json, 'contractVersion') ?? 1;
    final sites = _privacySafeLocations(
      _contractSafeLocations(parsedSites, contractVersion),
      responseMode,
    );
    final locations = _privacySafeLocations(
      _contractSafeLocations(parsedLocations, contractVersion),
      responseMode,
    );
    final alerts = _privacySafeAlerts(parsedAlerts, responseMode);
    final overview = DashboardOverview.fromJson(
      _optionalObject(json, 'overview'),
    );
    final rawAuditLog = AuditLog.fromJson(_optionalObject(json, 'auditLog'));
    final rawActivity = _objectListOrEmpty(
      json,
      'recentActivity',
    ).map(ActivityEvent.fromJson).toList(growable: false);
    final activity = rawActivity.isEmpty ? rawAuditLog.events : rawActivity;
    final sanitizedActivity = _privacySafeActivity(activity, responseMode)
      ..sort((left, right) {
        final leftTime = left.occurredAt ?? '';
        final rightTime = right.occurredAt ?? '';
        return rightTime.compareTo(leftTime);
      });
    final operationalMetrics = OperationalMetrics.fromJson(
      _optionalObject(json, 'operationalMetrics'),
    );
    final metrics = _objectList(
      json,
      'metrics',
    ).map(DashboardMetric.fromJson).toList(growable: false);
    final financialMetrics = FinancialMetrics.fromJson(
      _optionalObject(json, 'financialMetrics'),
    );
    final modeDetail = ModeDetail.fromJson(_optionalObject(json, 'modeDetail'));
    final dataAvailability = DataAvailability.fromJson(
      _optionalObject(json, 'dataAvailability'),
    );

    return DashboardSnapshot(
      contractVersion: contractVersion,
      generatedAt: _optionalTimestamp(json, 'generatedAt'),
      mode: responseMode,
      metrics: responseMode == TrackingMode.clinic
          ? _privacySafeMetrics(metrics)
          : metrics,
      sites: sites,
      locations: locations,
      alerts: alerts,
      synchronizedLabel: responseMode == TrackingMode.clinic
          ? _clinicSynchronizationLabel(_optionalTimestamp(json, 'generatedAt'))
          : (_optionalString(json, 'synchronizedLabel') ??
                _optionalTimestamp(json, 'generatedAt') ??
                'Data timestamp unavailable'),
      overview:
          overview.organizationName == null &&
              overview.locations.total == null &&
              overview.alerts.total == null
          ? DashboardOverview.fromLegacy(sites, alerts)
          : overview,
      recentActivity: sanitizedActivity,
      auditLog: responseMode == TrackingMode.clinic
          ? AuditLog(
              completeness: rawAuditLog.completeness,
              detail:
                  'Only aggregate platform and system activity is shown. Personal and medical records are excluded.',
              events: _privacySafeActivity(rawAuditLog.events, responseMode),
            )
          : rawAuditLog.withEvents(
              _privacySafeActivity(rawAuditLog.events, responseMode),
            ),
      financialMetrics: responseMode == TrackingMode.clinic
          ? _privacySafeFinancialMetrics(financialMetrics)
          : financialMetrics,
      operationalMetrics: responseMode == TrackingMode.clinic
          ? _privacySafeOperationalMetrics(operationalMetrics)
          : operationalMetrics,
      modeDetail: responseMode == TrackingMode.clinic
          ? _privacySafeModeDetail(modeDetail)
          : modeDetail,
      dataAvailability: responseMode == TrackingMode.clinic
          ? _privacySafeDataAvailability(dataAvailability)
          : dataAvailability,
      isDemo: false,
    );
  }

  final int contractVersion;
  final String? generatedAt;
  final TrackingMode mode;
  final List<DashboardMetric> metrics;
  final List<SiteSnapshot> sites;
  final List<SiteSnapshot> locations;
  final List<TrackingAlert> alerts;
  final String synchronizedLabel;
  final DashboardOverview overview;
  final List<ActivityEvent> recentActivity;
  final AuditLog auditLog;
  final FinancialMetrics financialMetrics;
  final OperationalMetrics operationalMetrics;
  final ModeDetail modeDetail;
  final DataAvailability dataAvailability;
  final bool isDemo;

  int get onlineSites => locations
      .where((site) => site.effectiveStatus == LocationStatus.online)
      .length;
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
    final mode = TrackingMode.values.where(
      (candidate) => candidate.apiValue == modeName,
    );
    if (mode.isEmpty) throw const FormatException('Unknown owner mode');
    return OwnerSession(
      token: _requiredString(json, 'token'),
      mode: mode.first,
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
      TrackingMode.business => _businessDemo,
      TrackingMode.clinic => _clinicDemo,
    };
  }
}

const _businessDemo = DashboardSnapshot(
  contractVersion: 2,
  generatedAt: '2026-10-11T12:00:00.000Z',
  mode: TrackingMode.business,
  metrics: [
    DashboardMetric(key: 'salesToday', label: 'Sales today', value: '₪18,420'),
    DashboardMetric(key: 'ordersToday', label: 'Orders today', value: '146'),
    DashboardMetric(key: 'stockAlerts', label: 'Stock alerts', value: '2'),
  ],
  sites: [
    SiteSnapshot(
      id: 'business-main',
      name: 'RTS Business Main Store',
      online: true,
      updatedLabel: 'Heartbeat just now',
      primaryLabel: 'Sales today',
      primaryValue: '₪9,840',
      status: LocationStatus.online,
      telemetry: ConnectivityInfo(
        available: true,
        status: LocationStatus.online,
        lastHeartbeatAt: '2026-10-11T11:59:00.000Z',
        source: 'source-application-heartbeat',
        detail: 'A recent source-application heartbeat was received.',
      ),
      licence: LicenceInfo(active: true, endsAt: '2027-10-11T00:00:00.000Z'),
    ),
    SiteSnapshot(
      id: 'business-mall',
      name: 'RTS Business Mall',
      online: true,
      updatedLabel: 'Heartbeat 2 min ago',
      primaryLabel: 'Sales today',
      primaryValue: '₪8,580',
      attention: '2 low-stock items need review',
      status: LocationStatus.online,
      telemetry: ConnectivityInfo(
        available: true,
        status: LocationStatus.online,
        lastHeartbeatAt: '2026-10-11T11:58:00.000Z',
        source: 'source-application-heartbeat',
      ),
      licence: LicenceInfo(active: true, endsAt: '2027-10-11T00:00:00.000Z'),
    ),
    SiteSnapshot(
      id: 'business-warehouse',
      name: 'RTS Business Warehouse',
      online: false,
      updatedLabel: 'Heartbeat 18 min ago',
      primaryLabel: 'Open stock tasks',
      primaryValue: '4',
      attention: 'Connection lost',
      status: LocationStatus.offline,
      telemetry: ConnectivityInfo(
        available: true,
        status: LocationStatus.offline,
        lastHeartbeatAt: '2026-10-11T11:42:00.000Z',
        source: 'source-application-heartbeat',
        detail: 'The source-application heartbeat is stale.',
      ),
      licence: LicenceInfo(active: true, endsAt: '2027-10-11T00:00:00.000Z'),
    ),
  ],
  locations: [
    SiteSnapshot(
      id: 'business-main',
      name: 'RTS Business Main Store',
      online: true,
      updatedLabel: 'Heartbeat just now',
      primaryLabel: 'Sales today',
      primaryValue: '₪9,840',
      status: LocationStatus.online,
      telemetry: ConnectivityInfo(
        available: true,
        status: LocationStatus.online,
        lastHeartbeatAt: '2026-10-11T11:59:00.000Z',
        source: 'source-application-heartbeat',
        detail: 'A recent source-application heartbeat was received.',
      ),
      licence: LicenceInfo(active: true, endsAt: '2027-10-11T00:00:00.000Z'),
    ),
    SiteSnapshot(
      id: 'business-mall',
      name: 'RTS Business Mall',
      online: true,
      updatedLabel: 'Heartbeat 2 min ago',
      primaryLabel: 'Sales today',
      primaryValue: '₪8,580',
      attention: '2 low-stock items need review',
      status: LocationStatus.online,
      telemetry: ConnectivityInfo(
        available: true,
        status: LocationStatus.online,
        lastHeartbeatAt: '2026-10-11T11:58:00.000Z',
        source: 'source-application-heartbeat',
      ),
      licence: LicenceInfo(active: true, endsAt: '2027-10-11T00:00:00.000Z'),
    ),
    SiteSnapshot(
      id: 'business-warehouse',
      name: 'RTS Business Warehouse',
      online: false,
      updatedLabel: 'Heartbeat 18 min ago',
      primaryLabel: 'Open stock tasks',
      primaryValue: '4',
      attention: 'Connection lost',
      status: LocationStatus.offline,
      telemetry: ConnectivityInfo(
        available: true,
        status: LocationStatus.offline,
        lastHeartbeatAt: '2026-10-11T11:42:00.000Z',
        source: 'source-application-heartbeat',
        detail: 'The source-application heartbeat is stale.',
      ),
      licence: LicenceInfo(active: true, endsAt: '2027-10-11T00:00:00.000Z'),
    ),
  ],
  alerts: [
    TrackingAlert(
      id: 'warehouse-offline',
      title: 'Warehouse heartbeat is stale',
      detail: 'RTS Business Warehouse has not checked in for 18 minutes.',
      level: AlertLevel.critical,
    ),
    TrackingAlert(
      id: 'low-stock',
      title: '2 low-stock items need review',
      detail: 'RTS Business Mall',
      level: AlertLevel.warning,
    ),
  ],
  synchronizedLabel: 'Demo snapshot generated locally',
  overview: DashboardOverview(
    organizationId: 'business-demo',
    organizationName: 'RTS Business',
    licence: LicenceInfo(active: true, endsAt: '2027-10-11T00:00:00.000Z'),
    locations: LocationOverview(total: 3, online: 2),
    alerts: AlertOverview(total: 2, critical: 1),
    staff: StaffSummary(totalAccounts: 9, activeAccounts: 8, adminAccounts: 2),
  ),
  recentActivity: [
    ActivityEvent(
      id: 'credit-usage-demo',
      category: 'platform-messaging',
      type: 'credit-usage',
      title: 'Messaging credits used',
      detail: '12 messages · ₪6.00',
      level: AlertLevel.info,
      occurredAt: '2026-10-11T11:45:00.000Z',
      source: 'rts-royal-d1',
    ),
    ActivityEvent(
      id: 'licence-check-demo',
      category: 'system',
      type: 'licence-check',
      title: 'Business licence checked',
      detail: 'A licence check is not a live heartbeat.',
      level: AlertLevel.info,
      occurredAt: '2026-10-11T11:42:00.000Z',
      source: 'firestore-licence',
    ),
  ],
  financialMetrics: FinancialMetrics(
    currency: 'ILS',
    businessRevenue: AvailabilityValue(
      available: false,
      reason: 'Sales are represented by demo data only.',
    ),
    platformMessaging: PlatformMessaging(
      available: true,
      source: 'rts-royal-d1',
      messageBalance: 124,
      prepaidBalanceNis: 62,
      customerPriceNis: 0.5,
      platformCostNis: 0.2,
      updatedAt: '2026-10-11T11:45:00.000Z',
    ),
  ),
  operationalMetrics: OperationalMetrics(
    connectivity: ConnectivityInfo(
      available: true,
      status: LocationStatus.online,
      lastHeartbeatAt: '2026-10-11T11:59:00.000Z',
      source: 'source-application-heartbeat',
    ),
    staff: StaffSummary(totalAccounts: 9, activeAccounts: 8, adminAccounts: 2),
    sourceBackend: 'demo-source',
  ),
  modeDetail: ModeDetail(
    kind: 'business',
    metrics: {
      'inventoryValue': AvailabilityValue(
        available: false,
        reason: 'Inventory value is not included in the demo source.',
      ),
    },
    patientMedicalDetailsIncluded: false,
  ),
  dataAvailability: DataAvailability(
    available: ['licence', 'staff-counts', 'operational-heartbeat'],
    unavailable: ['inventory'],
    gaps: [
      DataGap(
        key: 'business-inventory',
        reason: 'Inventory detail is not connected in this demo.',
        requiredTelemetry:
            'Publish aggregate inventory health to the owner feed.',
      ),
    ],
    privacy: PrivacyScope(
      scope: 'aggregate-only',
      patientMedicalDetailsIncluded: false,
      unnecessaryPersonalDataIncluded: false,
    ),
  ),
  isDemo: true,
);

const _clinicDemo = DashboardSnapshot(
  contractVersion: 2,
  generatedAt: '2026-10-11T12:00:00.000Z',
  mode: TrackingMode.clinic,
  metrics: [
    DashboardMetric(
      key: 'appointmentsToday',
      label: 'Scheduled today',
      value: '27',
    ),
    DashboardMetric(
      key: 'waitingCount',
      label: 'Aggregate waiting count',
      value: '4',
    ),
    DashboardMetric(key: 'followUps', label: 'Follow-ups due', value: '2'),
  ],
  sites: [
    SiteSnapshot(
      id: 'clinic-main',
      name: 'RTS Clinic Main',
      online: true,
      updatedLabel: 'Heartbeat just now',
      primaryLabel: 'Scheduled today',
      primaryValue: '14',
      status: LocationStatus.online,
      telemetry: ConnectivityInfo(
        available: true,
        status: LocationStatus.online,
        lastHeartbeatAt: '2026-10-11T11:59:00.000Z',
        source: 'source-application-heartbeat',
      ),
      licence: LicenceInfo(active: true, endsAt: '2027-10-11T00:00:00.000Z'),
    ),
    SiteSnapshot(
      id: 'clinic-north',
      name: 'RTS Clinic North',
      online: true,
      updatedLabel: 'Heartbeat 1 min ago',
      primaryLabel: 'Scheduled today',
      primaryValue: '13',
      attention: 'Aggregate waiting count is elevated',
      status: LocationStatus.online,
      telemetry: ConnectivityInfo(
        available: true,
        status: LocationStatus.online,
        lastHeartbeatAt: '2026-10-11T11:58:00.000Z',
        source: 'source-application-heartbeat',
      ),
      licence: LicenceInfo(active: true, endsAt: '2027-10-11T00:00:00.000Z'),
    ),
    SiteSnapshot(
      id: 'clinic-west',
      name: 'RTS Clinic West',
      online: false,
      updatedLabel: 'Heartbeat 11 min ago',
      primaryLabel: 'Scheduled today',
      primaryValue: '0',
      attention: 'Connection lost',
      status: LocationStatus.offline,
      telemetry: ConnectivityInfo(
        available: true,
        status: LocationStatus.offline,
        lastHeartbeatAt: '2026-10-11T11:49:00.000Z',
        source: 'source-application-heartbeat',
        detail: 'The source-application heartbeat is stale.',
      ),
      licence: LicenceInfo(active: true, endsAt: '2027-10-11T00:00:00.000Z'),
    ),
  ],
  locations: [
    SiteSnapshot(
      id: 'clinic-main',
      name: 'RTS Clinic Main',
      online: true,
      updatedLabel: 'Heartbeat just now',
      primaryLabel: 'Scheduled today',
      primaryValue: '14',
      status: LocationStatus.online,
      telemetry: ConnectivityInfo(
        available: true,
        status: LocationStatus.online,
        lastHeartbeatAt: '2026-10-11T11:59:00.000Z',
        source: 'source-application-heartbeat',
      ),
      licence: LicenceInfo(active: true, endsAt: '2027-10-11T00:00:00.000Z'),
    ),
    SiteSnapshot(
      id: 'clinic-north',
      name: 'RTS Clinic North',
      online: true,
      updatedLabel: 'Heartbeat 1 min ago',
      primaryLabel: 'Scheduled today',
      primaryValue: '13',
      attention: 'Aggregate waiting count is elevated',
      status: LocationStatus.online,
      telemetry: ConnectivityInfo(
        available: true,
        status: LocationStatus.online,
        lastHeartbeatAt: '2026-10-11T11:58:00.000Z',
        source: 'source-application-heartbeat',
      ),
      licence: LicenceInfo(active: true, endsAt: '2027-10-11T00:00:00.000Z'),
    ),
    SiteSnapshot(
      id: 'clinic-west',
      name: 'RTS Clinic West',
      online: false,
      updatedLabel: 'Heartbeat 11 min ago',
      primaryLabel: 'Scheduled today',
      primaryValue: '0',
      attention: 'Connection lost',
      status: LocationStatus.offline,
      telemetry: ConnectivityInfo(
        available: true,
        status: LocationStatus.offline,
        lastHeartbeatAt: '2026-10-11T11:49:00.000Z',
        source: 'source-application-heartbeat',
        detail: 'The source-application heartbeat is stale.',
      ),
      licence: LicenceInfo(active: true, endsAt: '2027-10-11T00:00:00.000Z'),
    ),
  ],
  alerts: [
    TrackingAlert(
      id: 'clinic-offline',
      title: 'Clinic heartbeat is stale',
      detail: 'RTS Clinic West has not checked in for 11 minutes.',
      level: AlertLevel.critical,
    ),
    TrackingAlert(
      id: 'follow-ups',
      title: 'Aggregate follow-up count needs review',
      detail: 'RTS Clinic North',
      level: AlertLevel.warning,
    ),
  ],
  synchronizedLabel: 'Demo snapshot generated locally',
  overview: DashboardOverview(
    organizationId: 'clinic-demo',
    organizationName: 'RTS Clinic',
    licence: LicenceInfo(active: true, endsAt: '2027-10-11T00:00:00.000Z'),
    locations: LocationOverview(total: 3, online: 2),
    alerts: AlertOverview(total: 2, critical: 1),
    staff: StaffSummary(
      totalAccounts: 11,
      activeAccounts: 10,
      adminAccounts: 2,
    ),
  ),
  recentActivity: [
    ActivityEvent(
      id: 'clinic-credit-usage-demo',
      category: 'platform-messaging',
      type: 'credit-usage',
      title: 'Messaging credits used',
      detail: '8 messages · ₪4.00',
      level: AlertLevel.info,
      occurredAt: '2026-10-11T11:45:00.000Z',
      source: 'rts-royal-d1',
    ),
    ActivityEvent(
      id: 'clinic-licence-check-demo',
      category: 'system',
      type: 'licence-check',
      title: 'Clinic licence checked',
      detail: 'A licence check is not a live heartbeat.',
      level: AlertLevel.info,
      occurredAt: '2026-10-11T11:42:00.000Z',
      source: 'firestore-licence',
    ),
  ],
  financialMetrics: FinancialMetrics(
    currency: 'ILS',
    businessRevenue: AvailabilityValue(
      available: false,
      reason: 'Clinic financial totals are not included in the demo source.',
    ),
    platformMessaging: PlatformMessaging(
      available: true,
      source: 'rts-royal-d1',
      messageBalance: 88,
      prepaidBalanceNis: 44,
      customerPriceNis: 0.5,
      platformCostNis: 0.2,
      updatedAt: '2026-10-11T11:45:00.000Z',
    ),
  ),
  operationalMetrics: OperationalMetrics(
    connectivity: ConnectivityInfo(
      available: true,
      status: LocationStatus.online,
      lastHeartbeatAt: '2026-10-11T11:59:00.000Z',
      source: 'source-application-heartbeat',
    ),
    staff: StaffSummary(
      totalAccounts: 11,
      activeAccounts: 10,
      adminAccounts: 2,
    ),
    sourceBackend: 'demo-source',
  ),
  modeDetail: ModeDetail(
    kind: 'clinic',
    metrics: {
      'appointmentsToday': AvailabilityValue(available: true, value: 27),
      'waitingCount': AvailabilityValue(available: true, value: 4),
      'followUpsDue': AvailabilityValue(available: true, value: 2),
    },
    patientMedicalDetailsIncluded: false,
  ),
  dataAvailability: DataAvailability(
    available: ['licence', 'staff-counts', 'operational-heartbeat'],
    unavailable: ['sessions', 'medical-records'],
    gaps: [
      DataGap(
        key: 'clinic-medical-records',
        reason:
            'Patient records and session details are deliberately excluded.',
        requiredTelemetry:
            'Publish aggregate-only clinic health and queue totals; never publish patient data.',
      ),
    ],
    privacy: PrivacyScope(
      scope: 'aggregate-only',
      patientMedicalDetailsIncluded: false,
      unnecessaryPersonalDataIncluded: false,
    ),
  ),
  isDemo: true,
);

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

String formatTimestamp(String? value) {
  if (value == null || value.trim().isEmpty) return 'Not published';
  final time = DateTime.tryParse(value);
  if (time == null) return value;
  final local = time.toLocal();
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}

String formatNis(double? value) {
  if (value == null) return 'Not published';
  return '₪${value.toStringAsFixed(2)}';
}

List<ActivityEvent> _privacySafeActivity(
  Iterable<ActivityEvent> events,
  TrackingMode mode,
) {
  return events
      .where((event) => mode != TrackingMode.clinic || event.isSafeForClinic)
      .map(
        (event) =>
            mode == TrackingMode.clinic ? event.privacySafeForClinic() : event,
      )
      .toList(growable: false);
}

List<DashboardMetric> _privacySafeMetrics(Iterable<DashboardMetric> metrics) {
  final safe = <DashboardMetric>[];
  for (final metric in metrics) {
    switch (metric.key) {
      case 'licence':
        safe.add(
          DashboardMetric(
            key: metric.key,
            label: 'Licence',
            value: {'Active', 'Expired'}.contains(metric.value)
                ? metric.value
                : 'Unavailable',
          ),
        );
        continue;
      case 'licenceEnd':
        safe.add(
          DashboardMetric(
            key: metric.key,
            label: 'Licence ends',
            value:
                DateTime.tryParse(
                  metric.value,
                )?.toIso8601String().split('T').first ??
                'Unavailable',
          ),
        );
        continue;
      case 'activeStaff':
        safe.add(
          DashboardMetric(
            key: metric.key,
            label: 'Active staff',
            value: int.tryParse(metric.value)?.toString() ?? 'Unavailable',
          ),
        );
        continue;
      case 'operationalStatus':
        safe.add(
          DashboardMetric(
            key: metric.key,
            label: 'Live status',
            value: {'Not connected', 'Online', 'Offline'}.contains(metric.value)
                ? metric.value
                : 'Unknown',
          ),
        );
        continue;
      case 'messageCredits':
        safe.add(
          DashboardMetric(
            key: metric.key,
            label: 'Message credits',
            value: int.tryParse(metric.value)?.toString() ?? 'Unavailable',
          ),
        );
        continue;
      case 'appointmentsToday':
        safe.add(
          DashboardMetric(
            key: metric.key,
            label: 'Appointments',
            value: int.tryParse(metric.value)?.toString() ?? 'Unavailable',
          ),
        );
        continue;
      case 'waitingCount':
        safe.add(
          DashboardMetric(
            key: metric.key,
            label: 'Patients waiting',
            value: int.tryParse(metric.value)?.toString() ?? 'Unavailable',
          ),
        );
        continue;
      case 'completedSessionsToday':
        safe.add(
          DashboardMetric(
            key: metric.key,
            label: 'Completed sessions',
            value: int.tryParse(metric.value)?.toString() ?? 'Unavailable',
          ),
        );
        continue;
      case 'followUpsDue':
        safe.add(
          DashboardMetric(
            key: metric.key,
            label: 'Follow-ups due',
            value: int.tryParse(metric.value)?.toString() ?? 'Unavailable',
          ),
        );
        continue;
    }
  }
  return List.unmodifiable(safe);
}

String _clinicSynchronizationLabel(String? generatedAt) {
  return generatedAt == null
      ? 'Clinic owner data timestamp unavailable'
      : 'Clinic owner data generated $generatedAt';
}

FinancialMetrics _privacySafeFinancialMetrics(FinancialMetrics metrics) {
  final messaging = metrics.platformMessaging;
  return FinancialMetrics(
    currency: metrics.currency == 'ILS' ? 'ILS' : null,
    businessRevenue: const AvailabilityValue(
      available: false,
      reason:
          'Clinic financial totals remain local and are not published to Tracking.',
    ),
    platformMessaging: PlatformMessaging(
      available: messaging.available,
      source: messaging.available ? 'RTS Royal messaging ledger' : null,
      messageBalance: messaging.messageBalance,
      prepaidBalanceNis: messaging.prepaidBalanceNis,
      customerPriceNis: messaging.customerPriceNis,
      platformCostNis: messaging.platformCostNis,
      updatedAt: messaging.updatedAt,
    ),
  );
}

ModeDetail _privacySafeModeDetail(ModeDetail detail) {
  const safeKeys = {
    'appointmentsToday',
    'waitingCount',
    'completedSessionsToday',
    'followUpsDue',
    'collectionsToday',
    'outstandingInsurance',
  };
  return ModeDetail(
    kind: 'clinic',
    metrics: Map.unmodifiable({
      for (final key in detail.metrics.keys.where(safeKeys.contains))
        key: const AvailabilityValue(
          available: false,
          reason:
              'This aggregate clinic metric is not published to Tracking yet.',
        ),
    }),
    patientMedicalDetailsIncluded: false,
  );
}

DataAvailability _privacySafeDataAvailability(DataAvailability availability) {
  const knownCapabilities = {
    'licence',
    'staff-counts',
    'last-licence-check',
    'platform-messaging-balance',
    'platform-messaging-ledger',
    'operational-heartbeat',
    'appointments',
    'queue',
    'sessions',
    'follow-ups',
    'clinic-revenue',
    'complete-audit-log',
  };
  final available = availability.available
      .where(knownCapabilities.contains)
      .toList(growable: false);
  final unavailable = availability.unavailable
      .where(knownCapabilities.contains)
      .toList(growable: false);
  final gaps = <DataGap>[];
  if (availability.gaps.any((gap) => gap.key == 'clinic-operations')) {
    gaps.add(
      const DataGap(
        key: 'clinic-operations',
        reason:
            'Appointments, sessions, payments, and audit records remain in the clinic workspace.',
        requiredTelemetry:
            'Publish aggregate-only clinic counts and financial totals without patient or medical data.',
      ),
    );
  }
  if (availability.gaps.any((gap) => gap.key == 'clinic-connectivity')) {
    gaps.add(
      const DataGap(
        key: 'clinic-connectivity',
        reason: 'The clinic does not publish a periodic operational heartbeat.',
        requiredTelemetry:
            'Publish a signed heartbeat containing only clinic identity, app version, sync time, and aggregate queue health.',
      ),
    );
  }
  return DataAvailability(
    available: available,
    unavailable: unavailable,
    gaps: gaps,
    privacy: const PrivacyScope(
      scope: 'aggregate-only',
      patientMedicalDetailsIncluded: false,
      unnecessaryPersonalDataIncluded: false,
    ),
  );
}

List<SiteSnapshot> _privacySafeLocations(
  Iterable<SiteSnapshot> locations,
  TrackingMode mode,
) {
  if (mode != TrackingMode.clinic) return locations.toList(growable: false);
  return locations
      .map(
        (location) => SiteSnapshot(
          id: location.id,
          name: location.name,
          online: location.online,
          updatedLabel: location.telemetry.lastHeartbeatAt == null
              ? 'Live status unavailable'
              : 'Heartbeat ${location.telemetry.lastHeartbeatAt}',
          primaryLabel: 'Clinic licence',
          primaryValue: switch (location.licence.active) {
            true => 'Active',
            false => 'Inactive',
            null => 'Not published',
          },
          attention: location.needsAttention
              ? 'This clinic needs owner attention. Sensitive details are hidden.'
              : null,
          mode: TrackingMode.clinic,
          status: location.effectiveStatus,
          telemetry: _privacySafeConnectivity(location.telemetry),
          licence: location.licence,
        ),
      )
      .toList(growable: false);
}

ConnectivityInfo _privacySafeConnectivity(ConnectivityInfo connectivity) {
  return ConnectivityInfo(
    available: connectivity.available,
    status: connectivity.status,
    lastHeartbeatAt: connectivity.lastHeartbeatAt,
    source: connectivity.available ? 'RTS operational heartbeat' : null,
    detail: connectivity.available
        ? 'Aggregate connectivity status only. No patient or medical data is included.'
        : 'No periodic operational heartbeat is connected.',
  );
}

OperationalMetrics _privacySafeOperationalMetrics(OperationalMetrics metrics) {
  const safeBackends = {'local-workspace', 'firestore', 'd1'};
  return OperationalMetrics(
    connectivity: _privacySafeConnectivity(metrics.connectivity),
    staff: metrics.staff,
    sourceBackend: safeBackends.contains(metrics.sourceBackend)
        ? metrics.sourceBackend
        : null,
  );
}

List<SiteSnapshot> _contractSafeLocations(
  Iterable<SiteSnapshot> locations,
  int contractVersion,
) {
  if (contractVersion < 2) return locations.toList(growable: false);
  return locations
      .map(
        (location) => location.status == null && !location.telemetry.available
            ? SiteSnapshot(
                id: location.id,
                name: location.name,
                online: false,
                updatedLabel: location.updatedLabel,
                primaryLabel: location.primaryLabel,
                primaryValue: location.primaryValue,
                attention: location.attention,
                mode: location.mode,
                status: LocationStatus.unknown,
                telemetry: location.telemetry,
                licence: location.licence,
              )
            : location,
      )
      .toList(growable: false);
}

List<TrackingAlert> _privacySafeAlerts(
  Iterable<TrackingAlert> alerts,
  TrackingMode mode,
) {
  if (mode != TrackingMode.clinic) return alerts.toList(growable: false);
  return alerts
      .map(
        (alert) => switch (alert.id) {
          'licence-expired' => TrackingAlert(
            id: alert.id,
            title: 'Clinic licence is inactive',
            detail: 'Renew the clinic licence to restore full access.',
            level: alert.level,
          ),
          'operational-telemetry-unavailable' => TrackingAlert(
            id: alert.id,
            title: 'Live clinic status is unavailable',
            detail: 'This clinic has not connected a periodic heartbeat.',
            level: alert.level,
          ),
          'operational-heartbeat-stale' => TrackingAlert(
            id: alert.id,
            title: 'Clinic heartbeat is stale',
            detail:
                'The latest operational heartbeat is outside the expected interval.',
            level: alert.level,
          ),
          'messaging-credit-low' => TrackingAlert(
            id: alert.id,
            title: 'Messaging credit balance is low',
            detail: 'Review the clinic messaging balance in Today.',
            level: alert.level,
          ),
          _ => TrackingAlert(
            id: alert.id,
            title: 'Clinic operational alert',
            detail:
                'Sensitive details are hidden. Review this alert in the clinic system.',
            level: alert.level,
          ),
        },
      )
      .toList(growable: false);
}

bool _isLocalHost(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'localhost' ||
      normalized == '127.0.0.1' ||
      normalized == '::1';
}

TrackingMode? _modeOrNull(Object? value) {
  return TrackingMode.values
      .where((mode) => mode.apiValue == value)
      .firstOrNull;
}

LocationStatus _locationStatus(Object? value) {
  return LocationStatus.values
          .where((status) => status.name == value)
          .firstOrNull ??
      LocationStatus.unknown;
}

AlertLevel _alertLevelOrInfo(String? value) {
  return AlertLevel.values.where((level) => level.name == value).firstOrNull ??
      AlertLevel.info;
}

String _activityTitle(String type) {
  return switch (type) {
    'credit-allocation' => 'Messaging credits allocated',
    'credit-usage' => 'Messaging credits used',
    'licence-check' => 'Licence checked',
    'licence-created' => 'Location provisioned',
    _ => 'System activity',
  };
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string');
  }
  return value;
}

String? _optionalTimestamp(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) return null;
  return DateTime.tryParse(value.trim())?.toUtc().toIso8601String();
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string when provided');
  }
  return value;
}

int? _optionalInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is num) return value.toInt();
  throw FormatException('$key must be a number when provided');
}

double? _optionalDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is num) return value.toDouble();
  throw FormatException('$key must be a number when provided');
}

Map<String, dynamic>? _optionalObject(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is Map<String, dynamic>) return value;
  throw FormatException('$key must be an object when provided');
}

List<String> _stringList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return const [];
  if (value is! List || value.any((item) => item is! String)) {
    throw FormatException('$key must be a list of strings when provided');
  }
  return value.cast<String>().toList(growable: false);
}

List<Map<String, dynamic>> _objectList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List) {
    throw FormatException('$key must be a list');
  }
  return _asObjectList(value, key);
}

List<Map<String, dynamic>> _objectListOrEmpty(
  Map<String, dynamic> json,
  String key,
) {
  final value = json[key];
  if (value == null) return const [];
  if (value is! List) {
    throw FormatException('$key must be a list when provided');
  }
  return _asObjectList(value, key);
}

List<Map<String, dynamic>> _asObjectList(List<dynamic> value, String key) {
  return value
      .map((item) {
        if (item is! Map<String, dynamic>) {
          throw FormatException('$key entries must be objects');
        }
        return item;
      })
      .toList(growable: false);
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
