import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/api_service.dart';
import '../services/audit_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  // State management
  bool _userFound = false;
  String? _userEmail;
  String? _userPhone;
  String? _username;
  String? _userId;
  bool _otpSent = false;

  static const double _formWidth = 370;
  static const EdgeInsets _formPadding = EdgeInsets.symmetric(
    vertical: 32.0,
    horizontal: 32.0,
  );

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

          // Back button (positioned absolutely)
          Positioned(
            top: 60,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // Centered content
          Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Icon
                    Image.asset('assets/icon.png', width: 100, height: 120),
                    const SizedBox(height: 20),

                    // Form container
                    Container(
                      padding: _formPadding,
                      width: _formWidth,
                      constraints: BoxConstraints(
                        minHeight: _userFound ? 500 : 350,
                      ),
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
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 10),
                            const Text(
                              'FORGOT PASSWORD',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              !_userFound
                                  ? 'Enter your email, phone, or username'
                                  : 'Choose verification method',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 28),

                            if (_errorMessage != null) ...[
                              _buildMessage(_errorMessage!, true),
                              const SizedBox(height: 16),
                            ],

                            if (_successMessage != null) ...[
                              _buildMessage(_successMessage!, false),
                              const SizedBox(height: 16),
                            ],

                            if (!_userFound) ...[
                              _buildIdentifierField(),
                              const SizedBox(height: 24),
                              _buildFindUserButton(),
                            ] else ...[
                              _buildUserInfoContainer(),
                              const SizedBox(height: 20),
                              _buildMethodSelection(),
                              if (_otpSent) ...[
                                const SizedBox(height: 20),
                                _buildOtpSection(),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserInfoContainer() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
              const SizedBox(width: 8),
              Text(
                'Account Found',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[900],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_username != null) ...[
            _buildInfoRow(Icons.person, 'Username', _username!),
            const SizedBox(height: 8),
          ],
          if (_userEmail != null) ...[
            _buildInfoRow(Icons.email, 'Email', _userEmail!),
            const SizedBox(height: 8),
          ],
          if (_userPhone != null) ...[
            _buildInfoRow(Icons.phone, 'Phone', _userPhone!),
          ],
        ],
      ),
    );
  }

  Widget _buildMethodSelection() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Choose how to receive verification code:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Centered email card
          if (_userEmail != null) ...[
            _buildMethodCard(
              icon: Icons.email,
              title: 'Email',
              description: 'Receive verification code via email',
              value: 'email',
              contact: _userEmail!,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMethodCard({
    required IconData icon,
    required String title,
    required String description,
    required String value,
    required String contact,
  }) {
    return InkWell(
      onTap: () => _selectMethod(value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue[300]!),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.blue[700], size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    contact,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.blue[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.blue[700], size: 18),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 13, color: Colors.grey[800]),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildMessage(String message, bool isError) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? Colors.red[50] : Colors.green[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isError ? Colors.red[200]! : Colors.green[200]!,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: isError ? Colors.red[700] : Colors.green[700],
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: isError ? Colors.red[700] : Colors.green[700],
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.close,
              color: isError ? Colors.red[700] : Colors.green[700],
              size: 18,
            ),
            onPressed: () {
              setState(() {
                _errorMessage = null;
                _successMessage = null;
              });
            },
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
        labelText: 'Email / Phone / Username',
        prefixIcon: Icon(Icons.person_search),
        border: OutlineInputBorder(),
        helperText: 'Enter your email, phone, or username',
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Please enter your identifier';
        }
        return null;
      },
      onChanged: (_) => _clearMessages(),
    );
  }

  Widget _buildFindUserButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _findUser,
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
            : const Text('Find Account', style: TextStyle(fontSize: 16)),
      ),
    );
  }

  void _selectMethod(String method) async {
    setState(() => _isLoading = true);

    if (method == 'email') {
      await AuditService.instance.log(
        event: 'password_method_selected',
        data: {'method': 'email', 'uid': _userId},
      );
      await _requestEmailOtp(_userEmail!);
    }
  }

  Widget _buildOtpSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _otpController,
          decoration: const InputDecoration(
            labelText: 'Enter 6-digit code',
            prefixIcon: Icon(Icons.verified_user),
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
          onChanged: (_) => _clearMessages(),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _newPasswordController,
          decoration: const InputDecoration(
            labelText: 'New password',
            prefixIcon: Icon(Icons.lock_outline),
            border: OutlineInputBorder(),
          ),
          obscureText: true,
          onChanged: (_) => _clearMessages(),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _confirmPasswordController,
          decoration: const InputDecoration(
            labelText: 'Confirm new password',
            prefixIcon: Icon(Icons.lock_reset),
            border: OutlineInputBorder(),
          ),
          obscureText: true,
          onChanged: (_) => _clearMessages(),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _submitOtpReset,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('Reset Password'),
          ),
        ),
      ],
    );
  }

  Future<void> _requestEmailOtp(String email) async {
    try {
      final resp = await requestPasswordOtp(email);
      if (resp['success'] == true) {
        setState(() {
          _otpSent = true;
          _successMessage =
              'Verification code sent to $email. It expires in 10 minutes.';
        });
        await AuditService.instance.log(
          event: 'password_otp_requested',
          data: {'method': 'email', 'uid': _userId, 'success': true},
        );
      } else {
        _setError(resp['error']?.toString() ?? 'Failed to send code');
        await AuditService.instance.log(
          event: 'password_otp_requested',
          data: {
            'method': 'email',
            'uid': _userId,
            'success': false,
            'error': resp['error']?.toString(),
          },
        );
      }
    } catch (e) {
      _setError('Failed to send code: ${e.toString()}');
      await AuditService.instance.log(
        event: 'password_otp_requested',
        data: {
          'method': 'email',
          'uid': _userId,
          'success': false,
          'error': e.toString(),
        },
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitOtpReset() async {
    _clearMessages();
    final otp = _otpController.text.trim();
    final p1 = _newPasswordController.text;
    final p2 = _confirmPasswordController.text;
    if (otp.length != 6) {
      _setError('Please enter the 6-digit code.');
      await AuditService.instance.log(
        event: 'password_reset_validation_error',
        data: {'reason': 'otp_length', 'uid': _userId},
      );
      return;
    }
    if (p1.isEmpty || p2.isEmpty) {
      _setError('Please enter and confirm your new password.');
      await AuditService.instance.log(
        event: 'password_reset_validation_error',
        data: {'reason': 'empty_password', 'uid': _userId},
      );
      return;
    }
    if (p1 != p2) {
      _setError('Passwords do not match.');
      await AuditService.instance.log(
        event: 'password_reset_validation_error',
        data: {'reason': 'password_mismatch', 'uid': _userId},
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final resp = await resetPasswordWithOtp(
        email: _userEmail!,
        otp: otp,
        newPassword: p1,
      );
      if (resp['success'] == true) {
        _setSuccess(
          'Password updated successfully. You can now sign in with your new password.',
        );
        await AuditService.instance.log(
          event: 'password_reset_success',
          data: {'uid': _userId},
        );
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.pop(context);
        });
      } else {
        _setError(resp['error']?.toString() ?? 'Reset failed');
        await AuditService.instance.log(
          event: 'password_reset_failed',
          data: {'uid': _userId, 'error': resp['error']?.toString()},
        );
      }
    } catch (e) {
      _setError('Reset failed: ${e.toString()}');
      await AuditService.instance.log(
        event: 'password_reset_failed',
        data: {'uid': _userId, 'error': e.toString()},
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _findUser() async {
    _clearMessages();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final identifier = _identifierController.text.trim();
      QuerySnapshot userQuery;

      if (identifier.contains('@')) {
        userQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: identifier)
            .limit(1)
            .get();
      } else if (RegExp(r'^[\+0-9]').hasMatch(identifier)) {
        String formattedPhone = _formatPhoneNumber(identifier);
        userQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('phone', arrayContains: formattedPhone)
            .limit(1)
            .get();
      } else {
        userQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('username', arrayContains: identifier)
            .limit(1)
            .get();
      }

      if (userQuery.docs.isEmpty) {
        _setError('User not found. Please check your details.');
        await AuditService.instance.log(
          event: 'password_recovery_lookup',
          data: {
            'identifier_type': identifier.contains('@')
                ? 'email'
                : (RegExp(r'^[\+0-9]').hasMatch(identifier)
                      ? 'phone'
                      : 'username'),
            'found': false,
          },
        );
        return;
      }

      final userDoc = userQuery.docs.first;
      _userId = userDoc.id;
      _userEmail = userDoc['email'];
      _userPhone = (userDoc['phone'] as List?)?.isNotEmpty == true
          ? userDoc['phone'][0]
          : null;
      _username = (userDoc['username'] as List?)?.isNotEmpty == true
          ? userDoc['username'][0]
          : null;

      setState(() {
        _userFound = true;
        _successMessage = 'Account found! Please choose a verification method.';
      });
      await AuditService.instance.log(
        event: 'password_recovery_lookup',
        data: {
          'identifier_type': identifier.contains('@')
              ? 'email'
              : (RegExp(r'^[\+0-9]').hasMatch(identifier)
                    ? 'phone'
                    : 'username'),
          'found': true,
          'uid': _userId,
        },
      );
    } catch (e) {
      _setError('Error finding user: ${e.toString()}');
      await AuditService.instance.log(
        event: 'password_recovery_lookup',
        data: {'error': e.toString()},
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatPhoneNumber(String phone) {
    phone = phone.replaceAll(' ', '').replaceAll('-', '');

    if (!phone.startsWith('+')) {
      if (phone.startsWith('63')) {
        return '+$phone';
      } else if (phone.startsWith('0')) {
        return '+63${phone.substring(1)}';
      } else {
        return '+63$phone';
      }
    }
    return phone;
  }

  Future<void> _sendEmailReset(String email) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _successMessage =
              'Password reset link sent successfully!\n\nEmail: $email\n\nPlease check your inbox and click the link to reset your password.';
        });

        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) Navigator.pop(context);
        });
      }
      await AuditService.instance.log(
        event: 'password_reset_link_sent',
        data: {'uid': _userId, 'email': email},
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _setError('Failed to send email: ${e.toString()}');
      }
      await AuditService.instance.log(
        event: 'password_reset_link_failed',
        data: {'uid': _userId, 'email': email, 'error': e.toString()},
      );
    }
  }

  void _setError(String message) {
    if (mounted) setState(() => _errorMessage = message);
  }

  void _setSuccess(String message) {
    if (mounted) setState(() => _successMessage = message);
  }

  void _clearMessages() {
    if ((_errorMessage != null || _successMessage != null) && mounted) {
      setState(() {
        _errorMessage = null;
        _successMessage = null;
      });
    }
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}
