import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../screens/auth_screen.dart';
import 'home_tab.dart';
import 'production_tab.dart';
import 'sales_tab.dart';
import 'monitoring_tab.dart';
import 'reports_tab.dart';
import '../users/admin_header.dart';
import 'profile_tab.dart';
import 'settings_tab.dart';
import '../screens/register_cashier_admin.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onLogout;

  const DashboardScreen({super.key, this.onLogout});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final GlobalKey _bellKey = GlobalKey();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();
  int _currentIndex = 0;
  int _notificationCount = 3;
  final ValueNotifier<String> adminNameNotifier = ValueNotifier<String>('Admin');
  static const Color bluerose = Color(0xFF24A8D8);

  final List<Widget> _screens = const [
    HomeTab(),
    ProductionTab(),
    SalesTab(),
    MonitoringTab(),
    ReportsTab(),
  ];

  @override
  void initState() {
    super.initState();
    _setFullScreen();
    _loadAdminName();
  }

  @override
  void dispose() {
    _exitFullScreen();
    adminNameNotifier.dispose();
    super.dispose();
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

  void _onNavTap(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  void _logout() {
    if (widget.onLogout != null) widget.onLogout!();
  }

  Future<void> _loadAdminName() async {
    final prefs = await SharedPreferences.getInstance();
    adminNameNotifier.value = prefs.getString('admin_display_name') ?? 'Admin';
  }

  @override
  Widget build(BuildContext context) {
    _setFullScreen();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.white,
        appBar: null,
        drawer: Drawer(
          child: Column(
            children: [
              Container(
                height: 160,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFE0F7FA), Color(0xFFB2EBF2), Color(0xFF80DEEA)],
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
                              offset: Offset(0, 4),
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
                                child: Icon(Icons.person, color: Colors.blueGrey[300], size: 40),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ValueListenableBuilder<String>(
                        valueListenable: adminNameNotifier,
                        builder: (context, name, _) {
                          return Text(
                            name,
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF006064)),
                          );
                        },
                      ),
                      const Text(
                        "OIP Sentinel",
                        style: TextStyle(fontSize: 14, color: Color(0xFF00838F)),
                      ),
                    ],
                  ),
                ),
              ),
              ListTile(
                leading: Icon(Icons.person, color: Color(0xFF00838F)),
                title: Text("Profile", style: TextStyle(color: Color(0xFF006064))),
                onTap: () async {
                  Navigator.pop(context);
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => ProfileTab(adminNameNotifier: adminNameNotifier)),
                  );
                  _loadAdminName();
                },
              ),
              ListTile(
                leading: Icon(Icons.person_add, color: Color(0xFF00838F)),
                title: Text("Register Cashier", style: TextStyle(color: Color(0xFF006064))),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => RegisterCashierAdminScreen()),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.settings, color: Color(0xFF00838F)),
                title: Text("Settings", style: TextStyle(color: Color(0xFF006064))),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const SettingsTab()),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.logout, color: Color(0xFF00838F)),
                title: Text("Logout", style: TextStyle(color: Color(0xFF006064))),
                onTap: _logout,
              ),
            ],
          ),
        ),
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
                child: AdminHeader(
                  scaffoldKey: _scaffoldKey,
                  bellKey: _bellKey,
                  notificationCount: _notificationCount,
                  onNotificationOpened: () {
                    setState(() => _notificationCount = 0);
                  },
                  adminNameNotifier: adminNameNotifier,
                ),
              ),
            ),
            Positioned.fill(
              top: 50,
              child: Column(
                children: [Expanded(child: _screens[_currentIndex])],
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                top: false,
                left: true,
                right: true,
                bottom: true,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        NavItem(
                          icon: Icons.home,
                          label: 'Home',
                          index: 0,
                          currentIndex: _currentIndex,
                          onTap: _onNavTap,
                          selectedColor: bluerose,
                          iconSize: 24,
                          labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        ),
                        NavItem(
                          icon: Icons.inventory,
                          label: 'Production',
                          index: 1,
                          currentIndex: _currentIndex,
                          onTap: _onNavTap,
                          selectedColor: bluerose,
                          iconSize: 24,
                          labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        ),
                        NavItem(
                          icon: Icons.point_of_sale,
                          label: 'Sales',
                          index: 2,
                          currentIndex: _currentIndex,
                          onTap: _onNavTap,
                          selectedColor: bluerose,
                          iconSize: 24,
                          labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        ),
                        NavItem(
                          icon: Icons.monitor_heart,
                          label: 'Monitoring',
                          index: 3,
                          currentIndex: _currentIndex,
                          onTap: _onNavTap,
                          selectedColor: bluerose,
                          iconSize: 24,
                          labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        ),
                        NavItem(
                          icon: Icons.analytics,
                          label: 'Reports',
                          index: 4,
                          currentIndex: _currentIndex,
                          onTap: _onNavTap,
                          selectedColor: bluerose,
                          iconSize: 24,
                          labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
            color: isSelected ? selectedColor.withOpacity(0.15) : Colors.transparent,
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
