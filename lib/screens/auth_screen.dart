import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dashboard_screen.dart';
import 'login_form.dart';
import 'register_form.dart';
import 'pos_sale_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    setImmersiveSticky();
  }

  void setImmersiveSticky() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
  }

  void _showRegister() => setState(() => _currentIndex = 1);
  void _showLogin() => setState(() => _currentIndex = 0);

  void _handleLoginSuccess(String role) {
    final Map<String, Widget> routeMap = {
      'admin': const DashboardScreen(),
      'cashier': const PosSaleScreen(),
    };
    final Widget? targetScreen = routeMap[role];
    if (targetScreen != null) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => targetScreen),
            (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    setImmersiveSticky();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // Gradient background
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF93E8F9), Color(0xFF0F8AA3)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
              Center(
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.9,
                  constraints: const BoxConstraints(maxWidth: 500),
                  margin: const EdgeInsets.all(20),
                  child: Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SizedBox(
                      height: 520,
                      child: Stack(
                        children: [
                          _AnimatedAuthForm(
                            index: 0,
                            currentIndex: _currentIndex,
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeInOut,
                            child: LoginForm(onLoginSuccess: _handleLoginSuccess),
                          ),
                          _AnimatedAuthForm(
                            index: 1,
                            currentIndex: _currentIndex,
                            duration: const Duration(milliseconds: 500),
                            curve: Curves.easeInOut,
                            child: RegisterForm(
                              onRegisterSuccess: _showLogin,
                            ),
                          ),
                          Positioned(
                            bottom: 20,
                            left: 0,
                            right: 0,
                            child: _AuthToggleButton(
                              currentIndex: _currentIndex,
                              onShowRegister: _showRegister,
                              onShowLogin: _showLogin,
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
      ),
    );
  }
}

class _AnimatedAuthForm extends StatelessWidget {
  final int index;
  final int currentIndex;
  final Duration duration;
  final Curve curve;
  final Widget child;

  const _AnimatedAuthForm({
    required this.index,
    required this.currentIndex,
    required this.duration,
    required this.curve,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: duration,
      curve: curve,
      left: currentIndex == index ? 0 : (index == 0 ? -500 : 500),
      right: currentIndex == index ? 0 : (index == 0 ? 500 : -500),
      child: child,
    );
  }
}

class _AuthToggleButton extends StatelessWidget {
  final int currentIndex;
  final VoidCallback onShowRegister;
  final VoidCallback onShowLogin;

  const _AuthToggleButton({
    required this.currentIndex,
    required this.onShowRegister,
    required this.onShowLogin,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: currentIndex == 0 ? onShowRegister : onShowLogin,
        child: Text(
          currentIndex == 0
              ? 'Don\'t have an account? Register Now'
              : 'Back to Login',
          style: const TextStyle(
            fontSize: 16,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }
}
