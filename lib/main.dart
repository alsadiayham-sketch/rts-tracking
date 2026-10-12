import 'package:flutter/material.dart';

import 'api_configuration.dart';
import 'tracking_data.dart';

void main() {
  final configuredBaseUrl = resolveApiBaseUrl();
  runApp(
    RtsTrackingApp(
      api: OwnerApi.fromConfiguredUrl(configuredBaseUrl),
      requireAuthentication: true,
    ),
  );
}

class RtsTrackingApp extends StatelessWidget {
  const RtsTrackingApp({
    super.key,
    this.api,
    this.sessionStore,
    this.requireAuthentication = true,
  });

  final OwnerApi? api;
  final OwnerSessionStore? sessionStore;
  final bool requireAuthentication;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF48115B);
    final effectiveApi = api ?? OwnerApi();
    return MaterialApp(
      title: 'RTS Tracking',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: _theme(Brightness.light, seed),
      darkTheme: _theme(Brightness.dark, seed),
      home: effectiveApi.isDemo && !requireAuthentication
          ? TrackingHome(api: effectiveApi)
          : AuthenticatedOwnerFlow(
              api: effectiveApi,
              sessionStore: sessionStore ?? SecureOwnerSessionStore(),
            ),
    );
  }

  ThemeData _theme(Brightness brightness, Color seed) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      useMaterial3: true,
      fontFamily: 'Arial',
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}

class AuthenticatedOwnerFlow extends StatefulWidget {
  const AuthenticatedOwnerFlow({
    super.key,
    required this.api,
    required this.sessionStore,
  });

  final OwnerApi api;
  final OwnerSessionStore sessionStore;

  @override
  State<AuthenticatedOwnerFlow> createState() => _AuthenticatedOwnerFlowState();
}

class _AuthenticatedOwnerFlowState extends State<AuthenticatedOwnerFlow> {
  OwnerSession? session;
  String? notice;
  bool restoring = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final restoredSession = await widget.sessionStore.read();
      if (!mounted) return;
      setState(() => session = restoredSession);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        notice = 'The saved session could not be restored. Sign in again.';
      });
    } finally {
      if (mounted) setState(() => restoring = false);
    }
  }

  Future<void> _login(
    String organizationName,
    String username,
    String password,
  ) async {
    final authenticated = await widget.api.login(
      organizationName,
      username,
      password,
    );
    await widget.sessionStore.write(authenticated);
    if (!mounted) return;
    setState(() {
      session = authenticated;
      notice = null;
    });
  }

  Future<void> _logout() async {
    await widget.sessionStore.clear();
    if (!mounted) return;
    setState(() {
      session = null;
      notice = null;
    });
  }

  Future<void> _invalidateSession() async {
    await widget.sessionStore.clear();
    if (!mounted) return;
    setState(() {
      session = null;
      notice = 'Your session expired. Sign in again.';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (restoring) {
      return const Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Restoring secure session…'),
              ],
            ),
          ),
        ),
      );
    }

    final activeSession = session;
    if (activeSession == null) {
      return OwnerLoginScreen(onLogin: _login, notice: notice);
    }
    return TrackingHome(
      api: widget.api,
      session: activeSession,
      onLogout: _logout,
      onAuthInvalidated: _invalidateSession,
    );
  }
}

class OwnerLoginScreen extends StatefulWidget {
  const OwnerLoginScreen({super.key, required this.onLogin, this.notice});

  final Future<void> Function(
    String organizationName,
    String username,
    String password,
  )
  onLogin;
  final String? notice;

  @override
  State<OwnerLoginScreen> createState() => _OwnerLoginScreenState();
}

class _OwnerLoginScreenState extends State<OwnerLoginScreen> {
  final formKey = GlobalKey<FormState>();
  final organizationNameController = TextEditingController();
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  bool submitting = false;
  bool obscurePassword = true;
  String? errorMessage;

  @override
  void dispose() {
    organizationNameController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (submitting || !formKey.currentState!.validate()) return;
    setState(() {
      submitting = true;
      errorMessage = null;
    });
    try {
      await widget.onLogin(
        organizationNameController.text.trim(),
        usernameController.text.trim(),
        passwordController.text,
      );
    } on LoginRejectedException {
      errorMessage =
          'The business/clinic name, username, or password is incorrect.';
    } on ApiConfigurationException catch (error) {
      errorMessage = error.message;
    } on ApiConnectionException {
      errorMessage =
          'Could not reach the sign-in service. Check your connection and '
          'the configured API URL.';
    } on ApiServerException catch (error) {
      errorMessage =
          'The sign-in service returned an error (${error.statusCode}). '
          'Try again later.';
    } on FormatException {
      errorMessage = 'The server returned an invalid login response.';
    } catch (_) {
      errorMessage = 'Could not sign in because of an unexpected error.';
    } finally {
      if (mounted) setState(() => submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Form(
                  key: formKey,
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 48),
                        Semantics(
                          label: 'RTS Tracking logo',
                          child: Image.asset(
                            'assets/rts-tracking-icon.png',
                            key: const Key('rts-login-logo'),
                            width: 96,
                            height: 96,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Owner sign in',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Sign in to view the operating view assigned to your account.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        if (widget.notice case final notice?) ...[
                          const SizedBox(height: 20),
                          _Notice(
                            icon: Icons.info_outline,
                            title: 'Sign-in required',
                            detail: notice,
                            color: scheme.primary,
                          ),
                        ],
                        const SizedBox(height: 28),
                        TextFormField(
                          key: const Key('owner-organization'),
                          controller: organizationNameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Business / Clinic ID or name',
                            prefixIcon: Icon(Icons.business_outlined),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Enter your business or clinic name'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('owner-username'),
                          controller: usernameController,
                          autofillHints: const [AutofillHints.username],
                          autocorrect: false,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Enter your username'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('owner-password'),
                          controller: passwordController,
                          autofillHints: const [AutofillHints.password],
                          obscureText: obscurePassword,
                          onFieldSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: obscurePassword
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () => setState(
                                () => obscurePassword = !obscurePassword,
                              ),
                              icon: Icon(
                                obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? 'Enter your password'
                              : null,
                        ),
                        if (errorMessage case final message?) ...[
                          const SizedBox(height: 12),
                          Text(
                            message,
                            key: const Key('login-error'),
                            style: TextStyle(
                              color: scheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: submitting ? null : _submit,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: submitting
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Sign in'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _LocationFilter { all, attention, offlineOrUnknown }

class TrackingHome extends StatefulWidget {
  const TrackingHome({
    super.key,
    required this.api,
    this.session,
    this.onLogout,
    this.onAuthInvalidated,
  });

  final OwnerApi api;
  final OwnerSession? session;
  final Future<void> Function()? onLogout;
  final Future<void> Function()? onAuthInvalidated;

  @override
  State<TrackingHome> createState() => _TrackingHomeState();
}

class _TrackingHomeState extends State<TrackingHome> {
  late TrackingMode mode;
  int selectedIndex = 0;
  DashboardSnapshot? dashboard;
  Object? error;
  bool loading = true;
  bool refreshing = false;
  _LocationFilter locationFilter = _LocationFilter.all;
  String locationQuery = '';
  String activityQuery = '';
  String activityFilter = 'All';
  final locationSearchController = TextEditingController();
  final activitySearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    mode = widget.session?.mode ?? TrackingMode.business;
    _refresh();
  }

  @override
  void dispose() {
    locationSearchController.dispose();
    activitySearchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (dashboard == null) {
      setState(() {
        loading = true;
        error = null;
      });
    } else {
      setState(() => refreshing = true);
    }

    try {
      final data = await widget.api.getDashboard(
        mode,
        authToken: widget.session?.token,
      );
      if (!mounted) return;
      setState(() {
        dashboard = data;
        error = null;
      });
    } catch (caughtError) {
      if (caughtError is AuthRequiredException && widget.session != null) {
        await widget.onAuthInvalidated?.call();
        return;
      }
      if (!mounted) return;
      setState(() => error = caughtError);
      if (dashboard != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Could not refresh. Showing the last available data.',
            ),
            action: SnackBarAction(label: 'Retry', onPressed: _refresh),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
          refreshing = false;
        });
      }
    }
  }

  Future<void> _selectMode(TrackingMode newMode) async {
    if (newMode == mode || widget.session != null) return;
    setState(() {
      mode = newMode;
      dashboard = null;
      error = null;
      locationFilter = _LocationFilter.all;
      locationQuery = '';
      activityQuery = '';
      activityFilter = 'All';
      locationSearchController.clear();
      activitySearchController.clear();
    });
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final header = _pageHeader();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Row(
          children: [
            Icon(Icons.track_changes),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'RTS Tracking',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        actions: [
          if (selectedIndex != 4)
            IconButton(
              tooltip: 'Refresh operating view',
              onPressed: refreshing ? null : _refresh,
              icon: refreshing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return ListView(
                key: const Key('tracking-scroll-view'),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 920),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _modeControl(),
                          const SizedBox(height: 18),
                          _PageHeading(
                            title: header.$1,
                            description: header.$2,
                            source: dashboard?.synchronizedLabel,
                          ),
                          const SizedBox(height: 20),
                          if (loading)
                            const _LoadingView()
                          else if (error != null && dashboard == null)
                            _ErrorView(error: error!, onRetry: _refresh)
                          else if (dashboard case final data?)
                            ..._dataView(data, constraints.maxWidth),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (value) => setState(() => selectedIndex = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            selectedIcon: Icon(Icons.today),
            label: 'Today',
          ),
          NavigationDestination(
            icon: Icon(Icons.location_on_outlined),
            selectedIcon: Icon(Icons.location_on),
            label: 'Locations',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'Activity',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_none),
            selectedIcon: Icon(Icons.notifications),
            label: 'Alerts',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz),
            selectedIcon: Icon(Icons.more),
            label: 'More',
          ),
        ],
      ),
    );
  }

  (String, String) _pageHeader() {
    return switch (selectedIndex) {
      0 => (
        'Today',
        mode == TrackingMode.clinic
            ? 'Prioritized operating decisions, source freshness, and aggregate-only clinic health.'
            : 'Prioritized operating decisions, location health, and business pulse.',
      ),
      1 => (
        mode == TrackingMode.clinic ? 'Clinic locations' : 'Business locations',
        'Search locations, check source freshness, and open the detail behind each status.',
      ),
      2 => (
        'Activity',
        mode == TrackingMode.clinic
            ? 'Privacy-safe platform and system changes only.'
            : 'Recent platform and system changes from connected sources.',
      ),
      3 => (
        'Alerts',
        'Critical items first, with their impact and the next owner action.',
      ),
      _ => (
        'More',
        'Account, security, data availability, privacy, and refresh behavior.',
      ),
    };
  }

  List<Widget> _dataView(DashboardSnapshot data, double availableWidth) {
    return [
      if (data.isDemo) ...[
        _Notice(
          icon: Icons.science_outlined,
          title: 'Demo data',
          detail:
              'Values are local examples for exploring the operating view. They are not production records.',
          color: Theme.of(context).colorScheme.tertiary,
        ),
        const SizedBox(height: 16),
      ],
      if (error != null) ...[
        _Notice(
          icon: Icons.cloud_off_outlined,
          title: 'Refresh failed',
          detail:
              'Showing the last available data. Pull down or use refresh to retry.',
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 16),
      ],
      switch (selectedIndex) {
        0 => _today(data),
        1 => _locations(data),
        2 => _activity(data),
        3 => _alerts(data),
        _ => _more(data),
      },
    ];
  }

  Widget _modeControl() {
    if (widget.session case final session?) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: _ModeBadge(
          mode: mode,
          label: '${mode.displayName} · ${session.greetingName}',
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth < 430 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.35;
        final options = [
          _ModeSwitchOption(
            mode: TrackingMode.business,
            selected: mode == TrackingMode.business,
            onSelected: () => _selectMode(TrackingMode.business),
          ),
          _ModeSwitchOption(
            mode: TrackingMode.clinic,
            selected: mode == TrackingMode.clinic,
            onSelected: () => _selectMode(TrackingMode.clinic),
          ),
        ];
        return compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  options.first,
                  const SizedBox(height: 8),
                  options.last,
                ],
              )
            : Row(
                children: [
                  Expanded(child: options.first),
                  const SizedBox(width: 8),
                  Expanded(child: options.last),
                ],
              );
      },
    );
  }

  Widget _today(DashboardSnapshot data) {
    final decisions =
        data.alerts.where((alert) => alert.level != AlertLevel.info).toList()
          ..sort(
            (left, right) =>
                left.level.severity.compareTo(right.level.severity),
          );
    final locations = data.locations;
    final unknownLocations = locations
        .where((location) => location.effectiveStatus == LocationStatus.unknown)
        .length;
    final source = data.operationalMetrics.sourceBackend;
    final messageBalance =
        data.financialMetrics.platformMessaging.messageBalance;
    final publishedModeMetrics = data.modeDetail.metrics.entries
        .where((entry) => entry.value.available)
        .toList(growable: false);
    final availableModeMetrics = publishedModeMetrics.isNotEmpty
        ? publishedModeMetrics
        : data.metrics
              .where(
                (metric) => _operatingMetricKeys(mode).contains(metric.key),
              )
              .map(
                (metric) => MapEntry(
                  metric.key,
                  AvailabilityValue(available: true, value: metric.value),
                ),
              )
              .toList(growable: false);
    final unavailableModeMetrics = data.modeDetail.metrics.entries
        .where((entry) => !entry.value.available && entry.value.reason != null)
        .toList(growable: false);
    final sourceFinancials = data
        .financialMetrics
        .sourceApplication
        .metrics
        .entries
        .where((entry) => entry.value.available)
        .toList(growable: false);
    final sourceHealth = data.operationalMetrics.health;
    final accountMetrics = data.metrics
        .where(
          (metric) =>
              !_operatingMetricKeys(mode).contains(metric.key) &&
              (metric.key != 'messageCredits' || messageBalance == null),
        )
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeading(
          title: 'Decisions to make',
          supporting: decisions.isEmpty
              ? 'No urgent action'
              : '${decisions.length} open',
        ),
        const SizedBox(height: 8),
        if (decisions.isEmpty)
          const _EmptyState(
            icon: Icons.task_alt,
            title: 'No critical or warning decisions',
            detail: 'New owner actions will appear here.',
          )
        else
          ...decisions.take(3).map(_alertRow),
        const SizedBox(height: 24),
        _SectionHeading(
          title: 'Location health',
          supporting: unknownLocations == 0
              ? '${data.onlineSites}/${locations.length} online'
              : '${data.onlineSites} online · $unknownLocations unknown',
        ),
        const SizedBox(height: 8),
        if (locations.isEmpty)
          _EmptyState(
            icon: Icons.location_off_outlined,
            title: 'No ${mode.locationNamePlural} published',
            detail:
                'Connected locations will appear when the owner feed publishes them.',
          )
        else
          ...locations
              .take(3)
              .map(
                (location) => _LocationRow(
                  location: location,
                  onTap: () => _openLocation(location, data),
                ),
              ),
        if (locations.length > 3)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => setState(() => selectedIndex = 1),
              child: const Text('View all locations'),
            ),
          ),
        const SizedBox(height: 16),
        _SectionHeading(
          title: mode == TrackingMode.business
              ? 'Business performance'
              : 'Clinic operations',
          supporting: availableModeMetrics.isEmpty
              ? 'Awaiting aggregate telemetry'
              : '${availableModeMetrics.length} live aggregate metrics',
        ),
        const SizedBox(height: 8),
        if (availableModeMetrics.isEmpty)
          _EmptyState(
            icon: Icons.query_stats_outlined,
            title: 'No live operating totals yet',
            detail:
                'Open the latest ${mode.displayName} desktop app to publish its first privacy-safe aggregate snapshot.',
          )
        else
          _DataPanel(
            children: availableModeMetrics
                .map(
                  (entry) => _KeyValueRow(
                    label: _modeMetricLabel(entry.key),
                    value: _formatAggregateValue(
                      entry.key,
                      entry.value.value,
                      data.financialMetrics.currency,
                    ),
                    detail: 'Aggregate only · ${data.synchronizedLabel}',
                  ),
                )
                .toList(growable: false),
          ),
        if (sourceFinancials.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionHeading(
            title: 'Financial position',
            supporting:
                'Source: ${data.financialMetrics.sourceApplication.source ?? mode.displayName}',
          ),
          const SizedBox(height: 8),
          _DataPanel(
            children: sourceFinancials
                .map(
                  (entry) => _KeyValueRow(
                    label: _sourceFinancialLabel(entry.key, mode),
                    value: _formatAggregateValue(
                      entry.key,
                      entry.value.value,
                      data.financialMetrics.currency,
                    ),
                    detail:
                        'Generated ${formatTimestamp(data.financialMetrics.sourceApplication.generatedAt)}',
                  ),
                )
                .toList(growable: false),
          ),
        ],
        const SizedBox(height: 20),
        const _SectionHeading(title: 'System and account health'),
        const SizedBox(height: 8),
        _DataPanel(
          children: [
            ...accountMetrics.map(
              (metric) =>
                  _KeyValueRow(label: metric.label, value: metric.value),
            ),
            if (data.overview.staff.activeAccounts != null)
              _KeyValueRow(
                label: 'Active staff accounts',
                value: '${data.overview.staff.activeAccounts}',
                detail: data.overview.staff.totalAccounts == null
                    ? null
                    : '${data.overview.staff.totalAccounts} total · ${data.overview.staff.adminAccounts ?? 0} administrators',
              ),
            if (sourceHealth.available)
              ...sourceHealth.metrics.entries.map(
                (entry) => _KeyValueRow(
                  label: _healthMetricLabel(entry.key),
                  value: _formatHealthValue(entry.value),
                  detail: sourceHealth.appVersion == null
                      ? null
                      : '${mode.displayName} ${sourceHealth.appVersion}',
                ),
              ),
            if (messageBalance != null)
              _KeyValueRow(
                label: 'Messaging credits',
                value: '$messageBalance',
                detail:
                    '₪${data.financialMetrics.platformMessaging.prepaidBalanceNis?.toStringAsFixed(2) ?? '0.00'} prepaid · source ${data.financialMetrics.platformMessaging.source ?? 'not published'}',
              ),
            if (source != null)
              _KeyValueRow(
                label: 'Configured backend',
                value: source,
                detail: data.operationalMetrics.connectivity.available
                    ? 'A live heartbeat is connected.'
                    : 'This identifies storage only, not a live operational feed.',
              ),
          ],
        ),
        if (!data.financialMetrics.businessRevenue.available &&
            data.financialMetrics.businessRevenue.reason != null) ...[
          const SizedBox(height: 8),
          _CapabilityState(
            title: mode == TrackingMode.clinic
                ? 'Clinic financial totals are not available'
                : 'Business revenue is not available',
            reason: data.financialMetrics.businessRevenue.reason!,
          ),
        ],
        if (data.dataAvailability.gaps.isNotEmpty ||
            unavailableModeMetrics.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionHeading(
            title: 'Not available yet',
            supporting:
                '${data.dataAvailability.gaps.length + unavailableModeMetrics.length} capability gap${data.dataAvailability.gaps.length + unavailableModeMetrics.length == 1 ? '' : 's'}',
          ),
          const SizedBox(height: 8),
          ...unavailableModeMetrics
              .take(2)
              .map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _CapabilityState(
                    title: '${_modeMetricLabel(entry.key)} is not available',
                    reason: entry.value.reason!,
                  ),
                ),
              ),
          ...data.dataAvailability.gaps
              .take(2)
              .map(
                (gap) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _CapabilityState(
                    title: _gapTitle(gap),
                    reason: gap.reason,
                    action: gap.requiredTelemetry,
                  ),
                ),
              ),
        ],
        const SizedBox(height: 24),
        _SectionHeading(title: 'Recent changes', supporting: 'Privacy-safe'),
        const SizedBox(height: 8),
        if (data.recentActivity.isEmpty)
          const _EmptyState(
            icon: Icons.history_outlined,
            title: 'No recent changes',
            detail: 'Connected platform and system changes will appear here.',
          )
        else
          ...data.recentActivity
              .take(3)
              .map((event) => _ActivityRow(event: event, mode: mode)),
      ],
    );
  }

  Widget _locations(DashboardSnapshot data) {
    final locations = data.locations.where((location) {
      final matchesQuery =
          locationQuery.isEmpty ||
          location.name.toLowerCase().contains(locationQuery.toLowerCase());
      final matchesFilter = switch (locationFilter) {
        _LocationFilter.all => true,
        _LocationFilter.attention => location.needsAttention,
        _LocationFilter.offlineOrUnknown =>
          location.effectiveStatus != LocationStatus.online,
      };
      return matchesQuery && matchesFilter;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('location-search'),
          controller: locationSearchController,
          onChanged: (value) => setState(() => locationQuery = value.trim()),
          decoration: const InputDecoration(
            labelText: 'Search locations',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _FilterChip(
              label: 'All',
              selected: locationFilter == _LocationFilter.all,
              onSelected: () =>
                  setState(() => locationFilter = _LocationFilter.all),
            ),
            _FilterChip(
              label: 'Needs attention',
              selected: locationFilter == _LocationFilter.attention,
              onSelected: () =>
                  setState(() => locationFilter = _LocationFilter.attention),
            ),
            _FilterChip(
              label: 'Offline / Unknown',
              selected: locationFilter == _LocationFilter.offlineOrUnknown,
              onSelected: () => setState(
                () => locationFilter = _LocationFilter.offlineOrUnknown,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _DataPanel(
          children: [
            _KeyValueRow(
              label: 'Snapshot freshness',
              value: data.synchronizedLabel,
            ),
            _KeyValueRow(
              label: 'Live heartbeat source',
              value:
                  data.operationalMetrics.connectivity.source ??
                  'Not published',
              detail: data.operationalMetrics.connectivity.detail,
            ),
          ],
        ),
        const SizedBox(height: 20),
        _SectionHeading(
          title: 'Locations',
          supporting: '${locations.length} shown',
        ),
        const SizedBox(height: 8),
        if (locations.isEmpty)
          _EmptyState(
            icon: Icons.search_off_outlined,
            title: 'No matching locations',
            detail: 'Try another search or clear the current filter.',
          )
        else
          ...locations.map(
            (location) => _LocationRow(
              location: location,
              onTap: () => _openLocation(location, data),
            ),
          ),
      ],
    );
  }

  Widget _activity(DashboardSnapshot data) {
    final categories = {
      'All',
      ...data.recentActivity.map((event) => _categoryLabel(event.category)),
    }.toList();
    final events = data.recentActivity.where((event) {
      final text = '${event.title} ${event.detail ?? ''} ${event.source ?? ''}'
          .toLowerCase();
      final matchesQuery =
          activityQuery.isEmpty || text.contains(activityQuery.toLowerCase());
      final matchesFilter =
          activityFilter == 'All' ||
          _categoryLabel(event.category) == activityFilter;
      return matchesQuery && matchesFilter;
    }).toList();
    final eventCounts = data.auditLog.eventCounts.entries
        .where((entry) => entry.value > 0)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (mode == TrackingMode.clinic) ...[
          _Notice(
            icon: Icons.privacy_tip_outlined,
            title: 'Aggregate-only activity',
            detail:
                'Clinic activity intentionally excludes patient names, medical notes, files, diagnoses, and session details.',
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
        ],
        if (data.auditLog.completeness != null ||
            data.auditLog.detail != null) ...[
          _Notice(
            icon: Icons.info_outline,
            title: 'Activity availability',
            detail:
                '${data.auditLog.completeness ?? 'Partial'} activity: ${data.auditLog.detail ?? 'Only connected source events are shown.'}',
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(height: 16),
        ],
        if (eventCounts.isNotEmpty) ...[
          _SectionHeading(
            title: 'Aggregate activity totals',
            supporting: '${eventCounts.length} active counters',
          ),
          const SizedBox(height: 8),
          _DataPanel(
            children: eventCounts
                .map(
                  (entry) => _KeyValueRow(
                    label: _eventCounterLabel(entry.key),
                    value: '${entry.value}',
                    detail:
                        'Aggregate count; no record-level details are uploaded.',
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 20),
        ],
        TextField(
          key: const Key('activity-search'),
          controller: activitySearchController,
          onChanged: (value) => setState(() => activityQuery = value.trim()),
          decoration: const InputDecoration(
            labelText: 'Search activity',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: categories
              .map(
                (category) => _FilterChip(
                  label: category,
                  selected: activityFilter == category,
                  onSelected: () => setState(() => activityFilter = category),
                ),
              )
              .toList(growable: false),
        ),
        const SizedBox(height: 20),
        _SectionHeading(
          title: 'Timeline',
          supporting: '${events.length} event${events.length == 1 ? '' : 's'}',
        ),
        const SizedBox(height: 8),
        if (events.isEmpty)
          const _EmptyState(
            icon: Icons.history_toggle_off_outlined,
            title: 'No matching activity',
            detail: 'Change the search or filter to see available events.',
          )
        else
          ...events.map((event) => _ActivityRow(event: event, mode: mode)),
      ],
    );
  }

  Widget _alerts(DashboardSnapshot data) {
    final alerts = [...data.alerts]
      ..sort(
        (left, right) => left.level.severity.compareTo(right.level.severity),
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (alerts.isEmpty)
          const _EmptyState(
            icon: Icons.notifications_off_outlined,
            title: 'No active alerts',
            detail:
                'Operational alerts will appear here when action is required.',
          )
        else ...[
          _Notice(
            icon: Icons.rule_outlined,
            title: 'Action order',
            detail:
                'Critical alerts appear before warnings and information. Each item includes its impact and next action.',
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          ...alerts.map(_alertRow),
        ],
      ],
    );
  }

  Widget _more(DashboardSnapshot data) {
    final session = widget.session;
    final privacy = data.dataAvailability.privacy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeading(title: 'Account'),
        const SizedBox(height: 8),
        _DataPanel(
          children: [
            _KeyValueRow(
              label: 'Access',
              value: session == null
                  ? 'Demo mode'
                  : 'Server-assigned ${session.mode.displayName}',
              detail: session == null
                  ? 'Switching products is available only in clearly marked demo mode.'
                  : 'Authenticated sessions cannot switch product mode in the app.',
            ),
            if (session != null)
              _KeyValueRow(
                label: 'Signed in as',
                value: session.greetingName,
                detail: session.organizationName,
              ),
          ],
        ),
        const SizedBox(height: 20),
        const _SectionHeading(title: 'Security'),
        const SizedBox(height: 8),
        _DataPanel(
          children: const [
            _KeyValueRow(
              label: 'Owner session',
              value: 'Protected platform storage',
              detail:
                  'Credentials are not retained after sign-in. The access token is used only for the configured API.',
            ),
          ],
        ),
        if (session != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('sign-out-button'),
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
        const SizedBox(height: 20),
        const _SectionHeading(title: 'Data sources and availability'),
        const SizedBox(height: 8),
        _DataPanel(
          children: [
            _KeyValueRow(
              label: 'Connected source',
              value: data.operationalMetrics.sourceBackend ?? 'Not published',
            ),
            _KeyValueRow(
              label: 'Available capabilities',
              value: data.dataAvailability.available.isEmpty
                  ? 'Not published'
                  : data.dataAvailability.available.join(', '),
            ),
            _KeyValueRow(
              label: 'Unavailable capabilities',
              value: data.dataAvailability.unavailable.isEmpty
                  ? 'None reported'
                  : data.dataAvailability.unavailable.join(', '),
            ),
          ],
        ),
        if (data.dataAvailability.gaps.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...data.dataAvailability.gaps.map(
            (gap) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CapabilityState(
                title: _gapTitle(gap),
                reason: gap.reason,
                action: gap.requiredTelemetry,
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        const _SectionHeading(title: 'Privacy'),
        const SizedBox(height: 8),
        _DataPanel(
          children: [
            _KeyValueRow(
              label: 'Data scope',
              value: privacy.scope ?? 'Not published',
              detail: mode == TrackingMode.clinic
                  ? 'This view never shows patient names, medical notes, files, diagnoses, or session details.'
                  : 'Only owner-safe operational data is shown.',
            ),
            _KeyValueRow(
              label: 'Medical detail',
              value: privacy.patientMedicalDetailsIncluded
                  ? 'Reported by source'
                  : 'Not included',
            ),
          ],
        ),
        const SizedBox(height: 20),
        const _SectionHeading(title: 'Refresh behavior'),
        const SizedBox(height: 8),
        _DataPanel(
          children: const [
            _KeyValueRow(
              label: 'Refresh',
              value: 'Manual and pull to refresh',
              detail:
                  'Requests time out after 12 seconds. The last in-memory snapshot remains visible when refresh fails.',
            ),
          ],
        ),
      ],
    );
  }

  Widget _alertRow(TrackingAlert alert) {
    return _AlertRow(
      alert: alert,
      action: switch (alert.level) {
        AlertLevel.critical =>
          'Restore the affected service or contact this location now.',
        AlertLevel.warning =>
          'Review this item today and confirm the local action.',
        AlertLevel.info =>
          'Monitor this item; no immediate action is required.',
      },
    );
  }

  void _openLocation(SiteSnapshot location, DashboardSnapshot data) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _LocationDetailsSheet(
        location: location,
        dashboard: data,
        mode: mode,
      ),
    );
  }
}

class _ModeBadge extends StatelessWidget {
  const _ModeBadge({required this.mode, required this.label});

  final TrackingMode mode;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: label,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.secondaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                mode == TrackingMode.clinic
                    ? Icons.local_hospital_outlined
                    : Icons.storefront_outlined,
                size: 18,
              ),
              const SizedBox(width: 8),
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeSwitchOption extends StatelessWidget {
  const _ModeSwitchOption({
    required this.mode,
    required this.selected,
    required this.onSelected,
  });

  final TrackingMode mode;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return selected
        ? FilledButton.icon(
            onPressed: onSelected,
            icon: Icon(
              mode == TrackingMode.clinic
                  ? Icons.local_hospital_outlined
                  : Icons.storefront_outlined,
            ),
            label: Text(mode.displayName),
          )
        : OutlinedButton.icon(
            onPressed: onSelected,
            icon: Icon(
              mode == TrackingMode.clinic
                  ? Icons.local_hospital_outlined
                  : Icons.storefront_outlined,
            ),
            label: Text(mode.displayName),
          );
  }
}

class _PageHeading extends StatelessWidget {
  const _PageHeading({
    required this.title,
    required this.description,
    this.source,
  });

  final String title;
  final String description;
  final String? source;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          description,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
        if (source != null) ...[
          const SizedBox(height: 8),
          Text(
            source!,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.supporting});

  final String title;
  final String? supporting;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        if (supporting != null)
          Text(
            supporting!,
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({required this.location, required this.onTap});

  final SiteSnapshot location;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = _statusColor(context, location.effectiveStatus);
    return Semantics(
      button: true,
      label:
          '${location.name}, ${location.effectiveStatus.displayName}, ${location.primaryLabel}: ${location.primaryValue}',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.13),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _statusIcon(location.effectiveStatus),
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          location.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${location.effectiveStatus.displayName} · ${location.updatedLabel}',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${location.primaryLabel}: ${location.primaryValue}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (location.attention case final attention?) ...[
                          const SizedBox(height: 4),
                          Text(
                            attention,
                            style: TextStyle(
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert, required this.action});

  final TrackingAlert alert;
  final String action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _alertColor(context, alert.level);
    return Semantics(
      label:
          '${alert.level.displayName} alert: ${alert.title}. Impact: ${alert.detail}. Action: $action',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_alertIcon(alert.level), color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _StatusPill(label: alert.level.displayName, color: color),
                      const SizedBox(height: 8),
                      Text(
                        alert.title,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text('Impact: ${alert.detail}'),
                      const SizedBox(height: 4),
                      Text(
                        'Action: $action',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.event, required this.mode});

  final ActivityEvent event;
  final TrackingMode mode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '${event.title}. ${event.detail ?? ''}',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _activityIcon(event.category),
                  color: _alertColor(context, event.level),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (event.detail case final detail?) ...[
                        const SizedBox(height: 3),
                        Text(
                          detail,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        [
                          _categoryLabel(event.category),
                          if (event.occurredAt != null)
                            formatTimestamp(event.occurredAt),
                          if (event.source != null) event.source!,
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DataPanel extends StatelessWidget {
  const _DataPanel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(
          children: children
              .expand(
                (child) => [
                  child,
                  if (child != children.last)
                    Divider(height: 1, color: scheme.outlineVariant),
                ],
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _KeyValueRow extends StatelessWidget {
  const _KeyValueRow({required this.label, required this.value, this.detail});

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          SelectableText(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (detail != null) ...[
            const SizedBox(height: 2),
            Text(
              detail!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _CapabilityState extends StatelessWidget {
  const _CapabilityState({
    required this.title,
    required this.reason,
    this.action,
  });

  final String title;
  final String reason;
  final String? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      child: Material(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: scheme.onSecondaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(reason),
                    if (action != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'To enable: $action',
                        style: TextStyle(
                          color: scheme.onSecondaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.detail,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      child: Material(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(detail),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationDetailsSheet extends StatelessWidget {
  const _LocationDetailsSheet({
    required this.location,
    required this.dashboard,
    required this.mode,
  });

  final SiteSnapshot location;
  final DashboardSnapshot dashboard;
  final TrackingMode mode;

  @override
  Widget build(BuildContext context) {
    final telemetry = location.telemetry;
    final licence = location.licence;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, controller) => SafeArea(
        top: false,
        child: ListView(
          key: const Key('location-details-scroll'),
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            Text(
              'Location details',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              location.name,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            const _SheetSectionHeading('Status and freshness'),
            _SheetDetailLine(
              label: 'Current status',
              value: location.effectiveStatus.displayName,
            ),
            _SheetDetailLine(
              label: 'Source freshness',
              value: location.updatedLabel,
            ),
            _SheetDetailLine(
              label: 'Last heartbeat',
              value: formatTimestamp(telemetry.lastHeartbeatAt),
            ),
            _SheetDetailLine(
              label: 'Heartbeat source',
              value: telemetry.source ?? 'Not published',
              detail: telemetry.detail,
            ),
            const SizedBox(height: 20),
            const _SheetSectionHeading('Licence and access'),
            _SheetDetailLine(
              label: 'Licence',
              value: licence.active == null
                  ? 'Not published'
                  : (licence.active! ? 'Active' : 'Inactive'),
            ),
            _SheetDetailLine(
              label: 'Licence ends',
              value: formatTimestamp(licence.endsAt),
            ),
            _SheetDetailLine(
              label: 'Last licence check',
              value: formatTimestamp(licence.lastCheckedAt),
              detail: 'A licence check is not a live heartbeat.',
            ),
            const SizedBox(height: 20),
            if (dashboard.modeDetail.metrics.values.any(
              (metric) => metric.available,
            )) ...[
              _SheetSectionHeading(
                mode == TrackingMode.business
                    ? 'Business performance'
                    : 'Clinic operations',
              ),
              ...dashboard.modeDetail.metrics.entries
                  .where((entry) => entry.value.available)
                  .map(
                    (entry) => _SheetDetailLine(
                      label: _modeMetricLabel(entry.key),
                      value: _formatAggregateValue(
                        entry.key,
                        entry.value.value,
                        dashboard.financialMetrics.currency,
                      ),
                      detail:
                          'Organization aggregate from the latest source snapshot.',
                    ),
                  ),
              const SizedBox(height: 20),
            ],
            if (dashboard.operationalMetrics.health.available) ...[
              const _SheetSectionHeading('Source application health'),
              ...dashboard.operationalMetrics.health.metrics.entries.map(
                (entry) => _SheetDetailLine(
                  label: _healthMetricLabel(entry.key),
                  value: _formatHealthValue(entry.value),
                ),
              ),
              const SizedBox(height: 20),
            ],
            const _SheetSectionHeading('Portfolio context'),
            const _SheetDetailLine(
              label: 'Staff and finance',
              value: 'Shown on Today',
              detail:
                  'Current staff-account and messaging figures are organization-wide, so they are not presented as location-specific values.',
            ),
            const SizedBox(height: 20),
            const _SheetSectionHeading('Privacy'),
            _SheetDetailLine(
              label: 'Data scope',
              value:
                  dashboard.dataAvailability.privacy.scope ?? 'Not published',
              detail: mode == TrackingMode.clinic
                  ? 'Patient names, medical notes, files, diagnoses, and session details are never shown here.'
                  : 'Only owner-safe operational data is shown.',
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetSectionHeading extends StatelessWidget {
  const _SheetSectionHeading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _SheetDetailLine extends StatelessWidget {
  const _SheetDetailLine({
    required this.label,
    required this.value,
    this.detail,
  });

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (detail != null) ...[
            const SizedBox(height: 2),
            Text(
              detail!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(
        children: [
          Icon(icon, size: 36, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final authError = error is AuthRequiredException;
    final configurationError = error is ApiConfigurationException;
    final connectionError = error is ApiConnectionException;
    final serverError = error is ApiServerException;
    return Column(
      children: [
        _EmptyState(
          icon: authError || configurationError
              ? Icons.lock_outline
              : Icons.cloud_off_outlined,
          title: authError
              ? 'Sign-in is required'
              : configurationError
              ? 'API configuration required'
              : 'Operating view unavailable',
          detail: authError
              ? 'The live endpoint requires a valid owner session.'
              : configurationError
              ? (error as ApiConfigurationException).message
              : connectionError
              ? 'The live API could not be reached. Check the connection and try again.'
              : serverError
              ? 'The live API returned an error. Try again later.'
              : 'The live API returned an unexpected response. Try again.',
        ),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try again'),
        ),
      ],
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    return Semantics(
      label: 'Loading operating view',
      child: Column(
        children: [
          ...List.generate(
            4,
            (_) => Container(
              height: 82,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _statusColor(BuildContext context, LocationStatus status) {
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    LocationStatus.online =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF8CE8AB)
          : const Color(0xFF0A6B34),
    LocationStatus.offline => scheme.error,
    LocationStatus.unknown =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFFFD27D)
          : const Color(0xFF815600),
  };
}

Color _alertColor(BuildContext context, AlertLevel level) {
  final scheme = Theme.of(context).colorScheme;
  return switch (level) {
    AlertLevel.info => scheme.primary,
    AlertLevel.warning =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFFFFD27D)
          : const Color(0xFF815600),
    AlertLevel.critical => scheme.error,
  };
}

IconData _statusIcon(LocationStatus status) {
  return switch (status) {
    LocationStatus.online => Icons.check_circle_outline,
    LocationStatus.offline => Icons.cloud_off_outlined,
    LocationStatus.unknown => Icons.help_outline,
  };
}

IconData _alertIcon(AlertLevel level) {
  return switch (level) {
    AlertLevel.info => Icons.info_outline,
    AlertLevel.warning => Icons.warning_amber_outlined,
    AlertLevel.critical => Icons.error_outline,
  };
}

IconData _activityIcon(String category) {
  return switch (category) {
    'platform-messaging' => Icons.forum_outlined,
    'administration' => Icons.admin_panel_settings_outlined,
    _ => Icons.settings_suggest_outlined,
  };
}

String _categoryLabel(String category) {
  return switch (category) {
    'platform-messaging' => 'Messaging',
    'administration' => 'Administration',
    'system' => 'System',
    _ => 'Other',
  };
}

String _modeMetricLabel(String key) {
  return switch (key) {
    'salesToday' => 'Sales today',
    'ordersToday' => 'Orders today',
    'averageOrderValue' => 'Average order value',
    'lowStockItems' => 'Low-stock items',
    'inventoryUnits' => 'Inventory units',
    'inventoryValue' => 'Inventory value',
    'returnsToday' => 'Returns today',
    'refundsToday' => 'Refunds today',
    'damageUnitsToday' => 'Damaged units today',
    'appointmentsToday' => 'Appointments today',
    'waitingCount' => 'Aggregate waiting count',
    'completedSessionsToday' => 'Completed-session count',
    'followUpsDue' => 'Follow-ups due',
    'collectionsToday' => 'Collections today',
    'outstandingInsurance' => 'Outstanding insurance',
    'openSessions' => 'Open sessions',
    'activeAccounts' => 'Active clinic accounts',
    _ => 'This operational metric',
  };
}

String _sourceFinancialLabel(String key, TrackingMode mode) {
  return switch (key) {
    'revenueToday' =>
      mode == TrackingMode.clinic ? 'Collections today' : 'Sales today',
    'averageOrderValue' => 'Average order value',
    'inventoryValue' => 'Inventory value',
    'refundsToday' => 'Refunds today',
    'outstandingBalance' => 'Outstanding insurance',
    _ => _modeMetricLabel(key),
  };
}

String _formatAggregateValue(String key, Object? value, String? currency) {
  if (value == null) return 'Unavailable';
  const moneyKeys = {
    'salesToday',
    'averageOrderValue',
    'inventoryValue',
    'refundsToday',
    'collectionsToday',
    'outstandingInsurance',
    'revenueToday',
    'outstandingBalance',
  };
  if (moneyKeys.contains(key) && value is num) {
    final symbol = currency == 'ILS' || currency == null ? '₪' : currency;
    return '$symbol${value.toStringAsFixed(2)}';
  }
  if (value is num) return value.toString();
  if (value is bool) return value ? 'Healthy' : 'Needs attention';
  if (value is String && value.trim().isNotEmpty) return value;
  return 'Unavailable';
}

Set<String> _operatingMetricKeys(TrackingMode mode) {
  return switch (mode) {
    TrackingMode.business => const {
      'salesToday',
      'ordersToday',
      'averageOrderValue',
      'lowStockItems',
      'inventoryUnits',
      'inventoryValue',
      'returnsToday',
      'refundsToday',
      'damageUnitsToday',
    },
    TrackingMode.clinic => const {
      'appointmentsToday',
      'waitingCount',
      'completedSessionsToday',
      'followUpsDue',
      'collectionsToday',
      'outstandingInsurance',
      'openSessions',
      'activeAccounts',
    },
  };
}

String _healthMetricLabel(String key) {
  return switch (key) {
    'terminalCount' => 'Registered terminals',
    'activeTerminalCount' => 'Active terminals',
    'pendingSyncCount' => 'Pending synchronizations',
    'failedSyncCount' => 'Failed synchronizations',
    'databaseHealthy' => 'Database health',
    'syncHealthy' => 'Synchronization health',
    'backupHealthy' => 'Backup health',
    _ => 'Source health',
  };
}

String _formatHealthValue(Object value) {
  if (value is bool) return value ? 'Healthy' : 'Needs attention';
  return '$value';
}

String _eventCounterLabel(String key) {
  return switch (key) {
    'auditEvents' => 'Audited events',
    'warningEvents' => 'Warnings',
    'errorEvents' => 'Errors',
    'loginsSucceeded' => 'Successful sign-ins',
    'loginsFailed' => 'Failed sign-ins',
    'syncsSucceeded' => 'Successful synchronizations',
    'syncsFailed' => 'Failed synchronizations',
    'backupsSucceeded' => 'Successful backups',
    'backupsFailed' => 'Failed backups',
    'salesCompleted' => 'Completed sales',
    'salesVoided' => 'Voided sales',
    'returnsCompleted' => 'Completed returns',
    'inventoryAdjustments' => 'Inventory adjustments',
    'appointmentsCreated' => 'Appointments created',
    'appointmentsCancelled' => 'Appointments cancelled',
    'sessionsCompleted' => 'Sessions completed',
    'paymentsRecorded' => 'Payments recorded',
    'followUpsCreated' => 'Follow-ups created',
    _ => 'Operational events',
  };
}

String _gapTitle(DataGap gap) {
  return switch (gap.key) {
    'business-operations' => 'Business operating data is not connected',
    'business-connectivity' => 'Business heartbeat is not connected',
    'clinic-operations' => 'Clinic operating data remains local',
    'clinic-connectivity' => 'Clinic heartbeat is not connected',
    _ => 'This capability is not available',
  };
}
