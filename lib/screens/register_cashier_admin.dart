import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/audit_service.dart';

class RegisterCashierAdminScreen extends StatefulWidget {
  const RegisterCashierAdminScreen({super.key});

  @override
  State<RegisterCashierAdminScreen> createState() =>
      _RegisterCashierAdminScreenState();
}

class _RegisterCashierAdminScreenState
    extends State<RegisterCashierAdminScreen> {
  @override
  void initState() {
    super.initState();
    _ensureAdmin();
  }

  Future<void> _ensureAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role');
    if (!mounted) return;
    if (role != 'admin') {
      await AuditService.instance.log(
        event: 'access_denied',
        data: {
          'screen': 'RegisterCashier',
          'required_role': 'admin',
          'actual_role': role,
        },
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Access denied: Admins only')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        backgroundColor: const Color(0xFF4267B2),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 10),
        children: [
          _CashierCardTable(
            title: 'Pending Cashier Requests',
            status: 'pending',
            showApprove: true,
            onAction: (context, doc, approve) async {
              if (approve) {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(doc.id)
                    .update({'status': 'approved'});
                await AuditService.instance.log(
                  event: 'admin_cashier_approved',
                  data: {'cashier_uid': doc.id},
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Cashier approved!'),
                    backgroundColor: Colors.green,
                  ),
                );
              } else {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(doc.id)
                    .delete();
                await AuditService.instance.log(
                  event: 'admin_cashier_rejected',
                  data: {'cashier_uid': doc.id},
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Cashier deleted.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
          ),
          const SizedBox(height: 22),
          _CashierCardTable(
            title: 'Registered Cashiers in OIPMS',
            status: 'approved',
            showApprove: false,
            onAction: (context, doc, _) async {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(doc.id)
                  .delete();
              await AuditService.instance.log(
                event: 'admin_cashier_deleted',
                data: {'cashier_uid': doc.id},
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Cashier deleted.'),
                  backgroundColor: Colors.red,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CashierCardTable extends StatelessWidget {
  final String title;
  final String status;
  final bool showApprove;
  final void Function(BuildContext, QueryDocumentSnapshot, bool) onAction;

  const _CashierCardTable({
    required this.title,
    required this.status,
    required this.onAction,
    required this.showApprove,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'cashier')
          .where('status', isEqualTo: status)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Card(
            elevation: 4,
            margin: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }
        final docs = snapshot.data!.docs;
        return Card(
          elevation: 6,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          margin: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF24A8D8),
                      ),
                    ),
                  ),
                ),
                if (docs.isEmpty)
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 16),
                    child: const Center(
                      child: Text(
                        'No cashiers found.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    separatorBuilder: (_, __) =>
                        Divider(height: 19, thickness: 0.8),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final hasPhoto =
                          data['profilePhoto'] != null &&
                          (data['profilePhoto'] as String).isNotEmpty;
                      final avatar = hasPhoto
                          ? NetworkImage(data['profilePhoto'])
                          : const AssetImage('assets/profile.png')
                                as ImageProvider;

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: avatar,
                          radius: 27,
                        ),
                        title: Text(
                          displayValue(data['username']),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        subtitle: Text(
                          displayValue(data['role']),
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 14,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (showApprove)
                              IconButton(
                                icon: const Icon(
                                  Icons.check_circle,
                                  color: Color(0xFF43A047),
                                ),
                                tooltip: "Approve",
                                onPressed: () => onAction(context, doc, true),
                              ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              tooltip: "Delete",
                              onPressed: () => onAction(context, doc, false),
                            ),
                          ],
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CashierDetailScreen(data: data),
                            settings: const RouteSettings(
                              name: 'CashierDetail',
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  static String displayValue(dynamic value) {
    if (value == null) return '';
    if (value is List) return value.join(', ');
    return value.toString();
  }
}

class CashierDetailScreen extends StatelessWidget {
  final Map<String, dynamic> data;
  const CashierDetailScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    String? photoUrl = data['profilePhoto'];
    final avatar = (photoUrl != null && photoUrl.isNotEmpty)
        ? NetworkImage(photoUrl)
        : const AssetImage('assets/profile.png') as ImageProvider;

    String simpleValue(dynamic val) {
      if (val == null) return '';
      if (val is List) return val.join(', ');
      return val.toString();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cashier Details'),
        backgroundColor: const Color(0xFF24A8D8),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 28),
            CircleAvatar(
              radius: 50,
              backgroundColor: const Color(0xFF24A8D8).withOpacity(0.13),
              backgroundImage: avatar,
            ),
            const SizedBox(height: 15),
            Text(
              simpleValue(data['username']).isNotEmpty
                  ? simpleValue(data['username'])
                  : "Cashier",
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            if (simpleValue(data['email']).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(
                  simpleValue(data['email']),
                  style: const TextStyle(color: Colors.grey, fontSize: 15),
                ),
              ),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              elevation: 5,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 19,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    detailRow('Role', simpleValue(data['role'])),
                    detailRow('Phone', simpleValue(data['phone'])),
                    detailRow('Status', simpleValue(data['status'])),
                    detailRow('Created At', formatTimestamp(data['createdAt'])),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7.5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: Color(0xFF349ECD),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontWeight: FontWeight.w400,
              fontSize: 16,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    ),
  );

  static String formatTimestamp(dynamic value) {
    if (value == null) return '';
    if (value is Timestamp) {
      final dt = value.toDate();
      return '${dt.year}-${_two(dt.month)}-${_two(dt.day)} '
          '${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}';
    }
    return value.toString();
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
