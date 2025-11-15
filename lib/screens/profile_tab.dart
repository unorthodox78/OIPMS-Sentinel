import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileTab extends StatefulWidget {
  final ValueNotifier<String> adminNameNotifier;
  const ProfileTab({required this.adminNameNotifier, Key? key}) : super(key: key);

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  static const String nameKey = "admin_display_name";
  static const String defaultRole = "OIP Sentinel";
  static const String defaultAsset = 'assets/profile.png';

  TextEditingController _nameController = TextEditingController(text: "Admin");
  TextEditingController _emailController = TextEditingController(text: "admin@email.com");
  String? _profileImagePath;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _nameController.text = prefs.getString(nameKey) ?? "Admin";
      _emailController.text = prefs.getString('admin_email') ?? "admin@email.com";
    });
  }

  Future<void> _pickProfileImage() async {
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
    await prefs.setString(nameKey, _nameController.text.trim());
    await prefs.setString('admin_email', _emailController.text.trim());
    widget.adminNameNotifier.value = _nameController.text.trim();
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved!'))
    );
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
                Icon(Icons.photo_library, color: Colors.teal),
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
            onPressed: () {
              setState(() => _profileImagePath = null);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        children: [
          Center(
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 54,
                  backgroundColor: Colors.teal.withOpacity(0.14),
                  backgroundImage: _profileImagePath != null
                      ? FileImage(File(_profileImagePath!))
                      : AssetImage(defaultAsset) as ImageProvider,
                ),
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: _showAvatarDialog,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.teal,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      padding: const EdgeInsets.all(7),
                      child: const Icon(Icons.camera_alt, color: Colors.white, size: 23),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Center(child: Text(defaultRole, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.teal))),
          const SizedBox(height: 24),
          // Display Name (now styled like Email)
          TextField(
            controller: _nameController,
            textAlign: TextAlign.start,
            style: theme.textTheme.bodyMedium,
            decoration: InputDecoration(
              labelText: 'Display Name',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              prefixIcon: Icon(Icons.person, color: Colors.teal),
            ),
            maxLength: 24,
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: theme.textTheme.bodyMedium,
            decoration: InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              prefixIcon: Icon(Icons.email, color: Colors.teal),
            ),
          ),
          const SizedBox(height: 22),
          ElevatedButton.icon(
            onPressed: _saveProfile,
            icon: const Icon(Icons.save),
            label: const Text('Save Changes'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 45),
              textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          const SizedBox(height: 16),
          Divider(height: 36),
          ListTile(
            leading: Icon(Icons.verified_user, color: Colors.teal),
            title: Text("Account Verified"),
            subtitle: Text("Your account email is verified"),
            trailing: Icon(Icons.check_circle, color: Colors.teal),
          ),
          ListTile(
            leading: Icon(Icons.security, color: Colors.teal),
            title: Text("Security Settings"),
            subtitle: Text("Manage security in Settings > Account Security"),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('See the main settings for security options.'))
              );
            },
          ),
        ],
      ),
    );
  }
}
