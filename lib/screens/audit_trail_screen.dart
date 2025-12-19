import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/notification/notification_bell.dart'
    show RightTrianglePainter;

// Helpers used by inline filters
bool sameRange(DateTimeRange a, DateTimeRange b) =>
    a.start.year == b.start.year &&
    a.start.month == b.start.month &&
    a.start.day == b.start.day &&
    a.end.year == b.end.year &&
    a.end.month == b.end.month &&
    a.end.day == b.end.day;

String fmtTwo(int n) => n.toString().padLeft(2, '0');

class AuditTrailScreen extends StatefulWidget {
  const AuditTrailScreen({super.key});

  @override
  State<AuditTrailScreen> createState() => _AuditTrailScreenState();
}

class _AuditTrailScreenState extends State<AuditTrailScreen> {
  // Pagination
  static const int _pageSize = 10;
  final List<DocumentSnapshot> _items = [];
  DocumentSnapshot? _lastDoc;
  bool _isLoading = false;
  bool _hasMore = true;
  final ScrollController _scroll = ScrollController();
  String? _errorMsg;

  // Filters
  DateTimeRange? _range; // applied range
  bool _showFilters = false; // show inline filter UI inside the table card
  final Map<String, String> _usernameCache = {}; // uid -> username
  final Set<String> _expanded = <String>{};
  String _mode = 'cashier'; // 'admin' or 'cashier'
  // Filter popover overlay (notification-like)
  final GlobalKey _filterKey = GlobalKey();
  OverlayEntry? _filterOverlayEntry;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _isLoading) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
      _fetchPage();
    }
  }

  Query _baseQuery() {
    final String col = _mode == 'admin'
        ? 'audit_logs_admin'
        : 'audit_logs_cashier';
    Query q = FirebaseFirestore.instance.collection(col);
    // Date range using Timestamp boundaries
    if (_range != null) {
      final start = Timestamp.fromDate(
        DateTime(_range!.start.year, _range!.start.month, _range!.start.day),
      );
      final end = Timestamp.fromDate(
        DateTime(
          _range!.end.year,
          _range!.end.month,
          _range!.end.day,
          23,
          59,
          59,
          999,
        ),
      );
      q = q
          .where('timestamp', isGreaterThanOrEqualTo: start)
          .where('timestamp', isLessThanOrEqualTo: end);
    }
    return q.orderBy('timestamp', descending: true);
  }

  Future<void> _loadInitial() async {
    setState(() {
      _items.clear();
      _lastDoc = null;
      _hasMore = true;
      _errorMsg = null;
    });
    await _fetchPage(reset: true);
  }

  Future<void> _fetchPage({bool reset = false}) async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      Query q = _baseQuery().limit(_pageSize);
      if (!reset && _lastDoc != null) {
        q = q.startAfterDocument(_lastDoc!);
      }
      final snap = await q.get();
      if (snap.docs.isNotEmpty) {
        setState(() {
          _items.addAll(snap.docs);
          _lastDoc = snap.docs.last;
          _errorMsg = null;
        });
        if (snap.docs.length < _pageSize) setState(() => _hasMore = false);
      } else {
        setState(() => _hasMore = false);
      }
    } catch (e) {
      setState(() {
        _errorMsg = e.toString();
        _hasMore = false;
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Inline filter helpers
  void _applyFilters(DateTimeRange? range) {
    setState(() {
      _range = range;
      _showFilters = false;
    });
    _loadInitial();
  }

  void _toggleFilterOverlay() {
    if (_filterOverlayEntry != null) {
      _filterOverlayEntry!.remove();
      _filterOverlayEntry = null;
      return;
    }

    final RenderBox renderBox =
        _filterKey.currentContext!.findRenderObject() as RenderBox;
    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _filterOverlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _toggleFilterOverlay,
            ),
          ),
          Positioned(
            top: offset.dy,
            left: offset.dx - 320,
            child: Material(
              color: Colors.transparent,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 300,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Filters',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF148AA0),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        _InlineFilters(
                          initialRange: _range,
                          onApply: (r) {
                            _toggleFilterOverlay();
                            _applyFilters(r);
                          },
                          autoApply: true,
                          showButtons: false,
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: size.height / 2 - 6,
                    right: -12,
                    child: CustomPaint(
                      size: const Size(12, 12),
                      painter: RightTrianglePainter(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(_filterOverlayEntry!);
  }

  Future<String> _username(String uid) async {
    if (uid.isEmpty) return '';
    final cached = _usernameCache[uid];
    if (cached != null) return cached;
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final name = (userDoc.data()?['username'] as String?) ?? '';
      _usernameCache[uid] = name;
      return name;
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Audit Trail'),
        backgroundColor: const Color(0xFF24A8D8),
        foregroundColor: Colors.white,
      ),
      body: Container(
        color: Colors.white,
        child: Column(
          children: [
            const SizedBox(height: 4),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadInitial,
                child: ListView(
                  controller: _scroll,
                  physics: _mode == 'cashier'
                      ? const NeverScrollableScrollPhysics()
                      : const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 28, 12, 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: _SegmentButton(
                              label: 'Admin',
                              selected: _mode == 'admin',
                              onTap: () {
                                if (_mode != 'admin') {
                                  setState(() => _mode = 'admin');
                                  _loadInitial();
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _SegmentButton(
                              label: 'Cashier',
                              selected: _mode == 'cashier',
                              onTap: () {
                                if (_mode != 'cashier') {
                                  setState(() => _mode = 'cashier');
                                  _loadInitial();
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          // Primary downward shadow
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 20,
                            spreadRadius: 1,
                            offset: Offset(0, 10),
                          ),
                          // Very light ambient for soft edges
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 4,
                            spreadRadius: 0,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
                              child: SizedBox(
                                height: 36,
                                child: Stack(
                                  children: [
                                    const Align(
                                      alignment: Alignment.center,
                                      child: Text(
                                        'Audit Trail',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF0F8AA3),
                                        ),
                                      ),
                                    ),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: _toggleFilterOverlay,
                                            child: Padding(
                                              key: _filterKey,
                                              padding: const EdgeInsets.all(6),
                                              child: Image.asset(
                                                'assets/filter.png',
                                                width: 20,
                                                height: 20,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_showFilters) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                                child: _InlineFilters(
                                  initialRange: _range,
                                  onApply: _applyFilters,
                                ),
                              ),
                            ],
                            const _TableHeader(),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16),
                              child: Divider(
                                height: 1,
                                thickness: 0.45,
                                color: Color(0xFFE6E6E6),
                              ),
                            ),
                            if (_mode == 'cashier')
                              StreamBuilder<QuerySnapshot>(
                                stream: _baseQuery().snapshots(),
                                builder: (context, snap) {
                                  if (snap.connectionState ==
                                      ConnectionState.waiting) {
                                    return const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 24,
                                      ),
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  }
                                  if (snap.hasError) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 24,
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'Failed to load audit logs',
                                            style: TextStyle(
                                              color: Colors.red[700],
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            _truncate(
                                              snap.error.toString(),
                                              200,
                                            ),
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Colors.black54,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  final allDocs = snap.data?.docs ?? const [];
                                  List<QueryDocumentSnapshot> docs = List.from(
                                    allDocs,
                                  );
                                  if (_range != null) {
                                    final start = DateTime(
                                      _range!.start.year,
                                      _range!.start.month,
                                      _range!.start.day,
                                    );
                                    final end = DateTime(
                                      _range!.end.year,
                                      _range!.end.month,
                                      _range!.end.day,
                                      23,
                                      59,
                                      59,
                                      999,
                                    );
                                    docs = allDocs
                                        .where((doc) {
                                          final data =
                                              doc.data()
                                                  as Map<String, dynamic>;
                                          final dynamic v = data['timestamp'];
                                          DateTime? dt;
                                          if (v is Timestamp) {
                                            dt = v.toDate();
                                          } else if (v is int) {
                                            dt =
                                                DateTime.fromMillisecondsSinceEpoch(
                                                  v,
                                                );
                                          } else if (v is String) {
                                            dt = DateTime.tryParse(v);
                                          }
                                          return dt != null &&
                                              !dt.isBefore(start) &&
                                              !dt.isAfter(end);
                                        })
                                        .toList(growable: false);
                                  }
                                  const int _visibleRows = 9;
                                  const double _rowApproxHeight =
                                      56; // row + divider spacing
                                  const double _listHeight =
                                      _visibleRows * _rowApproxHeight;
                                  if (docs.isEmpty) {
                                    return const SizedBox(
                                      height: _listHeight,
                                      child: Center(
                                        child: Text('No audit logs found.'),
                                      ),
                                    );
                                  }
                                  return SizedBox(
                                    height: _listHeight,
                                    child: ListView(
                                      physics: docs.length > _visibleRows
                                          ? const BouncingScrollPhysics()
                                          : const NeverScrollableScrollPhysics(),
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      children: List.generate(docs.length, (i) {
                                        final d =
                                            docs[i].data()
                                                as Map<String, dynamic>;
                                        final dynamic tsDyn = d['timestamp'];
                                        final tsText = formatTimestamp(tsDyn);
                                        final event =
                                            d['event']?.toString() ?? '';
                                        final uid = d['uid']?.toString() ?? '';
                                        final email =
                                            d['email']?.toString() ?? '';
                                        final unameField =
                                            d['username']?.toString() ?? '';
                                        String platform =
                                            d['device_platform']?.toString() ??
                                            '';
                                        String routeName =
                                            d['route_name']?.toString() ?? '';
                                        String deviceModel =
                                            d['device_model']?.toString() ?? '';
                                        String deviceManufacturer =
                                            d['device_manufacturer']
                                                ?.toString() ??
                                            '';
                                        String deviceProduct =
                                            d['device_product']?.toString() ??
                                            '';
                                        final String docId = docs[i].id;
                                        final bool isOpen = _expanded.contains(
                                          docId,
                                        );

                                        return Column(
                                          children: [
                                            InkWell(
                                              onTap: () {
                                                _showAuditDialog(
                                                  context,
                                                  usernameImmediate: unameField,
                                                  uid: uid,
                                                  routeName: routeName,
                                                  event: event,
                                                  dateText: tsText,
                                                  platform: platform,
                                                  deviceModel: deviceModel,
                                                  deviceManufacturer:
                                                      deviceManufacturer,
                                                  deviceProduct: deviceProduct,
                                                  email: email,
                                                );
                                              },
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 12,
                                                    ),
                                                child: Row(
                                                  children: [
                                                    Expanded(
                                                      flex: 2,
                                                      child: Align(
                                                        alignment: Alignment
                                                            .centerLeft,
                                                        child: Padding(
                                                          padding:
                                                              EdgeInsets.only(
                                                                left: 35,
                                                              ),
                                                          child:
                                                              unameField
                                                                  .isNotEmpty
                                                              ? Text(
                                                                  unameField,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                )
                                                              : FutureBuilder<
                                                                  String
                                                                >(
                                                                  future:
                                                                      _username(
                                                                        uid,
                                                                      ),
                                                                  builder: (context, snap) {
                                                                    final uname =
                                                                        (snap.data ??
                                                                                '')
                                                                            .trim();
                                                                    return Text(
                                                                      uname,
                                                                      overflow:
                                                                          TextOverflow
                                                                              .ellipsis,
                                                                    );
                                                                  },
                                                                ),
                                                        ),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      flex: 2,
                                                      child: Align(
                                                        alignment:
                                                            Alignment.center,
                                                        child: Text(
                                                          routeName,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          textAlign:
                                                              TextAlign.center,
                                                        ),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      flex: 2,
                                                      child: Align(
                                                        alignment:
                                                            (event == 'login' ||
                                                                event ==
                                                                    'logout')
                                                            ? Alignment.center
                                                            : Alignment
                                                                  .centerRight,
                                                        child:
                                                            (event == 'login' ||
                                                                event ==
                                                                    'logout')
                                                            ? Text(
                                                                event,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                textAlign:
                                                                    TextAlign
                                                                        .center,
                                                              )
                                                            : Padding(
                                                                padding:
                                                                    EdgeInsets.only(
                                                                      right: 16,
                                                                    ),
                                                                child: Text(
                                                                  event,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  textAlign:
                                                                      TextAlign
                                                                          .right,
                                                                ),
                                                              ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            if (isOpen)
                                              Padding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                      16,
                                                      0,
                                                      16,
                                                      12,
                                                    ),
                                                child: Column(
                                                  children: [
                                                    if (unameField.isNotEmpty)
                                                      _DetailRow(
                                                        label: 'Username',
                                                        value: unameField,
                                                      )
                                                    else
                                                      FutureBuilder<String>(
                                                        future: _username(uid),
                                                        builder:
                                                            (
                                                              context,
                                                              snap,
                                                            ) => _DetailRow(
                                                              label: 'Username',
                                                              value:
                                                                  (snap.data ??
                                                                          '')
                                                                      .trim(),
                                                            ),
                                                      ),
                                                    _DetailRow(
                                                      label: 'Route name',
                                                      value: routeName,
                                                    ),
                                                    _DetailRow(
                                                      label: 'Event',
                                                      value: event,
                                                    ),
                                                    _DetailRow(
                                                      label: 'Date',
                                                      value: tsText,
                                                    ),
                                                    if (platform.isNotEmpty)
                                                      _DetailRow(
                                                        label:
                                                            'Device platform',
                                                        value: platform,
                                                      ),
                                                    if (deviceModel.isNotEmpty)
                                                      _DetailRow(
                                                        label: 'Device model',
                                                        value: deviceModel,
                                                      ),
                                                    if (deviceManufacturer
                                                        .isNotEmpty)
                                                      _DetailRow(
                                                        label: 'Manufacturer',
                                                        value:
                                                            deviceManufacturer,
                                                      ),
                                                    if (deviceProduct
                                                        .isNotEmpty)
                                                      _DetailRow(
                                                        label: 'Product',
                                                        value: deviceProduct,
                                                      ),
                                                    if (email.isNotEmpty)
                                                      _DetailRow(
                                                        label: 'Email',
                                                        value: email,
                                                      ),
                                                    if (uid.isNotEmpty)
                                                      _DetailRow(
                                                        label: 'UID',
                                                        value: uid,
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            const Padding(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 16,
                                              ),
                                              child: Divider(
                                                height: 1,
                                                thickness: 0.45,
                                                color: Color(0xFFE6E6E6),
                                              ),
                                            ),
                                          ],
                                        );
                                      }),
                                    ),
                                  );
                                },
                              )
                            else
                              StreamBuilder<QuerySnapshot>(
                                stream: _baseQuery().limit(50).snapshots(),
                                builder: (context, snap) {
                                  if (snap.connectionState ==
                                      ConnectionState.waiting) {
                                    return const Padding(
                                      padding: EdgeInsets.symmetric(
                                        vertical: 24,
                                      ),
                                      child: Center(
                                        child: CircularProgressIndicator(),
                                      ),
                                    );
                                  }
                                  if (snap.hasError) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 24,
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'Failed to load audit logs',
                                            style: TextStyle(
                                              color: Colors.red[700],
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            _truncate(
                                              snap.error.toString(),
                                              200,
                                            ),
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: Colors.black54,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  final allDocs = snap.data?.docs ?? const [];
                                  List<QueryDocumentSnapshot> docs = List.from(
                                    allDocs,
                                  );
                                  if (_range != null) {
                                    final start = DateTime(
                                      _range!.start.year,
                                      _range!.start.month,
                                      _range!.start.day,
                                    );
                                    final end = DateTime(
                                      _range!.end.year,
                                      _range!.end.month,
                                      _range!.end.day,
                                      23,
                                      59,
                                      59,
                                      999,
                                    );
                                    docs = allDocs
                                        .where((doc) {
                                          final data =
                                              doc.data()
                                                  as Map<String, dynamic>;
                                          final dynamic v = data['timestamp'];
                                          DateTime? dt;
                                          if (v is Timestamp) {
                                            dt = v.toDate();
                                          } else if (v is int) {
                                            dt =
                                                DateTime.fromMillisecondsSinceEpoch(
                                                  v,
                                                );
                                          } else if (v is String) {
                                            dt = DateTime.tryParse(v);
                                          }
                                          return dt != null &&
                                              !dt.isBefore(start) &&
                                              !dt.isAfter(end);
                                        })
                                        .toList(growable: false);
                                  }
                                  const int _visibleRows = 9;
                                  const double _rowApproxHeight = 56;
                                  const double _listHeight =
                                      _visibleRows * _rowApproxHeight;
                                  if (docs.isEmpty) {
                                    return const SizedBox(
                                      height: _listHeight,
                                      child: Center(
                                        child: Text('No audit logs found.'),
                                      ),
                                    );
                                  }
                                  return SizedBox(
                                    height: _listHeight,
                                    child: ListView(
                                      physics: docs.length > _visibleRows
                                          ? const BouncingScrollPhysics()
                                          : const NeverScrollableScrollPhysics(),
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      children: List.generate(docs.length, (i) {
                                        final d =
                                            docs[i].data()
                                                as Map<String, dynamic>;
                                        final dynamic tsDyn = d['timestamp'];
                                        final tsText = formatTimestamp(tsDyn);
                                        final event =
                                            d['event']?.toString() ?? '';
                                        final email =
                                            d['email']?.toString() ?? '';
                                        final uid = d['uid']?.toString() ?? '';

                                        final Map<String, dynamic> device =
                                            (d['device'] as Map?)
                                                ?.cast<String, dynamic>() ??
                                            {};
                                        final Map<String, dynamic> data =
                                            (d['data'] as Map?)
                                                ?.cast<String, dynamic>() ??
                                            {};
                                        String platform =
                                            device['platform']?.toString() ??
                                            '';
                                        String routeName =
                                            data['route_name']?.toString() ??
                                            '';
                                        String deviceModel =
                                            (device['model'] ??
                                                    device['computerName'])
                                                ?.toString() ??
                                            '';
                                        String deviceManufacturer =
                                            (device['manufacturer'] ??
                                                    device['productName'])
                                                ?.toString() ??
                                            '';
                                        String deviceProduct =
                                            (device['productName'] ??
                                                    device['browser'])
                                                ?.toString() ??
                                            '';
                                        final String unameField =
                                            data['username']?.toString() ?? '';

                                        return Column(
                                          children: [
                                            InkWell(
                                              onTap: () {
                                                _showAuditDialog(
                                                  context,
                                                  usernameImmediate: unameField,
                                                  uid: uid,
                                                  routeName: routeName,
                                                  event: event,
                                                  dateText: tsText,
                                                  platform: platform,
                                                  deviceModel: deviceModel,
                                                  deviceManufacturer:
                                                      deviceManufacturer,
                                                  deviceProduct: deviceProduct,
                                                  email: email,
                                                );
                                              },
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 12,
                                                    ),
                                                child: Row(
                                                  children: [
                                                    Expanded(
                                                      flex: 2,
                                                      child: Align(
                                                        alignment: Alignment
                                                            .centerLeft,
                                                        child: Padding(
                                                          padding:
                                                              EdgeInsets.only(
                                                                left: 24,
                                                              ),
                                                          child:
                                                              unameField
                                                                  .isNotEmpty
                                                              ? Text(
                                                                  unameField,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                )
                                                              : FutureBuilder<
                                                                  String
                                                                >(
                                                                  future:
                                                                      _username(
                                                                        uid,
                                                                      ),
                                                                  builder: (context, snap) {
                                                                    final uname =
                                                                        (snap.data ??
                                                                                '')
                                                                            .trim();
                                                                    return Text(
                                                                      uname,
                                                                      overflow:
                                                                          TextOverflow
                                                                              .ellipsis,
                                                                    );
                                                                  },
                                                                ),
                                                        ),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      flex: 2,
                                                      child: Align(
                                                        alignment:
                                                            Alignment.center,
                                                        child: Text(
                                                          routeName,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          textAlign:
                                                              TextAlign.center,
                                                        ),
                                                      ),
                                                    ),
                                                    Expanded(
                                                      flex: 2,
                                                      child: Align(
                                                        alignment:
                                                            (event == 'login' ||
                                                                event ==
                                                                    'logout')
                                                            ? Alignment.center
                                                            : Alignment
                                                                  .centerRight,
                                                        child:
                                                            (event == 'login' ||
                                                                event ==
                                                                    'logout')
                                                            ? Text(
                                                                event,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                textAlign:
                                                                    TextAlign
                                                                        .center,
                                                              )
                                                            : Padding(
                                                                padding:
                                                                    EdgeInsets.only(
                                                                      right: 16,
                                                                    ),
                                                                child: Text(
                                                                  event,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  textAlign:
                                                                      TextAlign
                                                                          .right,
                                                                ),
                                                              ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            const Padding(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 16,
                                              ),
                                              child: Divider(
                                                height: 1,
                                                thickness: 1,
                                                color: Color(0xFFE6E6E6),
                                              ),
                                            ),
                                          ],
                                        );
                                      }),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _truncate(String s, int max) =>
      s.length <= max ? s : s.substring(0, max - 1) + '…';

  static String formatTimestamp(dynamic v) {
    if (v == null) return '';
    if (v is Timestamp) {
      final dt = v.toDate();
      return '${dt.year}-${_two(dt.month)}-${_two(dt.day)} ${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}';
    }
    return v.toString();
  }

  Future<void> _showAuditDialog(
    BuildContext context, {
    String usernameImmediate = '',
    required String uid,
    required String routeName,
    required String event,
    required String dateText,
    required String platform,
    required String deviceModel,
    required String deviceManufacturer,
    required String deviceProduct,
    required String email,
  }) async {
    final dialog = Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: Colors.white,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              const Center(
                child: Text(
                  'Audit Details',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF24A8D8),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1, thickness: 1, color: Color(0xFFE6E6E6)),
              const SizedBox(height: 8),
              if (usernameImmediate.isNotEmpty)
                _DetailRow(label: 'Username', value: usernameImmediate)
              else
                FutureBuilder<String>(
                  future: _username(uid),
                  builder: (context, snap) => _DetailRow(
                    label: 'Username',
                    value: (snap.data ?? '').trim(),
                  ),
                ),
              _DetailRow(label: 'Route name', value: routeName),
              _DetailRow(label: 'Event', value: event),
              _DetailRow(label: 'Date', value: dateText),
              if (platform.isNotEmpty)
                _DetailRow(label: 'Device platform', value: platform),
              if (deviceModel.isNotEmpty)
                _DetailRow(label: 'Device model', value: deviceModel),
              if (deviceManufacturer.isNotEmpty)
                _DetailRow(label: 'Manufacturer', value: deviceManufacturer),
              if (deviceProduct.isNotEmpty)
                _DetailRow(label: 'Product', value: deviceProduct),
              if (email.isNotEmpty) _DetailRow(label: 'Email', value: email),
              if (uid.isNotEmpty) _DetailRow(label: 'UID', value: uid),
              const SizedBox(height: 16),
              Center(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF148AA0),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (_) => dialog,
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  final String label;
  final bool selected;
  final IconData? icon;
  final VoidCallback onTap;
  const _FilterChipButton({
    required this.label,
    required this.onTap,
    this.selected = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    const Color teal = Color(0xFF148AA0);
    final Color fg = selected ? Colors.white : teal;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: fg),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(color: fg, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      shape: const StadiumBorder(),
      side: const BorderSide(color: teal, width: 1),
      backgroundColor: Colors.white,
      selectedColor: teal,
      selected: selected,
      onSelected: (_) => onTap(),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
    );
  }
}

class _InlineFilters extends StatefulWidget {
  final DateTimeRange? initialRange;
  final void Function(DateTimeRange?) onApply;
  final bool autoApply; // when true, apply immediately on selection
  final bool showButtons; // show Clear/Apply buttons row

  const _InlineFilters({
    required this.initialRange,
    required this.onApply,
    this.autoApply = false,
    this.showButtons = true,
  });

  @override
  State<_InlineFilters> createState() => _InlineFiltersState();
}

class _InlineFiltersState extends State<_InlineFilters> {
  DateTimeRange? _tempRange;

  @override
  void initState() {
    super.initState();
    _tempRange = widget.initialRange;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    // Yesterday full day
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final yesterdayEnd = todayStart.subtract(const Duration(milliseconds: 1));
    // Current week start (Sunday-based as before)
    final currentWeekStart = todayStart.subtract(
      Duration(days: todayStart.weekday % 7),
    );
    // Previous calendar week (Sun..Sat)
    final lastWeekStart = currentWeekStart.subtract(const Duration(days: 7));
    final lastWeekEnd = currentWeekStart.subtract(
      const Duration(milliseconds: 1),
    );
    // Previous calendar month
    final currentMonthStart = DateTime(now.year, now.month, 1);
    final lastMonthStart = DateTime(now.year, now.month - 1, 1);
    final lastMonthEnd = currentMonthStart.subtract(
      const Duration(milliseconds: 1),
    );
    // Previous calendar year
    final currentYearStart = DateTime(now.year, 1, 1);
    final lastYearStart = DateTime(now.year - 1, 1, 1);
    final lastYearEnd = currentYearStart.subtract(
      const Duration(milliseconds: 1),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _FilterChipButton(
              label: 'Today',
              selected:
                  _tempRange != null &&
                  sameRange(
                    _tempRange!,
                    DateTimeRange(start: todayStart, end: now),
                  ),
              onTap: () {
                setState(
                  () => _tempRange = DateTimeRange(start: todayStart, end: now),
                );
                if (widget.autoApply) widget.onApply(_tempRange);
              },
            ),
            _FilterChipButton(
              label: 'Last week',
              selected:
                  _tempRange != null &&
                  sameRange(
                    _tempRange!,
                    DateTimeRange(start: lastWeekStart, end: lastWeekEnd),
                  ),
              onTap: () {
                setState(
                  () => _tempRange = DateTimeRange(
                    start: lastWeekStart,
                    end: lastWeekEnd,
                  ),
                );
                if (widget.autoApply) widget.onApply(_tempRange);
              },
            ),
            _FilterChipButton(
              label: 'Last month',
              selected:
                  _tempRange != null &&
                  sameRange(
                    _tempRange!,
                    DateTimeRange(start: lastMonthStart, end: lastMonthEnd),
                  ),
              onTap: () {
                setState(
                  () => _tempRange = DateTimeRange(
                    start: lastMonthStart,
                    end: lastMonthEnd,
                  ),
                );
                if (widget.autoApply) widget.onApply(_tempRange);
              },
            ),
            _FilterChipButton(
              label: 'Last year',
              selected:
                  _tempRange != null &&
                  sameRange(
                    _tempRange!,
                    DateTimeRange(start: lastYearStart, end: lastYearEnd),
                  ),
              onTap: () {
                setState(
                  () => _tempRange = DateTimeRange(
                    start: lastYearStart,
                    end: lastYearEnd,
                  ),
                );
                if (widget.autoApply) widget.onApply(_tempRange);
              },
            ),
            _FilterChipButton(
              label: _tempRange == null
                  ? 'Pick date range'
                  : '${_tempRange!.start.year}-${fmtTwo(_tempRange!.start.month)}-${fmtTwo(_tempRange!.start.day)} to ${_tempRange!.end.year}-${fmtTwo(_tempRange!.end.month)}-${fmtTwo(_tempRange!.end.day)}',
              icon: Icons.date_range,
              onTap: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2023, 1, 1),
                  lastDate: DateTime(now.year + 1, 12, 31),
                  initialDateRange:
                      _tempRange ?? DateTimeRange(start: todayStart, end: now),
                  helpText: 'Select date range',
                );
                if (picked != null) {
                  setState(() => _tempRange = picked);
                  if (widget.autoApply) widget.onApply(_tempRange);
                }
              },
            ),
          ],
        ),
        if (widget.showButtons) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => widget.onApply(null),
                  child: const Text('Clear'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => widget.onApply(_tempRange),
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _TableHeader extends StatelessWidget {
  const _TableHeader();
  @override
  Widget build(BuildContext context) {
    TextStyle th = const TextStyle(
      fontWeight: FontWeight.w600,
      color: Colors.black87,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(left: 20),
                  child: Text('Username', style: th),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.center,
                child: Text('Route', style: th),
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: EdgeInsets.only(right: 36),
                  child: Text('Event', style: th),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _SegmentButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const Color teal = Color(0xFF148AA0);
    const Color grey = Color(0xFF7A7A7A);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeInOut,
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? teal : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: teal.withOpacity(0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: selected ? Colors.white : grey,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
