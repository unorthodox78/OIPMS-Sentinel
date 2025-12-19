import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart' as g;
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import '../services/audit_service.dart';
import 'register_form.dart';
import 'forgot_password_screen.dart';
import 'two_factor_screen.dart';
import 'dart:math';

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

  static const double _formWidth = 370;
  static const EdgeInsets _formPadding = EdgeInsets.symmetric(
    vertical: 32.0,
    horizontal: 32.0,
  );

  // For button and social container
  static const _buttonColor = Color(0xFF2193b0);

  // 2FA helpers
  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('device_id');
    if (id != null && id.isNotEmpty) return id;
    // Generate a pseudo-UUID without extra deps
    final rnd = Random.secure();
    String randChunk(int len) => List.generate(
      len,
      (_) => rnd.nextInt(16),
    ).map((n) => n.toRadixString(16)).join();
    id =
        '${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}${randChunk(16)}';
    await prefs.setString('device_id', id);
    return id;
  }

  Future<void> _loginWithFacebook() async {
    _clearError();
    setState(() => _isLoading = true);
    try {
      final preEmail = _identifierController.text.trim();
      if (preEmail.contains('@')) {
        final byEmail = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: preEmail)
            .limit(1)
            .get();
        if (byEmail.docs.isEmpty) {
          await AuditService.instance.log(
            event: 'login_facebook_no_binding_precheck',
            data: {'email': preEmail, 'reason': 'no_user_doc'},
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'No account bound. Please register a cashier account and bind your Facebook to log in.',
                ),
              ),
            );
          }
          setState(() => _isLoading = false);
          return;
        }
        final preData = byEmail.docs.first.data();
        final fbBound = preData['facebookBound'] == true;
        final fbBoundCashier = preData['facebookBoundCashier'] == true;
        if (!(fbBound || fbBoundCashier)) {
          await AuditService.instance.log(
            event: 'login_facebook_no_binding_precheck',
            data: {'email': preEmail, 'reason': 'flags_false_or_missing'},
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'No account bound. Please register a cashier account and bind your Facebook to log in.',
                ),
              ),
            );
          }
          setState(() => _isLoading = false);
          return;
        }
      }
      await FacebookAuth.instance.logOut();
      final LoginResult result = await FacebookAuth.instance.login(
        permissions: ['email', 'public_profile'],
        loginTracking: LoginTracking.limited,
        loginBehavior: LoginBehavior.nativeWithFallback,
      );

      if (result.status != LoginStatus.success) {
        await AuditService.instance.log(
          event: 'login_facebook_cancelled_or_failed',
          data: {'status': result.status.name, 'message': result.message},
        );
        return;
      }

      // Get user data (includes id/email)
      final userData = await FacebookAuth.instance.getUserData(
        fields: 'email,name,id',
      );
      final fbUid = userData['id'] as String?;
      final email = (userData['email'] as String?) ?? '';

      // Enforce account binding before Firebase sign-in
      // 1) Prefer binding by stored facebookUid
      Map<String, dynamic>? bindingDoc;
      String? bindingUid;
      // no expectedRole; we only need the binding UID
      if (fbUid != null && fbUid.isNotEmpty) {
        final byFbUid = await FirebaseFirestore.instance
            .collection('users')
            .where('facebookUid', isEqualTo: fbUid)
            .limit(1)
            .get();
        if (byFbUid.docs.isNotEmpty) {
          final doc = byFbUid.docs.first;
          bindingDoc = doc.data();
          bindingUid = doc.id;
        }
      }

      // 2) Fallback to email+flags when facebookUid not stored or not matching
      bool skipPrecheckAndVerifyAfter = false;
      if (bindingDoc == null) {
        if (email.isEmpty) {
          // Some FB accounts do not share email. Skip precheck and verify binding after sign-in by UID.
          skipPrecheckAndVerifyAfter = true;
        } else {
          final byEmail = await FirebaseFirestore.instance
              .collection('users')
              .where('email', isEqualTo: email)
              .limit(1)
              .get();
          if (byEmail.docs.isEmpty) {
            await AuditService.instance.log(
              event: 'login_facebook_no_binding',
              data: {'email': email, 'reason': 'no_user_doc'},
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'No account bound. Please register a cashier account and bind your Facebook to log in.',
                  ),
                ),
              );
            }
            await FacebookAuth.instance.logOut();
            return;
          }
          final preDoc = byEmail.docs.first;
          final data = preDoc.data();
          final fbBound = data['facebookBound'] == true;
          final fbBoundCashier = data['facebookBoundCashier'] == true;
          if (!(fbBound || fbBoundCashier)) {
            await AuditService.instance.log(
              event: 'login_facebook_no_binding',
              data: {'email': email, 'reason': 'flags_false_or_missing'},
            );
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'No account bound. Please register a cashier account and bind your Facebook to log in.',
                  ),
                ),
              );
            }
            await FacebookAuth.instance.logOut();
            return;
          }
          bindingDoc = data;
          bindingUid = preDoc.id;
        }
      }

      // Exchange for Firebase credential (null-safe with tokenString) [web:39]
      final accessToken = result.accessToken;
      if (accessToken == null) {
        _setError('Login succeeded but no access token received.');
        await AuditService.instance.log(
          event: 'login_facebook_failure',
          data: {'reason': 'no_access_token'},
        );
        return;
      }

      final credential = FacebookAuthProvider.credential(
        accessToken.tokenString,
      );
      final userCred = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      final uid = userCred.user?.uid;
      if (uid == null) {
        _setError('Facebook sign-in failed.');
        await AuditService.instance.log(
          event: 'login_facebook_failure',
          data: {'reason': 'no_uid_after_precheck'},
        );
        return;
      }

      // Ensure the signed-in Firebase user matches the bound record we pre-validated
      if (bindingUid != null && uid != bindingUid) {
        _setError('This Facebook account is linked to a different user.');
        await AuditService.instance.log(
          event: 'login_facebook_mismatch_uid',
          data: {
            'signed_in_uid': uid,
            'expected_uid': bindingUid,
            'reason': 'credential_linked_to_other_user',
          },
        );
        await FirebaseAuth.instance.signOut();
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = userDoc.data() ?? {};
      final role = data['role'] ?? '';
      // If we skipped precheck due to missing email, verify flags now on the signed-in user
      if (skipPrecheckAndVerifyAfter) {
        final fbBound = data['facebookBound'] == true;
        final fbBoundCashier = data['facebookBoundCashier'] == true;
        if (!(fbBound || fbBoundCashier)) {
          _setError('This Facebook is not bound to this account.');
          await AuditService.instance.log(
            event: 'login_facebook_no_binding_post_signin',
            data: {'uid': uid},
          );
          await FirebaseAuth.instance.signOut();
          return;
        }
      }
      final status = data['status'] ?? '';

      if (role == 'cashier' && status != 'approved') {
        _setError('Your cashier account is pending approval.');
        await AuditService.instance.log(
          event: 'login_facebook_failure',
          data: {
            'uid': uid,
            'role': role,
            'status': status,
            'reason': 'pending_cashier',
          },
        );
        await FirebaseAuth.instance.signOut();
        return;
      }

      if (role != 'admin' && role != 'cashier') {
        _setError('User role is invalid.');
        await FirebaseAuth.instance.signOut();
        return;
      }

      final userEmailFor2FA = (email.isNotEmpty)
          ? email
          : ((data['email'] as String?) ?? '');
      if (userEmailFor2FA.isEmpty) {
        _setError(
          'No email available for verification. Please contact support.',
        );
        await FirebaseAuth.instance.signOut();
        return;
      }
      final allowed = await _enforce2FA(uid: uid, email: userEmailFor2FA);
      if (!allowed) {
        _setError('Verification required to continue.');
        await FirebaseAuth.instance.signOut();
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_role', role);
      await prefs.setString('user_uid', uid);
      await AuditService.instance.log(
        event: 'login_facebook_success',
        data: {'uid': uid, 'role': role},
      );
      widget.onLoginSuccess(role);
    } on FirebaseAuthException catch (e) {
      _setError(e.message ?? 'Facebook login failed');
      await AuditService.instance.log(
        event: 'login_facebook_failure',
        data: {'code': e.code, 'message': e.message},
      );
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      _setError(e.toString());
      await AuditService.instance.log(
        event: 'login_facebook_failure',
        data: {'error': e.toString()},
      );
      await FirebaseAuth.instance.signOut();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _isDeviceTrusted(String uid) async {
    final deviceId = await _getDeviceId();
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('trustedDevices')
        .doc(deviceId)
        .get();
    if (!doc.exists) return false;
    final data = doc.data() as Map<String, dynamic>;
    final ts = (data['trustedUntil'] as Timestamp?);
    if (ts == null) return false;
    return ts.toDate().isAfter(DateTime.now());
  }

  Future<void> _refreshTrust(String uid, {int days = 30}) async {
    final deviceId = await _getDeviceId();
    final now = DateTime.now();
    final until = now.add(Duration(days: days));
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('trustedDevices')
        .doc(deviceId);
    await ref.set({
      'firstSeenAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
      'trustedUntil': Timestamp.fromDate(until),
    }, SetOptions(merge: true));
    await AuditService.instance.log(
      event: 'device_trusted_updated',
      data: {
        'uid': uid,
        'device_id': deviceId,
        'trusted_until': until.toIso8601String(),
      },
    );
  }

  Future<bool> _enforce2FA({required String uid, required String email}) async {
    // If device already trusted, refresh window and allow
    final trusted = await _isDeviceTrusted(uid);
    if (trusted) {
      await _refreshTrust(uid);
      return true;
    }
    // Require OTP
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TwoFactorScreen(email: email),
        settings: const RouteSettings(name: 'TwoFactor'),
      ),
    );
    if (result is Map && result['trusted'] == true) {
      await _refreshTrust(uid);
      return true;
    }
    return result
        is Map; // if verified but not trusting, still allow this session
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
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
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 50),
                Image.asset('assets/icon.png', width: 100, height: 120),
                const SizedBox(height: 1),

                // The login container
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
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),
                        const Text(
                          'LOGIN',
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 28),
                        if (_errorMessage != null) ...[
                          _buildErrorMessage(),
                          const SizedBox(height: 16),
                        ],
                        _buildIdentifierField(),
                        const SizedBox(height: 16),
                        _buildPasswordField(),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ForgotPasswordScreen(),
                                ),
                              );
                            },
                            child: Text(
                              'Forgot Password?',
                              style: TextStyle(
                                color: Colors.blue.shade700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 1),
                        _buildLoginButton(),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(child: Divider(thickness: 1)),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                "or",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                            Expanded(child: Divider(thickness: 1)),
                          ],
                        ),
                        const SizedBox(height: 22),

                        // Social login icons - now circular like register and same size
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildSocialButton(
                              asset: 'assets/facebook.png',
                              background: const Color(0xFF1877F2),
                              onTap: _isLoading ? () {} : _loginWithFacebook,
                            ),
                            const SizedBox(width: 24),
                            _buildSocialButton(
                              asset: 'assets/google.png',
                              background: Colors.white,
                              onTap: _isLoading ? () {} : _loginWithGoogle,
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                          ],
                        ),

                        const SizedBox(height: 30),

                        GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => RegisterForm()),
                            );
                          },
                          child: Text(
                            "Don't have an account? Register Now",
                            style: TextStyle(
                              color: Colors.purple.shade700,
                              decoration: TextDecoration.underline,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loginWithGoogle() async {
    _clearError();
    setState(() => _isLoading = true);
    try {
      final googleSignIn = g.GoogleSignIn.instance;
      // Ensure account picker shows without revoking consent
      await googleSignIn.signOut();
      await g.GoogleSignIn.instance.initialize(
        serverClientId:
            '665376916406-59ir2p9f0d76l1i7jb1t48ktv3i0bqje.apps.googleusercontent.com',
      );
      final googleUser = await googleSignIn.authenticate();
      final googleAuth = await googleUser.authentication;

      // Pre-check binding by email BEFORE Firebase sign-in to avoid transient login
      final byEmail = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: googleUser.email)
          .limit(1)
          .get();
      if (byEmail.docs.isEmpty) {
        await AuditService.instance.log(
          event: 'login_google_no_binding',
          data: {'email': googleUser.email, 'reason': 'no_user_doc'},
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No account bound. Please register a cashier account and bind your Google to log in.',
              ),
            ),
          );
        }
        try {
          await g.GoogleSignIn.instance.disconnect();
        } catch (_) {}
        await g.GoogleSignIn.instance.signOut();
        return;
      }
      final gPreDoc = byEmail.docs.first.data();
      final gBound = gPreDoc['googleBound'] == true;
      final gBoundCashier = gPreDoc['googleBoundCashier'] == true;
      if (!(gBound || gBoundCashier)) {
        // Not bound to any user record
        await AuditService.instance.log(
          event: 'login_google_no_binding',
          data: {'email': googleUser.email, 'reason': 'flags_false_or_missing'},
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No account bound. Please register a cashier account and bind your Google to log in.',
              ),
            ),
          );
        }
        // Ensure no lingering session
        try {
          await g.GoogleSignIn.instance.disconnect();
        } catch (_) {}
        await g.GoogleSignIn.instance.signOut();
        return;
      }
      // Binding confirmed -> proceed to Firebase sign-in
      if (googleAuth.idToken == null || googleAuth.idToken!.isEmpty) {
        await AuditService.instance.log(
          event: 'login_google_cancelled',
          data: {'reason': 'no_id_token'},
        );
        return;
      }
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      final userCred = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      final uid = userCred.user?.uid;
      if (uid == null) {
        _setError('Google sign-in failed.');
        await AuditService.instance.log(
          event: 'login_google_failure',
          data: {'reason': 'no_uid_after_precheck'},
        );
        return;
      }
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final data = userDoc.data() ?? {};
      final role = data['role'] ?? '';
      // At this point, binding was already validated by email, so continue
      final status = data['status'] ?? '';

      if (role == 'cashier' && status != 'approved') {
        _setError('Your cashier account is pending approval.');
        await AuditService.instance.log(
          event: 'login_google_failure',
          data: {
            'uid': uid,
            'role': role,
            'status': status,
            'reason': 'pending_cashier',
          },
        );
        await FirebaseAuth.instance.signOut();
        return;
      }

      if (role != 'admin' && role != 'cashier') {
        _setError('User role is invalid.');
        await FirebaseAuth.instance.signOut();
        return;
      }

      // Step-up 2FA enforcement
      final allowed = await _enforce2FA(uid: uid, email: googleUser.email);
      if (!allowed) {
        _setError('Verification required to continue.');
        await FirebaseAuth.instance.signOut();
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_role', role);
      await prefs.setString('user_uid', uid);
      await AuditService.instance.log(
        event: 'login_google_success',
        data: {'uid': uid, 'role': role},
      );
      widget.onLoginSuccess(role);
    } on g.GoogleSignInException catch (e) {
      // User cancelled the Google picker; show friendly message and return
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google sign-in cancelled')),
        );
      }
      await AuditService.instance.log(
        event: 'login_google_cancelled',
        data: {'code': e.code.name},
      );
      return;
    } on FirebaseAuthException catch (e) {
      _setError(e.message ?? 'Google login failed');
      await AuditService.instance.log(
        event: 'login_google_failure',
        data: {'code': e.code, 'message': e.message},
      );
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      _setError(e.toString());
      await AuditService.instance.log(
        event: 'login_google_failure',
        data: {'error': e.toString()},
      );
      await FirebaseAuth.instance.signOut();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
        if (value == null || value.isEmpty) {
          return 'Please enter your identifier';
        }
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
        if (value == null || value.isEmpty) {
          return 'Please enter your password';
        }
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
      height: 48,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _login,
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          backgroundColor: _buttonColor, // Match register button color
          elevation: 0, // Match flat, modern look
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
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
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
      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(email: emailForLogin, password: password);
      DocumentSnapshot<Map<String, dynamic>> userDoc = await FirebaseFirestore
          .instance
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
        _setError(
          'Your account is pending approval. Please wait for the admin to accept your request.',
        );
        await AuditService.instance.log(
          event: 'login_blocked_pending',
          data: {
            'uid': userCredential.user?.uid,
            'role': role,
            'status': status,
            'identifier_type': identifier.contains('@')
                ? 'email'
                : (RegExp(r'^\+?\d{7,}$').hasMatch(identifier)
                      ? 'phone'
                      : 'username'),
          },
        );
        await FirebaseAuth.instance.signOut();
        return;
      }

      if (role.isEmpty) {
        _setError('User role is empty. Please contact admin.');
        await FirebaseAuth.instance.signOut();
        return;
      }

      final uid = userCredential.user!.uid;
      final allowed = await _enforce2FA(uid: uid, email: emailForLogin);
      if (!allowed) {
        _setError('Verification required to continue.');
        await FirebaseAuth.instance.signOut();
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_role', role);
      await prefs.setString('user_uid', uid);
      await AuditService.instance.log(
        event: 'login_success',
        data: {
          'uid': uid,
          'role': role,
          'identifier_type': identifier.contains('@')
              ? 'email'
              : (RegExp(r'^\+?\d{7,}$').hasMatch(identifier)
                    ? 'phone'
                    : 'username'),
        },
      );
      widget.onLoginSuccess(role);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' || e.code == 'wrong-password') {
        _setError('Invalid credentials');
      } else {
        _setError('Failed to login: ${e.message}');
      }
      await AuditService.instance.log(
        event: 'login_failure',
        data: {
          'code': e.code,
          'message': e.message,
          'identifier_type': identifier.contains('@')
              ? 'email'
              : (RegExp(r'^\+?\d{7,}$').hasMatch(identifier)
                    ? 'phone'
                    : 'username'),
        },
      );
    } catch (e) {
      _setError(e.toString());
      await AuditService.instance.log(
        event: 'login_failure',
        data: {
          'error': e.toString(),
          'identifier_type': identifier.contains('@')
              ? 'email'
              : (RegExp(r'^\+?\d{7,}$').hasMatch(identifier)
                    ? 'phone'
                    : 'username'),
        },
      );
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
