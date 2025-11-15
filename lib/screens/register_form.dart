import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_form.dart';

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

  static const double _formHeight = 620;
  static const EdgeInsets _formPadding = EdgeInsets.all(30.0);

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
              width: 370,
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 40),
                  const Text(
                    'REGISTER',
                    style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  if (_errorMessage != null) ...[
                    _buildErrorMessage(),
                    const SizedBox(height: 15),
                  ],
                  _buildEmailField(),
                  const SizedBox(height: 15),
                  _buildPhoneField(),
                  const SizedBox(height: 15),
                  _buildUsernameField(),
                  const SizedBox(height: 15),
                  _buildPasswordField(),
                  const SizedBox(height: 15),
                  _buildConfirmPasswordField(),
                  const SizedBox(height: 30),
                  _buildRegisterButton(),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => LoginForm(onLoginSuccess: (_) {}))
                      );
                    },
                    child: Text(
                      "Already have an account? Log In",
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
          Icon(Icons.error_outline, color: Colors.red[700]),
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
          ),
        ],
      ),
    );
  }

  Widget _buildEmailField() {
    return TextFormField(
      controller: _emailController,
      decoration: const InputDecoration(
        labelText: 'Email',
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
        prefixIcon: const Icon(Icons.lock_outline),
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(
            _obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
          ),
          onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
        ),
      ),
      onChanged: (_) => _clearError(),
    );
  }

  Widget _buildRegisterButton() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _register,
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
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
            : const Text('Register', style: TextStyle(fontSize: 18)),
      ),
    );
  }

  void _register() async {
    _clearError();

    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (email.isEmpty || phone.isEmpty || username.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      _setError('Please fill all fields');
      return;
    }
    if (!RegExp(r'^[\w-.]+@([\w-]+\.)+[\w]{2,4}').hasMatch(email)) {
      _setError('Please enter a valid email address');
      return;
    }
    if (!RegExp(r'^[0-9+]+$').hasMatch(phone) || phone.length < 9) {
      _setError('Please enter a valid phone number');
      return;
    }
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
      var existing = await FirebaseFirestore.instance
          .collection('users')
          .where('username', arrayContains: username)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        _setError('Username already exists');
        setState(() => _isLoading = false);
        return;
      }
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await FirebaseFirestore.instance.collection('users').doc(userCredential.user?.uid).set({
        'email': email,
        'phone': [phone],
        'username': [username],
        'role': 'cashier',
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      _showMessage('Registration successful! Wait for approval.');
      widget.onRegisterSuccess?.call();
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => LoginForm(onLoginSuccess: (_) {})));
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') _setError('Email is already registered');
      else if (e.code == 'invalid-email') _setError('Invalid email address');
      else if (e.code == 'weak-password') _setError('The password is too weak');
      else _setError('Registration failed. Please try again.');
    } catch (e) {
      _setError('An error occurred. Please try again.');
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
