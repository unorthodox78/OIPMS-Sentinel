import 'package:flutter/material.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({Key? key}) : super(key: key);

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  bool darkMode = false;
  bool notifications = true;
  bool smsNotifications = false;
  bool biometricUnlock = false;
  bool faceRecognition = false;
  bool twoStepVerification = false;
  bool cloudSync = true;
  bool offlineMode = false;
  bool automatedReports = false;
  double fontSize = 16;
  bool voiceAssist = false;
  String language = "English";

  final TextEditingController _oldPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();

  void _showChangePasswordDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Change Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _oldPasswordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Current Password',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 12),
            TextField(
              controller: _newPasswordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'New Password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _oldPasswordController.clear();
              _newPasswordController.clear();
              Navigator.pop(context);
            },
            child: Text('Cancel', style: TextStyle(color: Colors.teal)),
          ),
          ElevatedButton(
            onPressed: () {
              _oldPasswordController.clear();
              _newPasswordController.clear();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Password changed (mock)!'))
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            child: Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showSecurityDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Advanced Security'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile(
              value: twoStepVerification,
              onChanged: (v) => setState(() {
                twoStepVerification = v;
                Navigator.pop(context);
              }),
              activeColor: Colors.teal,
              title: Text('2-Step Verification'),
              subtitle: Text('Add an extra layer of security on sign in'),
            ),
            SwitchListTile(
              value: faceRecognition,
              onChanged: (v) => setState(() {
                faceRecognition = v;
                Navigator.pop(context);
              }),
              activeColor: Colors.teal,
              title: Text('Face Recognition Login'),
              subtitle: Text('Use device camera for authentication'),
            ),
            SwitchListTile(
              value: biometricUnlock,
              onChanged: (v) => setState(() {
                biometricUnlock = v;
                Navigator.pop(context);
              }),
              activeColor: Colors.teal,
              title: Text('Fingerprint Unlock'),
              subtitle: Text('Enable fingerprint login'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Done', style: TextStyle(color: Colors.teal)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 20),
          ListTile(
            leading: Icon(Icons.color_lens, color: Colors.teal),
            title: Text("Dark Mode"),
            subtitle: Text("Reduce eye strain and save battery"),
            trailing: Switch(
              value: darkMode,
              onChanged: (val) => setState(() => darkMode = val),
              activeColor: Colors.teal,
            ),
          ),
          ListTile(
            leading: Icon(Icons.notifications_active_outlined, color: Colors.teal),
            title: Text("Push Notifications"),
            subtitle: Text("Get notified for app alerts and updates"),
            trailing: Switch(
              value: notifications,
              onChanged: (val) => setState(() => notifications = val),
              activeColor: Colors.teal,
            ),
          ),
          ListTile(
            leading: Icon(Icons.sms, color: Colors.teal),
            title: Text("SMS Notifications"),
            subtitle: Text("Receive notifications via SMS"),
            trailing: Switch(
              value: smsNotifications,
              onChanged: (val) => setState(() => smsNotifications = val),
              activeColor: Colors.teal,
            ),
          ),
          ListTile(
            leading: Icon(Icons.lock, color: Colors.teal),
            title: Text("Account Security"),
            subtitle: Text("Password, authentication & advanced security"),
            onTap: _showChangePasswordDialog,
            trailing: IconButton(
              icon: Icon(Icons.security, color: Colors.teal),
              onPressed: _showSecurityDialog,
              tooltip: 'Advanced Security Settings',
            ),
          ),
          ListTile(
            leading: Icon(Icons.sync, color: Colors.teal),
            title: Text("Cloud Backup & Sync"),
            subtitle: Text("Keep your data synced & backed up"),
            trailing: Switch(
              value: cloudSync,
              onChanged: (val) => setState(() => cloudSync = val),
              activeColor: Colors.teal,
            ),
          ),
          ListTile(
            leading: Icon(Icons.wifi_off, color: Colors.teal),
            title: Text("Offline Mode"),
            subtitle: Text("Work without internet connection"),
            trailing: Switch(
              value: offlineMode,
              onChanged: (val) => setState(() => offlineMode = val),
              activeColor: Colors.teal,
            ),
          ),
          ListTile(
            leading: Icon(Icons.auto_graph, color: Colors.teal),
            title: Text("Automated Reports"),
            subtitle: Text("Send scheduled reports via email"),
            trailing: Switch(
              value: automatedReports,
              onChanged: (val) => setState(() => automatedReports = val),
              activeColor: Colors.teal,
            ),
          ),
          ListTile(
            leading: Icon(Icons.language, color: Colors.teal),
            title: Text("Language"),
            subtitle: Text("Choose app language"),
            trailing: DropdownButton<String>(
              value: language,
              underline: Container(),
              items: ['English', 'Filipino', 'Spanish'].map((lang) =>
                  DropdownMenuItem(child: Text(lang), value: lang)
              ).toList(),
              onChanged: (val) => setState(() => language = val!),
            ),
          ),
          Divider(height: 40),
          ListTile(
            leading: Icon(Icons.settings_accessibility, color: Colors.teal),
            title: Text("Font Size"),
            subtitle: Text("Adjust for accessibility"),
            trailing: Container(
              width: 120,
              child: Row(
                children: [
                  Icon(Icons.text_fields, color: Colors.teal, size: 18),
                  Expanded(
                    child: Slider(
                      value: fontSize,
                      min: 12,
                      max: 24,
                      divisions: 6,
                      label: "${fontSize.toInt()}",
                      onChanged: (val) => setState(() => fontSize = val),
                      activeColor: Colors.teal,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            leading: Icon(Icons.record_voice_over, color: Colors.teal),
            title: Text("Voice Assist"),
            subtitle: Text("Enable audio guidance"),
            trailing: Switch(
              value: voiceAssist,
              onChanged: (val) => setState(() => voiceAssist = val),
              activeColor: Colors.teal,
            ),
          ),
          Divider(height: 40),
          ListTile(
            leading: Icon(Icons.info_outline_rounded, color: Colors.teal),
            title: Text("About App"),
            subtitle: Text("Version: 1.0.0\nPOS for Ice Plant Oroquieta"),
          ),
          ListTile(
            leading: Icon(Icons.feedback, color: Colors.teal),
            title: Text("Send Feedback"),
            subtitle: Text("Let us know what you think."),
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text('Send Feedback'),
                  content: Text('Feedback popups or form go here.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text('Close', style: TextStyle(color: Colors.teal)),
                    )
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
