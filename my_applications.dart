import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../widgets/oma_background.dart';

class MyApplicationsPage extends StatelessWidget {
  const MyApplicationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = FirebaseDatabase.instance.ref('permits/$uid');

    return Scaffold(
      body: Stack(
        children: [
          const OmaBackground(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'Back',
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'My Applications',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Live list
                  Expanded(
                    child: StreamBuilder<DatabaseEvent>(
                      stream: ref.onValue,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final root = snap.data?.snapshot.value;
                        final items = _flattenPermits(root);
                        items.sort(
                          (a, b) => b.createdAt.compareTo(a.createdAt),
                        );

                        if (items.isEmpty) {
                          return const Center(
                            child: Text(
                              'No applications yet. Submit a permit to see it here.',
                            ),
                          );
                        }

                        return ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final r = items[i];
                            final dateStr = r.createdAt > 0
                                ? DateTime.fromMillisecondsSinceEpoch(
                                    r.createdAt,
                                  ).toLocal().toString()
                                : '';
                            final subtitle = StringBuffer()
                              ..write(r.permitType)
                              ..write(
                                r.detail.isNotEmpty ? ' • ${r.detail}' : '',
                              );

                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.black12),
                              ),
                              child: ListTile(
                                title: Text(
                                  subtitle.toString(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  dateStr,
                                  style: TextStyle(
                                    color: Colors.black.withOpacity(.6),
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: _StatusChip(status: r.status),
                                onTap: () {
                                  // Optional: push a user-facing details page
                                  // Navigator.push(context, MaterialPageRoute(builder: (_) => UserPermitDetails(row: r)));
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Flatten /permits/{uid}/{type}/{id} -> rows
  List<_UserPermitRow> _flattenPermits(dynamic root) {
    final out = <_UserPermitRow>[];
    if (root is! Map) return out;

    root.forEach((typeKey, permits) {
      if (permits is! Map) return;
      permits.forEach((pid, data) {
        if (data is! Map) return;

        final status = (data['status']?.toString() ?? 'submitted');
        final createdAt = (data['createdAt'] is num)
            ? (data['createdAt'] as num).toInt()
            : 0;
        final request = (data['request'] as Map?) ?? {};

        // Human readable type
        final prettyType = switch (typeKey.toString()) {
          'plants' => 'Plants and Products',
          'animals' => 'Animals and Livestock',
          'fishery' => 'Fishery shipping permits',
          _ => typeKey.toString(),
        };

        // Try to show a meaningful detail from request
        final detail =
            (request['productType'] ??
                    request['animalType'] ??
                    request['product'] ??
                    request['reason'] ??
                    '')
                .toString();

        out.add(
          _UserPermitRow(
            id: pid.toString(),
            typeKey: typeKey.toString(),
            permitType: prettyType,
            status: status,
            detail: detail,
            createdAt: createdAt,
          ),
        );
      });
    });

    return out;
  }
}

class _UserPermitRow {
  final String id;
  final String typeKey; // plants | animals | fishery
  final String permitType; // pretty
  final String status; // approved/rejected/submitted/under review
  final String detail; // e.g., Coconut or Pig, etc.
  final int createdAt;

  _UserPermitRow({
    required this.id,
    required this.typeKey,
    required this.permitType,
    required this.status,
    required this.detail,
    required this.createdAt,
  });
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  Color _color(String s) {
    final low = s.toLowerCase();
    if (low.contains('approve')) return const Color(0xFF1FAB64); // green
    if (low.contains('reject')) return Colors.red.shade700; // red
    return const Color(0xFFB3A400); // amber for submitted/under review
  }

  String _label(String s) {
    final low = s.toLowerCase();
    if (low.contains('approve')) return 'Approved';
    if (low.contains('reject')) return 'Rejected';
    if (low.contains('review')) return 'Under Review';
    if (low.contains('submit')) return 'Under Review';
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final c = _color(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withOpacity(.12),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.withOpacity(.5)),
      ),
      child: Text(
        _label(status),
        style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}
