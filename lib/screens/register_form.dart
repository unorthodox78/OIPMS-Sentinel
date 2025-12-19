import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisterForm extends StatefulWidget {
  final VoidCallback? onRegisterSuccess;
  const RegisterForm({super.key, this.onRegisterSuccess});

  @override
  State<RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<RegisterForm> {
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  static const double _formWidth = 370;
  static const EdgeInsets _formPadding = EdgeInsets.symmetric(
    vertical: 32.0,
    horizontal: 32.0,
  );
  static const _buttonColor = Color(0xFF2193b0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Background gradient
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF6dd5fa), Color(0xFF2193b0)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Mascot/logo
                  Image.asset('assets/icon.png', width: 100, height: 120),
                  const SizedBox(height: 1),
                  // Registration Card
                  Container(
                    padding: _formPadding,
                    width: _formWidth,
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          "CREATE ACCOUNT",
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 22),
                        if (_errorMessage != null) ...[
                          _buildErrorMessage(),
                          const SizedBox(height: 12),
                        ],
                        _buildEmailField(),
                        const SizedBox(height: 14),
                        _buildPhoneField(),
                        const SizedBox(height: 14),
                        _buildUsernameField(),
                        const SizedBox(height: 14),
                        _buildPasswordField(),
                        const SizedBox(height: 14),
                        _buildConfirmPasswordField(),
                        const SizedBox(height: 22),
                        _buildRegisterButton(),
                        const SizedBox(height: 18),
                        GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                          },
                          child: Text(
                            "Already have an account? Log In",
                            style: TextStyle(
                              color: Colors.purple[800],
                              decoration: TextDecoration.underline,
                              fontWeight: FontWeight.normal,
                              fontSize: 13, // <--- match login form size
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 2),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSocialButton({
    required String asset,
    required Color background,
    Border? border,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(25),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
          border: border,
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Image.asset(asset),
        ),
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
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
              style: TextStyle(
                color: Colors.red[700],
                fontSize: 13,
                height: 1.4,
              ),
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

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      decoration: const InputDecoration(
        labelText: 'Email Address',
        prefixIcon: Icon(Icons.email),
        border: OutlineInputBorder(),
      ),
      keyboardType: TextInputType.emailAddress,
      onChanged: (_) => _clearError(),
    );
  }

  Widget _buildPhoneField() {
    return TextFormField(
      controller: _phoneController,
      decoration: const InputDecoration(
        labelText: 'Phone Number',
        prefixIcon: Icon(Icons.phone),
        border: OutlineInputBorder(),
      ),
      keyboardType: TextInputType.phone,
      onChanged: (_) => _clearError(),
    );
  }

  Widget _buildUsernameField() {
    return TextFormField(
      controller: _usernameController,
      decoration: const InputDecoration(
        labelText: 'Username',
        prefixIcon: Icon(Icons.person),
        border: OutlineInputBorder(),
      ),
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
      onChanged: (_) => _clearError(),
    );
  }

  Widget _buildConfirmPasswordField() {
    return TextFormField(
      controller: _confirmPasswordController,
      obscureText: _obscureConfirmPassword,
      decoration: InputDecoration(
        labelText: 'Confirm Password',
        prefixIcon: const Icon(Icons.lock),
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(
            _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
            color: Colors.grey[600],
          ),
          onPressed: () => setState(
            () => _obscureConfirmPassword = !_obscureConfirmPassword,
          ),
        ),
      ),
      onChanged: (_) => _clearError(),
    );
  }

  Widget _buildRegisterButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _register,
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          backgroundColor: _buttonColor,
          elevation: 0,
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
            : const Text(
                'Register',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  void _register() async {
    _clearError();

    final email = _emailController.text.trim().toLowerCase();
    final phone = _phoneController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (email.isEmpty ||
        phone.isEmpty ||
        username.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
      _setError('Please fill all fields');
      return;
    }
    if (!RegExp(r'^[\w-.]+@([\w-]+\.)+[\w]{2,4}').hasMatch(email)) {
      _setError('Please enter a valid email address');
      return;
    }
    String formattedPhone = _formatPhoneNumber(phone);

    if (username.length < 3) {
      _setError('Username must be at least 3 characters');
      return;
    }
    if (password.length < 6) {
      _setError('Password must be at least 6 characters');
      return;
    }
    if (password != confirmPassword) {
      _setError('Passwords do not match');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Check duplicate username among active/pending users (ignore deleted)
      final usernameQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('username', arrayContains: username)
          .get();
      final usernameTaken = usernameQuery.docs.any((d) {
        final data = d.data();
        final status = (data['status'] ?? '').toString().toLowerCase();
        return status != 'deleted';
      });
      if (usernameTaken) {
        _setError('Username already exists');
        setState(() => _isLoading = false);
        return;
      }

      // Check duplicate email among active/pending users (ignore deleted)
      final emailQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .get();
      final emailTaken = emailQuery.docs.any((d) {
        final data = d.data();
        final status = (data['status'] ?? '').toString().toLowerCase();
        return status != 'deleted';
      });
      if (emailTaken) {
        _setError('Email is already registered');
        setState(() => _isLoading = false);
        return;
      }

      // Extra safety: check Firebase Auth directly for existing email
      final methods = <String>[];
      if (methods.isNotEmpty) {
        // Email exists in Firebase Auth. See if there's an existing Firestore user doc.
        // If none, try to sign in with the provided password and recreate the Firestore record.
        try {
          final signIn = await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: email,
            password: password,
          );
          final uid = signIn.user?.uid;
          if (uid == null) {
            _setError('Email is already registered in the system.');
            setState(() => _isLoading = false);
            return;
          }
          final docRef = FirebaseFirestore.instance
              .collection('users')
              .doc(uid);
          final docSnap = await docRef.get();
          if (!docSnap.exists) {
            await docRef.set({
              'email': email,
              'phone': [formattedPhone],
              'username': [username],
              'role': 'cashier',
              'status': 'pending',
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
          _showMessage('Registration successful! Wait for approval.');
          widget.onRegisterSuccess?.call();
          await FirebaseAuth.instance.signOut();
          Navigator.of(context).pop();
          return;
        } on FirebaseAuthException catch (_) {
          _setError(
            'Email is already registered in the system. If this user was previously deleted, ask the admin to reactivate or fully remove the old account.',
          );
          setState(() => _isLoading = false);
          return;
        }
      }
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user?.uid)
          .set({
            'email': email,
            'phone': [formattedPhone],
            'username': [username],
            'role': 'cashier',
            'status': 'pending',
            'createdAt': FieldValue.serverTimestamp(),
          });

      _showMessage('Registration successful! Wait for approval.');
      widget.onRegisterSuccess?.call();
      await FirebaseAuth.instance.signOut();
      Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use')
        _setError(
          'Email is already registered in the system. If this user was previously deleted, ask the admin to reactivate or fully remove the old account.',
        );
      else if (e.code == 'invalid-email')
        _setError('Invalid email address');
      else if (e.code == 'weak-password')
        _setError('The password is too weak');
      else
        _setError('Registration failed. Please try again.');
    } catch (e) {
      _setError('An error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatPhoneNumber(String phone) {
    phone = phone.replaceAll(' ', '').replaceAll('-', '');
    if (!phone.startsWith('+')) {
      if (phone.startsWith('63')) return '+$phone';
      if (phone.startsWith('0')) return '+63${phone.substring(1)}';
      return '+63$phone';
    }
    return phone;
  }

  void _setError(String message) {
    if (mounted) setState(() => _errorMessage = message);
  }

  void _clearError() {
    if (_errorMessage != null && mounted) setState(() => _errorMessage = null);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _phoneController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}
