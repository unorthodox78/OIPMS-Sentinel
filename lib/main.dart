import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'screens/login_form.dart';
import 'screens/dashboard_screen.dart';
import 'screens/pos_sale_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
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

  @override
  void initState() {
    super.initState();
    _authStateChanges = FirebaseAuth.instance.authStateChanges();
    // You may wish to add logic here to fetch and set _userRole from user profile data upon login
  }

  void _onLoginSuccess(String role) {
    setState(() {
      _userRole = role;
    });
  }

  void _logout() async {
    await FirebaseAuth.instance.signOut();
    setState(() {
      _userRole = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authStateChanges,
      builder: (context, snapshot) {
        final user = snapshot.data;
        if (user == null) {
          // User not logged in
          return LoginForm(onLoginSuccess: _onLoginSuccess);
        } else {
          // User logged in, route by role
          if (_userRole == 'admin') {
            return DashboardScreen(onLogout: _logout);
          } else if (_userRole == 'cashier') {
            return PosSaleScreen(onLogout: _logout);
          } else {
            return LoginForm(onLoginSuccess: _onLoginSuccess);
          }
        }
      },
    );
  }
}
