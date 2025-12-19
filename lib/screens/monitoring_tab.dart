import 'package:flutter/material.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/camera_repository.dart';
import '../widgets/webrtc_viewer_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MonitoringTab extends StatefulWidget {
  const MonitoringTab({super.key});

  @override
  State<MonitoringTab> createState() => _MonitoringTabState();
}

class _CameraBox extends StatefulWidget {
  final String title;
  final String configDoc;
  const _CameraBox({required this.title, required this.configDoc});

  @override
  State<_CameraBox> createState() => _CameraBoxState();
}

class _CameraBoxState extends State<_CameraBox> {
  String? _joinedRoom;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _showOptions(context),
          child: Container(
            height: 220,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[500]!, width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            padding: const EdgeInsets.all(8),
            child: WebRTCViewerPanel(
              configDoc: widget.configDoc,
              onJoined: (id) {
                if (!mounted) return;
                setState(() => _joinedRoom = id);
              },
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _joinedRoom == null ? 'Connecting…' : 'Room: ${_joinedRoom!}',
          style: const TextStyle(fontSize: 12, color: Colors.black54),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Future<List<String>> _fetchActiveCashiers([
    Duration window = const Duration(minutes: 15),
  ]) async {
    try {
      final since = Timestamp.fromDate(DateTime.now().subtract(window));
      final qs = await FirebaseFirestore.instance
          .collection('audit_logs_cashier')
          .where('timestamp', isGreaterThan: since)
          .where('route_name', isEqualTo: 'PosSale')
          .orderBy('timestamp', descending: true)
          .limit(200)
          .get();
      final set = <String>{};
      for (final d in qs.docs) {
        final u = (d.data()['username'] as String?)?.trim();
        if (u != null && u.isNotEmpty) set.add(u);
      }
      if (set.isEmpty) {
        final user = FirebaseAuth.instance.currentUser;
        final email = user?.email ?? '';
        final name =
            user?.displayName ??
            (email.contains('@') ? email.split('@').first : 'Cashier');
        return [name];
      }
      return set.toList();
    } catch (_) {
      final user = FirebaseAuth.instance.currentUser;
      final email = user?.email ?? '';
      final name =
          user?.displayName ??
          (email.contains('@') ? email.split('@').first : 'Cashier');
      return [name];
    }
  }

  Future<String?> _getAdminName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final n = prefs.getString('admin_display_name');
      return (n != null && n.trim().isNotEmpty) ? n.trim() : null;
    } catch (_) {
      return null;
    }
  }

  List<String> _filterOutAdmin(List<String> names) {
    final set = <String>{};
    set.addAll(names.where((e) => e.trim().isNotEmpty).map((e) => e.trim()));
    return set.toList();
  }

  String _shiftDocId(Map<String, dynamic> shift) {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final dateIso = '$y-$m-$d';
    final sn = (shift['shiftName'] ?? 'Shift').toString().replaceAll(' ', '_');
    return '${dateIso}_$sn';
  }

  Future<List<String>> _loadShiftStaffOverride(
    Map<String, dynamic> shift,
  ) async {
    try {
      final id = _shiftDocId(shift);
      final doc = await FirebaseFirestore.instance
          .collection('shift_present_staff')
          .doc(id)
          .get();
      final data = doc.data();
      if (data == null) return const <String>[];
      final list =
          (data['staff'] as List?)?.map((e) => e.toString()).toList() ??
          const <String>[];
      return list;
    } catch (_) {
      return const <String>[];
    }
  }

  Future<void> _saveShiftStaffOverride(
    Map<String, dynamic> shift,
    List<String> names,
  ) async {
    try {
      final now = DateTime.now();
      final y = now.year.toString().padLeft(4, '0');
      final m = now.month.toString().padLeft(2, '0');
      final d = now.day.toString().padLeft(2, '0');
      final dateIso = '$y-$m-$d';
      final id = _shiftDocId(shift);
      final clean = names
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
      await FirebaseFirestore.instance
          .collection('shift_present_staff')
          .doc(id)
          .set({
            'date': dateIso,
            'shiftName': (shift['shiftName'] ?? 'Shift').toString(),
            'time': (shift['time'] ?? '').toString(),
            'staff': clean,
            'updatedAt': Timestamp.now(),
          }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<List<String>> _getPresentStaff(Map<String, dynamic> shift) async {
    final override = await _loadShiftStaffOverride(shift);
    List<String> base = override.isNotEmpty
        ? override
        : await _fetchActiveCashiers(const Duration(minutes: 20));
    base = _filterOutAdmin(base);
    final adminName = (await _getAdminName())?.toLowerCase();
    if (adminName != null && adminName.isNotEmpty) {
      base = base.where((n) => n.toLowerCase() != adminName).toList();
    }
    return base;
  }

  Future<void> _showEditStaffDialog(
    BuildContext ctx,
    Map<String, dynamic> shift,
    List<String> current,
  ) async {
    final controller = TextEditingController(text: current.join(', '));
    await showDialog(
      context: ctx,
      builder: (dCtx) {
        return AlertDialog(
          title: const Text('Edit Present Staff'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Enter names separated by commas',
            ),
            minLines: 1,
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dCtx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final raw = controller.text;
                final parts = raw
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                final adminName = (await _getAdminName())?.toLowerCase();
                final filtered = adminName == null
                    ? parts
                    : parts.where((n) => n.toLowerCase() != adminName).toList();
                await _saveShiftStaffOverride(shift, filtered);
                if (mounted) setState(() {});
                if (mounted) Navigator.of(dCtx).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.fullscreen),
                title: const Text('View fullscreen'),
                onTap: () {
                  Navigator.of(ctx).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (_) => _FullscreenCameraPage(
                        title: widget.title,
                        configDoc: widget.configDoc,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }
}

class _FullscreenCameraPage extends StatelessWidget {
  final String title;
  final String configDoc;
  const _FullscreenCameraPage({required this.title, required this.configDoc});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('$title — Fullscreen'),
      ),
      body: SafeArea(
        child: Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: WebRTCViewerPanel(configDoc: configDoc),
            ),
          ),
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetricPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.22),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffChip extends StatelessWidget {
  final String initials;
  final String name;

  const _StaffChip({required this.initials, required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: const Color(0xFF0F8AA3),
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            name,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonitoringTabState extends State<MonitoringTab> {
  late final CameraRepository _camRepo;
  Timer? _camPollTimer;
  double _battery = 0.0;

  @override
  void initState() {
    super.initState();
    _setupBatteryMonitor();
  }

  Future<void> _setupBatteryMonitor() async {
    String? token;
    try {
      token = await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {}
    _camRepo = CameraRepository(
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
      },
    );
    // Immediate fetch to avoid placeholder flash on tab switch
    try {
      final b0 = await _camRepo.fetchLatestBatteryPercent();
      if (b0 != null && mounted) {
        setState(() => _battery = b0.clamp(0, 100).toDouble());
      }
    } catch (_) {}
    _camPollTimer?.cancel();
    _camPollTimer = Timer.periodic(const Duration(milliseconds: 500), (
      _,
    ) async {
      try {
        final b = await _camRepo.fetchLatestBatteryPercent();
        if (b != null && mounted) {
          setState(() => _battery = b.clamp(0, 100).toDouble());
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _camPollTimer?.cancel();
    super.dispose();
  }

  Future<String?> _getAdminName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final n = prefs.getString('admin_display_name');
      return (n != null && n.trim().isNotEmpty) ? n.trim() : null;
    } catch (_) {
      return null;
    }
  }

  List<String> _filterOutAdmin(List<String> names) {
    final set = <String>{};
    set.addAll(names.where((e) => e.trim().isNotEmpty).map((e) => e.trim()));
    return set.toList();
  }

  String _shiftDocId(Map<String, dynamic> shift) {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final dateIso = '$y-$m-$d';
    final sn = (shift['shiftName'] ?? 'Shift').toString().replaceAll(' ', '_');
    return '${dateIso}_$sn';
  }

  Future<List<String>> _loadShiftStaffOverride(
    Map<String, dynamic> shift,
  ) async {
    try {
      final id = _shiftDocId(shift);
      final doc = await FirebaseFirestore.instance
          .collection('shift_present_staff')
          .doc(id)
          .get();
      final data = doc.data();
      if (data == null) return const <String>[];
      final list =
          (data['staff'] as List?)?.map((e) => e.toString()).toList() ??
          const <String>[];
      return list;
    } catch (_) {
      return const <String>[];
    }
  }

  Future<void> _saveShiftStaffOverride(
    Map<String, dynamic> shift,
    List<String> names,
  ) async {
    try {
      final now = DateTime.now();
      final y = now.year.toString().padLeft(4, '0');
      final m = now.month.toString().padLeft(2, '0');
      final d = now.day.toString().padLeft(2, '0');
      final dateIso = '$y-$m-$d';
      final id = _shiftDocId(shift);
      final clean = names
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
      await FirebaseFirestore.instance
          .collection('shift_present_staff')
          .doc(id)
          .set({
            'date': dateIso,
            'shiftName': (shift['shiftName'] ?? 'Shift').toString(),
            'time': (shift['time'] ?? '').toString(),
            'staff': clean,
            'updatedAt': Timestamp.now(),
          }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<List<String>> _getPresentStaff(Map<String, dynamic> shift) async {
    final override = await _loadShiftStaffOverride(shift);
    List<String> base = override.isNotEmpty
        ? override
        : await _fetchActiveCashiers(const Duration(minutes: 20));
    base = _filterOutAdmin(base);
    final adminName = (await _getAdminName())?.toLowerCase();
    if (adminName != null && adminName.isNotEmpty) {
      base = base.where((n) => n.toLowerCase() != adminName).toList();
    }
    return base;
  }

  Future<void> _showEditStaffDialog(
    BuildContext ctx,
    Map<String, dynamic> shift,
    List<String> current,
  ) async {
    final controller = TextEditingController(text: current.join(', '));
    await showDialog(
      context: ctx,
      builder: (dCtx) {
        return AlertDialog(
          title: const Text('Edit Present Staff'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Enter names separated by commas',
            ),
            minLines: 1,
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dCtx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final raw = controller.text;
                final parts = raw
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                final adminName = (await _getAdminName())?.toLowerCase();
                final filtered = adminName == null
                    ? parts
                    : parts.where((n) => n.toLowerCase() != adminName).toList();
                await _saveShiftStaffOverride(shift, filtered);
                if (mounted) setState(() {});
                if (context.mounted) Navigator.of(dCtx).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<List<String>> _fetchActiveCashiers([
    Duration window = const Duration(minutes: 15),
  ]) async {
    try {
      final since = Timestamp.fromDate(DateTime.now().subtract(window));
      final qs = await FirebaseFirestore.instance
          .collection('audit_logs_cashier')
          .where('timestamp', isGreaterThan: since)
          .where('route_name', isEqualTo: 'PosSale')
          .orderBy('timestamp', descending: true)
          .limit(200)
          .get();
      final set = <String>{};
      for (final d in qs.docs) {
        final u = (d.data()['username'] as String?)?.trim();
        if (u != null && u.isNotEmpty) set.add(u);
      }
      if (set.isEmpty) {
        final user = FirebaseAuth.instance.currentUser;
        final email = user?.email ?? '';
        final name =
            user?.displayName ??
            (email.contains('@') ? email.split('@').first : 'Cashier');
        return [name];
      }
      return set.toList();
    } catch (_) {
      final user = FirebaseAuth.instance.currentUser;
      final email = user?.email ?? '';
      final name =
          user?.displayName ??
          (email.contains('@') ? email.split('@').first : 'Cashier');
      return [name];
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22.0, 22.0, 22.0, 100.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Production & Inventory Monitoring',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            // Monitoring + Shift row (like Production/Sales)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 165,
                  child: Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Container(
                      width: 165,
                      height: 185,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF9C27B0), Color(0xFFBA68C8)],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.purple.withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Transform.scale(
                            scale: 2.5,
                            child: Image.asset(
                              'assets/monitor.png',
                              width: 28,
                              height: 48,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Monitoring',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'System Status',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            height: 4,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  return Container(
                                    width:
                                        constraints.maxWidth * (_battery / 100),
                                    decoration: BoxDecoration(
                                      color: _battery < 20
                                          ? Colors.redAccent
                                          : _battery < 50
                                          ? Colors.yellowAccent
                                          : Colors.greenAccent,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_battery.toStringAsFixed(0)}% system health',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: const Offset(16, 23),
                  child: SizedBox(
                    width: 160,
                    child: _StackedSolidShiftCards(
                      onShiftTap: (shift) {
                        final List<Color> g = List<Color>.from(
                          (shift['gradient'] ??
                                  const [Colors.teal, Colors.greenAccent])
                              as List,
                        );
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(20),
                            ),
                          ),
                          builder: (ctx) {
                            int sold = 0;
                            try {
                              final m = RegExp(
                                r"(\d+)",
                              ).firstMatch((shift['count'] ?? '').toString());
                              if (m != null) sold = int.parse(m.group(1)!);
                            } catch (_) {}
                            final int expected = sold + 10;
                            final int actual = sold;
                            final int discrepancy =
                                actual - expected; // negative = short
                            return SafeArea(
                              child: Padding(
                                padding: MediaQuery.of(ctx).viewInsets,
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: g,
                                    ),
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(20),
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(20),
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        18,
                                        16,
                                        16,
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              CircleAvatar(
                                                backgroundColor: Colors.white
                                                    .withOpacity(0.18),
                                                child: Padding(
                                                  padding: const EdgeInsets.all(
                                                    2.0,
                                                  ),
                                                  child: Image.asset(
                                                    'assets/shift.png',
                                                    width: 26,
                                                    height: 26,
                                                    fit: BoxFit.contain,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Text(
                                                  (shift['shiftName'] ??
                                                          'Shift')
                                                      .toString(),
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.white,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 6,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withOpacity(0.18),
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                ),
                                                child: Text(
                                                  (shift['time'] ?? '')
                                                      .toString(),
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 14),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              _MetricPill(
                                                icon:
                                                    Icons.shopping_bag_outlined,
                                                label: 'Sold',
                                                value: '$sold blocks',
                                              ),
                                              _MetricPill(
                                                icon: Icons
                                                    .precision_manufacturing_outlined,
                                                label: 'Expected',
                                                value: '$expected',
                                              ),
                                              _MetricPill(
                                                icon: Icons.done_all_rounded,
                                                label: 'Actual',
                                                value: '$actual',
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 16),
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: const [
                                              Text(
                                                'Present Staff',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          FutureBuilder<List<String>>(
                                            future: _getPresentStaff(shift),
                                            builder: (ctx, snap) {
                                              if (snap.connectionState !=
                                                  ConnectionState.done) {
                                                return const SizedBox(
                                                  height: 28,
                                                  child: Center(
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: Colors.white,
                                                        ),
                                                  ),
                                                );
                                              }
                                              final names =
                                                  snap.data ?? const <String>[];
                                              if (names.isEmpty) {
                                                return const Text(
                                                  'No staff present.',
                                                  style: TextStyle(
                                                    color: Colors.white70,
                                                  ),
                                                );
                                              }
                                              return Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Wrap(
                                                    spacing: 10,
                                                    runSpacing: 10,
                                                    children: [
                                                      for (final name in names)
                                                        _StaffChip(
                                                          initials:
                                                              name.isNotEmpty
                                                              ? name[0]
                                                                    .toUpperCase()
                                                              : '?',
                                                          name: name,
                                                        ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Align(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    child: TextButton.icon(
                                                      onPressed: () async {
                                                        final current =
                                                            await _getPresentStaff(
                                                              shift,
                                                            );
                                                        await _showEditStaffDialog(
                                                          ctx,
                                                          shift,
                                                          current,
                                                        );
                                                        if (mounted)
                                                          setState(() {});
                                                      },
                                                      icon: const Icon(
                                                        Icons.edit,
                                                        color: Colors.white,
                                                      ),
                                                      label: const Text(
                                                        'Edit',
                                                        style: TextStyle(
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                      style: TextButton.styleFrom(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 4,
                                                            ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              );
                                            },
                                          ),
                                          const SizedBox(height: 16),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 12,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.redAccent,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withOpacity(0.08),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 3),
                                                ),
                                              ],
                                            ),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                  Icons.warning_amber_rounded,
                                                  color: Colors.white,
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    'Discrepancy: $discrepancy blocks',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                                TextButton.icon(
                                                  onPressed: () {},
                                                  icon: const Icon(
                                                    Icons.report_outlined,
                                                    color: Colors.white,
                                                  ),
                                                  label: const Text(
                                                    'Report',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                  style: TextButton.styleFrom(
                                                    foregroundColor:
                                                        Colors.white,
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 8,
                                                        ),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            20,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 14),
                                          Align(
                                            alignment: Alignment.center,
                                            child: ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.white,
                                                foregroundColor: Colors.black87,
                                                shape: const StadiumBorder(),
                                                elevation: 0,
                                              ),
                                              onPressed: () =>
                                                  Navigator.of(ctx).pop(),
                                              child: const Padding(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: 22.0,
                                                  vertical: 10,
                                                ),
                                                child: Text('Close'),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Camera Preview Section (Entrance / Exit)
            Text(
              'Live Camera Monitoring',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: const [
                _CameraBox(
                  title: 'Entrance',
                  configDoc: 'camera_room_entrance',
                ),
                SizedBox(height: 12),
                _CameraBox(title: 'Exit', configDoc: 'camera_room_exit'),
              ],
            ),
            SizedBox(height: 30),
            // Monitoring Records table (no search icon)
            _buildMonitoringRecordsTable(),
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMonitoringRecordsTable() {
    final List<Map<String, String>> records = [
      {'date': '2025-10-26', 'shift': '1', 'duration': '10 seconds'},
      {'date': '2025-10-26', 'shift': '3', 'duration': '30 seconds'},
    ];

    const headerStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 14,
      color: Colors.black87,
    );
    const cellStyle = TextStyle(fontSize: 15, color: Colors.black);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  alignment: Alignment.center,
                  margin: const EdgeInsets.only(bottom: 10),
                  child: const Text(
                    'Monitoring Records',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F8AA3),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: DataTable(
                    columnSpacing: 26,
                    dataRowMinHeight: 44,
                    dataRowMaxHeight: 48,
                    headingRowHeight: 36,
                    dividerThickness: 0.45,
                    columns: const [
                      DataColumn(
                        label: Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.only(left: 12.0),
                            child: Text('Date', style: headerStyle),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Align(
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: 60,
                            child: Text(
                              'Shift',
                              style: headerStyle,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Align(
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: 140,
                            child: Text(
                              'Duration',
                              style: headerStyle,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    ],
                    rows: records.map((r) {
                      return DataRow(
                        cells: [
                          DataCell(
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(r['date'] ?? '', style: cellStyle),
                            ),
                          ),
                          DataCell(
                            Align(
                              alignment: Alignment.center,
                              child: Text(r['shift'] ?? '', style: cellStyle),
                            ),
                          ),
                          DataCell(
                            Align(
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    r['duration'] ?? '',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.play_circle_outline,
                                    color: Color(0xFF5C6BC0),
                                    size: 18,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
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

class _StackedSolidShiftCards extends StatefulWidget {
  final void Function(Map<String, dynamic>) onShiftTap;
  const _StackedSolidShiftCards({super.key, required this.onShiftTap});

  @override
  State<_StackedSolidShiftCards> createState() =>
      _StackedSolidShiftCardsState();
}

class _StackedSolidShiftCardsState extends State<_StackedSolidShiftCards>
    with SingleTickerProviderStateMixin {
  final List<Map<String, dynamic>> _shifts = const [
    {
      "shiftName": "Shift 1",
      "time": "6AM - 2PM",
      "count": "100 blocks",
      "color": Color(0xFF43EA7E),
      "gradient": [Color(0xFF43EA7E), Color(0xFF81E6C2)],
    },
    {
      "shiftName": "Shift 2",
      "time": "2PM - 10PM",
      "count": "50 blocks",
      "color": Color(0xFFFFB74D),
      "gradient": [Color(0xFFFFB74D), Color(0xFFFFD580)],
    },
    {
      "shiftName": "Shift 3",
      "time": "10PM - 6AM",
      "count": "16 blocks",
      "color": Color(0xFF1976D2),
      "gradient": [Color(0xFF42A5F5), Color(0xFF1976D2)],
    },
  ];

  int _topIndex = 0;
  bool _isAnimating = false;

  @override
  void initState() {
    super.initState();
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return false;
      setState(() => _isAnimating = true);
      await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) return false;
      setState(() {
        _topIndex = (_topIndex + 1) % _shifts.length;
        _isAnimating = false;
      });
      return mounted;
    });
  }

  @override
  Widget build(BuildContext context) {
    const double verticalOffset = 16.0;
    final List<int> indices = [
      _topIndex,
      (_topIndex + 1) % 3,
      (_topIndex + 2) % 3,
    ];
    final List<Widget> stack = <Widget>[];
    for (int i = 2; i >= 0; i--) {
      double start = verticalOffset * i;
      double animOffset = 0.0;
      if (_isAnimating) {
        if (i == 0) animOffset = 2 * verticalOffset;
        if (i == 1) animOffset = -verticalOffset;
        if (i == 2) animOffset = -2 * verticalOffset;
      }
      stack.add(
        AnimatedPositioned(
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOut,
          left: 0,
          right: 0,
          top: start + animOffset,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              splashColor: Colors.white24,
              highlightColor: Colors.white10,
              onTap: () => widget.onShiftTap(_shifts[indices[i]]),
              child: _ShiftCard(
                shiftName: _shifts[indices[i]]["shiftName"],
                time: _shifts[indices[i]]["time"],
                count: _shifts[indices[i]]["count"],
                color: _shifts[indices[i]]["color"],
                gradientColors: List<Color>.from(
                  _shifts[indices[i]]["gradient"],
                ),
                iconPath: 'assets/shift.png',
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: 160,
      height: 190,
      child: Stack(alignment: Alignment.topCenter, children: stack),
    );
  }
}

class _ShiftCard extends StatelessWidget {
  final String shiftName;
  final String time;
  final String count;
  final Color color;
  final String iconPath;
  final List<Color> gradientColors;

  const _ShiftCard({
    required this.shiftName,
    required this.time,
    required this.count,
    required this.color,
    required this.gradientColors,
    required this.iconPath,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradientColors,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.white.withOpacity(0.18),
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: Image.asset(
                      iconPath,
                      width: 26,
                      height: 26,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    shiftName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              time,
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            ),
            const SizedBox(height: 6),
            Text(
              count,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 16,
                shadows: [
                  Shadow(
                    blurRadius: 6,
                    color: color.withOpacity(0.5),
                    offset: const Offset(1, 1),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
