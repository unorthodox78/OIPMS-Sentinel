import 'package:flutter/material.dart';

class MonitoringTab extends StatelessWidget {
  const MonitoringTab({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22.0, 22.0, 22.0, 100.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Production & Inventory Monitoring',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),

            // Camera Preview Section
            Text(
              'Live Camera Monitoring',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 10),
            Row(
              children: [
                // Live Preview Camera Container
                Expanded(
                  child: Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[400]!, width: 2),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.videocam, size: 40, color: Colors.grey[600]),
                          SizedBox(height: 8),
                          Text(
                            'Live Preview Camera',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                          Text(
                            'Camera 1',
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 16),
                // Android Camera Preview Container
                Expanded(
                  child: Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[500]!, width: 2),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.camera_alt, size: 40, color: Colors.grey[700]),
                          SizedBox(height: 8),
                          Text(
                            'Android Camera Preview',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                          Text(
                            'Device Camera',
                            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 30),

            // KPI Dashboard Section
            Text(
              'Key Performance Indicators',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 10),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!, width: 1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildKPIItem('Total Sales', '₱12,540', Colors.green),
                  _buildKPIItem('Inventory', '850 blocks', Colors.blue),
                  _buildKPIItem('Discrepancies', '3', Colors.red),
                  _buildKPIItem('Active Shifts', '2', Colors.orange),
                ],
              ),
            ),
            SizedBox(height: 20),

            // Production Summary Section
            Text(
              'Production Summary',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 10),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green[200]!, width: 1),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Today\'s Production:', style: TextStyle(fontWeight: FontWeight.w500)),
                      Text('1,200 blocks', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Morning Shift:', style: TextStyle(fontSize: 14)),
                      Text('600 blocks', style: TextStyle(fontSize: 14)),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Afternoon Shift:', style: TextStyle(fontSize: 14)),
                      Text('600 blocks', style: TextStyle(fontSize: 14)),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: 20),

            // Inventory Status Section
            Text(
              'Inventory Status',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 10),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!, width: 1),
              ),
              child: Column(
                children: [
                  _buildInventoryItem('Ice Blocks', '450', 'Low Stock', Colors.red),
                  _buildInventoryItem('Ice Cubes', '200', 'Normal', Colors.green),
                  _buildInventoryItem('Broken Ice', '180', 'Normal', Colors.green),
                ],
              ),
            ),
            SizedBox(height: 20),

            // Alerts Section
            Text(
              'System Alerts',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 10),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[200]!, width: 1),
              ),
              child: Column(
                children: [
                  _buildAlertItem('Inventory Mismatch', 'Block count discrepancy detected', '10:30 AM'),
                  _buildAlertItem('Low Stock Warning', 'Ice blocks below threshold', '11:15 AM'),
                  _buildAlertItem('Camera Offline', 'Live preview camera disconnected', '2:45 PM'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKPIItem(String title, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          title,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildInventoryItem(String product, String quantity, String status, Color statusColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(product, style: TextStyle(fontWeight: FontWeight.w500)),
          Text('$quantity units', style: TextStyle(fontSize: 14)),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 12,
                color: statusColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertItem(String title, String description, String time) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning, color: Colors.red, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                ),
                Text(
                  description,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Text(
            time,
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}
