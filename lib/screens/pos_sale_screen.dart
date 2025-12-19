import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/audit_service.dart';
import 'profile_tab.dart';
import 'settings_tab.dart';
import '../widgets/notification/notification_bell.dart';
import 'inventory_cashier.dart';
import 'reports_tab_cashier.dart' as cashier_reports;
import 'cashier_sale_tab.dart' as cashier_pos;

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
  String? _lastResolvedDrawerAvatarUrl;
  ImageProvider? _drawerAvatarProvider;
  bool _isDrawerOpen = false;
  String? _pendingAvatarUrl;

  @override
  void initState() {
    super.initState();
    _ensureCashier();
    _warmUpAvatar();
  }

  /// Pre-resolve and cache the avatar once on startup to avoid first drawer-open flicker.
  Future<void> _warmUpAvatar() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (_drawerAvatarProvider == null) {
          setState(() {
            _drawerAvatarProvider = const AssetImage('assets/profile.png');
          });
        }
        return;
      }

      Map<String, dynamic>? data;
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        data = snap.data();
      } catch (_) {}

      final url = _resolveDrawerAvatar(user: user, data: data);

      // If nothing resolvable and no social bound, keep asset and exit
      final hasSocial = user.providerData.any(
        (p) => p.providerId == 'facebook.com' || p.providerId == 'google.com',
      );
      if ((url == null || url.isEmpty) && !hasSocial) {
        if (_drawerAvatarProvider == null) {
          setState(() {
            _drawerAvatarProvider = const AssetImage('assets/profile.png');
          });
        }
        return;
      }

      // Determine desired URL (resolved -> provider photo)
      String? providerPhoto;
      try {
        final fb = user.providerData.firstWhere(
          (p) => p.providerId == 'facebook.com',
        );
        providerPhoto = fb.photoURL ?? providerPhoto;
      } catch (_) {}
      try {
        if (providerPhoto == null) {
          final g = user.providerData.firstWhere(
            (p) => p.providerId == 'google.com',
          );
          providerPhoto = g.photoURL ?? providerPhoto;
        }
      } catch (_) {}

      final desired = (url != null && url.isNotEmpty) ? url : providerPhoto;
      if (desired == null || desired.isEmpty) {
        if (_drawerAvatarProvider == null) {
          setState(() {
            _drawerAvatarProvider = const AssetImage('assets/profile.png');
          });
        }
        return;
      }

      final next = NetworkImage(desired);
      if (mounted) {
        final current = _drawerAvatarProvider;
        final currentUrl = (current is NetworkImage) ? current.url : null;
        if (currentUrl != desired) {
          setState(() {
            _drawerAvatarProvider = next;
            _lastResolvedDrawerAvatarUrl = desired;
          });
        } else {
          _lastResolvedDrawerAvatarUrl = desired;
        }
      }
      try {
        // ignore: unawaited_futures
        precacheImage(next, context);
      } catch (_) {}
    } catch (_) {}
  }

  // Resolve avatar URL using cashier-specific Firestore fields
  String? _resolveDrawerAvatar({
    required User user,
    required Map<String, dynamic>? data,
  }) {
    final fbBound = (data?['facebookBoundCashier'] as bool?) == true;
    final gBound = (data?['googleBoundCashier'] as bool?) == true;
    final anyBound = fbBound || gBound;
    final firestorePhoto =
        data?['profilePhotoCashier'] as String? ??
        data?['profilePhoto'] as String?; // allow legacy
    // Always prefer uploaded photo if present, even if no social bound
    if (firestorePhoto != null && firestorePhoto.isNotEmpty)
      return firestorePhoto;
    try {
      if (fbBound) {
        final fb = user.providerData.firstWhere(
          (p) => p.providerId == 'facebook.com',
        );
        if (fb.photoURL != null && fb.photoURL!.isNotEmpty) return fb.photoURL;
      }
    } catch (_) {}
    try {
      if (gBound) {
        final g = user.providerData.firstWhere(
          (p) => p.providerId == 'google.com',
        );
        if (g.photoURL != null && g.photoURL!.isNotEmpty) return g.photoURL;
      }
    } catch (_) {}
    return null;
  }

  Widget _drawerAvatar(double size) {
    Widget buildAvatar(String? url) {
      final fallback = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.blueGrey[100],
        ),
        child: Icon(
          Icons.person,
          color: Colors.blueGrey[300],
          size: size * 0.5,
        ),
      );

      // If we already have a provider, keep showing it across opens to avoid regressions
      if (_drawerAvatarProvider != null) {
        return ClipOval(
          child: Image(
            image: _drawerAvatarProvider!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        );
      }

      // If a resolved URL exists (uploaded or social), apply immediately and precache in background
      if (url != null && url.isNotEmpty) {
        final next = NetworkImage(url);
        _drawerAvatarProvider = next;
        _lastResolvedDrawerAvatarUrl = url;
        try {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            precacheImage(next, context);
          });
        } catch (_) {}
        return ClipOval(
          child: Image(
            image: _drawerAvatarProvider!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        );
      }

      // If url empty, decide based on social bound
      if (url == null || url.isEmpty) {
        final u = FirebaseAuth.instance.currentUser;
        final hasSocial =
            u?.providerData.any(
              (p) =>
                  p.providerId == 'facebook.com' ||
                  p.providerId == 'google.com',
            ) ??
            false;
        if (hasSocial) {
          // Count bound providers and pick a single provider photo only when exactly one is bound
          int boundCount = 0;
          String? providerPhoto;
          try {
            final fb = u?.providerData.firstWhere(
              (p) => p.providerId == 'facebook.com',
            );
            if (fb != null) {
              boundCount++;
              providerPhoto = fb.photoURL ?? providerPhoto;
            }
          } catch (_) {}
          try {
            final g = u?.providerData.firstWhere(
              (p) => p.providerId == 'google.com',
            );
            if (g != null) {
              boundCount++;
              providerPhoto = providerPhoto ?? g.photoURL;
            }
          } catch (_) {}

          if (_lastResolvedDrawerAvatarUrl != null &&
              _lastResolvedDrawerAvatarUrl!.isNotEmpty) {
            return ClipOval(
              child: Image.network(
                _lastResolvedDrawerAvatarUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
              ),
            );
          }
          if (boundCount == 1 &&
              providerPhoto != null &&
              providerPhoto.isNotEmpty) {
            return ClipOval(
              child: Image.network(
                providerPhoto,
                width: size,
                height: size,
                fit: BoxFit.cover,
              ),
            );
          }
        }
        return ClipOval(
          child: Image.asset(
            'assets/profile.png',
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => fallback,
          ),
        );
      }

      return ClipOval(
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            final u = FirebaseAuth.instance.currentUser;
            final hasSocial =
                u?.providerData.any(
                  (p) =>
                      p.providerId == 'facebook.com' ||
                      p.providerId == 'google.com',
                ) ??
                false;
            if (hasSocial &&
                _lastResolvedDrawerAvatarUrl != null &&
                _lastResolvedDrawerAvatarUrl!.isNotEmpty) {
              return ClipOval(
                child: Image.network(
                  _lastResolvedDrawerAvatarUrl!,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                ),
              );
            }
            return ClipOval(
              child: Image.asset(
                'assets/profile.png',
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback,
              ),
            );
          },
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            final u = FirebaseAuth.instance.currentUser;
            final hasSocial =
                u?.providerData.any(
                  (p) =>
                      p.providerId == 'facebook.com' ||
                      p.providerId == 'google.com',
                ) ??
                false;
            if (hasSocial &&
                _lastResolvedDrawerAvatarUrl != null &&
                _lastResolvedDrawerAvatarUrl!.isNotEmpty) {
              return ClipOval(
                child: Image.network(
                  _lastResolvedDrawerAvatarUrl!,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                ),
              );
            }
            return ClipOval(
              child: Image.asset(
                'assets/profile.png',
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback,
              ),
            );
          },
        ),
      );
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, authSnap) {
        final user = authSnap.data;
        if (user == null) return buildAvatar(null);
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, snap) {
            final data = snap.data?.data();
            final url = _resolveDrawerAvatar(user: user, data: data);
            if (url != null && url.isNotEmpty)
              _lastResolvedDrawerAvatarUrl = url;
            final desiredUrl = (url != null && url.isNotEmpty)
                ? url
                : (_lastResolvedDrawerAvatarUrl != null &&
                      _lastResolvedDrawerAvatarUrl!.isNotEmpty)
                ? _lastResolvedDrawerAvatarUrl
                : null;
            if (desiredUrl != null && desiredUrl.isNotEmpty) {
              final next = NetworkImage(desiredUrl);
              final current = _drawerAvatarProvider;
              final currentUrl = (current is NetworkImage) ? current.url : null;
              if (currentUrl != desiredUrl) {
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  try {
                    await precacheImage(next, context);
                    if (!mounted) return;
                    final nowUrl = (_drawerAvatarProvider is NetworkImage)
                        ? (_drawerAvatarProvider as NetworkImage).url
                        : null;
                    if (nowUrl == desiredUrl) return;
                    setState(() => _drawerAvatarProvider = next);
                  } catch (_) {}
                });
              }
            } else {
              // No URL: force asset if no social accounts are bound, so removed uploads disappear instantly
              final u = FirebaseAuth.instance.currentUser;
              final hasSocial =
                  u?.providerData.any(
                    (p) =>
                        p.providerId == 'facebook.com' ||
                        p.providerId == 'google.com',
                  ) ??
                  false;
              if (!hasSocial) {
                if (!(_drawerAvatarProvider is AssetImage)) {
                  _drawerAvatarProvider = const AssetImage(
                    'assets/profile.png',
                  );
                  if (mounted) setState(() {});
                }
              } else {
                if (_drawerAvatarProvider == null) {
                  _drawerAvatarProvider = const AssetImage(
                    'assets/profile.png',
                  );
                }
              }
            }
            return buildAvatar(desiredUrl);
          },
        );
      },
    );
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
      onDrawerChanged: (isOpen) async {
        _isDrawerOpen = isOpen;
        if (isOpen) {
          try {
            await FirebaseAuth.instance.currentUser?.reload();
          } catch (_) {}
          if (_lastResolvedDrawerAvatarUrl != null &&
              _lastResolvedDrawerAvatarUrl!.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              precacheImage(
                NetworkImage(_lastResolvedDrawerAvatarUrl!),
                context,
              );
            });
          }
          // Actively resolve latest desired URL and apply immediately if changed
          try {
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              Map<String, dynamic>? data;
              try {
                final snap = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .get();
                data = snap.data();
              } catch (_) {}

              final resolved = _resolveDrawerAvatar(user: user, data: data);
              String? providerPhoto;
              try {
                final fb = user.providerData.firstWhere(
                  (p) => p.providerId == 'facebook.com',
                );
                providerPhoto = fb.photoURL ?? providerPhoto;
              } catch (_) {}
              try {
                if (providerPhoto == null) {
                  final g = user.providerData.firstWhere(
                    (p) => p.providerId == 'google.com',
                  );
                  providerPhoto = g.photoURL ?? providerPhoto;
                }
              } catch (_) {}

              final desiredUrl = (resolved != null && resolved.isNotEmpty)
                  ? resolved
                  : (_lastResolvedDrawerAvatarUrl != null &&
                        _lastResolvedDrawerAvatarUrl!.isNotEmpty)
                  ? _lastResolvedDrawerAvatarUrl
                  : providerPhoto;

              if (desiredUrl != null && desiredUrl.isNotEmpty) {
                final next = NetworkImage(desiredUrl);
                final current = _drawerAvatarProvider;
                final currentUrl = (current is NetworkImage)
                    ? current.url
                    : null;
                if (currentUrl != desiredUrl) {
                  if (mounted) {
                    setState(() {
                      _drawerAvatarProvider = next;
                      _lastResolvedDrawerAvatarUrl = desiredUrl;
                      _pendingAvatarUrl = null;
                    });
                  }
                  try {
                    // ignore: unawaited_futures
                    precacheImage(next, context);
                  } catch (_) {}
                }
              }
            }
          } catch (_) {}
        } else {
          // Drawer just closed: if there was a pending avatar URL captured while open, apply it now
          final desired = _pendingAvatarUrl;
          if (desired != null && desired.isNotEmpty) {
            try {
              final next = NetworkImage(desired);
              await precacheImage(next, context);
              if (mounted) {
                setState(() {
                  _drawerAvatarProvider = next;
                  _lastResolvedDrawerAvatarUrl = desired;
                  _pendingAvatarUrl = null;
                });
              }
            } catch (_) {
              _pendingAvatarUrl = null;
            }
          }
        }
      },
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
                      child: _drawerAvatar(80),
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
                      role: 'cashier',
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
        return const cashier_pos.CashierSalesTab();
      case 1:
        return const InventoryCashier();
      case 2:
        return const cashier_reports.ReportsTab();
      case 3:
        return const Center(child: Text('Settings Page'));
      default:
        return const cashier_pos.CashierSalesTab();
    }
  }
}

class CashierHeader extends StatefulWidget {
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

  @override
  State<CashierHeader> createState() => _CashierHeaderState();
}

class _CashierHeaderState extends State<CashierHeader> {
  static const double _avatarRadius = 18;
  static const double _spacing = 8;
  static const String _profileAssetPath = 'assets/profile.png';

  ImageProvider? _avatarProvider;
  String? _lastUrl;

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
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    return GestureDetector(
      onTap: _openDrawer,
      child: Row(
        children: [
          if (uid == null)
            _buildProfileAvatar()
          else
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .snapshots(),
              builder: (context, snapshot) {
                final data = snapshot.data?.data();
                final photoCashier = data?['profilePhotoCashier'] as String?;
                final fbFlag = data?['facebookBoundCashier'] as bool?;
                final gFlag = data?['googleBoundCashier'] as bool?;
                final flagsPresent = fbFlag != null || gFlag != null;

                bool isFacebookBound = false;
                bool isGoogleBound = false;
                String? providerPhoto;

                if (flagsPresent) {
                  isFacebookBound = fbFlag == true;
                  isGoogleBound = gFlag == true;
                  if (isFacebookBound) {
                    try {
                      final fb = user!.providerData.firstWhere(
                        (p) => p.providerId == 'facebook.com',
                      );
                      providerPhoto = fb.photoURL ?? providerPhoto;
                    } catch (_) {}
                  }
                  if (isGoogleBound && providerPhoto == null) {
                    try {
                      final g = user!.providerData.firstWhere(
                        (p) => p.providerId == 'google.com',
                      );
                      providerPhoto = g.photoURL ?? providerPhoto;
                    } catch (_) {}
                  }
                } else {
                  for (final p in user!.providerData) {
                    if (p.providerId == 'facebook.com') {
                      isFacebookBound = true;
                      providerPhoto = p.photoURL ?? providerPhoto;
                    }
                    if (p.providerId == 'google.com') {
                      isGoogleBound = true;
                      providerPhoto = providerPhoto ?? p.photoURL;
                    }
                  }
                }
                final noneLinked =
                    !(isFacebookBound || isGoogleBound) && flagsPresent;

                String? desiredUrl;
                if (!noneLinked || !flagsPresent) {
                  final firestorePhoto =
                      (photoCashier != null && photoCashier.isNotEmpty)
                      ? photoCashier
                      : data?['profilePhoto'] as String?; // legacy fallback
                  desiredUrl =
                      (firestorePhoto != null && firestorePhoto.isNotEmpty)
                      ? firestorePhoto
                      : providerPhoto;
                }

                if (desiredUrl != null && desiredUrl.isNotEmpty) {
                  if (_lastUrl != desiredUrl) _lastUrl = desiredUrl;
                  final next = NetworkImage(desiredUrl);
                  final current = _avatarProvider;
                  final currentUrl = (current is NetworkImage)
                      ? current.url
                      : null;
                  if (currentUrl != desiredUrl) {
                    WidgetsBinding.instance.addPostFrameCallback((_) async {
                      try {
                        await precacheImage(next, context);
                        if (!mounted) return;
                        final nowUrl = (_avatarProvider is NetworkImage)
                            ? (_avatarProvider as NetworkImage).url
                            : null;
                        if (nowUrl == desiredUrl) return;
                        setState(() {
                          _avatarProvider = next;
                        });
                      } catch (_) {}
                    });
                  }
                } else {
                  if (_avatarProvider == null) {
                    _avatarProvider = const AssetImage(_profileAssetPath);
                  } else if (noneLinked && _avatarProvider is NetworkImage) {
                    _avatarProvider = const AssetImage(_profileAssetPath);
                  }
                }

                return _buildProfileAvatar();
              },
            ),
          const SizedBox(width: _spacing),
          if (uid == null)
            ValueListenableBuilder<String>(
              valueListenable: widget.cashierNameNotifier,
              builder: (context, name, _) => _buildNameText(name),
            )
          else
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .snapshots(),
              builder: (context, snapshot) {
                final data = snapshot.data?.data();
                final name =
                    (data?['name'] as String?) ??
                    widget.cashierNameNotifier.value;
                return _buildNameText(name);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildProfileAvatar() {
    final bg = Colors.grey.shade300;
    return CircleAvatar(
      radius: _avatarRadius,
      backgroundColor: bg,
      child: ClipOval(
        child: Image(
          image: _avatarProvider ?? const AssetImage(_profileAssetPath),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          width: _avatarRadius * 2,
          height: _avatarRadius * 2,
        ),
      ),
    );
  }

  Widget _buildNameText(String name) {
    return Text(
      name,
      style: const TextStyle(
        color: Colors.black87,
        fontWeight: FontWeight.bold,
        fontSize: 16,
      ),
    );
  }

  Widget _buildNotificationSection() {
    return NotificationBell(
      bellKey: widget.bellKey,
      notificationCount: widget.notificationCount,
      onOpened: widget.onNotificationOpened,
    );
  }

  void _openDrawer() {
    widget.scaffoldKey.currentState?.openDrawer();
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
