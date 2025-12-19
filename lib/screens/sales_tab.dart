import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/inventory_repository.dart';
import '../services/price_repository.dart';
import '../services/sales_repository.dart';
import '../services/audit_service.dart';
import 'profile_tab.dart';
import 'settings_tab.dart';
import '../widgets/notification/notification_bell.dart';
import 'inventory_cashier.dart';
import 'reports_tab_cashier.dart' as cashier_reports;

/// Cashier entry screen that enforces role and renders the Sales tab UI.
class PosSaleScreen extends StatefulWidget {
  final VoidCallback? onLogout;
  const PosSaleScreen({super.key, this.onLogout});

  @override
  State<PosSaleScreen> createState() => _PosSaleScreenState();
}

class _PosSaleScreenState extends State<PosSaleScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey _bellKey = GlobalKey();
  final ValueNotifier<String> cashierNameNotifier = ValueNotifier<String>(
    'Cashier',
  );
  int _selectedIndex = 0;
  int _notificationCount = 0;

  @override
  void initState() {
    super.initState();
    _ensureCashier();
  }

  Future<void> _setFullScreen() async {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
    await Future.delayed(const Duration(milliseconds: 50));
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _exitFullScreen() async {
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
  }

  Widget _buildBottomNav() {
    const Color bluerose = Color(0xFF24A8D8);
    return SafeArea(
      top: false,
      left: true,
      right: true,
      bottom: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              NavItem(
                icon: Icons.home,
                label: 'POS',
                index: 0,
                currentIndex: _selectedIndex,
                onTap: _onNavTap,
                selectedColor: bluerose,
                iconSize: 24,
                labelPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
              ),
              NavItem(
                icon: Icons.inventory,
                label: 'Inventory',
                index: 1,
                currentIndex: _selectedIndex,
                onTap: _onNavTap,
                selectedColor: bluerose,
                iconSize: 24,
                labelPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
              ),
              NavItem(
                icon: Icons.analytics,
                label: 'Reports',
                index: 2,
                currentIndex: _selectedIndex,
                onTap: _onNavTap,
                selectedColor: bluerose,
                iconSize: 24,
                labelPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _exitFullScreen();
    super.dispose();
  }

  Future<void> _ensureCashier() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role');
    if (role != 'cashier' && mounted) {
      await AuditService.instance.log(
        event: 'access_denied',
        data: {
          'screen': 'PosSale',
          'required_role': 'cashier',
          'actual_role': role,
        },
      );
      await FirebaseAuth.instance.signOut();
      widget.onLogout?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    _setFullScreen();
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;

    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        child: Column(
          children: [
            // Header copied from admin
            Container(
              height: 160,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFE0F7FA),
                    Color(0xFFB2EBF2),
                    Color(0xFF80DEEA),
                  ],
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/profile.png',
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.blueGrey[100],
                              child: Icon(
                                Icons.person,
                                color: Colors.blueGrey[300],
                                size: 40,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Cashier',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF006064),
                      ),
                    ),
                    const Text(
                      'OIP Sentinel',
                      style: TextStyle(fontSize: 14, color: Color(0xFF00838F)),
                    ),
                  ],
                ),
              ),
            ),
            // Items copied from admin (minus Register Cashier)
            ListTile(
              leading: const Icon(Icons.person, color: Color(0xFF00838F)),
              title: const Text(
                'Profile',
                style: TextStyle(color: Color(0xFF006064)),
              ),
              onTap: () async {
                Navigator.pop(context);
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProfileTab(
                      adminNameNotifier: cashierNameNotifier,
                      primaryColor: const Color(0xFF754ef9),
                    ),
                    settings: const RouteSettings(name: 'Profile'),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings, color: Color(0xFF00838F)),
              title: const Text(
                'Settings',
                style: TextStyle(color: Color(0xFF006064)),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        const SettingsTab(primaryColor: Color(0xFF00838F)),
                    settings: const RouteSettings(name: 'Settings'),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Color(0xFF00838F)),
              title: const Text(
                'Logout',
                style: TextStyle(color: Color(0xFF006064)),
              ),
              onTap: () {
                Navigator.pop(context);
                _onLogout();
              },
            ),
          ],
        ),
      ),
      appBar: null,
      body: Stack(
        children: [
          Positioned.fill(child: Container(color: Colors.white)),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: CashierHeader(
                scaffoldKey: _scaffoldKey,
                bellKey: _bellKey,
                notificationCount: _notificationCount,
                onNotificationOpened: () {
                  setState(() => _notificationCount = 0);
                },
                cashierNameNotifier: cashierNameNotifier,
              ),
            ),
          ),
          Positioned.fill(
            top: 50,
            child: Column(children: [Expanded(child: _buildBody())]),
          ),
          Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomNav()),
        ],
      ),
      // bottomNavigationBar removed to mirror admin's floating nav
    );
  }

  void _onNavTap(int idx) {
    setState(() => _selectedIndex = idx);
    _scaffoldKey.currentState?.closeDrawer();
    AuditService.instance.log(
      event: 'tab_selected',
      data: {
        'screen': 'PosSale',
        'index': _selectedIndex,
        'label': [
          'POS Sale',
          'Inventory',
          'Reports',
          'Settings',
        ][_selectedIndex],
      },
    );
  }

  Future<void> _onLogout() async {
    _scaffoldKey.currentState?.closeDrawer();
    await FirebaseAuth.instance.signOut();
    widget.onLogout?.call();
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return const SalesTab();
      case 1:
        return const InventoryCashier();
      case 2:
        return const cashier_reports.ReportsTab();
      case 3:
        return const Center(child: Text('Settings Page'));
      default:
        return const SalesTab();
    }
  }
}

class CashierHeader extends StatelessWidget {
  final GlobalKey<ScaffoldState> scaffoldKey;
  final GlobalKey bellKey;
  final int notificationCount;
  final VoidCallback onNotificationOpened;
  final ValueNotifier<String> cashierNameNotifier;

  const CashierHeader({
    super.key,
    required this.scaffoldKey,
    required this.bellKey,
    required this.notificationCount,
    required this.onNotificationOpened,
    required this.cashierNameNotifier,
  });

  static const double _avatarRadius = 18;
  static const double _spacing = 8;
  static const String _profileAssetPath = 'assets/profile.png';

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _buildProfileSection(context),
        const Spacer(),
        _buildNotificationSection(),
      ],
    );
  }

  Widget _buildProfileSection(BuildContext context) {
    return GestureDetector(
      onTap: _openDrawer,
      child: Row(
        children: [
          _buildProfileAvatar(),
          const SizedBox(width: _spacing),
          ValueListenableBuilder<String>(
            valueListenable: cashierNameNotifier,
            builder: (context, name, _) {
              return Text(
                name,
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProfileAvatar() {
    return CircleAvatar(
      radius: _avatarRadius,
      backgroundColor: Colors.grey.shade300,
      child: _buildProfileImage(),
    );
  }

  Widget _buildProfileImage() {
    try {
      return Image.asset(
        _profileAssetPath,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return _buildFallbackAvatar();
        },
      );
    } catch (e) {
      return _buildFallbackAvatar();
    }
  }

  Widget _buildFallbackAvatar() {
    return const Icon(Icons.person, color: Colors.white, size: _avatarRadius);
  }

  Widget _buildNotificationSection() {
    return NotificationBell(
      bellKey: bellKey,
      notificationCount: notificationCount,
      onOpened: onNotificationOpened,
    );
  }

  void _openDrawer() {
    scaffoldKey.currentState?.openDrawer();
  }
}

class NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int index;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final Color selectedColor;
  final double iconSize;
  final EdgeInsets labelPadding;

  const NavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.index,
    required this.currentIndex,
    required this.onTap,
    required this.selectedColor,
    this.iconSize = 28,
    this.labelPadding = const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
  });

  @override
  Widget build(BuildContext context) {
    final bool isSelected = currentIndex == index;

    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? selectedColor.withOpacity(0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: iconSize,
                color: isSelected ? selectedColor : Colors.black38,
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) {
                  final offsetAnimation = Tween<Offset>(
                    begin: const Offset(0.0, 0.5),
                    end: Offset.zero,
                  ).animate(animation);
                  return SlideTransition(
                    position: offsetAnimation,
                    child: FadeTransition(opacity: animation, child: child),
                  );
                },
                child: isSelected
                    ? Container(
                        key: ValueKey(label),
                        margin: const EdgeInsets.only(top: 2),
                        decoration: BoxDecoration(
                          color: selectedColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: labelPadding,
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                            color: Colors.white,
                          ),
                        ),
                      )
                    : const SizedBox(key: ValueKey('empty')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Dummy/Static Sales Data
class SalesData {
  static int dailySalesGoal = 800;
  static int todaySales = 964;
  static List<Map<String, dynamic>> salesShifts = [
    {
      "shiftName": "Shift 1",
      "time": "6AM - 2PM",
      "count": "400 blocks",
      "expected": 410,
      "actual": 400,
      "presentStaff": ['Angela', 'John'],
      "color": Color(0xFF43EA7E),
      "gradient": [Color(0xFF43EA7E), Color(0xFF81E6C2)],
    },
    {
      "shiftName": "Shift 2",
      "time": "2PM - 10PM",
      "count": "50 blocks",
      "expected": 50,
      "actual": 50,
      "presentStaff": ['Mia'],
      "color": Color(0xFFFFB74D),
      "gradient": [Color(0xFFFFB74D), Color(0xFFFFD580)],
    },
    {
      "shiftName": "Shift 3",
      "time": "10PM - 6AM",
      "count": "38 blocks",
      "expected": 40,
      "actual": 38,
      "presentStaff": ['Sam', 'Lyn'],
      "color": Color(0xFF1976D2),
      "gradient": [Color(0xFF42A5F5), Color(0xFF1976D2)],
    },
  ];

  static Map<String, double> prices = {"Ice Block": 120.0, "Ice Cube": 50.0};

  static List<Map<String, dynamic>> salesHistory = [
    {"type": "Ice Block", "qty": 140, "amount": 12000},
    {"type": "Ice Cube", "qty": 75, "amount": 3750},
  ];

  static List<Map<String, dynamic>> inventory = [
    {"type": "Ice Block", "inStock": 140, "inProduction": 10},
    {"type": "Ice Cube", "inStock": 75, "inProduction": 8},
  ];
}

class SalesTab extends StatefulWidget {
  const SalesTab({super.key});
  @override
  State<SalesTab> createState() => _SalesTabState();
}

class _SalesTabState extends State<SalesTab> with TickerProviderStateMixin {
  static const Color _primaryColor = Color(0xFF4CAF50);

  late final AnimationController _progressController;
  late final Animation<double> _progressAnimation;
  // Mock Sales Today state (mirrors Production Today behavior)
  static const int _salesMax = 900;
  int _salesToday = 0;
  int _prevSalesToday = 0;
  int _salesDirection = 1; // 1 = increasing, -1 = decreasing
  late Timer _salesTimer;
  // Unified progress: track Blocks and Cubes separately, display whichever changed more recently
  static const int _blocksMax = 200;
  static const int _cubesMax = 200;
  int _blocksToday = 0;
  int _prevBlocksToday = 0;
  int _blocksDirection = 1;
  int _cubesToday = 0;
  int _prevCubesToday = 0;
  int _cubesDirection = 1;
  bool _activeIsBlocks = true;
  int _prevActiveValue = 0;
  int _activeValue = 0;
  double _prevActiveRatio = 0.0;
  double _activeRatio = 0.0;
  int _salesTodayBlocks = 0;
  // Inventory state mirroring Production tab
  final Random _rng = Random();
  final ValueNotifier<int> _uiTick = ValueNotifier<int>(0);
  late Timer _inventoryTimer;
  late final InventoryRepository _inventoryRepo;
  late final PriceRepository _priceRepo;
  late final SalesRepository _salesRepo;
  StreamSubscription<List<Map<String, dynamic>>>? _salesStreamSub;
  List<Map<String, dynamic>> _salesTx = [];
  Timer? _salesPollTimer;
  bool _isSalesFetching = false;
  StreamSubscription<Map<String, double>>? _priceStreamSub;
  Timer? _pricePollTimer;
  bool _isPriceFetching = false;
  DateTime? _pollSuspendUntil;
  List<Map<String, int>> _inventoryData = [
    {
      'inStock': 140,
      'prevInStock': 132,
      'inProduction': 10,
      'prevInProduction': 12,
    },
    {
      'inStock': 75,
      'prevInStock': 80,
      'inProduction': 8,
      'prevInProduction': 6,
    },
  ];

  // Delta-badge timing like Production tab
  static const Duration _deltaTTL = Duration(seconds: 4);
  final List<DateTime?> _stockChangeAt = [null, null];
  final List<DateTime?> _prodChangeAt = [null, null];
  // Mock production values to mirror Production tab's behavior
  Timer? _prodMockTimer;
  static const int _productionMax = 200;
  static const int _cubeProductionMax = 200;
  int _prodTodayMock = 0;
  int _prevProdTodayMock = 0;
  int _cubeProdMock = 0;
  int _prevCubeProdMock = 0;

  double get salesProgress => _salesMax == 0 ? 0.0 : _salesToday / _salesMax;

  String _manilaTimeNow() {
    final nowUtc = DateTime.now().toUtc();
    final manila = nowUtc.add(const Duration(hours: 8)); // GMT+8
    int hour = manila.hour;
    final minute = manila.minute;
    final ampm = hour >= 12 ? 'PM' : 'AM';
    hour = hour % 12;
    if (hour == 0) hour = 12;
    final mm = minute.toString().padLeft(2, '0');
    return '$hour:$mm $ampm';
  }

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    // Use controller directly for progress and animate between updates
    _progressAnimation = _progressController;

    // Initialize mock Sales Today and animate initial progress
    _salesToday = 100 + (Random().nextInt(41)); // 100..140
    _prevSalesToday = 0; // animate number from 0 -> initial on first load
    _progressController.value = 0.0;
    _progressController.animateTo(
      salesProgress.clamp(0.0, 1.0),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
    );

    // Initialize blocks/cubes values for unified bar
    _blocksToday = 80 + _rng.nextInt(61); // 80..140
    _prevBlocksToday = 0;
    _cubesToday = 60 + _rng.nextInt(61); // 60..120
    _prevCubesToday = 0;
    _activeIsBlocks = true;
    _prevActiveValue = _prevBlocksToday;
    _activeValue = _blocksToday;
    _prevActiveRatio = 0.0;
    _activeRatio = _blocksToday / _blocksMax;

    // Periodically update mock sales-today value up/down within 0.._salesMax
    _salesTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      final int step = 4 + _rng.nextInt(13); // 4..16
      if (_rng.nextInt(5) == 0) {
        _salesDirection *= -1; // occasionally flip direction
      }
      _prevSalesToday = _salesToday;
      _salesToday = (_salesToday + _salesDirection * step).clamp(0, _salesMax);
      if (_salesToday == 0 || _salesToday == _salesMax) {
        _salesDirection *= -1; // bounce at bounds
      }
      // Update blocks metric
      final int blockStep = 3 + _rng.nextInt(10);
      if (_rng.nextInt(6) == 0) _blocksDirection *= -1;
      _prevBlocksToday = _blocksToday;
      _blocksToday = (_blocksToday + _blocksDirection * blockStep).clamp(
        0,
        _blocksMax,
      );
      if (_blocksToday == 0 || _blocksToday == _blocksMax)
        _blocksDirection *= -1;
      // Update cubes metric
      final int cubeStep = 2 + _rng.nextInt(8);
      if (_rng.nextInt(6) == 0) _cubesDirection *= -1;
      _prevCubesToday = _cubesToday;
      _cubesToday = (_cubesToday + _cubesDirection * cubeStep).clamp(
        0,
        _cubesMax,
      );
      if (_cubesToday == 0 || _cubesToday == _cubesMax) _cubesDirection *= -1;

      // Decide which metric to show
      // Prefer the one with larger absolute change; if equal and any change occurred, toggle to show variety; if no change, keep current
      final int dBlocks = (_blocksToday - _prevBlocksToday).abs();
      final int dCubes = (_cubesToday - _prevCubesToday).abs();
      if (dBlocks == 0 && dCubes == 0) {
        // keep prior _activeIsBlocks
      } else if (dBlocks > dCubes) {
        _activeIsBlocks = true;
      } else if (dCubes > dBlocks) {
        _activeIsBlocks = false;
      } else {
        // tie but some change: flip to alternate
        _activeIsBlocks = !_activeIsBlocks;
      }
      _prevActiveValue = _activeIsBlocks ? _prevBlocksToday : _prevCubesToday;
      _activeValue = _activeIsBlocks ? _blocksToday : _cubesToday;
      _prevActiveRatio = _activeIsBlocks
          ? (_prevBlocksToday / _blocksMax)
          : (_prevCubesToday / _cubesMax);
      _activeRatio = _activeIsBlocks
          ? (_blocksToday / _blocksMax)
          : (_cubesToday / _cubesMax);

      final double newProgress = salesProgress.clamp(0.0, 1.0);
      _progressController.animateTo(
        newProgress,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutCubic,
      );
      _uiTick.value++;
      if (mounted) setState(() {});
    });

    // Initialize inventory previous values for first-load animation
    if (_inventoryData.isNotEmpty) {
      _inventoryData[0]['prevInStock'] = 0;
      _inventoryData[0]['prevInProduction'] = 0;
    }
    if (_inventoryData.length > 1) {
      _inventoryData[1]['prevInStock'] = 0;
      _inventoryData[1]['prevInProduction'] = 0;
    }

    // Initialize mock In Production from current table values (no random reseed)
    _prodTodayMock =
        (_inventoryData.isNotEmpty
                ? (_inventoryData[0]['inProduction'] ?? 0)
                : 0)
            .clamp(0, _productionMax);
    _prevProdTodayMock = _prodTodayMock;
    _cubeProdMock =
        (_inventoryData.length > 1
                ? (_inventoryData[1]['inProduction'] ?? 0)
                : 0)
            .clamp(0, _cubeProductionMax);
    _prevCubeProdMock = _cubeProdMock;
    if (_inventoryData.isNotEmpty) {
      _inventoryData[0]['prevInProduction'] = _prevProdTodayMock;
      _inventoryData[0]['inProduction'] = _prodTodayMock;
    }
    if (_inventoryData.length > 1) {
      _inventoryData[1]['prevInProduction'] = _prevCubeProdMock;
      _inventoryData[1]['inProduction'] = _cubeProdMock;
    }
    _prodMockTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      // Block production mock (increase-only)
      final int step = 4 + _rng.nextInt(13); // 4..16
      _prevProdTodayMock = _prodTodayMock;
      _prodTodayMock = (_prodTodayMock + step).clamp(0, _productionMax);
      // Cube production mock (increase-only)
      final int cubeStep = 3 + _rng.nextInt(10);
      _prevCubeProdMock = _cubeProdMock;
      _cubeProdMock = (_cubeProdMock + cubeStep).clamp(0, _cubeProductionMax);
      // Apply to table and mark delta timestamps
      if (_inventoryData.isNotEmpty) {
        _inventoryData[0]['prevInProduction'] = _prevProdTodayMock;
        _inventoryData[0]['inProduction'] = _prodTodayMock;
        if (_inventoryData[0]['inProduction'] !=
            _inventoryData[0]['prevInProduction']) {
          _prodChangeAt[0] = DateTime.now();
        }
      }
      if (_inventoryData.length > 1) {
        _inventoryData[1]['prevInProduction'] = _prevCubeProdMock;
        _inventoryData[1]['inProduction'] = _cubeProdMock;
        if (_inventoryData[1]['inProduction'] !=
            _inventoryData[1]['prevInProduction']) {
          _prodChangeAt[1] = DateTime.now();
        }
      }
      if (mounted) setState(() {});
      _uiTick.value++;
    });

    // Initialize repository with Authorization header (same source as Production)
    Future<void> _setupInventorySales() async {
      String? token;
      try {
        token = await FirebaseAuth.instance.currentUser?.getIdToken();
      } catch (_) {}
      _inventoryRepo = InventoryRepository(
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );
      await _fetchAndApplyInventorySales();
    }

    _setupInventorySales();
    _setupPrices();
    Future<void> _setupSalesHistory() async {
      String? token;
      try {
        token = await FirebaseAuth.instance.currentUser?.getIdToken();
      } catch (_) {}
      _salesRepo = SalesRepository(
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
        },
      );
      await _salesRepo.ensureTableMetadata();
      try {
        final list = await _salesRepo.fetchAllSales();
        _applySalesSnapshot(list);
      } catch (_) {}
      try {
        _salesStreamSub?.cancel();
        _salesStreamSub = _salesRepo.streamSalesHistory().listen((list) {
          if (!mounted) return;
          _applySalesSnapshot(list);
        });
      } catch (_) {}
      _salesPollTimer?.cancel();
      _salesPollTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
        if (!mounted) return;
        _fetchAndApplySalesHistory();
      });
    }

    _setupSalesHistory();
    _inventoryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _fetchAndApplyInventorySales();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Clear stale delta badges when entering Sales tab
    for (int i = 0; i < _stockChangeAt.length; i++) {
      _stockChangeAt[i] = null;
    }
    for (int i = 0; i < _prodChangeAt.length; i++) {
      _prodChangeAt[i] = null;
    }
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
    // 1) Try override
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
                // Filter out admin before saving
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

  @override
  void dispose() {
    _progressController.dispose();
    _salesTimer.cancel();
    _inventoryTimer.cancel();
    _prodMockTimer?.cancel();
    _salesStreamSub?.cancel();
    _salesPollTimer?.cancel();
    _priceStreamSub?.cancel();
    _pricePollTimer?.cancel();
    _uiTick.dispose();
    super.dispose();
  }

  void _applySalesSnapshot(List<Map<String, dynamic>> list) {
    final txList = <Map<String, dynamic>>[];
    int blocksTotal = 0;
    for (final r in list) {
      final type = (r['type'] ?? '').toString();
      final q = r['qty'];
      final a = r['amount'];
      final qty = q is num ? q.toInt() : int.tryParse(q?.toString() ?? '') ?? 0;
      final amt = a is num
          ? a.toDouble()
          : double.tryParse(a?.toString() ?? '') ?? 0.0;
      final unit = r['unitPrice'];
      final unitPrice = unit is num
          ? unit.toDouble()
          : double.tryParse(unit?.toString() ?? '') ?? 0.0;
      final tsRaw = r['timestamp']?.toString();
      DateTime? ts;
      try {
        ts = tsRaw != null ? DateTime.tryParse(tsRaw) : null;
      } catch (_) {}
      txList.add({
        'type': type,
        'qty': qty,
        'unitPrice': unitPrice,
        'amount': amt,
        'timestamp': ts?.millisecondsSinceEpoch ?? 0,
        'cashierId': r['cashierId']?.toString(),
      });
      if (type.toLowerCase().contains('block')) blocksTotal += qty;
    }
    txList.sort(
      (a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int),
    );
    if (!mounted) return;
    setState(() {
      _salesTx = txList;
      _salesTodayBlocks = blocksTotal;
    });
    _uiTick.value++;
  }

  Future<void> _fetchAndApplySalesHistory() async {
    if (_isSalesFetching) return;
    _isSalesFetching = true;
    try {
      final list = await _salesRepo.fetchAllSales();
      _applySalesSnapshot(list);
    } catch (_) {
      // ignore errors in fast poll
    } finally {
      _isSalesFetching = false;
    }
  }

  // Generate PDF report for inventory (same as Production tab behavior)
  Future<void> _generateInventoryReport() async {
    try {
      final pdf = pw.Document();
      final types = ['Ice Block', 'Ice Cube'];

      int totalStock = 0;
      int totalProduction = 0;
      for (int i = 0; i < _inventoryData.length; i++) {
        totalStock += _inventoryData[i]['inStock'] ?? 0;
        totalProduction += _inventoryData[i]['inProduction'] ?? 0;
      }

      pdf.addPage(
        pw.MultiPage(
          pageTheme: const pw.PageTheme(margin: pw.EdgeInsets.all(24)),
          build: (context) {
            return [
              pw.Header(
                level: 0,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Inventory Report',
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text('${DateTime.now()}'),
                  ],
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Summary',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Bullet(text: 'Total In Stock: $totalStock'),
              pw.Bullet(text: 'Total In Production: $totalProduction'),
              pw.SizedBox(height: 12),
              pw.Text(
                'Details',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Table.fromTextArray(
                headers: ['Type', 'In Stock', 'In Production'],
                data: List.generate(_inventoryData.length, (i) {
                  final row = _inventoryData[i];
                  final type = types[i % types.length];
                  return [
                    type,
                    (row['inStock'] ?? 0).toString(),
                    (row['inProduction'] ?? 0).toString(),
                  ];
                }),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFE0F2F1),
                ),
                cellAlignment: pw.Alignment.centerLeft,
                cellStyle: const pw.TextStyle(fontSize: 11),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2),
                  1: const pw.FlexColumnWidth(1),
                  2: const pw.FlexColumnWidth(1),
                },
              ),
            ];
          },
        ),
      );

      final bytes = await pdf.save();
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/inventory_report_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = await File(path).writeAsBytes(bytes, flush: true);
      await OpenFilex.open(file.path);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Report saved to: ${file.path}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to generate report: $e')));
    }
  }

  Future<void> _promptEditInStock(int index) async {
    if (index < 0 || index >= _inventoryData.length) return;
    final row = _inventoryData[index];
    final controller = TextEditingController(
      text: (row['inStock'] ?? 0).toString(),
    );
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: const Text(
            'Edit In Stock',
            style: TextStyle(
              color: Color(0xFF0F8AA3),
              fontWeight: FontWeight.w800,
            ),
          ),
          content: SizedBox(
            width: 260,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'Enter new value',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF0F8AA3),
              ),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F8AA3),
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
                elevation: 1,
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (result == null) return;
    final parsed = int.tryParse(result);
    if (parsed == null) return;
    setState(() {
      final curr = row['inStock'] ?? 0;
      row['prevInStock'] = curr;
      row['inStock'] = parsed.clamp(0, 999999);
      _stockChangeAt[index] = DateTime.now();
    });
    _pollSuspendUntil = DateTime.now().add(const Duration(seconds: 2));
    _uiTick.value++;
  }

  Future<void> _fetchAndApplyInventorySales() async {
    if (_pollSuspendUntil != null &&
        DateTime.now().isBefore(_pollSuspendUntil!)) {
      return;
    }
    try {
      final items = await _inventoryRepo.fetchInventory();
      if (items.isEmpty) return;
      final block = items.firstWhere(
        (e) => e.type == 'Ice Block',
        orElse: () => items.first,
      );
      final cube = items.firstWhere(
        (e) => e.type == 'Ice Cube',
        orElse: () => items.length > 1 ? items[1] : items.first,
      );
      setState(() {
        // Row 0: Ice Block
        final r0 = _inventoryData[0];
        final prevStock0 = r0['inStock'] ?? 0;
        r0['prevInStock'] = prevStock0;
        r0['inStock'] = block.inStock;
        if (r0['inStock'] != r0['prevInStock']) {
          _stockChangeAt[0] = DateTime.now();
        }
        final prevProd0 = r0['inProduction'] ?? 0;
        r0['prevInProduction'] = prevProd0;
        r0['inProduction'] = block.inProduction;
        if (r0['inProduction'] != r0['prevInProduction']) {
          _prodChangeAt[0] = DateTime.now();
        }

        // Row 1: Ice Cube
        final r1 = _inventoryData[1];
        final prevStock1 = r1['inStock'] ?? 0;
        r1['prevInStock'] = prevStock1;
        r1['inStock'] = cube.inStock;
        if (r1['inStock'] != r1['prevInStock']) {
          _stockChangeAt[1] = DateTime.now();
        }
        final prevProd1 = r1['inProduction'] ?? 0;
        r1['prevInProduction'] = prevProd1;
        r1['inProduction'] = cube.inProduction;
        if (r1['inProduction'] != r1['prevInProduction']) {
          _prodChangeAt[1] = DateTime.now();
        }
      });
      _uiTick.value++;
    } catch (_) {
      // ignore transient errors
    }
  }

  Future<void> _setupPrices() async {
    String? token;
    try {
      token = await FirebaseAuth.instance.currentUser?.getIdToken();
    } catch (_) {}
    _priceRepo = PriceRepository(
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Cache-Control': 'no-cache',
        'Pragma': 'no-cache',
      },
    );
    await _priceRepo.ensureTableMetadata();
    await _fetchAndApplyPrices();
    // Subscribe to live price updates via SSE
    try {
      _priceStreamSub?.cancel();
      _priceStreamSub = _priceRepo.streamPrices().listen((map) {
        if (map.isEmpty) return;
        if (!mounted) return;
        setState(() {
          map.forEach((k, v) => SalesData.prices[k] = v);
        });
        _uiTick.value++;
      });
    } catch (_) {}
    // Fast polling fallback for prices to feel instant
    _pricePollTimer?.cancel();
    _pricePollTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (!mounted) return;
      _fetchAndApplyPrices();
    });
  }

  Future<void> _fetchAndApplyPrices() async {
    if (_isPriceFetching) return;
    _isPriceFetching = true;
    try {
      final map = await _priceRepo.fetchAllPrices();
      if (map.isEmpty) return;
      setState(() {
        map.forEach((k, v) => SalesData.prices[k] = v);
      });
      _uiTick.value++;
    } catch (_) {
      // ignore transient errors
    } finally {
      _isPriceFetching = false;
    }
  }

  Future<void> _savePrice(String type, double price) async {
    try {
      await _priceRepo.ensureTableMetadata();
      final ok = await _priceRepo.upsertPrice(type: type, price: price);
      if (ok) {
        setState(() {
          SalesData.prices[type] = price;
        });
        _uiTick.value++;
      }
    } catch (_) {
      // ignore
    }
  }

  void _openInventoryPopup() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Inventory',
      pageBuilder: (_, __, ___) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Transform.scale(
              scale: 1.0,
              child: Container(
                width: MediaQuery.of(context).size.width * .9,
                constraints: const BoxConstraints(maxWidth: 520),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 30,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const SizedBox(width: 44),
                        const Expanded(
                          child: Text(
                            'Inventory',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F8AA3),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 44,
                          height: 44,
                          child: Center(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _generateInventoryReport,
                              child: Transform.translate(
                                offset: const Offset(0, -2),
                                child: Image.asset(
                                  'assets/report.png',
                                  width: 26,
                                  height: 26,
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0),
                      child: ValueListenableBuilder<int>(
                        valueListenable: _uiTick,
                        builder: (context, _, __) => _buildInventoryDataTable(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.center,
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F8AA3),
                          foregroundColor: Colors.white,
                          shape: const StadiumBorder(),
                          elevation: 1,
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 8,
                          ),
                          child: Text(
                            'Close',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        final curved = Curves.easeOutBack.transform(anim1.value);
        return Opacity(
          opacity: anim1.value,
          child: Transform.scale(
            scale: 0.9 + curved * 0.1,
            child: Transform.translate(
              offset: Offset(0, 40 * (1 - curved)),
              child: child,
            ),
          ),
        );
      },
    );
  }

  // Builds only the DataTable body used in the popup to avoid duplicating the card chrome
  Widget _buildInventoryDataTable() {
    final types = ['Ice Block', 'Ice Cube'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 18,
        headingRowHeight: 36,
        dividerThickness: 0.45,
        columns: [
          DataColumn(
            label: Padding(
              padding: EdgeInsets.only(left: 12.0),
              child: Text(
                'Type',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
          DataColumn(
            label: Builder(
              builder: (context) {
                final fontSize =
                    DefaultTextStyle.of(context).style.fontSize ?? 14.0;
                return Transform.translate(
                  offset: Offset(-(fontSize * 0.6 * 4), 0),
                  child: const Text(
                    'In Stock',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.black,
                    ),
                  ),
                );
              },
            ),
          ),
          DataColumn(
            label: Builder(
              builder: (context) {
                final fontSize =
                    DefaultTextStyle.of(context).style.fontSize ?? 14.0;
                return Transform.translate(
                  offset: Offset(-(fontSize * 0.6 * 4), 0),
                  child: const Text(
                    'In Production',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.black,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        rows: List.generate(_inventoryData.length, (i) {
          final row = _inventoryData[i];
          final type = types[i % types.length];
          return DataRow(
            cells: [
              DataCell(
                Builder(
                  builder: (context) {
                    final fontSize =
                        DefaultTextStyle.of(context).style.fontSize ?? 14.0;
                    final double blockSize = fontSize * 5.0;
                    final double iconBox = blockSize;
                    final double iconSize = blockSize;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: iconBox,
                          height: iconBox,
                          child: Center(
                            child: Transform.translate(
                              offset: Offset(-(fontSize * 0.6 * 4), 0),
                              child: Image.asset(
                                type.contains('Cube')
                                    ? 'assets/cube.png'
                                    : 'assets/ice_block.png',
                                width: iconSize,
                                height: iconSize,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          fit: FlexFit.loose,
                          child: Transform.translate(
                            offset: Offset(-(fontSize * 0.6 * 5), 0),
                            child: Text(
                              type,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.black87),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              DataCell(
                Builder(
                  builder: (context) {
                    final fontSize =
                        DefaultTextStyle.of(context).style.fontSize ?? 14.0;
                    return InkWell(
                      onTap: () => _promptEditInStock(i),
                      child: Transform.translate(
                        offset: Offset(-(fontSize * 0.6 * 4), 0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Tooltip(
                              message: 'Tap to edit',
                              child: _deltaValue(
                                row['prevInStock']!,
                                row['inStock']!,
                                lastChange: _stockChangeAt[i],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Tooltip(
                              message: 'Edit In Stock',
                              child: Icon(
                                Icons.edit,
                                size: 14,
                                color: Color(0xFF0F8AA3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              DataCell(
                Builder(
                  builder: (context) {
                    final fontSize =
                        DefaultTextStyle.of(context).style.fontSize ?? 14.0;
                    final int prevProd = row['prevInProduction']!;
                    final int currProd = row['inProduction']!;
                    return Transform.translate(
                      offset: Offset(-(fontSize * 0.6 * 3), 0),
                      child: _deltaValue(
                        prevProd,
                        currProd,
                        lastChange: _prodChangeAt[i],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  // Renders animated numeric value with delta arrow and +/- amount (Production-like)
  Widget _deltaValue(int prev, int curr, {DateTime? lastChange}) {
    final bool up = curr >= prev;
    final int delta = (curr - prev).abs();
    final bool hasDelta = curr != prev;
    final bool showDelta =
        hasDelta &&
        lastChange != null &&
        DateTime.now().difference(lastChange) <= _deltaTTL;
    // Cap displayed delta at 999
    const int cap = 999;
    final String deltaStr = delta > cap ? '999+' : '$delta';

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: prev.toDouble(), end: curr.toDouble()),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value.toInt().toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black),
              ),
              if (showDelta) ...[
                const SizedBox(width: 4),
                Icon(
                  up ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  color: up ? Colors.green : Colors.red,
                  size: 18,
                ),
                const SizedBox(width: 2),
                Text(
                  up ? '+$deltaStr' : '-$deltaStr',
                  style: TextStyle(
                    color: up ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'POS Sale',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: _primaryColor,
                    ),
                  ),
                  Text(
                    _manilaTimeNow(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _primaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSalesTodayCard(),
                  Transform.translate(
                    offset: const Offset(16, 23),
                    child: SizedBox(
                      width: 160,
                      child: _StackedSolidShiftCards(
                        onShiftTap: _openShiftDetails,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              _buildPriceStickyNotes(),
              const SizedBox(height: 32),
              _buildInventoryTable(),
              const SizedBox(height: 20),
              _buildSalesHistoryTable(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSalesTodayCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 165,
        height: 185,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.greenAccent.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withOpacity(0.33),
                shape: BoxShape.circle,
              ),
              child: Transform.scale(
                scale: 2.0,
                child: Image.asset(
                  'assets/sales.png',
                  width: 28,
                  height: 28,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.attach_money,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "Sales Today",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "${_salesTodayBlocks} Blocks",
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final maxW = constraints.maxWidth;
                final ratio = (_salesMax == 0)
                    ? 0.0
                    : (_salesTodayBlocks / _salesMax).clamp(0, 1).toDouble();
                return Container(
                  height: 4,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: maxW * ratio,
                      decoration: BoxDecoration(
                        color: Colors.greenAccent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
            Builder(
              builder: (context) {
                final percent = (_salesMax == 0)
                    ? 0
                    : ((_salesTodayBlocks * 100) / _salesMax)
                          .clamp(0, 100)
                          .toInt();
                return Text(
                  "$percent% of daily goal",
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceStickyNotes() {
    return Row(
      children: [
        Expanded(
          child: _StickyNotePrice(
            imagePath: 'assets/notes.png',
            label: 'Ice Block',
            price: SalesData.prices["Ice Block"] ?? 0.0,
            onValueChanged: (newPrice) {
              _savePrice('Ice Block', newPrice);
            },
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _StickyNotePrice(
            imagePath: 'assets/notes.png',
            label: 'Ice Cube',
            price: SalesData.prices["Ice Cube"] ?? 0.0,
            onValueChanged: (newPrice) {
              _savePrice('Ice Cube', newPrice);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSalesHistoryTable() {
    const headerTextStyle = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 14,
      color: Colors.black87,
    );
    const cellTextStyle = TextStyle(fontSize: 15, color: Colors.black);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 4,
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
                    'Sales History',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF43EA7E),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: (() {
                    const headerH = 36.0;
                    const rowH = 48.0;
                    const visible = 10;

                    final headerTable = DataTable(
                      columnSpacing: 26,
                      headingRowHeight: headerH,
                      dividerThickness: 0.45,
                      columns: [
                        DataColumn(
                          label: Container(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 12.0),
                              child: Text('Type', style: headerTextStyle),
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Container(
                            alignment: Alignment.center,
                            width: 70,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 14.0),
                              child: Text('Quantity', style: headerTextStyle),
                            ),
                          ),
                        ),
                        DataColumn(
                          label: Container(
                            alignment: Alignment.center,
                            width: 80,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: Text(
                                'Amount',
                                style: headerTextStyle,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ],
                      rows: const [],
                    );

                    final bodyTable = DataTable(
                      columnSpacing: 26,
                      dataRowMinHeight: 44,
                      dataRowMaxHeight: rowH,
                      headingRowHeight: 0,
                      dividerThickness: 0.45,
                      columns: [
                        DataColumn(label: const SizedBox.shrink()),
                        DataColumn(label: const SizedBox.shrink()),
                        DataColumn(label: const SizedBox.shrink()),
                      ],
                      rows: _salesTx.map((tx) {
                        final t = (tx['type'] ?? '').toString();
                        final qStr = (tx['qty'] ?? 0).toString();
                        final a = tx['amount'];
                        final amt = a is num
                            ? a.toDouble()
                            : double.tryParse(a?.toString() ?? '0') ?? 0.0;
                        final amtStr = amt.toStringAsFixed(2);
                        return DataRow(
                          cells: [
                            DataCell(
                              Container(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  t,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: cellTextStyle,
                                ),
                              ),
                            ),
                            DataCell(
                              Container(
                                alignment: Alignment.center,
                                width: 70,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 14.0),
                                  child: Text(
                                    qStr,
                                    textAlign: TextAlign.center,
                                    style: cellTextStyle,
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              Container(
                                alignment: Alignment.center,
                                width: 80,
                                child: Padding(
                                  padding: const EdgeInsets.only(left: 8.0),
                                  child: Text(
                                    '\u20B1$amtStr',
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: cellTextStyle,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    );

                    if (_salesTx.length > visible) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          headerTable,
                          SizedBox(
                            height: rowH * visible,
                            child: SingleChildScrollView(child: bodyTable),
                          ),
                        ],
                      );
                    } else {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [headerTable, bodyTable],
                      );
                    }
                  })(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInventoryTable() {
    final types = ['Ice Block', 'Ice Cube'];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 4,
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 28,
                  child: Stack(
                    children: [
                      const Align(
                        alignment: Alignment.center,
                        child: Text(
                          'Inventory',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F8AA3),
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12.0),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _openInventoryPopup,
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: Center(
                                child: Transform.translate(
                                  offset: const Offset(0, -2),
                                  child: Image.asset(
                                    'assets/maximize.png',
                                    width: 20,
                                    height: 20,
                                    color: Color(0xFF0F8AA3),
                                    colorBlendMode: BlendMode.srcIn,
                                    filterQuality: FilterQuality.high,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                  child: DataTable(
                    columnSpacing: 26,
                    headingRowHeight: 36,
                    dividerThickness: 0.45,
                    columns: [
                      DataColumn(
                        label: Container(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12.0),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                SizedBox(width: 10),
                                Text(
                                  'Type',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Container(
                          alignment: Alignment.center,
                          width: 70,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 14.0),
                            child: Transform.translate(
                              offset: const Offset(-66, 0),
                              child: const Text(
                                'In Stock',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Container(
                          alignment: Alignment.center,
                          width: 80,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8.0),
                            child: Transform.translate(
                              offset: const Offset(-75, 0),
                              child: const Text(
                                'In Production',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.black,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    rows: List.generate(_inventoryData.length, (i) {
                      final row = _inventoryData[i];
                      final type = types[i % types.length];
                      return DataRow(
                        cells: [
                          DataCell(
                            Container(
                              alignment: Alignment.centerLeft,
                              child: Builder(
                                builder: (context) {
                                  final style = const TextStyle(
                                    color: Colors.black87,
                                    fontWeight: FontWeight.normal,
                                  );
                                  final assetPath = type.contains('Cube')
                                      ? 'assets/cube.png'
                                      : 'assets/ice_block.png';
                                  final fontSize =
                                      DefaultTextStyle.of(
                                        context,
                                      ).style.fontSize ??
                                      14.0;
                                  final double blockSize = fontSize * 5.0;
                                  final double iconBox = blockSize;
                                  final double iconSize = blockSize;
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: iconBox,
                                        height: iconBox,
                                        child: Center(
                                          child: Transform.translate(
                                            offset: Offset(
                                              -(fontSize * 0.6 * 4),
                                              0,
                                            ),
                                            child: Image.asset(
                                              assetPath,
                                              width: iconSize,
                                              height: iconSize,
                                              filterQuality: FilterQuality.high,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Flexible(
                                        fit: FlexFit.loose,
                                        child: Transform.translate(
                                          offset: Offset(
                                            -(fontSize * 0.6 * 5),
                                            0,
                                          ),
                                          child: Text(
                                            type,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: style,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                          DataCell(
                            Builder(
                              builder: (context) {
                                final fontSize =
                                    DefaultTextStyle.of(
                                      context,
                                    ).style.fontSize ??
                                    14.0;
                                // Nudge In Stock value left by ~1 space (from 3 to 4)
                                return Transform.translate(
                                  offset: Offset(-(fontSize * 0.6 * 4), 0),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _deltaValue(
                                        row['prevInStock']!,
                                        row['inStock']!,
                                        lastChange: _stockChangeAt[i],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          DataCell(
                            Builder(
                              builder: (context) {
                                final fontSize =
                                    DefaultTextStyle.of(
                                      context,
                                    ).style.fontSize ??
                                    14.0;
                                final int prevProd = row['prevInProduction']!;
                                final int currProd = row['inProduction']!;
                                return Transform.translate(
                                  offset: Offset(-(fontSize * 0.6 * 4), 0),
                                  child: _deltaValue(
                                    prevProd,
                                    currProd,
                                    lastChange: _prodChangeAt[i],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openShiftDetails(Map<String, dynamic> shift) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final List<Color> g = List<Color>.from(
          (shift['gradient'] ?? const [Colors.teal, Colors.greenAccent])
              as List,
        );
        int sold = 0;
        try {
          final m = RegExp(
            r'(\d+)',
          ).firstMatch((shift['count'] ?? '').toString());
          if (m != null) sold = int.parse(m.group(1)!);
        } catch (_) {}
        final int expected = (shift['expected'] is num)
            ? (shift['expected'] as num).toInt()
            : int.tryParse('${shift['expected'] ?? ''}') ?? (sold + 10);
        final int actual = (shift['actual'] is num)
            ? (shift['actual'] as num).toInt()
            : int.tryParse('${shift['actual'] ?? ''}') ?? sold;
        final int discrepancy = actual - expected;
        final List<String> staff =
            (shift['presentStaff'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            [];
        return SafeArea(
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
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.white.withOpacity(0.18),
                            child: Padding(
                              padding: const EdgeInsets.all(2.0),
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
                              (shift['shiftName'] ?? 'Shift').toString(),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              (shift['time'] ?? '').toString(),
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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _MetricPill(
                            icon: Icons.shopping_bag_outlined,
                            label: 'Sold',
                            value: '$sold blocks',
                          ),
                          _MetricPill(
                            icon: Icons.precision_manufacturing_outlined,
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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                          if (snap.connectionState != ConnectionState.done) {
                            return const SizedBox(
                              height: 28,
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                            );
                          }
                          final names = snap.data ?? const <String>[];
                          if (names.isEmpty) {
                            return const Text(
                              'No staff present.',
                              style: TextStyle(color: Colors.white70),
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  for (final name in names)
                                    _StaffChip(
                                      initials: name.isNotEmpty
                                          ? name[0].toUpperCase()
                                          : '?',
                                      name: name,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () async {
                                    final current = await _getPresentStaff(
                                      shift,
                                    );
                                    await _showEditStaffDialog(
                                      ctx,
                                      shift,
                                      current,
                                    );
                                    if (mounted) setState(() {});
                                  },
                                  icon: const Icon(
                                    Icons.edit,
                                    color: Colors.white,
                                  ),
                                  label: const Text(
                                    'Edit',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
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
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
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
                                  fontWeight: FontWeight.w700,
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
                                style: TextStyle(color: Colors.white),
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
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
                          onPressed: () => Navigator.of(ctx).pop(),
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
  }

  Widget _buildShiftDetailContent(Map<String, dynamic> shift) {
    final discrepancy = (shift['actual'] ?? 0) - (shift['expected'] ?? 0);
    final gradient = shift['gradient'] is List<Color>
        ? shift['gradient']
        : [Colors.grey[200]!, Colors.white];
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.white.withOpacity(0.18),
                child: Padding(
                  padding: const EdgeInsets.all(2.0),
                  child: Image.asset(
                    'assets/shift.png',
                    width: 30,
                    height: 30,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Flexible(
                child: Text(
                  shift['shiftName'] ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                    color: Colors.white,
                    shadows: [Shadow(blurRadius: 5, color: Colors.black12)],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: Colors.white.withOpacity(0.1),
                ),
                child: Text(
                  shift['time'] ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.13),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceEvenly,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 21,
              runSpacing: 13,
              children: [
                _detailInfo(
                  Icons.shopping_bag,
                  "Sold",
                  shift['count'] ?? '',
                  Colors.white,
                ),
                _detailInfo(
                  Icons.new_releases,
                  "Expected",
                  '${shift['expected'] ?? '-'}',
                  Colors.white,
                ),
                _detailInfo(
                  Icons.verified,
                  "Actual",
                  '${shift['actual'] ?? '-'}',
                  Colors.white,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerLeft,
            child: const Text(
              "Present Staff",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 17,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: 8),
          StaffCards(staff: List<String>.from(shift['presentStaff'] ?? [])),
          const SizedBox(height: 14),
          if (discrepancy != 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
              margin: const EdgeInsets.only(bottom: 10, top: 2),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.83),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.white, size: 22),
                  const SizedBox(width: 12),
                  Text(
                    "Discrepancy: $discrepancy blocks",
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.redAccent,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        vertical: 0,
                        horizontal: 12,
                      ),
                    ),
                    icon: const Icon(Icons.report),
                    label: const Text("Report"),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: gradient[0],
                  shape: const StadiumBorder(),
                  elevation: 2,
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                  child: Text(
                    "Close",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailInfo(IconData icon, String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class StaffCards extends StatelessWidget {
  final List<String> staff;
  const StaffCards({super.key, required this.staff});

  @override
  Widget build(BuildContext context) {
    if (staff.isEmpty) {
      return const Text(
        "No staff present.",
        style: TextStyle(color: Colors.white70),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: staff.map((name) {
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.92),
            borderRadius: BorderRadius.circular(13),
            boxShadow: const [
              BoxShadow(
                blurRadius: 8,
                color: Colors.black12,
                offset: Offset(1, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                child: Text(name[0]),
              ),
              const SizedBox(width: 12),
              Text(
                name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        );
      }).toList(),
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
  final List<Map<String, dynamic>> _shifts = SalesData.salesShifts;
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
      setState(() {
        _topIndex = (_topIndex + 1) % _shifts.length;
        _isAnimating = false;
      });
      return mounted;
    });
  }

  @override
  Widget build(BuildContext context) {
    double verticalOffset = 16.0;
    List<int> indices = [
      _topIndex,
      (_topIndex + 1) % _shifts.length,
      (_topIndex + 2) % _shifts.length,
    ];
    List<Widget> stack = [];
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

class _StickyNotePrice extends StatelessWidget {
  final String imagePath;
  final String label;
  final double price;
  final ValueChanged<double> onValueChanged;

  const _StickyNotePrice({
    required this.imagePath,
    required this.label,
    required this.price,
    required this.onValueChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        showGeneralDialog(
          context: context,
          barrierDismissible: true,
          barrierLabel: "",
          pageBuilder: (_, __, ___) => const SizedBox.shrink(),
          transitionBuilder: (_, anim, __, ___) {
            return Transform.scale(
              scale: Curves.elasticOut.transform(anim.value),
              child: Opacity(
                opacity: anim.value,
                child: _StickyNoteEditDialog(
                  label: label,
                  price: price,
                  onValueChanged: onValueChanged,
                ),
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 350),
        );
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: 1.2,
            child: Image.asset(
              imagePath,
              fit: BoxFit.contain,
              alignment: Alignment.topCenter,
              errorBuilder: (context, error, stackTrace) => Container(
                decoration: BoxDecoration(
                  color: Colors.yellow[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Icon(Icons.note, size: 50, color: Colors.brown),
                ),
              ),
            ),
          ),
          Positioned(
            top: 38,
            left: 0,
            right: 0,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 19,
                color: Colors.brown[700],
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            child: Container(
              alignment: Alignment.center,
              margin: const EdgeInsets.only(top: 28),
              child: Text(
                "₱${price.toStringAsFixed(2)}",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 26,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StickyNoteEditDialog extends StatefulWidget {
  final String label;
  final double price;
  final ValueChanged<double> onValueChanged;

  const _StickyNoteEditDialog({
    required this.label,
    required this.price,
    required this.onValueChanged,
  });

  @override
  State<_StickyNoteEditDialog> createState() => _StickyNoteEditDialogState();
}

class _StickyNoteEditDialogState extends State<_StickyNoteEditDialog> {
  bool isEditing = false;
  late TextEditingController controller;
  late double localPrice;

  @override
  void initState() {
    super.initState();
    localPrice = widget.price;
    controller = TextEditingController(text: localPrice.toStringAsFixed(2));
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.only(
        top: 10,
        left: 20,
        right: 20,
        bottom: 40,
      ),
      child: Center(
        child: Container(
          width: 310,
          height: 250,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            image: DecorationImage(
              image: const AssetImage('assets/notes.png'),
              fit: BoxFit.contain,
              alignment: Alignment.topCenter,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 18,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                top: 70,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 24,
                      color: Colors.brown[700],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 42,
                right: 72,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(100),
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      child: const Icon(Icons.close, size: 20),
                    ),
                  ),
                ),
              ),
              Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: !isEditing
                      ? Row(
                          key: const ValueKey('display'),
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              "₱${localPrice.toStringAsFixed(2)}",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 36,
                                color: Colors.black,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => setState(() => isEditing = true),
                              child: const Icon(
                                Icons.edit,
                                size: 27,
                                color: Colors.green,
                              ),
                            ),
                          ],
                        )
                      : Row(
                          key: const ValueKey('editing'),
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 120,
                              alignment: Alignment.center,
                              child: TextField(
                                controller: controller,
                                textAlign: TextAlign.center,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                style: const TextStyle(
                                  fontSize: 36,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  prefixText: "₱",
                                  prefixStyle: TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  border: UnderlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  localPrice =
                                      double.tryParse(controller.text) ??
                                      widget.price;
                                  isEditing = false;
                                  widget.onValueChanged(localPrice);
                                });
                              },
                              child: const Icon(
                                Icons.save,
                                color: Colors.green,
                                size: 27,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
