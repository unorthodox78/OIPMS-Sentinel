import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PosSaleScreen extends StatefulWidget {
  final VoidCallback? onLogout;

  const PosSaleScreen({super.key, this.onLogout});

  @override
  State<PosSaleScreen> createState() => _PosSaleScreenState();
}

class _PosSaleScreenState extends State<PosSaleScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();
  int _selectedIndex = 0;
  int notificationCount = 3;

  final List<String> mainNavItems = ['POS Sale', 'Inventory', 'Reports'];
  final List<IconData> mainNavIcons = [
    Icons.point_of_sale,
    Icons.inventory,
    Icons.bar_chart,
  ];

  void _onNavTap(int idx, {bool inDrawer = false}) {
    if (inDrawer) {
      setState(() => _selectedIndex = 3); // Settings when tapped from drawer
    } else {
      setState(() => _selectedIndex = idx);
    }
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState?.closeDrawer();
    }
  }

  void _openProfileDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  Future<void> _onLogout() async {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState?.closeDrawer();
    }
    await FirebaseAuth.instance.signOut();
    if (widget.onLogout != null) {
      widget.onLogout!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;

    return Scaffold(
      key: _scaffoldKey,
      drawer: Drawer(
        elevation: 16,
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 32),
              CircleAvatar(
                backgroundColor: Colors.white70,
                radius: 32,
                child: Icon(Icons.person, color: const Color(0xFF754ef9), size: 32),
              ),
              const SizedBox(height: 18),
              Text(
                'Cashier',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF754ef9),
                  fontSize: 22,
                ),
              ),
              Text(
                'Oroquieta',
                style: GoogleFonts.poppins(
                  color: Colors.grey[700],
                  fontSize: 14,
                ),
              ),
              const Divider(height: 32),
              if (isPortrait) ...[
                ListTile(
                  leading: const Icon(Icons.point_of_sale, color: Color(0xFF754ef9)),
                  title: Text('POS Sale', style: GoogleFonts.poppins()),
                  selected: _selectedIndex == 0,
                  selectedTileColor: const Color(0xFF754ef9).withOpacity(0.10),
                  onTap: () {
                    setState(() => _selectedIndex = 0);
                    _scaffoldKey.currentState?.closeDrawer();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.inventory, color: Color(0xFF754ef9)),
                  title: Text('Inventory', style: GoogleFonts.poppins()),
                  selected: _selectedIndex == 1,
                  selectedTileColor: const Color(0xFF754ef9).withOpacity(0.10),
                  onTap: () {
                    setState(() => _selectedIndex = 1);
                    _scaffoldKey.currentState?.closeDrawer();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.bar_chart, color: Color(0xFF754ef9)),
                  title: Text('Reports', style: GoogleFonts.poppins()),
                  selected: _selectedIndex == 2,
                  selectedTileColor: const Color(0xFF754ef9).withOpacity(0.10),
                  onTap: () {
                    setState(() => _selectedIndex = 2);
                    _scaffoldKey.currentState?.closeDrawer();
                  },
                ),
              ],
              ListTile(
                leading: const Icon(Icons.settings, color: Color(0xFF754ef9)),
                title: Text('Settings', style: GoogleFonts.poppins()),
                selected: _selectedIndex == 3,
                selectedTileColor: const Color(0xFF754ef9).withOpacity(0.10),
                onTap: () {
                  setState(() => _selectedIndex = 3);
                  _scaffoldKey.currentState?.closeDrawer();
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout, color: Color(0xFF754ef9)),
                title: Text('Logout', style: GoogleFonts.poppins()),
                onTap: _onLogout,
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        backgroundColor: const Color(0xFF754ef9),
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 16),
            GestureDetector(
              onTap: _openProfileDrawer,
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.white70,
                    radius: 17,
                    child: Icon(Icons.person, color: const Color(0xFF754ef9)),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cashier',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Oroquieta',
                        style: GoogleFonts.poppins(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        automaticallyImplyLeading: false,
        leading: null,
        actions: [
          if (!isPortrait)
            ...mainNavItems.asMap().entries.map(
                  (entry) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: TextButton(
                  onPressed: () => setState(() => _selectedIndex = entry.key),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        entry.value,
                        style: GoogleFonts.poppins(
                          color: _selectedIndex == entry.key ? Colors.white : Colors.white70,
                          fontWeight: _selectedIndex == entry.key ? FontWeight.bold : FontWeight.normal,
                          fontSize: 15,
                        ),
                      ),
                      if (_selectedIndex == entry.key)
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          height: 2,
                          width: 28,
                          color: Colors.white,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          Stack(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.notifications_none,
                  color: Colors.white,
                  size: 26,
                ),
                onPressed: () {
                  setState(() => notificationCount = 0);
                },
              ),
              if (notificationCount > 0)
                Positioned(
                  right: 7,
                  top: 10,
                  child: CircleAvatar(
                    radius: 8,
                    backgroundColor: Colors.red,
                    child: Text(
                      '$notificationCount',
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return _buildPOSContent();
      case 1:
        return Center(
          child: Text(
            'Inventory Page',
            style: GoogleFonts.poppins(fontSize: 24, color: const Color(0xFF754ef9)),
          ),
        );
      case 2:
        return Center(
          child: Text(
            'Reports Page',
            style: GoogleFonts.poppins(fontSize: 24, color: const Color(0xFF754ef9)),
          ),
        );
      case 3:
        return Center(
          child: Text(
            'Settings Page',
            style: GoogleFonts.poppins(fontSize: 24, color: const Color(0xFF754ef9)),
          ),
        );
      default:
        return _buildPOSContent();
    }
  }

  Widget _buildPOSContent() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(20),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.point_of_sale, size: 64, color: const Color(0xFF754ef9)),
            const SizedBox(height: 20),
            Text(
              'POS Sale Screen',
              style: GoogleFonts.poppins(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF754ef9),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Cashier Interface - Ice Block Sales',
              style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}
