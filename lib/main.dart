import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'services/audit_service.dart';
import 'services/audit_route_observer.dart';
import 'screens/login_form.dart';
import 'screens/dashboard_screen.dart';
import 'screens/pos_sale_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Enable Firebase App Check so Firebase Storage accepts uploads.
  // For development, use the Debug provider. Add the printed debug token
  // in Firebase Console > App Check > Your Android app > Add debug token.
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.debug,
    appleProvider: AppleProvider.debug,
    webProvider: ReCaptchaV3Provider('not-used-on-mobile'),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Role-based Login',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.blue),
      navigatorObservers: [AuditRouteObserver()],
      home: const AuthHome(),
    );
  }
}

class AuthHome extends StatefulWidget {
  const AuthHome({super.key});

  @override
  State<AuthHome> createState() => _AuthHomeState();
}

class _AuthHomeState extends State<AuthHome> {
  String? _userRole;
  late final Stream<User?> _authStateChanges;
  bool _navigated = false; // retained but unused for navigation now
  String? _lastScreenLogged;
  bool _roleReady = false;

  @override
  void initState() {
    super.initState();
    _authStateChanges = FirebaseAuth.instance.authStateChanges();
    _loadCachedRole();
  }

  void _onLoginSuccess(String role) {
    setState(() {
      _userRole = role;
    });
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedUid = prefs.getString('user_uid');
    final cachedRole = prefs.getString('user_role');
    await AuditService.instance.log(
      event: 'logout',
      data: {'uid': cachedUid, 'role': cachedRole, 'source': 'user_action'},
    );
    await FirebaseAuth.instance.signOut();
    setState(() {
      _userRole = null;
      _navigated = false;
      _lastScreenLogged = null;
    });
    await prefs.remove('user_role');
    await prefs.remove('user_uid');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authStateChanges,
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user == null) {
          _roleReady = true; // no user, role resolution not needed
          // User not logged in
          return LoginForm(onLoginSuccess: _onLoginSuccess);
        } else {
          // User logged in: ensure role/status resolved before showing any dashboard
          if (_userRole == null && !_roleReady) {
            _loadRoleFor(user);
            return const Scaffold(
              backgroundColor: Colors.white,
              body: Center(child: CircularProgressIndicator()),
            );
          }
          // One-shot screen_view log without navigation
          if (_userRole == 'admin' && _lastScreenLogged != 'Dashboard') {
            _lastScreenLogged = 'Dashboard';
            WidgetsBinding.instance.addPostFrameCallback((_) {
              AuditService.instance.log(
                event: 'screen_view',
                data: {'route_action': 'push', 'route_name': 'Dashboard'},
              );
            });
            return DashboardScreen(onLogout: _logout);
          } else if (_userRole == 'cashier' && _lastScreenLogged != 'PosSale') {
            _lastScreenLogged = 'PosSale';
            WidgetsBinding.instance.addPostFrameCallback((_) {
              AuditService.instance.log(
                event: 'screen_view',
                data: {'route_action': 'push', 'route_name': 'PosSale'},
              );
            });
            return PosSaleScreen(onLogout: _logout);
          }
          if (_userRole == 'admin') return DashboardScreen(onLogout: _logout);
          if (_userRole == 'cashier') return PosSaleScreen(onLogout: _logout);
          // If role not set yet, keep showing loading to avoid flashes
          if (!_roleReady) {
            return const Scaffold(
              backgroundColor: Colors.white,
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return LoginForm(onLoginSuccess: _onLoginSuccess);
        }
      },
    );
  }

  Future<void> _loadCachedRole() async {
    final prefs = await SharedPreferences.getInstance();
    final cachedRole = prefs.getString('user_role');
    // Do not set _userRole here to avoid flashing a dashboard with stale role.
    // Let _loadRoleFor() resolve role + status from Firestore before showing UI.
  }

  Future<void> _loadRoleFor(User user) async {
    final prefs = await SharedPreferences.getInstance();
    final cachedRole = prefs.getString('user_role');
    if (cachedRole != null && cachedRole.isNotEmpty) {
      if (mounted)
        setState(() {
          _userRole = cachedRole;
          _roleReady = true;
        });
      return;
    }
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = doc.data();
    final role = data?['role'] as String?;
    final status = (data?['status'] as String?) ?? '';
    // Prevent pending cashiers from being considered logged-in at the app level
    if ((role == 'cashier') && (status.toLowerCase() != 'approved')) {
      await prefs.remove('user_role');
      await prefs.remove('user_uid');
      _userRole = null;
      _lastScreenLogged = null;
      await FirebaseAuth.instance.signOut();
      if (mounted)
        setState(() {
          _roleReady = true;
        });
      return;
    }
    if (role != null && role.isNotEmpty) {
      await prefs.setString('user_role', role);
      await prefs.setString('user_uid', user.uid);
      if (mounted)
        setState(() {
          _userRole = role;
          _roleReady = true;
        });
    }
    if (mounted && _userRole == null)
      setState(() {
        _roleReady = true;
      });
  }
}
