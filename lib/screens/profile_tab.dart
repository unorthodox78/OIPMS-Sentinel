import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart' as g;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

class ProfileTab extends StatefulWidget {
  final ValueNotifier<String> adminNameNotifier;
  final Color? primaryColor;
  final String
  role; // 'admin' or 'cashier' (defaults to admin for backward-compat)
  const ProfileTab({
    required this.adminNameNotifier,
    this.primaryColor,
    this.role = 'admin',
    Key? key,
  }) : super(key: key);

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  static const String nameKey = "admin_display_name";
  static const String defaultRole = "OIP Sentinel";
  static const String defaultAsset = 'assets/profile.png';
  static const String cachedAvatarKey = 'cached_avatar_url';
  Color get _mainColor => widget.primaryColor ?? const Color(0xFF2193b0);
  bool get _isAdminRole => widget.role == 'admin';
  String get _photoField =>
      _isAdminRole ? 'profilePhoto' : 'profilePhotoCashier';
  String get _fbFlagField =>
      _isAdminRole ? 'facebookBound' : 'facebookBoundCashier';
  String get _gFlagField => _isAdminRole ? 'googleBound' : 'googleBoundCashier';

  TextEditingController _nameController = TextEditingController();
  TextEditingController _emailController = TextEditingController();
  String? _profileImagePath;
  String? _profilePhotoUrl;
  String? _profilePhotoSource; // 'social' or 'upload'
  String? _role;
  List<dynamic> _usernames = [];
  List<dynamic> _phones = [];

  String? _googleName;
  String? _googlePhotoUrl;
  String? _facebookName;
  String? _facebookPhotoUrl;

  bool _isFacebookBound = false;
  bool _isGoogleBound = false;
  bool _showGoogleUnbind = false;
  bool _showFacebookUnbind = false;
  String? _cachedAvatarUrl;
  String? _lastResolvedProfileAvatarUrl;
  ImageProvider? _profileAvatarProvider;

  @override
  void initState() {
    super.initState();
    _primeAvatarFromAuth();
    _hydrateCachedAvatar();
    _loadProfile();
    _checkSocialBindings();
  }

  void _primeAvatarFromAuth() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    // Read provider data synchronously (no reload) for instant UI
    UserInfo? googleInfo;
    UserInfo? fbInfo;
    for (final p in user.providerData) {
      if (p.providerId == 'facebook.com') fbInfo = p;
      if (p.providerId == 'google.com') googleInfo = p;
    }
    bool changed = false;
    if (fbInfo != null) {
      final f = fbInfo;
      _isFacebookBound = true;
      _facebookName = f.displayName;
      _facebookPhotoUrl = f.photoURL ?? _facebookPhotoUrl;
      changed = true;
    }
    if (googleInfo != null) {
      final g = googleInfo;
      _isGoogleBound = true;
      _googleName = g.displayName;
      _googlePhotoUrl = g.photoURL ?? _googlePhotoUrl;
      changed = true;
    }
    if (changed && mounted) {
      setState(() {});
      // Prefer FB > Google for cache
      final primed = _facebookPhotoUrl ?? _googlePhotoUrl;
      if (primed != null) {
        _precacheAfterBuild(primed);
        // Persist cached avatar (fire-and-forget)
        _setCachedAvatar(primed);
      }
    }
  }

  Future<void> _ensureProfilePhotoFromSocial(String url) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final snap = await ref.get();
      final data = snap.data();
      final existing = (data != null) ? (data[_photoField] as String?) : null;
      if (existing == null || existing.isEmpty) {
        await ref.set({_photoField: url}, SetOptions(merge: true));
        _profilePhotoUrl = url;
      }
    } catch (_) {}
  }

  void _precacheAfterBuild(String url) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await precacheImage(NetworkImage(url), context);
      } catch (_) {}
    });
  }

  Future<void> _hydrateCachedAvatar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString(cachedAvatarKey);
      if (mounted && url != null && url.isNotEmpty) {
        setState(() {
          _cachedAvatarUrl = url;
        });
        _precacheAfterBuild(url);
      }
    } catch (_) {}
  }

  Future<void> _setCachedAvatar(String? url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (url == null || url.isEmpty) {
        await prefs.remove(cachedAvatarKey);
        if (mounted) setState(() => _cachedAvatarUrl = null);
        return;
      }
      await prefs.setString(cachedAvatarKey, url);
      if (mounted) setState(() => _cachedAvatarUrl = url);
      _precacheAfterBuild(url);
    } catch (_) {}
  }

  Future<void> _refreshCachedAvatarChoice() async {
    final chosen =
        _profilePhotoUrl ??
        (_isFacebookBound ? _facebookPhotoUrl : null) ??
        (_isGoogleBound ? _googlePhotoUrl : null);
    await _setCachedAvatar(chosen);
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final user = FirebaseAuth.instance.currentUser;
    DocumentSnapshot<Map<String, dynamic>>? userDoc;
    if (user != null) {
      userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
    }

    setState(() {
      if (userDoc?.exists == true) {
        final data = userDoc!.data();
        final usernames = (data?['username'] is List)
            ? List<String>.from(data?['username'] ?? const [])
            : <String>[];
        final emailPrefix = (data?['email'] as String?)?.split('@').first;
        _nameController.text =
            (data?['name'] as String?) ??
            (usernames.isNotEmpty ? usernames.first : null) ??
            (user?.displayName) ??
            emailPrefix ??
            (user?.email?.split('@').first) ??
            prefs.getString(nameKey) ??
            "User";
        _emailController.text =
            data?['email'] ??
            user?.email ??
            prefs.getString('admin_email') ??
            "admin@email.com";
        // Prefer role-specific uploaded photo field first, then legacy
        final adminUrl = data?['profilePhotoAdmin'] as String?;
        final cashierUrl = data?['profilePhotoCashier'] as String?;
        final legacyUrl = data?['profilePhoto'] as String?;
        _profilePhotoUrl = _isAdminRole
            ? (adminUrl != null && adminUrl.isNotEmpty ? adminUrl : legacyUrl)
            : (cashierUrl != null && cashierUrl.isNotEmpty
                  ? cashierUrl
                  : legacyUrl);
        _profilePhotoSource = data?['profilePhotoSource'];
        _role = data?['role'] ?? defaultRole;
        _usernames = data?['username'] ?? [];
        _phones = data?['phone'] ?? [];
      } else {
        final emailPrefix = user?.email?.split('@').first;
        _nameController.text =
            user?.displayName ??
            emailPrefix ??
            prefs.getString(nameKey) ??
            "User";
        _emailController.text =
            user?.email ?? prefs.getString('admin_email') ?? "admin@email.com";
        _profilePhotoUrl = null;
        _profilePhotoSource = null;
        _role = defaultRole;
        _usernames = [];
        _phones = [];
      }
    });
    await _refreshCachedAvatarChoice();
  }

  Future<void> _checkSocialBindings() async {
    await FirebaseAuth.instance.currentUser?.reload();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // Read current role-specific flags once to avoid auto-overwrites across roles
      Map<String, dynamic>? docData;
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        docData = snap.data();
      } catch (_) {}
      final googleProviders = user.providerData
          .where((info) => info.providerId == 'google.com')
          .toList();
      if (googleProviders.isNotEmpty) {
        final googleProvider = googleProviders.first;
        setState(() {
          _isGoogleBound = true;
          _googleName = googleProvider.displayName;
          _googlePhotoUrl = googleProvider.photoURL;
          _showGoogleUnbind = false;
        });
        // Precache Google avatar to avoid first-paint delay
        if (mounted && _googlePhotoUrl != null) {
          _precacheAfterBuild(_googlePhotoUrl!);
        }
        if (_googlePhotoUrl != null) {
          _setCachedAvatar(_googlePhotoUrl);
          // Only persist role-specific photo if this role is explicitly bound to Google
          final gFlagIsTrue = (docData?[_gFlagField] == true);
          if (gFlagIsTrue) {
            await _ensureProfilePhotoFromSocial(_googlePhotoUrl!);
          }
        }
      } else {
        setState(() {
          _isGoogleBound = false;
          _googleName = null;
          _googlePhotoUrl = null;
          _showGoogleUnbind = false;
        });
      }

      final fbProviders = user.providerData
          .where((info) => info.providerId == 'facebook.com')
          .toList();
      if (fbProviders.isNotEmpty) {
        final fbProvider = fbProviders.first;

        // Default detection using Firebase providerData and stored flags/uid
        final fbFlagIsTrue = (docData?[_fbFlagField] == true);
        final storedFbUid = docData?['facebookUid'] as String?;
        final providerFbUid = fbProvider.uid; // may be null on some platforms

        // Consider bound when flag is true and either uid matches or stored uid is present without provider uid
        final uidMatches =
            fbFlagIsTrue &&
            ((storedFbUid != null &&
                    providerFbUid != null &&
                    storedFbUid == providerFbUid) ||
                (storedFbUid != null && providerFbUid == null));

        setState(() {
          _isFacebookBound =
              uidMatches || (fbFlagIsTrue && storedFbUid != null);
          _facebookName = fbProvider.displayName;
          _facebookPhotoUrl = fbProvider.photoURL ?? _facebookPhotoUrl;
          _showFacebookUnbind = false;
        });

        // CRITICAL: Fetch the DIRECT CDN URL from Facebook Graph API
        try {
          print('🔄 Fetching Facebook profile picture...');
          final fbUser = await FacebookAuth.instance.getUserData(
            fields: "name,picture.width(512).height(512)",
          );

          if (mounted) {
            final enhancedName = fbUser['name'] as String?;
            // Get the direct CDN URL (not the Graph API endpoint)
            final pictureData = fbUser['picture']?['data'];
            final directUrl = pictureData?['url'] as String?;
            final currentFbUid = fbUser['id'] as String?;

            print('✅ Facebook CDN URL: $directUrl');

            setState(() {
              _facebookName = enhancedName ?? _facebookName;
              _facebookPhotoUrl = directUrl; // Use direct CDN URL
            });

            if (_facebookPhotoUrl != null) {
              _precacheAfterBuild(_facebookPhotoUrl!);
              _setCachedAvatar(_facebookPhotoUrl);
              // Only persist role-specific photo if this role is explicitly bound to Facebook AND the facebookUid matches
              final fbFlagIsTrue2 = (docData?[_fbFlagField] == true);
              final storedFbUid2 = docData?['facebookUid'] as String?;
              final uidMatches2 =
                  fbFlagIsTrue2 &&
                  storedFbUid2 != null &&
                  currentFbUid != null &&
                  storedFbUid2 == currentFbUid;

              if (uidMatches2) {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .set({
                      _photoField: _facebookPhotoUrl,
                      'profilePhotoSource': 'social',
                    }, SetOptions(merge: true));
                await _ensureProfilePhotoFromSocial(_facebookPhotoUrl!);
                // Mark as bound for this role in UI only when the uid matches
                if (mounted) {
                  setState(() {
                    _isFacebookBound = true;
                  });
                }
              }
            }
          }
        } catch (e) {
          print('❌ Error fetching Facebook data: $e');
          // Fallback: try to use provider photoURL if available
          final fallbackUrl = fbProvider.photoURL;
          if (fallbackUrl != null && mounted) {
            setState(() {
              _facebookPhotoUrl = fallbackUrl;
            });
          }
        }
      } else {
        setState(() {
          _isFacebookBound = false;
          _facebookName = null;
          _facebookPhotoUrl = null;
          _showFacebookUnbind = false;
        });
      }
      await _refreshCachedAvatarChoice();
    } else {
      setState(() {
        _isGoogleBound = false;
        _isFacebookBound = false;
        _googleName = null;
        _googlePhotoUrl = null;
        _facebookName = null;
        _facebookPhotoUrl = null;
        _showGoogleUnbind = false;
        _showFacebookUnbind = false;
      });
      await _refreshCachedAvatarChoice();
    }
  }

  Future<bool> _requestStoragePermission() async {
    final status = await Permission.photos.request();
    final storageStatus = await Permission.storage.request();
    final mediaStatus = await Permission.mediaLibrary.request();
    return status.isGranted || storageStatus.isGranted || mediaStatus.isGranted;
  }

  Future<String?> _uploadProfileImageViaApi(File imageFile) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      final token = await user.getIdToken();
      final uri = Uri.parse('http://139.162.46.103:8080/upload-avatar');
      final req = http.MultipartRequest('POST', uri);
      req.headers['Authorization'] = 'Bearer $token';
      req.files.add(await http.MultipartFile.fromPath('file', imageFile.path));
      final resp = await req.send();
      final body = await resp.stream.bytesToString();
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final Map<String, dynamic> jsonResp =
            json.decode(body) as Map<String, dynamic>;
        final url = jsonResp['url'] as String?;
        return url;
      }
      print('Upload failed: ${resp.statusCode} $body');
      return null;
    } catch (e) {
      print('Image upload failed: $e');
      return null;
    }
  }

  Future<void> _pickProfileImage() async {
    final permissionGranted = await _requestStoragePermission();
    if (!permissionGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Permission denied to access storage/photos.')),
      );
      return;
    }
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _profileImagePath = image.path;
      });
    }
  }

  Future<void> _saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    widget.adminNameNotifier.value = _nameController.text.trim();

    final user = FirebaseAuth.instance.currentUser;
    String newName = _nameController.text.trim();
    String newEmail = _emailController.text.trim();

    bool emailChanged = user != null && newEmail != user.email;
    bool nameChanged = user != null && newName != user.displayName;

    await prefs.setString(nameKey, newName);
    await prefs.setString('admin_email', newEmail);

    String? imageUrlToSave = _profilePhotoUrl;
    bool photoAttempted = false;
    bool photoSuccess = false;

    if (_profileImagePath != null) {
      photoAttempted = true;
      final pickedFile = File(_profileImagePath!);
      if (pickedFile.existsSync()) {
        try {
          final uploadedUrl = await _uploadProfileImageViaApi(pickedFile);
          if (uploadedUrl != null) {
            imageUrlToSave = uploadedUrl;
            _profilePhotoUrl = uploadedUrl;
            _profilePhotoSource = 'upload';
            _profileImagePath = null;
            photoSuccess = true;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Profile photo uploaded successfully!'),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to upload profile photo.')),
            );
          }
        } catch (e) {
          print('Full error: $e');
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Upload error: $e')));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selected photo file does not exist.')),
        );
      }
    }

    try {
      if (user != null) {
        // Align with drawer logic: always set legacy 'profilePhoto' and role-specific field
        final Map<String, dynamic> updateData = {
          'name': newName,
          'email': newEmail,
          'role': _role ?? defaultRole,
          'username': _usernames,
          'phone': _phones,
          'profilePhoto': imageUrlToSave,
        };
        if (photoSuccess) {
          updateData['profilePhotoSource'] = 'upload';
        }
        if (_isAdminRole) {
          updateData['profilePhotoAdmin'] = imageUrlToSave;
        } else {
          updateData['profilePhotoCashier'] = imageUrlToSave;
        }
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .set(updateData, SetOptions(merge: true));
      }

      if (user != null && nameChanged) {
        await user.updateDisplayName(newName);
      }
      if (user != null && emailChanged) {
        try {
          await user.verifyBeforeUpdateEmail(newEmail);
        } on FirebaseAuthException catch (e) {
          if (e.code == 'requires-recent-login') {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Please re-authenticate to update email.'),
              ),
            );
            return;
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error updating email: ${e.message}')),
            );
            return;
          }
        }
      }

      await user?.reload();
      await _loadProfile();
      setState(() {});

      if (photoAttempted && photoSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Profile saved and photo uploaded!')),
        );
      } else if (photoAttempted && !photoSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Profile saved, but photo upload failed.')),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Profile saved!')));
      }
    } catch (e) {
      print('Main save error: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Profile save failed: $e')));
    }
  }

  Future<void> _bindFacebookAccount() async {
    try {
      // Ensure a fresh FB session so chooser appears and previous session doesn't interfere
      try {
        await FacebookAuth.instance.logOut();
      } catch (_) {}
      final result = await FacebookAuth.instance.login();
      if (result.status == LoginStatus.success) {
        final credential = FacebookAuthProvider.credential(
          result.accessToken!.tokenString,
        );
        // Fetch FB user data first to inspect uid/email and enforce manual-unbind policy
        Map<String, dynamic>? fbUser;
        String? pendingFbUid;
        try {
          fbUser = await FacebookAuth.instance.getUserData(
            fields: "id,name,email,picture.width(512).height(512)",
          );
          pendingFbUid = fbUser['id'] as String?;
        } catch (_) {}

        // Load current user's Firestore doc
        Map<String, dynamic>? docData;
        String? otherFlagField;
        try {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            final snap = await FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get();
            docData = snap.data();
          }
          otherFlagField = _fbFlagField == 'facebookBound'
              ? 'facebookBoundCashier'
              : 'facebookBound';
        } catch (_) {}

        // If either role is already marked bound in this doc, require manual unbind first
        final thisRoleBound = (docData?[_fbFlagField] == true);
        final otherRoleBound = (docData?[otherFlagField] == true);
        final storedFbUid = docData?['facebookUid'] as String?;
        if (thisRoleBound || otherRoleBound) {
          // Only treat as a real binding if we have a concrete UID stored
          final hasConcreteUid = storedFbUid != null && storedFbUid.isNotEmpty;
          final sameUid =
              hasConcreteUid &&
              pendingFbUid != null &&
              storedFbUid == pendingFbUid;
          final staleOtherRoleFlag = otherRoleBound && !hasConcreteUid;
          if (!sameUid && !staleOtherRoleFlag) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    otherRoleBound
                        ? (_isAdminRole
                              ? 'Facebook is already bound in the Cashier role. Unbind it there first.'
                              : 'Facebook is already bound in the Admin role. Unbind it there first.')
                        : 'Facebook is already bound in this role. Unbind it first to replace.',
                  ),
                ),
              );
            }
            return;
          }
          // Auto-heal: if the other role flag is stale (no UID), clear both role flags so user can proceed
          if (staleOtherRoleFlag) {
            try {
              final u = FirebaseAuth.instance.currentUser;
              if (u != null) {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(u.uid)
                    .set({
                      'facebookBound': false,
                      'facebookBoundCashier': false,
                    }, SetOptions(merge: true));
              }
            } catch (_) {}
          }
        }

        // Cross-user guard: prevent binding if this Facebook is already bound to another user
        try {
          if (pendingFbUid != null) {
            final dup = await FirebaseFirestore.instance
                .collection('users')
                .where('facebookUid', isEqualTo: pendingFbUid)
                .limit(1)
                .get();
            final currentUid = FirebaseAuth.instance.currentUser?.uid;
            if (dup.docs.isNotEmpty && dup.docs.first.id != currentUid) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'This Facebook is already bound to a different account. Unbind it there first.',
                    ),
                  ),
                );
              }
              return;
            }
          }
        } catch (_) {}
        await FirebaseAuth.instance.currentUser?.reload();
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          try {
            await user.linkWithCredential(credential);
          } on FirebaseAuthException catch (e) {
            if (mounted) {
              String msg = 'Facebook link failed';
              if (e.code == 'credential-already-in-use') {
                msg =
                    'This Facebook is already linked to another account. Unbind it there first.';
              } else if (e.message != null && e.message!.isNotEmpty) {
                msg = e.message!;
              }
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(msg)));
            }
            return;
          }
        } else {
          await FirebaseAuth.instance.signInWithCredential(credential);
        }

        // CRITICAL: Immediately fetch CDN URL after binding
        try {
          print('🔄 Fetching Facebook CDN URL after binding...');
          final fbUser = await FacebookAuth.instance.getUserData(
            fields: "name,email,picture.width(512).height(512)",
          );

          final enhancedName = fbUser['name'] as String?;
          final pictureData = fbUser['picture']?['data'];
          final directUrl = pictureData?['url'] as String?;
          // Also capture the FB user id for robust login pre-checks
          final fbUid = fbUser['id'] as String?;

          print('✅ Facebook CDN URL: $directUrl');

          final boundUser = FirebaseAuth.instance.currentUser;
          if (boundUser != null && directUrl != null) {
            // Save CDN URL to Firestore immediately (role-aware)
            await FirebaseFirestore.instance
                .collection('users')
                .doc(boundUser.uid)
                .set({
                  _photoField: directUrl,
                  'profilePhotoSource': 'social',
                  _fbFlagField: true,
                  'facebookEmail': fbUser['email'] ?? FieldValue.delete(),
                  if (fbUid != null) 'facebookUid': fbUid,
                }, SetOptions(merge: true));

            print('✅ Saved Facebook CDN URL to Firestore');

            // Update local state
            if (mounted) {
              setState(() {
                _facebookName = enhancedName;
                _facebookPhotoUrl = directUrl;
                _profilePhotoUrl = directUrl;
              });
              _precacheAfterBuild(directUrl);
              await _setCachedAvatar(directUrl);
            }
          }
        } catch (e) {
          print('❌ Error fetching Facebook CDN URL: $e');
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Facebook account linked!')),
          );
        }
        await _checkSocialBindings();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Facebook login failed: ${result.status}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error binding Facebook: $e')));
      }
    }
  }

  Future<void> _unbindFacebookAccount() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          await user.unlink('facebook.com');
        } on FirebaseAuthException catch (e) {
          if (e.code == 'requires-recent-login') {
            final ok = await _reauthenticateWithFacebook();
            if (!ok) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Re-authentication required to unbind Facebook.',
                    ),
                  ),
                );
              }
              return;
            }
            await user.unlink('facebook.com');
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error unbinding Facebook: ${e.message}'),
                ),
              );
            }
            return;
          }
        }
        try {
          await user.reload();
        } catch (_) {}
        // Clear binding flags in Firestore (role-aware) and release globally for this user
        final unboundUser = FirebaseAuth.instance.currentUser;
        if (unboundUser != null) {
          final otherFlag = _fbFlagField == 'facebookBound'
              ? 'facebookBoundCashier'
              : 'facebookBound';
          await FirebaseFirestore.instance
              .collection('users')
              .doc(unboundUser.uid)
              .set({
                _fbFlagField: false,
                otherFlag: false,
                'facebookEmail': FieldValue.delete(),
                'facebookUid': FieldValue.delete(),
              }, SetOptions(merge: true));
        }
        // Also clear local Facebook session credentials
        try {
          await FacebookAuth.instance.logOut();
        } catch (_) {}
        await _checkSocialBindings();
        // Decide avatar after FB unbind: prefer Google, else default
        final hasGoogle = _isGoogleBound && _googlePhotoUrl != null;
        final noneLinked = !_isGoogleBound && !_isFacebookBound;
        if (hasGoogle && unboundUser != null) {
          // Fall back to Google avatar
          await FirebaseFirestore.instance
              .collection('users')
              .doc(unboundUser.uid)
              .set({
                _photoField: _googlePhotoUrl,
                'profilePhotoSource': 'social',
              }, SetOptions(merge: true));
          setState(() {
            _profilePhotoUrl = _googlePhotoUrl;
          });
          await _setCachedAvatar(_googlePhotoUrl);
        } else if (noneLinked && unboundUser != null) {
          // No social providers left: reset to default
          await FirebaseFirestore.instance
              .collection('users')
              .doc(unboundUser.uid)
              .set({
                _photoField: FieldValue.delete(),
                'profilePhotoSource': FieldValue.delete(),
              }, SetOptions(merge: true));
          setState(() {
            _profilePhotoUrl = null;
          });
          await _setCachedAvatar(null);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Facebook account unbound.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error unbinding Facebook: $e')));
    }
  }

  Future<bool> _reauthenticateWithFacebook() async {
    try {
      try {
        await FacebookAuth.instance.logOut();
      } catch (_) {}
      final result = await FacebookAuth.instance.login();
      if (result.status != LoginStatus.success || result.accessToken == null)
        return false;
      final credential = FacebookAuthProvider.credential(
        result.accessToken!.tokenString,
      );
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      await user.reauthenticateWithCredential(credential);
      await user.reload();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _bindGoogleAccount() async {
    try {
      final googleSignIn = g.GoogleSignIn.instance;
      // Reset previous session so the chooser appears without revoking consent
      await googleSignIn.signOut();
      await g.GoogleSignIn.instance.initialize(
        serverClientId:
            '665376916406-59ir2p9f0d76l1i7jb1t48ktv3i0bqje.apps.googleusercontent.com',
      );
      final googleUser = await googleSignIn.authenticate();
      if (googleUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google sign-in cancelled')),
        );
        return;
      }
      final googleAuth = await googleUser.authentication;
      final googleCredential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      // Manual-only guards: block if role (or other role) already bound to a different Google
      Map<String, dynamic>? docData;
      String? otherFlagField;
      try {
        final u = FirebaseAuth.instance.currentUser;
        if (u != null) {
          final snap = await FirebaseFirestore.instance
              .collection('users')
              .doc(u.uid)
              .get();
          docData = snap.data();
        }
        otherFlagField = _gFlagField == 'googleBound'
            ? 'googleBoundCashier'
            : 'googleBound';
      } catch (_) {}

      final thisRoleBound = (docData?[_gFlagField] == true);
      final otherRoleBound = (docData?[otherFlagField] == true);
      final storedGoogleEmail = docData?['googleEmail'] as String?;
      if (thisRoleBound || otherRoleBound) {
        final hasConcreteEmail =
            storedGoogleEmail != null && storedGoogleEmail.isNotEmpty;
        final sameEmail =
            hasConcreteEmail && storedGoogleEmail == googleUser.email;
        final staleOtherRoleFlag = otherRoleBound && !hasConcreteEmail;
        if (!sameEmail && !staleOtherRoleFlag) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  otherRoleBound
                      ? (_isAdminRole
                            ? 'Google is already bound in the Cashier role. Unbind it there first.'
                            : 'Google is already bound in the Admin role. Unbind it there first.')
                      : 'Google is already bound in this role. Unbind it first to replace.',
                ),
              ),
            );
          }
          return;
        }
        // Auto-heal: if the other role flag is stale (no email), clear both role flags so user can proceed
        if (staleOtherRoleFlag) {
          try {
            final u = FirebaseAuth.instance.currentUser;
            if (u != null) {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(u.uid)
                  .set({
                    'googleBound': false,
                    'googleBoundCashier': false,
                  }, SetOptions(merge: true));
            }
          } catch (_) {}
        }
      }

      // Cross-user guard: prevent binding if this Google email is already bound to another account
      try {
        if (googleUser.email.isNotEmpty) {
          final dup = await FirebaseFirestore.instance
              .collection('users')
              .where('googleEmail', isEqualTo: googleUser.email)
              .limit(1)
              .get();
          final currentUid = FirebaseAuth.instance.currentUser?.uid;
          if (dup.docs.isNotEmpty && dup.docs.first.id != currentUid) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'This Google account is already bound to a different user. Unbind it there first.',
                  ),
                ),
              );
            }
            return;
          }
        }
      } catch (_) {}

      await FirebaseAuth.instance.currentUser?.reload();
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          await user.linkWithCredential(googleCredential);
        } on FirebaseAuthException catch (e) {
          String msg = 'Google link failed';
          if (e.code == 'credential-already-in-use') {
            msg =
                'This Google account is already linked to another user. Unbind it there first.';
          } else if (e.code == 'account-exists-with-different-credential') {
            msg =
                'This email is used with a different sign-in method. Sign in with that method, then link Google from Profile.';
          } else if (e.message != null && e.message!.isNotEmpty) {
            msg = e.message!;
          }
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(msg)));
          }
          return;
        }
      } else {
        await FirebaseAuth.instance.signInWithCredential(googleCredential);
      }
      await FirebaseAuth.instance.currentUser?.reload();
      // Persist binding flags in Firestore
      final boundUser = FirebaseAuth.instance.currentUser;
      if (boundUser != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(boundUser.uid)
            .set({
              _gFlagField: true,
              'googleEmail': googleUser.email,
            }, SetOptions(merge: true));
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Google account linked!')));
      await _checkSocialBindings();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error binding Google: $e')));
    }
  }

  Future<void> _unbindGoogleAccount() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.unlink('google.com');
        await FirebaseAuth.instance.currentUser?.reload();
        try {
          final googleSignIn = g.GoogleSignIn.instance;
          try {
            await googleSignIn.disconnect();
          } catch (_) {}
          await googleSignIn.signOut();
        } catch (_) {}
        // Clear binding flags in Firestore (both roles) and remove stored Google credentials
        final unboundUser = FirebaseAuth.instance.currentUser;
        if (unboundUser != null) {
          final otherFlag = _gFlagField == 'googleBound'
              ? 'googleBoundCashier'
              : 'googleBound';
          await FirebaseFirestore.instance
              .collection('users')
              .doc(unboundUser.uid)
              .set({
                _gFlagField: false,
                otherFlag: false,
                'googleEmail': FieldValue.delete(),
              }, SetOptions(merge: true));
        }
        await _checkSocialBindings();
        // Decide avatar after Google unbind: prefer Facebook, else default
        final hasFacebook = _isFacebookBound && _facebookPhotoUrl != null;
        final noneLinked = !_isGoogleBound && !_isFacebookBound;
        if (hasFacebook && unboundUser != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(unboundUser.uid)
              .set({
                _photoField: _facebookPhotoUrl,
                'profilePhotoSource': 'social',
              }, SetOptions(merge: true));
          setState(() {
            _profilePhotoUrl = _facebookPhotoUrl;
          });
          await _setCachedAvatar(_facebookPhotoUrl);
        } else if (noneLinked && unboundUser != null) {
          // If no providers remain, remove profile photo so default shows
          await FirebaseFirestore.instance
              .collection('users')
              .doc(unboundUser.uid)
              .set({
                _photoField: FieldValue.delete(),
                'profilePhotoSource': FieldValue.delete(),
              }, SetOptions(merge: true));
          setState(() {
            _profilePhotoUrl = null;
          });
        }
        // Verify provider is removed
        final stillLinked =
            FirebaseAuth.instance.currentUser?.providerData.any(
              (p) => p.providerId == 'google.com',
            ) ??
            false;
        if (stillLinked && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Google still appears linked. Please try again or re-authenticate.',
              ),
            ),
          );
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google account unbound.')),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        // Reauthenticate with Google then retry unlink
        final reauthed = await _reauthenticateWithGoogle();
        if (reauthed) {
          return _unbindGoogleAccount();
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Re-authentication required to unbind Google.'),
              ),
            );
          }
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error unbinding Google: ${e.message}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error unbinding Google: $e')));
    }
  }

  Future<bool> _reauthenticateWithGoogle() async {
    try {
      final googleSignIn = g.GoogleSignIn.instance;
      await googleSignIn.signOut();
      await g.GoogleSignIn.instance.initialize(
        serverClientId:
            '665376916406-59ir2p9f0d76l1i7jb1t48ktv3i0bqje.apps.googleusercontent.com',
      );
      final googleUser = await googleSignIn.authenticate();
      if (googleUser == null) return false;
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      await user.reauthenticateWithCredential(credential);
      await user.reload();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _showAvatarDialog() {
    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        title: Text('Profile Photo'),
        children: [
          SimpleDialogOption(
            child: Row(
              children: [
                Icon(Icons.photo_library, color: _mainColor),
                SizedBox(width: 10),
                Text("Choose from Gallery"),
              ],
            ),
            onPressed: () {
              Navigator.pop(context);
              _pickProfileImage();
            },
          ),
          SimpleDialogOption(
            child: Row(
              children: [
                Icon(Icons.delete, color: Colors.red),
                SizedBox(width: 10),
                Text("Remove Photo"),
              ],
            ),
            onPressed: () async {
              // Only allow removing uploaded photos; don't remove social avatars
              final user = FirebaseAuth.instance.currentUser;
              final isUploaded =
                  _profilePhotoSource == 'upload' ||
                  (_profilePhotoUrl != null &&
                      _profilePhotoUrl!.startsWith(
                        'http://139.162.46.103:8080/img/',
                      ));
              if (!isUploaded) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Only uploaded photos can be removed here. Unbind social to remove social avatars.',
                    ),
                  ),
                );
                return;
              }
              try {
                if (user != null) {
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .set({
                        _photoField: FieldValue.delete(),
                        'profilePhoto': FieldValue.delete(),
                        if (_isAdminRole)
                          'profilePhotoAdmin': FieldValue.delete()
                        else
                          'profilePhotoCashier': FieldValue.delete(),
                        'profilePhotoSource': FieldValue.delete(),
                      }, SetOptions(merge: true));
                }
              } catch (_) {}
              // Compute immediate fallback for local UI
              String? fallback;
              if (_isFacebookBound &&
                  _facebookPhotoUrl != null &&
                  _facebookPhotoUrl!.isNotEmpty) {
                fallback = _facebookPhotoUrl;
              } else if (_isGoogleBound &&
                  _googlePhotoUrl != null &&
                  _googlePhotoUrl!.isNotEmpty) {
                fallback = _googlePhotoUrl;
              }
              setState(() {
                _profileImagePath = null;
                _profilePhotoUrl = null;
                _profilePhotoSource = null;
                _profileAvatarProvider = fallback != null
                    ? NetworkImage(fallback)
                    : const AssetImage(defaultAsset);
              });
              await _refreshCachedAvatarChoice();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSocialBindButton({
    required String label,
    required String asset,
    required Color border,
    required Color background,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
          border: Border.all(color: border, width: 2),
        ),
        child: Center(child: Image.asset(asset, width: 32, height: 32)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Determine and maintain a stable avatar provider (instant display like side menu)
    final bool noneLinked = !_isFacebookBound && !_isGoogleBound;
    if (_profileImagePath != null) {
      // Show freshly picked local image immediately
      final fileProvider = FileImage(File(_profileImagePath!));
      if (!identical(_profileAvatarProvider, fileProvider)) {
        _profileAvatarProvider = fileProvider;
      }
    } else {
      // Resolve desired URL like drawer: prefer uploaded Firestore photo first, then social FB > Google
      String? desiredUrl;
      if (_profilePhotoUrl != null && _profilePhotoUrl!.isNotEmpty) {
        desiredUrl = _profilePhotoUrl;
      } else if (_isFacebookBound &&
          _facebookPhotoUrl != null &&
          _facebookPhotoUrl!.isNotEmpty) {
        desiredUrl = _facebookPhotoUrl;
      } else if (_isGoogleBound &&
          _googlePhotoUrl != null &&
          _googlePhotoUrl!.isNotEmpty) {
        desiredUrl = _googlePhotoUrl;
      }

      if (desiredUrl != null && desiredUrl.isNotEmpty) {
        if (_lastResolvedProfileAvatarUrl != desiredUrl) {
          _lastResolvedProfileAvatarUrl = desiredUrl;
        }
        final nextProvider = NetworkImage(desiredUrl);
        final current = _profileAvatarProvider;
        final currentUrl = (current is NetworkImage) ? current.url : null;
        if (currentUrl != desiredUrl) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            // Instant swap, precache in background
            setState(() {
              _profileAvatarProvider = nextProvider;
            });
            try {
              await precacheImage(nextProvider, context);
            } catch (_) {}
          });
        }
      } else {
        // No desired URL
        if (_profileAvatarProvider == null) {
          // If no accounts bound, force default asset
          if (noneLinked) {
            _profileAvatarProvider = const AssetImage(defaultAsset);
          } else {
            // Some social bound but no URLs yet: try cached/provider photo first
            if (_lastResolvedProfileAvatarUrl != null &&
                _lastResolvedProfileAvatarUrl!.isNotEmpty) {
              _profileAvatarProvider = NetworkImage(
                _lastResolvedProfileAvatarUrl!,
              );
            } else {
              final user = FirebaseAuth.instance.currentUser;
              String? providerPhoto;
              try {
                final fb = user?.providerData.firstWhere(
                  (p) => p.providerId == 'facebook.com',
                );
                providerPhoto = fb?.photoURL ?? providerPhoto;
              } catch (_) {}
              try {
                if (providerPhoto == null) {
                  final g = user?.providerData.firstWhere(
                    (p) => p.providerId == 'google.com',
                  );
                  providerPhoto = g?.photoURL ?? providerPhoto;
                }
              } catch (_) {}
              _profileAvatarProvider =
                  (providerPhoto != null && providerPhoto.isNotEmpty)
                  ? NetworkImage(providerPhoto)
                  : const AssetImage(defaultAsset);
            }
          }
        } else {
          // If no social bound anymore and provider is a NetworkImage, reset to asset to avoid stale social pic
          if (noneLinked && _profileAvatarProvider is NetworkImage) {
            _profileAvatarProvider = const AssetImage(defaultAsset);
          }
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: _mainColor,
        foregroundColor: Colors.white,
      ),
      body: Container(
        color: Colors.white,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          children: [
            Center(
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  ClipOval(
                    child: Image(
                      image:
                          _profileAvatarProvider ??
                          const AssetImage(defaultAsset),
                      width: 108,
                      height: 108,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  ),
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: GestureDetector(
                      onTap: _showAvatarDialog,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _mainColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        padding: const EdgeInsets.all(7),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 23,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              textAlign: TextAlign.start,
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                labelText: 'Display Name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                prefixIcon: Icon(Icons.person, color: _mainColor),
              ),
              maxLength: 24,
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _emailController,
              enabled: true,
              keyboardType: TextInputType.emailAddress,
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                prefixIcon: Icon(Icons.email, color: _mainColor),
              ),
            ),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              onPressed: _saveProfile,
              icon: const Icon(Icons.save),
              label: const Text('Save Changes'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _mainColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 45,
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Divider(height: 28),
            Padding(
              padding: const EdgeInsets.only(top: 7.0, bottom: 16.0),
              child: Text(
                "Bind Social Account",
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildSocialBindButton(
                  label: "Facebook",
                  asset: 'assets/facebook.png',
                  border: const Color(0xFF1877F2),
                  background: Colors.white,
                  onTap: () {
                    if (_isFacebookBound) {
                      setState(() {
                        _showFacebookUnbind = !_showFacebookUnbind;
                        _showGoogleUnbind = false;
                      });
                    } else {
                      _bindFacebookAccount();
                    }
                  },
                ),
                const SizedBox(width: 40),
                _buildSocialBindButton(
                  label: "Google",
                  asset: 'assets/google.png',
                  border: Colors.red,
                  background: Colors.white,
                  onTap: () {
                    if (_isGoogleBound) {
                      setState(() {
                        _showGoogleUnbind = !_showGoogleUnbind;
                        _showFacebookUnbind = false;
                      });
                    } else {
                      _bindGoogleAccount();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),
            Divider(height: 28),
            Padding(
              padding: const EdgeInsets.only(top: 7.0, bottom: 4.0),
              child: Text(
                "Accounts",
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 10),
            // Show Facebook first
            if (_isFacebookBound)
              Column(
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Column(
                        children: [
                          ListTile(
                            onTap: () {
                              setState(() {
                                _showFacebookUnbind = !_showFacebookUnbind;
                                _showGoogleUnbind = false;
                              });
                            },
                            leading: CircleAvatar(
                              backgroundImage: _facebookPhotoUrl != null
                                  ? NetworkImage(_facebookPhotoUrl!)
                                  : AssetImage('assets/facebook.png')
                                        as ImageProvider,
                              radius: 16,
                            ),
                            title: Text(
                              _facebookName != null
                                  ? _facebookName!
                                  : "Facebook Connected",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            trailing: Icon(Icons.check, color: Colors.green),
                            subtitle: Text("Facebook account linked."),
                          ),
                          if (_showFacebookUnbind)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                              ),
                              child: ElevatedButton.icon(
                                onPressed: _unbindFacebookAccount,
                                icon: Icon(Icons.close, color: Colors.white),
                                label: Text("Unbind Facebook"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  minimumSize: Size(double.infinity, 38),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
              ),
            if (!_isFacebookBound)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.white,
                      backgroundImage:
                          AssetImage('assets/facebook.png') as ImageProvider,
                      radius: 16,
                    ),
                    title: const Text('No Facebook account linked'),
                    trailing: const Icon(Icons.close, color: Colors.red),
                  ),
                ),
              ),
            // Then Google
            if (_isGoogleBound)
              Column(
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Column(
                        children: [
                          ListTile(
                            onTap: () {
                              setState(() {
                                _showGoogleUnbind = !_showGoogleUnbind;
                                _showFacebookUnbind = false;
                              });
                            },
                            leading: CircleAvatar(
                              backgroundImage: _googlePhotoUrl != null
                                  ? NetworkImage(_googlePhotoUrl!)
                                  : AssetImage('assets/google.png')
                                        as ImageProvider,
                              radius: 16,
                            ),
                            title: Text(
                              _googleName != null
                                  ? _googleName!
                                  : "Google Connected",
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            trailing: Icon(Icons.check, color: Colors.green),
                            subtitle: Text("Google account linked."),
                          ),
                          if (_showGoogleUnbind)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                              ),
                              child: ElevatedButton.icon(
                                onPressed: _unbindGoogleAccount,
                                icon: Icon(Icons.close, color: Colors.white),
                                label: Text("Unbind Google"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  minimumSize: Size(double.infinity, 38),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            if (!_isGoogleBound) const SizedBox(height: 10),
            if (!_isGoogleBound)
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.white,
                      backgroundImage:
                          AssetImage('assets/google.png') as ImageProvider,
                      radius: 16,
                    ),
                    title: const Text('No Google account linked'),
                    trailing: const Icon(Icons.close, color: Colors.red),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
