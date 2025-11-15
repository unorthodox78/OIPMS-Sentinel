import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'register_form.dart';

class LoginForm extends StatefulWidget {
  final void Function(String role) onLoginSuccess;
  const LoginForm({super.key, required this.onLoginSuccess});

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;
  static const double _formHeight = 520;
  static const double _formWidth = 370;
  static const EdgeInsets _formPadding = EdgeInsets.symmetric(vertical: 30.0, horizontal: 28.0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF6dd5fa), Color(0xFF2193b0)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              padding: _formPadding,
              width: _formWidth,
              height: _formHeight,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    const SizedBox(height: 40),
                    const Text(
                      'LOGIN',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 36),
                    if (_errorMessage != null) ...[
                      _buildErrorMessage(),
                      const SizedBox(height: 18),
                    ],
                    _buildIdentifierField(),
                    const SizedBox(height: 18),
                    _buildPasswordField(),
                    const SizedBox(height: 36),
                    _buildLoginButton(),
                    const SizedBox(height: 18),
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => RegisterForm()),
                        );
                      },
                      child: Text(
                        "Don't have an account? Register Now",
                        style: TextStyle(
                          color: Colors.purple.shade700,
                          decoration: TextDecoration.underline,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red[700], size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(color: Colors.red[700], fontSize: 14),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: Colors.red[700], size: 18),
            onPressed: _clearError,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildIdentifierField() {
    return TextFormField(
      controller: _identifierController,
      decoration: const InputDecoration(
        labelText: 'Username / Email / Phone',
        prefixIcon: Icon(Icons.person),
        border: OutlineInputBorder(),
      ),
      textInputAction: TextInputAction.next,
      validator: (value) {
        if (value == null || value.isEmpty) return 'Please enter your identifier';
        if (value.length < 3) return 'Must be at least 3 characters';
        return null;
      },
      onChanged: (_) => _clearError(),
    );
  }

  Widget _buildPasswordField() {
    return TextFormField(
      controller: _passwordController,
      obscureText: _obscurePassword,
      decoration: InputDecoration(
        labelText: 'Password',
        prefixIcon: const Icon(Icons.lock),
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(
            _obscurePassword ? Icons.visibility_off : Icons.visibility,
            color: Colors.grey[600],
          ),
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        ),
      ),
      textInputAction: TextInputAction.done,
      validator: (value) {
        if (value == null || value.isEmpty) return 'Please enter your password';
        if (value.length < 6) return 'Password must be at least 6 characters';
        return null;
      },
      onFieldSubmitted: (_) => _login(),
      onChanged: (_) => _clearError(),
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _login,
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 2,
        ),
        child: _isLoading
            ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        )
            : const Text('Login', style: TextStyle(fontSize: 18)),
      ),
    );
  }

  void _login() async {
    _clearError();
    if (!_formKey.currentState!.validate()) return;
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text;

    setState(() => _isLoading = true);

    try {
      String emailForLogin;
      if (identifier.contains('@')) {
        emailForLogin = identifier;
      } else if (RegExp(r'^\+?\d{7,}$').hasMatch(identifier)) {
        var query = await FirebaseFirestore.instance
            .collection('users')
            .where('phone', arrayContains: identifier)
            .limit(1)
            .get();
        if (query.docs.isEmpty) throw Exception('Phone number not found');
        emailForLogin = query.docs.first['email'];
      } else {
        var query = await FirebaseFirestore.instance
            .collection('users')
            .where('username', arrayContains: identifier)
            .limit(1)
            .get();
        if (query.docs.isEmpty) throw Exception('Username not found');
        emailForLogin = query.docs.first['email'];
      }
      UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailForLogin,
        password: password,
      );
      DocumentSnapshot<Map<String, dynamic>> userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user?.uid)
          .get();
      if (!userDoc.exists) {
        _setError('User record not found. Please contact admin.');
        return;
      }
      final role = userDoc.data()?['role'] ?? '';
      final status = userDoc.data()?['status'] ?? '';
      if (role == 'cashier' && status != 'approved') {
        _setError('Your account is pending approval.');
        return;
      }
      if (role.isEmpty) {
        _setError('User role is empty. Please contact admin.');
        return;
      }
      widget.onLoginSuccess(role);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'wrong-password') {
        _setError('Invalid credentials');
      } else {
        _setError('Failed to login: ${e.message}');
      }
    } catch (e) {
      _setError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setError(String message) {
    if (mounted) setState(() => _errorMessage = message);
  }

  void _clearError() {
    if (_errorMessage != null && mounted) setState(() => _errorMessage = null);
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
