import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

void main() {
  runApp(const RtsTrackingApp());
}

class RtsTrackingApp extends StatelessWidget {
  const RtsTrackingApp({super.key});

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF48115B);
    return MaterialApp(
      title: 'RTS Tracking',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: purple),
        scaffoldBackgroundColor: const Color(0xFFF8F6F9),
        useMaterial3: true,
        fontFamily: 'Arial',
      ),
      home: const TrackingHome(),
    );
  }
}

enum TrackingMode { business, clinic }

class OwnerApi {
  OwnerApi({this.baseUrl});

  final Uri? baseUrl;

  Future<Map<String, dynamic>> getDashboard() async {
    if (baseUrl == null) return _demoDashboard();
    final client = HttpClient();
    try {
      final request = await client.getUrl(baseUrl!.resolve('/owner/dashboard'));
      request.headers.contentType = ContentType.json;
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Dashboard request failed: ${response.statusCode}');
      }
      return jsonDecode(await response.transform(utf8.decoder).join())
          as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  Map<String, dynamic> _demoDashboard() => {
    'sites': 4,
    'online': 3,
    'alerts': 2,
    'businessSales': '₪18,420',
    'clinicAppointments': 27,
    'clinicNoShows': 2,
  };
}

class TrackingHome extends StatefulWidget {
  const TrackingHome({super.key});

  @override
  State<TrackingHome> createState() => _TrackingHomeState();
}

class _TrackingHomeState extends State<TrackingHome> {
  final OwnerApi api = OwnerApi();
  TrackingMode mode = TrackingMode.business;
  int selectedIndex = 0;
  Map<String, dynamic> dashboard = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => loading = true);
    final data = await api.getDashboard();
    if (!mounted) return;
    setState(() {
      dashboard = data;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final clinic = mode == TrackingMode.clinic;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Row(
          children: [
            const Icon(Icons.track_changes, color: Color(0xFF48115B)),
            const SizedBox(width: 8),
            const Text(
              'RTS Tracking',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh)),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.account_circle_outlined),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _modePicker(),
            const SizedBox(height: 18),
            Text(
              clinic ? 'Clinic overview' : 'Business overview',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              clinic
                  ? 'Monitor appointments, utilization, and clinic alerts.'
                  : 'Monitor stores, sales, stock, and operational alerts.',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 18),
            if (loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              _summaryGrid(clinic),
              const SizedBox(height: 18),
              _sectionTitle(clinic ? 'Clinic status' : 'Store status'),
              const SizedBox(height: 8),
              ..._siteCards(clinic),
              const SizedBox(height: 18),
              _sectionTitle('Attention needed'),
              const SizedBox(height: 8),
              _alertCard(
                clinic
                    ? '2 appointment follow-ups need review'
                    : '2 stores have low-stock alerts',
                clinic ? Icons.event_note_outlined : Icons.inventory_2_outlined,
                Colors.orange,
              ),
              _alertCard(
                'Last synchronized moments ago',
                Icons.cloud_done_outlined,
                Colors.green,
              ),
            ],
          ],
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
            label: 'Sites',
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

  Widget _modePicker() {
    return SegmentedButton<TrackingMode>(
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
      onSelectionChanged: (value) => setState(() => mode = value.first),
    );
  }

  Widget _summaryGrid(bool clinic) {
    final items = clinic
        ? [
            (
              'Appointments',
              '${dashboard['clinicAppointments']}',
              Icons.event_available_outlined,
              Colors.blue,
            ),
            (
              'No-shows',
              '${dashboard['clinicNoShows']}',
              Icons.event_busy_outlined,
              Colors.orange,
            ),
            (
              'Clinics online',
              '${dashboard['online']}/${dashboard['sites']}',
              Icons.cloud_done_outlined,
              Colors.green,
            ),
            (
              'Alerts',
              '${dashboard['alerts']}',
              Icons.warning_amber_outlined,
              Colors.red,
            ),
          ]
        : [
            (
              'Sales today',
              '${dashboard['businessSales']}',
              Icons.payments_outlined,
              Colors.green,
            ),
            (
              'Stores online',
              '${dashboard['online']}/${dashboard['sites']}',
              Icons.store_outlined,
              Colors.blue,
            ),
            (
              'Alerts',
              '${dashboard['alerts']}',
              Icons.warning_amber_outlined,
              Colors.red,
            ),
            ('Sync', 'Healthy', Icons.cloud_done_outlined, Colors.teal),
          ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 116,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(item.$3, color: item.$4),
                const Spacer(),
                Text(
                  item.$1,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                ),
                Text(
                  item.$2,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _siteCards(bool clinic) {
    final names = clinic
        ? ['RTS Clinic Main', 'RTS Clinic North', 'RTS Clinic West']
        : [
            'RTS Business Main Store',
            'RTS Business Mall',
            'RTS Business Warehouse',
          ];
    return names.map((name) {
      final online = name != names.last;
      return Card(
        elevation: 0,
        color: Colors.white,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: online ? Colors.green.shade50 : Colors.red.shade50,
            child: Icon(
              online ? Icons.check : Icons.cloud_off,
              color: online ? Colors.green : Colors.red,
            ),
          ),
          title: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            online
                ? 'Online · updated just now'
                : 'Offline · last update 18 min ago',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {},
        ),
      );
    }).toList();
  }

  Widget _sectionTitle(String title) => Text(
    title,
    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
  );

  Widget _alertCard(String text, IconData icon, Color color) {
    return Card(
      elevation: 0,
      color: Colors.white,
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(text),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {},
      ),
    );
  }
}
