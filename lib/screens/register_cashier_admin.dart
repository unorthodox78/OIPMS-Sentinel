import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisterCashierAdminScreen extends StatelessWidget {
  const RegisterCashierAdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Approve Cashiers'),
        backgroundColor: const Color(0xFF24A8D8),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 8),
        children: [
          _CashierDataTable(
            title: 'Pending Cashier Requests',
            status: 'pending',
            onAction: (context, doc, approve) async {
              if (approve) {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(doc.id)
                    .update({'status': 'approved'});
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cashier approved!'), backgroundColor: Colors.green),
                );
              } else {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(doc.id)
                    .delete();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cashier deleted.'), backgroundColor: Colors.red),
                );
              }
            },
            showApprove: true,
          ),
          const SizedBox(height: 22),
          _CashierDataTable(
            title: 'Registered Cashiers in OIPMS',
            status: 'approved',
            onAction: (context, doc, _) async {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(doc.id)
                  .delete();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cashier deleted.'), backgroundColor: Colors.red),
              );
            },
            showApprove: false,
          ),
        ],
      ),
    );
  }
}

class _CashierDataTable extends StatelessWidget {
  final String title;
  final String status;
  final bool showApprove;
  final void Function(BuildContext, QueryDocumentSnapshot, bool) onAction;

  const _CashierDataTable({
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
            padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF24A8D8),
                      ),
                    ),
                  ),
                ),
                SingleChildScrollView(
                  // Make scrollable horizontally on small screens
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 22,
                    horizontalMargin: 6,
                    columns: const [
                      DataColumn(
                        label: Text('Username', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      DataColumn(
                        label: Text('Role', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      DataColumn(
                        label: Text('Action', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                    rows: docs.isEmpty
                        ? [
                      const DataRow(cells: [
                        DataCell(Text('No registered cashiers.', style: TextStyle(color: Colors.black54))),
                        DataCell(Text('')),
                        DataCell(Text('')),
                      ]),
                    ]
                        : docs.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      return DataRow(
                        cells: [
                          DataCell(
                            _DataCellContent(
                              text: displayValue(data['username']),
                              onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => CashierDetailScreen(data: data)),
                              ),
                            ),
                          ),
                          DataCell(
                            _DataCellContent(
                              text: displayValue(data['role']),
                              onTap: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => CashierDetailScreen(data: data)),
                              ),
                            ),
                          ),
                          DataCell(Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (showApprove)
                                TextButton.icon(
                                  icon: const Icon(Icons.check, color: Color(0xFF43A047), size: 22),
                                  label: const Text('Accept', style: TextStyle(color: Color(0xFF43A047))),
                                  onPressed: () => onAction(context, doc, true),
                                ),
                              TextButton.icon(
                                icon: const Icon(Icons.delete, color: Colors.red, size: 22),
                                label: const Text('Delete', style: TextStyle(color: Colors.red)),
                                onPressed: () => onAction(context, doc, false),
                              ),
                            ],
                          )),
                        ],
                      );
                    }).toList(),
                  ),
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

class _DataCellContent extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _DataCellContent({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFF222222),
            fontSize: 15,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }
}

class CashierDetailScreen extends StatelessWidget {
  final Map<String, dynamic> data;
  const CashierDetailScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cashier Details'),
        backgroundColor: const Color(0xFF24A8D8),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: data.entries.map((e) {
          return ListTile(
            dense: true,
            title: Text(
              e.key.replaceAll('_', ' ').toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              e.key.toLowerCase().contains('created')
                  ? formatTimestamp(e.value)
                  : _CashierDataTable.displayValue(e.value),
            ),
          );
        }).toList(),
      ),
    );
  }

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
