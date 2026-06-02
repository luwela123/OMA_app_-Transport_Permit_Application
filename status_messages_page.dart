import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

class StatusMessagesPage extends StatelessWidget {
  final String uid;
  final String permitId;
  final String typeKey;

  const StatusMessagesPage({
    super.key,
    required this.uid,
    required this.permitId,
    required this.typeKey,
  });

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseDatabase.instance.ref('permits/$uid/$typeKey/$permitId');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Message', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 1,
        shadowColor: Colors.black26,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: ref.onValue,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
            return const Center(child: Text('Message details not found.'));
          }

          final data = snapshot.data!.snapshot.value as Map;
          final status = data['status']?.toString() ?? 'Unknown';
          final statusReason = data['statusReason'] as String?;
          final reviewedAt = (data['reviewedAt'] is int) ? DateTime.fromMillisecondsSinceEpoch(data['reviewedAt']) : DateTime.now();
          final createdAt = (data['createdAt'] is int) ? DateTime.fromMillisecondsSinceEpoch(data['createdAt']) : DateTime.now();

          String message = 'Thank you for filing up the form. We have received your application and it is now pending review.';
          DateTime timestamp = createdAt;

          // Added "Paid" Status Logic here
          if (status.toLowerCase().contains('paid')) {
            final orNumber = data['orNumber'] as String?;
            final orAmount = data['orAmount'] as String?;
            final paidAtValue = data['paidAt'];
            final paidAt = (paidAtValue is int) ? DateTime.fromMillisecondsSinceEpoch(paidAtValue) : reviewedAt;
            
            message = 'Payment received successfully!\n\nAmount Paid: ₱${orAmount ?? '0.00'}\nO.R. Number: ${orNumber ?? 'N/A'}\n\nYour permit process is now officially complete. Thank you!';
            timestamp = paidAt;
          } 
          else if (status.toLowerCase().contains('approve')) {
            final claimDateStr = data['claimDate'] as String?;
            String claimDateDisplay = '';
            if (claimDateStr != null) {
              try {
                final date = DateTime.parse(claimDateStr);
                claimDateDisplay = DateFormat('MMMM d, yyyy').format(date);
              } catch (_) {}
            }
            message = 'Your application has been approved! You can claim your permit on $claimDateDisplay. ${statusReason ?? ''}';
            timestamp = reviewedAt;
          } else if (status.toLowerCase().contains('reject')) {
            message = 'Your application was rejected. Reason: ${statusReason ?? 'No reason provided.'}';
            timestamp = reviewedAt;
          } else if (status.toLowerCase().contains('cancel')) {
            message = 'You have cancelled this application. Reason: ${statusReason ?? 'No reason provided.'}';
            // Assuming cancellation time is not stored, fallback to reviewedAt or now
            timestamp = reviewedAt;
          }
          
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _MessageTile(
                timestamp: timestamp,
                message: message.trim(),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  final DateTime timestamp;
  final String message;

  const _MessageTile({required this.timestamp, required this.message});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              radius: 24,
              backgroundImage: AssetImage('assets/logo.png'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'OMA -admin',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const Spacer(),
                      Text(
                        DateFormat('h:mm a').format(timestamp),
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 15),
                  ),
                ],
              ),
            ),
          ],
        ),
        const Divider(height: 24),
      ],
    );
  }
}

// ---------------------------------------------------------
// ALL STATUS MESSAGES PAGE
// ---------------------------------------------------------

// Helper Data Class for a Status Message
class StatusMessage {
  final String permitId;
  final String typeKey;
  final String permitType; // e.g., "Plants and Products"
  final String detail;     // e.g., "Coconut"
  final String message;
  final DateTime timestamp;

  StatusMessage({
    required this.permitId,
    required this.typeKey,
    required this.permitType,
    required this.detail,
    required this.message,
    required this.timestamp,
  });
}

class AllStatusMessagesPage extends StatefulWidget {
  final String uid;
  const AllStatusMessagesPage({super.key, required this.uid});

  @override
  State<AllStatusMessagesPage> createState() => _AllStatusMessagesPageState();
}

class _AllStatusMessagesPageState extends State<AllStatusMessagesPage> {
  int? _expandedIndex;

  @override
  void initState() {
    super.initState();
    _markAllAsRead();
  }

  Future<void> _markAllAsRead() async {
    final ref = FirebaseDatabase.instance.ref('permits/${widget.uid}');
    final snapshot = await ref.get();
    if (!snapshot.exists) return;

    final allPermits = snapshot.value as Map;
    final Map<String, dynamic> updates = {};

    for (var typeEntry in allPermits.entries) {
      final typeKey = typeEntry.key;
      final permitsOfType = typeEntry.value as Map;
      for (var permitEntry in permitsOfType.entries) {
        final permitId = permitEntry.key;
        final permitData = permitEntry.value as Map;
        if (permitData['isNewStatusUpdate'] == true) {
          updates['permits/${widget.uid}/$typeKey/$permitId/isNewStatusUpdate'] = false;
        }
      }
    }

    if (updates.isNotEmpty) {
      await FirebaseDatabase.instance.ref().update(updates);
    }
  }

  List<StatusMessage> _parseMessages(dynamic root) {
    final List<StatusMessage> messages = [];
    if (root is! Map) return messages;

    root.forEach((typeKey, permits) {
      if (permits is! Map) return;
      permits.forEach((permitId, data) {
        if (data is! Map) return;

        final status = (data['status'] as String? ?? '').toLowerCase();
        
        // Added 'paid' condition to trigger notification fetch
        if (status.contains('approve') || status.contains('reject') || status.contains('cancel') || status.contains('paid')) {
          final statusReason = data['statusReason'] as String?;
          
          final timestampValue = data['paidAt'] ?? data['reviewedAt'] ?? data['cancelledAt'];
          final timestamp = (timestampValue is int) ? DateTime.fromMillisecondsSinceEpoch(timestampValue) : null;

          String message = 'Status was updated.';
          String permitDetail = (data['request']?['productType'] ?? data['request']?['animalType'] ?? '').toString();
          String permitTypeDisplay = (typeKey).toString().replaceFirst(typeKey[0], typeKey[0].toUpperCase());

          // Added "Paid" formatting
          if (status.contains('paid')) {
            final orNumber = data['orNumber'] as String?;
            final orAmount = data['orAmount'] as String?;
            message = 'Payment complete! Amount: ₱${orAmount ?? '0.00'} (O.R. No: ${orNumber ?? 'N/A'}). Your permit process is finished.';
          } else if (status.contains('approve')) {
            final claimDateStr = data['claimDate'] as String?;
            String claimDateDisplay = 'a future date';
            if (claimDateStr != null) {
              try {
                final date = DateTime.parse(claimDateStr);
                claimDateDisplay = DateFormat('MMMM d, yyyy').format(date);
              } catch (_) {}
            }
            message = 'Approved! You can claim your permit on $claimDateDisplay. ${statusReason ?? ''}'.trim();
          } else if (status.contains('reject')) {
            message = 'Rejected. Reason: ${statusReason ?? 'No reason provided.'}';
          } else if (status.contains('cancel')) {
            message = 'Cancelled by you. Reason: ${statusReason ?? 'No reason provided.'}';
          }

          if (timestamp != null) {
            messages.add(StatusMessage(
              permitId: permitId.toString(),
              typeKey: typeKey.toString(),
              permitType: permitTypeDisplay,
              detail: permitDetail,
              message: message,
              timestamp: timestamp,
            ));
          }
        }
      });
    });
    
    messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return messages;
  }

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseDatabase.instance.ref('permits/${widget.uid}');

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 245, 245, 245),
      appBar: AppBar(
        title: const Text(
          'Messages',
          style: TextStyle(
            color: Colors.black, // Set color to pure black
          ),
        ),
        backgroundColor: const Color.fromARGB(255, 255, 255, 255),
        elevation: 1,
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: ref.onValue,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
            return const Center(child: Text('No messages yet.'));
          }

          final messages = _parseMessages(snapshot.data!.snapshot.value);

          if (messages.isEmpty) {
            return const Center(child: Text('No messages yet.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final msg = messages[index];
              final isExpanded = _expandedIndex == index;

              return Card(
                color: const Color.fromARGB(255, 248, 243, 241),
                margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                elevation: isExpanded ? 4 : 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() {
                      _expandedIndex = isExpanded ? null : index;
                    });
                  },
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: isExpanded
                          ? _buildExpandedView(msg)
                          : _buildCollapsedView(msg),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildCollapsedView(StatusMessage msg) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          backgroundColor: Colors.green.withOpacity(0.1),
          foregroundColor: Colors.green,
          child: const Icon(Icons.mark_email_read_outlined),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Update for ${msg.permitType} Permit',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                msg.message,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade400),
      ],
    );
  }

  Widget _buildExpandedView(StatusMessage msg) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              radius: 24,
              backgroundImage: AssetImage('assets/logo.png'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'OMA - Admin',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                      ),
                      const Spacer(),
                      Text(
                        DateFormat('h:mm a').format(msg.timestamp),
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                   Text(
                    DateFormat('MMMM d, yyyy').format(msg.timestamp),
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if(msg.detail.isNotEmpty) ...[
          Text(
            'Regarding your application for a "${msg.detail}" permit:',
            style: TextStyle(color: Colors.grey.shade700, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 8),
        ],
        Text(
          msg.message,
          style: TextStyle(color: Colors.grey.shade800, fontSize: 15, height: 1.4),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.center,
          child: Icon(Icons.keyboard_arrow_up, color: Colors.grey.shade400),
        ),
      ],
    );
  }
}