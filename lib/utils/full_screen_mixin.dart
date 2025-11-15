import 'package:flutter/material.dart';

class LoginForm extends StatefulWidget {
  final void Function(String role) onLoginSuccess;

  const LoginForm({super.key, required this.onLoginSuccess});

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  // Constants for better maintainability
  static const double _formHeight = 520;
  static const EdgeInsets _formPadding = EdgeInsets.all(30.0);
  static const double _largeSpacing = 50.0;
  static const double _mediumSpacing = 20.0;
  static const Duration _simulatedDelay = Duration(milliseconds: 1500);

  // Demo credentials (in real app, this would come from API/backend)
  static const Map<String, Map<String, dynamic>> _demoUsers = {
    'jom': {
      'password': '1234',
      'role': 'admin',
      'name': 'Jomari Administrator',
    },
    'cashier': {
      'password': '5678',
      'role': 'cashier',
      'name': 'Cashier User',
    },
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: _formPadding,
      height: _formHeight,
      width: double.infinity,
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildHeader(),
            const SizedBox(height: _largeSpacing),

            // Error message display
            if (_errorMessage != null) ...[
              _buildErrorMessage(),
              const SizedBox(height: _mediumSpacing),
            ],

            _buildUsernameField(),
            const SizedBox(height: _mediumSpacing),
            _buildPasswordField(),
            const SizedBox(height: _largeSpacing),
            _buildLoginButton(),

            // Demo credentials hint (remove in production)
            _buildDemoHint(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return const Text(
      'LOGIN',
      style: TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
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
              style: TextStyle(
                color: Colors.red[700],
                fontSize: 14,
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

  Widget _buildUsernameField() {
    return TextFormField(
      controller: _usernameController,
      decoration: const InputDecoration(
        labelText: 'Username',
        prefixIcon: Icon(Icons.person),
        border: OutlineInputBorder(),
      ),
      textInputAction: TextInputAction.next,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter your username';
        }
        if (value.length < 3) {
          return 'Username must be at least 3 characters';
        }
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
        if (value == null || value.isEmpty) {
          return 'Please enter your password';
        }
        if (value.length < 4) {
          return 'Password must be at least 4 characters';
        }
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
            : const Text(
          'Login',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }

  Widget _buildDemoHint() {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue[700], size: 16),
              const SizedBox(width: 4),
              Text(
                'Demo Credentials',
                style: TextStyle(
                  color: Colors.blue[700],
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Admin: jom / 1234\nCashier: cashier / 5678',
            style: TextStyle(
              color: Colors.blue[700],
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  void _login() async {
    // Clear previous errors
    _clearError();

    // Form validation
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    setState(() => _isLoading = true);

    try {
      // Simulate API call delay
      await Future.delayed(_simulatedDelay);

      // Demo authentication (replace with real API call)
      final user = _demoUsers[username];

      if (user != null && user['password'] == password) {
        final String role = user['role'];
        final String name = user['name'];

        _showSuccessMessage('Welcome back, $name!');
        widget.onLoginSuccess(role);
      } else {
        _setError('Invalid username or password');
      }
    } catch (e) {
      _setError('Login failed. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _setError(String message) {
    if (mounted) {
      setState(() => _errorMessage = message);
    }
  }

  void _clearError() {
    if (_errorMessage != null && mounted) {
      setState(() => _errorMessage = null);
    }
  }

  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}