import 'package:flutter/material.dart';

import 'tracking_data.dart';

void main() {
  const configuredBaseUrl = String.fromEnvironment('RTS_API_BASE_URL');
  final baseUrl = configuredBaseUrl.isEmpty
      ? null
      : Uri.tryParse(configuredBaseUrl);
  runApp(RtsTrackingApp(api: OwnerApi(baseUrl: baseUrl)));
}

class RtsTrackingApp extends StatelessWidget {
  const RtsTrackingApp({super.key, this.api, this.sessionStore});

  final OwnerApi? api;
  final OwnerSessionStore? sessionStore;

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
      home: effectiveApi.isDemo
          ? TrackingHome(api: effectiveApi)
          : AuthenticatedOwnerFlow(
              api: effectiveApi,
              sessionStore: sessionStore ?? SecureOwnerSessionStore(),
            ),
    );
  }

  ThemeData _theme(Brightness brightness, Color seed) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,
      useMaterial3: true,
      fontFamily: 'Arial',
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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

  Future<void> _login(String username, String password) async {
    final authenticated = await widget.api.login(username, password);
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

  final Future<void> Function(String username, String password) onLogin;
  final String? notice;

  @override
  State<OwnerLoginScreen> createState() => _OwnerLoginScreenState();
}

class _OwnerLoginScreenState extends State<OwnerLoginScreen> {
  final formKey = GlobalKey<FormState>();
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  bool submitting = false;
  bool obscurePassword = true;
  String? errorMessage;

  @override
  void dispose() {
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
        usernameController.text.trim(),
        passwordController.text,
      );
    } on LoginRejectedException {
      errorMessage = 'The username or password is incorrect.';
    } on FormatException {
      errorMessage = 'The server returned an invalid login response.';
    } catch (_) {
      errorMessage = 'Could not sign in. Check the connection and try again.';
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
                        Icon(
                          Icons.track_changes,
                          size: 48,
                          color: scheme.primary,
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
                          'Sign in to view the dashboard assigned to your account.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                        if (widget.notice case final notice?) ...[
                          const SizedBox(height: 20),
                          _StatusBanner(
                            icon: Icons.info_outline,
                            title: 'Sign-in required',
                            detail: notice,
                            color: scheme.primary,
                          ),
                        ],
                        const SizedBox(height: 28),
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

  @override
  void initState() {
    super.initState();
    mode = widget.session?.mode ?? TrackingMode.business;
    _refresh();
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
    if (newMode == mode) return;
    setState(() {
      mode = newMode;
      dashboard = null;
      error = null;
    });
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
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
          if (selectedIndex != 3)
            IconButton(
              tooltip: 'Refresh dashboard',
              onPressed: refreshing ? null : _refresh,
              icon: refreshing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
            ),
          IconButton(
            tooltip: 'Account and connection settings',
            onPressed: () => setState(() => selectedIndex = 3),
            icon: const Icon(Icons.account_circle_outlined),
          ),
          if (widget.session != null)
            IconButton(
              tooltip: 'Sign out',
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1080),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _modeControl(),
                          const SizedBox(height: 20),
                          _pageHeader(),
                          const SizedBox(height: 18),
                          if (selectedIndex == 3)
                            _settingsView()
                          else if (loading)
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
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.location_on_outlined),
            selectedIcon: Icon(Icons.location_on),
            label: 'Locations',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_none),
            selectedIcon: Icon(Icons.notifications),
            label: 'Alerts',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _modeControl() {
    if (widget.session case final session?) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: Chip(
          avatar: Icon(
            mode == TrackingMode.clinic
                ? Icons.local_hospital_outlined
                : Icons.storefront_outlined,
          ),
          label: Text('${mode.displayName} · ${session.greetingName}'),
        ),
      );
    }
    return SegmentedButton<TrackingMode>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(
          value: TrackingMode.business,
          icon: Icon(Icons.storefront_outlined),
          label: Text('RTS Business'),
        ),
        ButtonSegment(
          value: TrackingMode.clinic,
          icon: Icon(Icons.local_hospital_outlined),
          label: Text('RTS Clinic'),
        ),
      ],
      selected: {mode},
      onSelectionChanged: (value) => _selectMode(value.first),
    );
  }

  Widget _pageHeader() {
    final (title, description) = switch (selectedIndex) {
      0 =>
        mode == TrackingMode.clinic
            ? (
                'Clinic overview',
                'Appointments, waiting patients, location health, and follow-ups.',
              )
            : (
                'Business overview',
                'Sales, orders, store health, stock, and operational alerts.',
              ),
      1 => (
        mode == TrackingMode.clinic ? 'Clinic locations' : 'Business stores',
        'Live operational status for every ${mode.locationName}.',
      ),
      2 => (
        '${mode.displayName} alerts',
        'Items that need owner attention, ordered by severity.',
      ),
      _ => (
        'Settings',
        'Review the data source, authentication, and connectivity status.',
      ),
    };
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
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  List<Widget> _dataView(DashboardSnapshot data, double availableWidth) {
    return [
      if (data.isDemo) ...[
        _StatusBanner(
          icon: Icons.science_outlined,
          title: 'Demo data',
          detail:
              'No live API is configured. Values are local examples and are '
              'not production records.',
          color: Theme.of(context).colorScheme.tertiary,
        ),
        const SizedBox(height: 16),
      ],
      if (error != null) ...[
        _StatusBanner(
          icon: Icons.cloud_off_outlined,
          title: 'Refresh failed',
          detail: 'Showing the last available data. Pull down to retry.',
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 16),
      ],
      switch (selectedIndex) {
        0 => _overview(data, availableWidth),
        1 => _locations(data, availableWidth),
        2 => _alerts(data),
        _ => const SizedBox.shrink(),
      },
    ];
  }

  Widget _overview(DashboardSnapshot data, double availableWidth) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _summaryGrid(data.metrics, availableWidth),
        const SizedBox(height: 24),
        _sectionTitle(
          '${mode.locationNamePlural[0].toUpperCase()}'
              '${mode.locationNamePlural.substring(1)} status',
          '${data.onlineSites}/${data.sites.length} online',
        ),
        const SizedBox(height: 8),
        ...data.sites.take(3).map(_siteCard),
        const SizedBox(height: 20),
        _sectionTitle('Attention needed', '${data.alerts.length} open'),
        const SizedBox(height: 8),
        if (data.alerts.isEmpty)
          const _EmptyState(
            icon: Icons.task_alt,
            title: 'Nothing needs attention',
            detail: 'New operational alerts will appear here.',
          )
        else
          ...data.alerts.take(3).map(_alertCard),
        const SizedBox(height: 12),
        Text(
          data.synchronizedLabel,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _locations(DashboardSnapshot data, double availableWidth) {
    if (data.sites.isEmpty) {
      return _EmptyState(
        icon: mode == TrackingMode.clinic
            ? Icons.local_hospital_outlined
            : Icons.storefront_outlined,
        title: 'No ${mode.locationNamePlural} found',
        detail:
            'Locations returned by the owner dashboard API will appear here.',
      );
    }

    final columns = availableWidth >= 760 ? 2 : 1;
    if (columns == 1) {
      return Column(children: data.sites.map(_siteCard).toList());
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: data.sites
              .map(
                (site) => SizedBox(
                  width: itemWidth,
                  child: _siteCard(site, margin: EdgeInsets.zero),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _alerts(DashboardSnapshot data) {
    if (data.alerts.isEmpty) {
      return const _EmptyState(
        icon: Icons.notifications_off_outlined,
        title: 'No active alerts',
        detail: 'Operational alerts will appear here when action is required.',
      );
    }
    return Column(children: data.alerts.map(_alertCard).toList());
  }

  Widget _settingsView() {
    final scheme = Theme.of(context).colorScheme;
    if (widget.session case final session?) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusBanner(
            icon: Icons.verified_user_outlined,
            title: 'Signed in as ${session.greetingName}',
            detail:
                '${session.mode.displayName} access is assigned by the server '
                'and cannot be changed in the app.',
            color: scheme.primary,
          ),
          const SizedBox(height: 12),
          _StatusBanner(
            icon: Icons.lock_outline,
            title: 'Secure owner session',
            detail:
                'The access token is stored in secure platform storage and '
                'sent only to the configured API.',
            color: scheme.secondary,
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusBanner(
          icon: widget.api.isDemo
              ? Icons.science_outlined
              : Icons.cloud_outlined,
          title: widget.api.isDemo ? 'Demo data source' : 'Live API configured',
          detail: widget.api.isDemo
              ? 'Set RTS_API_BASE_URL at build time to select a live endpoint.'
              : 'Endpoint: ${widget.api.baseUrl}',
          color: widget.api.isDemo ? scheme.tertiary : scheme.primary,
        ),
        const SizedBox(height: 12),
        _StatusBanner(
          icon: Icons.lock_outline,
          title: widget.api.tokenProvider == null
              ? 'Authentication not connected'
              : 'Authentication provider connected',
          detail: widget.api.tokenProvider == null
              ? 'A live identity provider and owner sign-in contract are still '
                    'required before production data can be requested.'
              : 'Live requests require a valid owner bearer token.',
          color: widget.api.tokenProvider == null
              ? scheme.error
              : scheme.primary,
        ),
        const SizedBox(height: 12),
        _StatusBanner(
          icon: Icons.wifi_outlined,
          title: 'Connectivity behavior',
          detail:
              'Requests use a 12-second timeout, preserve last-known data on '
              'refresh failure, and expose retry actions.',
          color: scheme.secondary,
        ),
      ],
    );
  }

  Widget _summaryGrid(List<DashboardMetric> metrics, double availableWidth) {
    if (metrics.isEmpty) {
      return const _EmptyState(
        icon: Icons.query_stats_outlined,
        title: 'No summary available',
        detail: 'The dashboard API returned no summary metrics.',
      );
    }
    final columns = availableWidth < 360
        ? 1
        : availableWidth < 760
        ? 2
        : 4;
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = 12.0;
        final width =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: metrics
              .map(
                (metric) => SizedBox(
                  width: width,
                  child: _MetricCard(metric: metric),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _siteCard(SiteSnapshot site, {EdgeInsets? margin}) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = site.online ? const Color(0xFF137333) : scheme.error;
    return Semantics(
      label:
          '${site.name}, ${site.online ? 'online' : 'offline'}, '
          '${site.primaryLabel}: ${site.primaryValue}',
      child: Card(
        margin: margin ?? const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: statusColor.withValues(alpha: 0.12),
                foregroundColor: statusColor,
                child: Icon(
                  site.online ? Icons.check : Icons.cloud_off_outlined,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      site.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${site.online ? 'Online' : 'Offline'} · '
                      '${site.updatedLabel}',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    if (site.attention case final attention?) ...[
                      const SizedBox(height: 6),
                      Text(
                        attention,
                        style: TextStyle(
                          color: site.online ? scheme.tertiary : scheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      site.primaryValue,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      site.primaryLabel,
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
    );
  }

  Widget _alertCard(TrackingAlert alert) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (alert.level) {
      AlertLevel.info => (Icons.info_outline, scheme.primary),
      AlertLevel.warning => (Icons.warning_amber_outlined, scheme.tertiary),
      AlertLevel.critical => (Icons.error_outline, scheme.error),
    };
    return Semantics(
      label: '${alert.level.name} alert: ${alert.title}. ${alert.detail}',
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 6,
          ),
          leading: Icon(icon, color: color),
          title: Text(
            alert.title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(alert.detail),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, String status) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final stacked = constraints.maxWidth < 380 || textScale >= 1.5;
        return Flex(
          direction: stacked ? Axis.vertical : Axis.horizontal,
          crossAxisAlignment: stacked
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            if (!stacked)
              Expanded(child: _sectionHeading(title))
            else
              _sectionHeading(title),
            SizedBox(width: stacked ? 0 : 12, height: stacked ? 4 : 0),
            Text(
              status,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _sectionHeading(String title) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final DashboardMetric metric;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '${metric.label}: ${metric.value}',
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                metric.label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                metric.value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
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
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
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
                      style: const TextStyle(fontWeight: FontWeight.w700),
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
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
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
    return _EmptyStateWithAction(
      icon: authError ? Icons.lock_outline : Icons.cloud_off_outlined,
      title: authError ? 'Sign-in is required' : 'Dashboard unavailable',
      detail: authError
          ? 'The live endpoint is configured, but no owner authentication '
                'provider is connected.'
          : 'Check the connection and try again. No demo data replaces a '
                'failed live response.',
      actionLabel: 'Try again',
      onAction: onRetry,
    );
  }
}

class _EmptyStateWithAction extends StatelessWidget {
  const _EmptyStateWithAction({
    required this.icon,
    required this.title,
    required this.detail,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String detail;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _EmptyState(icon: icon, title: title, detail: detail),
        FilledButton.icon(
          onPressed: onAction,
          icon: const Icon(Icons.refresh),
          label: Text(actionLabel),
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
      label: 'Loading dashboard',
      child: Column(
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: List.generate(
              4,
              (_) => Container(
                width: 150,
                height: 92,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          ...List.generate(
            3,
            (_) => Container(
              height: 82,
              margin: const EdgeInsets.only(bottom: 10),
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
