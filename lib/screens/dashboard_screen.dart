import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/auth_screen.dart';
import 'home_tab.dart';
import 'production_tab.dart';
import 'sales_tab.dart';
import 'monitoring_tab.dart';
import 'admin_reports_tab.dart';
import '../users/admin_header.dart';
import 'profile_tab.dart';
import 'settings_tab.dart';
import '../screens/register_cashier_admin.dart';
import '../services/audit_service.dart';
import '../screens/audit_trail_screen.dart';

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
  final ValueNotifier<String> adminNameNotifier = ValueNotifier<String>(
    'Admin',
  );
  static const Color bluerose = Color(0xFF24A8D8);

  String? _lastResolvedDrawerAvatarUrl;
  ImageProvider? _drawerAvatarProvider;
  bool _isDrawerOpen = false;
  String? _pendingAvatarUrl;

  final List<Widget> _screens = const [
    HomeTab(),
    ProductionTab(),
    SalesTab(),
    MonitoringTab(),
    AdminReportsTab(),
  ];

  @override
  void initState() {
    super.initState();
    _setFullScreen();
    _loadAdminName();
    _ensureAdmin();
    _warmUpAvatar();
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
    AuditService.instance.log(
      event: 'tab_selected',
      data: {
        'screen': 'Dashboard',
        'index': index,
        'label': [
          'Home',
          'Production',
          'Sales',
          'Monitoring',
          'Reports',
        ][index],
      },
    );
  }

  void _logout() {
    if (widget.onLogout != null) widget.onLogout!();
  }

  Future<void> _ensureAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role');
    if (role != 'admin') {
      if (mounted) {
        await AuditService.instance.log(
          event: 'access_denied',
          data: {
            'screen': 'Dashboard',
            'required_role': 'admin',
            'actual_role': role,
          },
        );
        if (widget.onLogout != null) widget.onLogout!();
      }
    }
  }

  Future<void> _loadAdminName() async {
    final prefs = await SharedPreferences.getInstance();
    adminNameNotifier.value = prefs.getString('admin_display_name') ?? 'Admin';
  }

  /// Pre-resolve and cache the avatar once on startup to avoid first drawer-open flicker.
  Future<void> _warmUpAvatar() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        // Default to asset when no user yet
        if (_drawerAvatarProvider == null) {
          setState(() {
            _drawerAvatarProvider = const AssetImage('assets/profile.png');
          });
        }
        return;
      }

      // Fetch Firestore user doc once
      Map<String, dynamic>? data;
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        data = snap.data();
      } catch (_) {}

      // Resolve best URL using the same logic path
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

      // Determine a desired URL (resolved -> provider photo) and pre-cache it
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
        // Fall back to asset
        if (_drawerAvatarProvider == null) {
          setState(() {
            _drawerAvatarProvider = const AssetImage('assets/profile.png');
          });
        }
        return;
      }

      final nextProvider = NetworkImage(desired);
      // Apply immediately so first frame doesn't show asset
      if (mounted) {
        final current = _drawerAvatarProvider;
        final currentUrl = (current is NetworkImage) ? current.url : null;
        if (currentUrl != desired) {
          setState(() {
            _drawerAvatarProvider = nextProvider;
            _lastResolvedDrawerAvatarUrl = desired;
          });
        } else {
          _lastResolvedDrawerAvatarUrl = desired;
        }
      }
      // Then precache in background to stabilize future loads
      try {
        // ignore: unawaited_futures
        precacheImage(nextProvider, context);
      } catch (_) {
        // If pre-cache fails, keep existing provider/asset
      }
    } catch (_) {}
  }

  /// Resolves avatar URL using cascade prioritization:
  /// 1. Facebook photo - when Facebook is bound (Firestore profilePhoto or provider photoURL)
  /// 2. Google photo - when Google is bound (Firestore profilePhoto or provider photoURL)
  /// 3. Stored profile photo - from Firestore (uploaded photos)
  /// 4. Default asset - assets/profile.png (fallback)
  String? _resolveDrawerAvatar({
    required User user,
    required Map<String, dynamic>? data,
  }) {
    // Read optional admin-specific fields and binding flags
    final firestorePhotoAdmin = data?['profilePhotoAdmin'] as String?;
    final firestorePhotoLegacy = data?['profilePhoto'] as String?;
    final adminFbFlag = data?['facebookBoundAdmin'] as bool?;
    final adminGFlag = data?['googleBoundAdmin'] as bool?;
    final flagsPresent = adminFbFlag != null || adminGFlag != null;

    bool isFacebookBound = false;
    bool isGoogleBound = false;
    String? providerPhoto;

    if (flagsPresent) {
      // Use admin flags when available
      isFacebookBound = adminFbFlag == true;
      isGoogleBound = adminGFlag == true;
      if (isFacebookBound) {
        try {
          final fb = user.providerData.firstWhere(
            (p) => p.providerId == 'facebook.com',
          );
          providerPhoto = fb.photoURL ?? providerPhoto;
        } catch (_) {}
      }
      if (isGoogleBound && providerPhoto == null) {
        try {
          final g = user.providerData.firstWhere(
            (p) => p.providerId == 'google.com',
          );
          providerPhoto = g.photoURL ?? providerPhoto;
        } catch (_) {}
      }
    } else {
      // Legacy fallback: infer from providerData
      for (final p in user.providerData) {
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

    final noneLinked = !(isFacebookBound || isGoogleBound);

    // Pick Firestore photo preference (admin first, then legacy)
    final firestorePhoto =
        (firestorePhotoAdmin != null && firestorePhotoAdmin.isNotEmpty)
        ? firestorePhotoAdmin
        : firestorePhotoLegacy;

    // If any social is linked OR flags are not present (legacy), prefer Firestore photo then provider
    if (!noneLinked || !flagsPresent) {
      if (firestorePhoto != null && firestorePhoto.isNotEmpty) {
        return firestorePhoto;
      }
      if (providerPhoto != null && providerPhoto.isNotEmpty) {
        return providerPhoto;
      }
    }

    // If none linked, only use uploaded Firestore photo; else fall back to asset
    if (noneLinked) {
      if (firestorePhoto != null && firestorePhoto.isNotEmpty) {
        return firestorePhoto;
      }
      return null; // indicates to use asset
    }

    // Default fallback
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

      // If we already have a provider and no new URL is provided, render it to avoid flicker across opens
      if (_drawerAvatarProvider != null && (url == null || url.isEmpty)) {
        // If no social accounts are bound and previous provider was a network image, fallback to asset
        final u = FirebaseAuth.instance.currentUser;
        final hasSocial =
            u?.providerData.any(
              (p) =>
                  p.providerId == 'facebook.com' ||
                  p.providerId == 'google.com',
            ) ??
            false;
        if (!hasSocial && _drawerAvatarProvider is NetworkImage) {
          _drawerAvatarProvider = const AssetImage('assets/profile.png');
        }
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

      // If a resolved URL is provided (uploaded or social), always apply it immediately
      if (url != null && url.isNotEmpty) {
        final next = NetworkImage(url);
        final current = _drawerAvatarProvider;
        final currentUrl = (current is NetworkImage) ? current.url : null;
        if (currentUrl != url) {
          _drawerAvatarProvider = next;
          _lastResolvedDrawerAvatarUrl = url;
          // Precache in background to stabilize subsequent frames
          try {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              precacheImage(next, context);
            });
          } catch (_) {}
        }
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

      // If no URL, try last successful URL first to avoid showing asset briefly
      if (url == null || url.isEmpty) {
        if (_lastResolvedDrawerAvatarUrl != null &&
            _lastResolvedDrawerAvatarUrl!.isNotEmpty) {
          final last = _lastResolvedDrawerAvatarUrl!;
          _drawerAvatarProvider = NetworkImage(last);
          // Precache in the background
          try {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              precacheImage(NetworkImage(last), context);
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

        // Decide based on whether a social account is bound
        final u = FirebaseAuth.instance.currentUser;
        final hasSocial =
            u?.providerData.any(
              (p) =>
                  p.providerId == 'facebook.com' ||
                  p.providerId == 'google.com',
            ) ??
            false;
        if (hasSocial) {
          // Count bound providers
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
              // If only Google is bound, use its photo; when both are bound we won't use provider fallback here
              providerPhoto = providerPhoto ?? g.photoURL;
            }
          } catch (_) {}

          // Try last successful cached URL first
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
          // If exactly one provider is bound and we have its photo, use it to avoid showing asset on first open
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
        // If no social bound (or no usable photo), show default asset
        return ClipOval(
          child: Image.asset(
            'assets/profile.png',
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => fallback,
          ),
        );
      }

      // Use network image for social or uploaded photos
      return ClipOval(
        child: Image.network(
          url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            print('Avatar load error for URL: $url');
            print('Error: $error');
            // Try last successful URL if available (only when social is bound)
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
            // If not social-bound or no cached, fall back to default asset
            // Fallback to default asset on network error
            return ClipOval(
              child: Image.asset(
                'assets/profile.png',
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => fallback,
              ),
            );
          },
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            // While loading, if social is bound, show the last successful avatar instantly; else fallback asset
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
                errorBuilder: (context, error, stackTrace) => fallback,
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

        if (user == null) {
          print('Dashboard: No authenticated user');
          return buildAvatar(null);
        }

        print('Dashboard: User authenticated - ${user.email}');
        print(
          'Dashboard: Provider data: ${user.providerData.map((p) => p.providerId).toList()}',
        );

        // Listen to Firestore changes for real-time updates
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              print('Dashboard: Firestore stream error: ${snapshot.error}');
            }

            final data = snapshot.data?.data();
            print('Dashboard: Firestore data exists: ${data != null}');
            if (data != null) {
              print('Dashboard: profilePhoto field: ${data['profilePhoto']}');
            }

            final url = _resolveDrawerAvatar(user: user, data: data);
            print('Dashboard: Final resolved URL: $url');
            if (url != null && url.isNotEmpty) {
              _lastResolvedDrawerAvatarUrl = url;
            }

            // Compute desired URL prioritizing: resolved -> last cached -> provider photo (to avoid asset when bound)
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

            // Compute hasSocial once to decide fallback behavior
            final hasSocial = user.providerData.any(
              (p) =>
                  p.providerId == 'facebook.com' ||
                  p.providerId == 'google.com',
            );

            String? desiredUrl = (url != null && url.isNotEmpty) ? url : null;
            if (desiredUrl == null) {
              if (hasSocial) {
                // With social bound, allow last cached or providerPhoto as fallback
                desiredUrl =
                    (_lastResolvedDrawerAvatarUrl != null &&
                        _lastResolvedDrawerAvatarUrl!.isNotEmpty)
                    ? _lastResolvedDrawerAvatarUrl
                    : providerPhoto;
              }
            }

            // If we have a desired URL, swap immediately and precache in background
            // Avoid swapping while the drawer is open to prevent flicker when opening from Profile tab
            if (!_isDrawerOpen && desiredUrl != null && desiredUrl.isNotEmpty) {
              final nextProvider = NetworkImage(desiredUrl);
              final current = _drawerAvatarProvider;
              final currentUrl = (current is NetworkImage) ? current.url : null;
              if (currentUrl != desiredUrl) {
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  if (!mounted) return;
                  setState(() {
                    _drawerAvatarProvider = nextProvider;
                  });
                  try {
                    precacheImage(nextProvider, context);
                  } catch (_) {}
                });
              }
            } else if (_isDrawerOpen &&
                desiredUrl != null &&
                desiredUrl.isNotEmpty) {
              // Capture pending desired URL to apply right after the drawer closes
              _pendingAvatarUrl = desiredUrl;
            } else {
              // No URL resolved.
              final hasSocial = user.providerData.any(
                (p) =>
                    p.providerId == 'facebook.com' ||
                    p.providerId == 'google.com',
              );
              if (!hasSocial) {
                // Treat as deletion of uploaded photo: evict previous network and clear last cache, then force asset immediately
                try {
                  if (_lastResolvedDrawerAvatarUrl != null &&
                      _lastResolvedDrawerAvatarUrl!.isNotEmpty) {
                    final img = NetworkImage(_lastResolvedDrawerAvatarUrl!);
                    img.evict();
                  }
                } catch (_) {}
                _lastResolvedDrawerAvatarUrl = null;
                if (!(_drawerAvatarProvider is AssetImage)) {
                  setState(() {
                    _drawerAvatarProvider = const AssetImage(
                      'assets/profile.png',
                    );
                  });
                }
              } else {
                // Some social bound but no URL ready: keep current to avoid flicker, ensure we at least have an asset
                if (_drawerAvatarProvider == null) {
                  _drawerAvatarProvider = const AssetImage(
                    'assets/profile.png',
                  );
                }
              }
            }

            // Always render current provider to keep display stable
            return buildAvatar(desiredUrl);
          },
        );
      },
    );
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
        onDrawerChanged: (isOpen) async {
          _isDrawerOpen = isOpen;
          if (isOpen) {
            // Immediately render the last known avatar to avoid showing asset on the first frame
            if (_lastResolvedDrawerAvatarUrl != null &&
                _lastResolvedDrawerAvatarUrl!.isNotEmpty) {
              final last = _lastResolvedDrawerAvatarUrl!;
              setState(() {
                _drawerAvatarProvider = NetworkImage(last);
              });
              try {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  precacheImage(NetworkImage(last), context);
                });
              } catch (_) {}
            }
            try {
              await FirebaseAuth.instance.currentUser?.reload();
            } catch (_) {}
            // Precache last successful avatar to ensure instant display
            if (_lastResolvedDrawerAvatarUrl != null &&
                _lastResolvedDrawerAvatarUrl!.isNotEmpty) {
              try {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  precacheImage(
                    NetworkImage(_lastResolvedDrawerAvatarUrl!),
                    context,
                  );
                });
              } catch (_) {}
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
                    // Apply immediately so first frame doesn't show asset
                    if (mounted) {
                      setState(() {
                        _drawerAvatarProvider = next;
                        _lastResolvedDrawerAvatarUrl = desiredUrl;
                        _pendingAvatarUrl = null;
                      });
                    }
                    // Then precache in background to stabilize future loads
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
              Container(
                height: 160,
                decoration: BoxDecoration(
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
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: _drawerAvatar(80),
                      ),
                      const SizedBox(height: 12),
                      ValueListenableBuilder<String>(
                        valueListenable: adminNameNotifier,
                        builder: (context, name, _) {
                          return Text(
                            name,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF006064),
                            ),
                          );
                        },
                      ),
                      const Text(
                        "OIP Sentinel",
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF00838F),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ListTile(
                leading: Icon(Icons.person, color: Color(0xFF00838F)),
                title: Text(
                  "Profile",
                  style: TextStyle(color: Color(0xFF006064)),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => ProfileTab(
                        adminNameNotifier: adminNameNotifier,
                        role: 'admin',
                      ),
                      settings: const RouteSettings(name: 'Profile'),
                    ),
                  );
                  _loadAdminName();
                  try {
                    await FirebaseAuth.instance.currentUser?.reload();
                  } catch (_) {}
                  if (mounted) setState(() {});
                },
              ),
              ListTile(
                leading: Icon(Icons.person_add, color: Color(0xFF00838F)),
                title: Text(
                  "Register Cashier",
                  style: TextStyle(color: Color(0xFF006064)),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => RegisterCashierAdminScreen(),
                      settings: const RouteSettings(name: 'RegisterCashier'),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.history, color: Color(0xFF00838F)),
                title: Text(
                  "Audit Trail",
                  style: TextStyle(color: Color(0xFF006064)),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const AuditTrailScreen(),
                      settings: const RouteSettings(name: 'AuditTrail'),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.settings, color: Color(0xFF00838F)),
                title: Text(
                  "Settings",
                  style: TextStyle(color: Color(0xFF006064)),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const SettingsTab(),
                      settings: const RouteSettings(name: 'Settings'),
                    ),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.logout, color: Color(0xFF00838F)),
                title: Text(
                  "Logout",
                  style: TextStyle(color: Color(0xFF006064)),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _logout();
                },
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
                          labelPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                        ),
                        NavItem(
                          icon: Icons.inventory,
                          label: 'Production',
                          index: 1,
                          currentIndex: _currentIndex,
                          onTap: _onNavTap,
                          selectedColor: bluerose,
                          iconSize: 24,
                          labelPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                        ),
                        NavItem(
                          icon: Icons.point_of_sale,
                          label: 'Sales',
                          index: 2,
                          currentIndex: _currentIndex,
                          onTap: _onNavTap,
                          selectedColor: bluerose,
                          iconSize: 24,
                          labelPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                        ),
                        NavItem(
                          icon: Icons.monitor_heart,
                          label: 'Monitoring',
                          index: 3,
                          currentIndex: _currentIndex,
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
                          index: 4,
                          currentIndex: _currentIndex,
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
