import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../firebase_service.dart';
import '../models/permit_row.dart';
import 'permit_details.dart';

/* ═══════════════════════ THEME CONSTANTS ═══════════════════════ */

const _kSidebarGreen = Color.fromARGB(255, 2, 221, 93);
const _kBg = Color(0xFFF1F5F9);
const _kBlue = Color(0xFF2563EB); 
const _kAmber = Color(0xFFF59E0B);
const _kEmerald = Color(0xFF10B981);
const _kRose = Color(0xFFEF4444);
const _kSlate = Color(0xFF64748B);
const _kSlate900 = Color(0xFF0F172A);

/* ═══════════════════════ ADMIN DASHBOARD ═══════════════════════ */

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _navIndex = 0;
  bool _loading = true;
  String? _error;
  List<PermitRow> _permitRows = [];

  @override
  void initState() {
    super.initState();
    _ensureAdminAndLoad();
  }

  Future<void> _ensureAdminAndLoad() async {
    try {
      await FirebaseService.instance.autoPromoteCurrentUser();
      if (!mounted) return;
      await _loadAllData();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error: $e';
        _loading = false;
      });
    }
  }

  Future<void> _loadAllData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final permitData = await FirebaseService.instance.dbGet('permits');
      if (!mounted) return;
      final permitList = _flattenPermits(permitData);
      permitList.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      setState(() {
        _permitRows = permitList;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load data: $e';
        _loading = false;
      });
    }
  }

  List<PermitRow> _flattenPermits(dynamic root) {
    final out = <PermitRow>[];
    if (root is! Map) return out;
    root.forEach((uid, types) {
      if (types is! Map) return;
      types.forEach((type, permits) {
        if (permits is! Map) return;
        permits.forEach((pid, data) {
          if (data is! Map) return;
          final status = data['status']?.toString() ?? 'submitted';
          if (status == 'cancelled by user') return;
          final applicant = (data['applicant'] as Map?) ?? {};
          final createdAt = (data['createdAt'] is num)
              ? (data['createdAt'] as num).toInt()
              : 0;
          final first = applicant['firstName']?.toString() ?? '';
          final last = applicant['lastName']?.toString() ?? '';
          var name =
              [first, last].where((s) => s.trim().isNotEmpty).join(' ').trim();
          if (name.isEmpty) name = applicant['sender']?.toString() ?? '';
          if (name.isEmpty) {
            name = applicant['contact']?.toString() ?? 'Unknown Applicant';
          }
          out.add(PermitRow(
            applicant: name,
            permitType: _prettyType(type.toString()),
            status: status,
            createdAt: createdAt,
            id: pid.toString(),
            uid: uid.toString(),
            typeKey: type.toString(),
          ));
        });
      });
    });
    return out;
  }

  static String _prettyType(String t) {
    switch (t) {
      case 'plants':
        return 'Plants and Products';
      case 'animals':
        return 'Animals and Livestock';
      default:
        return t;
    }
  }

  Future<void> _openDetails(PermitRow r) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => PermitDetailsPage(row: r)));
    if (!mounted) return;
    _loadAllData();
  }

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.logout_rounded, color: _kRose, size: 22),
          SizedBox(width: 10),
          Text('Log Out'),
        ]),
        content: const Text('Are you sure you want to log out?'),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: _kSlate)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _kRose,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await FirebaseService.instance.signOut();
              if (!mounted) return;
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseService.instance.auth.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: _kBg,
      body: Row(
        children: [
          _Sidebar(
            email: user.email ?? user.uid,
            selectedIndex: _navIndex,
            onSelect: (i) => setState(() => _navIndex = i),
            onLogout: _handleLogout,
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(loading: _loading, onRefresh: _loadAllData),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                    child: _error != null
                        ? Center(
                            child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.error_outline_rounded,
                                  size: 48, color: _kRose.withOpacity(0.6)),
                              const SizedBox(height: 12),
                              Text(_error!,
                                  style: const TextStyle(color: _kRose)),
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: _loadAllData,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Retry'),
                              ),
                            ],
                          ))
                        : AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: [
                              _DashboardView(
                                  key: const ValueKey(0), rows: _permitRows),
                              _ApplicationsView(
                                  key: const ValueKey(1),
                                  rows: _permitRows,
                                  onRowTap: _openDetails),
                              _ReportsView(
                                  key: const ValueKey(2), rows: _permitRows),
                              const _AboutView(key: ValueKey(3)),
                            ][_navIndex],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/* ═══════════════════════ TOP BAR ═══════════════════════ */

class _TopBar extends StatelessWidget {
  final bool loading;
  final VoidCallback onRefresh;
  const _TopBar({required this.loading, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 22, 32, 14),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Welcome back, Admin 👋',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: _kSlate900)),
              const SizedBox(height: 2),
              Text(_formatToday(),
                  style:
                      TextStyle(fontSize: 12, color: _kSlate.withOpacity(0.8))),
            ],
          ),
          const Spacer(),
          if (loading)
            const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: _kSidebarGreen))
          else
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              elevation: 1,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: onRefresh,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child:
                      Icon(Icons.refresh_rounded, color: _kSlate, size: 20),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _formatToday() {
    final now = DateTime.now();
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
      'Sunday'
    ];
    return '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}, ${now.year}';
  }
}

/* ═══════════════════════ SIDEBAR ═══════════════════════ */

class _Sidebar extends StatelessWidget {
  final String email;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;

  const _Sidebar({
    required this.email,
    required this.selectedIndex,
    required this.onSelect,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      color: _kSidebarGreen,
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: ClipOval(
                child: Image.asset('assets/logo.png',
                    width: 90, height: 90, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'ADMIN',
              style: TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                email,
                style: TextStyle(
                    color: Colors.black.withOpacity(0.55), fontSize: 11),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(height: 40),

            _SidebarItem(
              icon: Icons.dashboard_outlined,
              label: 'Dashboard',
              isSelected: selectedIndex == 0,
              onTap: () => onSelect(0),
            ),
            const SizedBox(height: 6),
            _SidebarItem(
              icon: Icons.description_outlined,
              label: 'Applications',
              isSelected: selectedIndex == 1,
              onTap: () => onSelect(1),
            ),
            const SizedBox(height: 6),
            _SidebarItem(
              icon: Icons.assessment_outlined,
              label: 'Reports',
              isSelected: selectedIndex == 2,
              onTap: () => onSelect(2),
            ),
            const SizedBox(height: 6),
            _SidebarItem(
              icon: Icons.info_outline_rounded,
              label: 'About',
              isSelected: selectedIndex == 3,
              onTap: () => onSelect(3),
            ),

            const Spacer(),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
              child: InkWell(
                onTap: onLogout,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.logout,
                          color: Colors.black.withOpacity(0.7), size: 20),
                      const SizedBox(width: 14),
                      Text('Log out',
                          style: TextStyle(
                              color: Colors.black.withOpacity(0.7),
                              fontSize: 15)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 20),
      decoration: isSelected
          ? const BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.horizontal(left: Radius.circular(30)),
            )
          : null,
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: Colors.black, size: 22),
        title: Text(
          label,
          style: TextStyle(
            color: Colors.black,
            fontSize: 15,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.horizontal(left: Radius.circular(30)),
        ),
      ),
    );
  }
}

/* ═══════════════════════ HELPERS ═══════════════════════ */

int _countStatus(List<PermitRow> list, String keyword) =>
    list.where((r) => r.status.toLowerCase().contains(keyword)).length;

int _countReview(List<PermitRow> list) => list.where((r) {
      final s = r.status.toLowerCase();
      return !s.contains('approve') &&
          !s.contains('reject') &&
          !s.contains('cancel') &&
          !s.contains('paid'); 
    }).length;

String _fmtDate(int millis) {
  if (millis == 0) return 'N/A';
  final d = DateTime.fromMillisecondsSinceEpoch(millis);
  const m = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${m[d.month - 1]} ${d.day}, ${d.year}';
}

String _statusLabel(String s) {
  final low = s.toLowerCase();
  if (low.contains('paid')) return 'Paid';
  if (low.contains('approve')) return 'Approved';
  if (low.contains('reject')) return 'Rejected';
  return 'Under Review';
}

String _typeKeyFromLabel(String label) {
  switch (label) {
    case 'Plants':
      return 'plants';
    case 'Animals':
      return 'animals';
    default:
      return label;
  }
}

/* ═══════════════════════ STATUS BADGE ═══════════════════════ */

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final low = status.toLowerCase();
    final Color bg, fg;
    final String text;
    
    if (low.contains('paid')) {
      bg = _kBlue.withOpacity(0.10);
      fg = _kBlue;
      text = 'Paid';
    } else if (low.contains('approve')) {
      bg = _kEmerald.withOpacity(0.10);
      fg = const Color(0xFF059669);
      text = 'Approved';
    } else if (low.contains('reject')) {
      bg = _kRose.withOpacity(0.10);
      fg = const Color(0xFFDC2626);
      text = 'Rejected';
    } else {
      bg = _kAmber.withOpacity(0.10);
      fg = const Color(0xFFD97706);
      text = 'Under Review';
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style:
              TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/* ═══════════════════════ DASHBOARD VIEW ═══════════════════════ */

class _DashboardView extends StatelessWidget {
  final List<PermitRow> rows;
  const _DashboardView({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    final total = rows.length;
    final review = _countReview(rows);
    final approved = _countStatus(rows, 'approve');
    final paid = _countStatus(rows, 'paid');
    final rejected = _countStatus(rows, 'reject');

    final plants = rows.where((r) => r.typeKey == 'plants').toList();
    final animals = rows.where((r) => r.typeKey == 'animals').toList();
    final recent = rows.take(5).toList();

    return ListView(
      children: [
        const Text('Dashboard',
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: _kSlate900)),
        const SizedBox(height: 20),

        Row(children: [
          _SummaryCard(
              icon: Icons.inbox_rounded,
              label: 'Total',
              count: total,
              gradient: const [Color(0xFF8B5CF6), Color(0xFF6D28D9)]), 
          const SizedBox(width: 12),
          _SummaryCard(
              icon: Icons.schedule_rounded,
              label: 'Review',
              count: review,
              gradient: const [Color(0xFFFBBF24), Color(0xFFD97706)]),
          const SizedBox(width: 12),
          _SummaryCard(
              icon: Icons.check_circle_rounded,
              label: 'Approved',
              count: approved,
              gradient: const [Color(0xFF34D399), Color(0xFF059669)]),
          const SizedBox(width: 12),
          _SummaryCard(
              icon: Icons.receipt_long_rounded,
              label: 'Paid',
              count: paid,
              gradient: const [Color(0xFF60A5FA), Color(0xFF2563EB)]), 
          const SizedBox(width: 12),
          _SummaryCard(
              icon: Icons.cancel_rounded,
              label: 'Rejected',
              count: rejected,
              gradient: const [Color(0xFFFB7185), Color(0xFFE11D48)]),
        ]),
        const SizedBox(height: 24),

        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: _BreakdownCard(
                  title: 'Plants & Products',
                  icon: Icons.local_florist_rounded,
                  rows: plants,
                  accent: const Color(0xFF4CAF50))),
          const SizedBox(width: 16),
          Expanded(
              child: _BreakdownCard(
                  title: 'Animals & Livestock',
                  icon: Icons.pets_rounded,
                  rows: animals,
                  accent: const Color(0xFF8D6E63))),
          const SizedBox(width: 16),
        ]),
        const SizedBox(height: 24),

        if (recent.isNotEmpty) _RecentCard(rows: recent),
      ],
    );
  }
}

/* ── Summary Card ── */

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final List<Color> gradient;

  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.count,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradient),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: gradient.first.withOpacity(0.35),
                blurRadius: 16,
                offset: const Offset(0, 8))
          ],
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.20),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 18),
          Text(count.toString(),
              style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1)),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.85),
                  fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}

/* ── Breakdown Card ── */

class _BreakdownCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<PermitRow> rows;
  final Color accent;

  const _BreakdownCard({
    required this.title,
    required this.icon,
    required this.rows,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final review = _countReview(rows);
    final approved = _countStatus(rows, 'approve');
    final paid = _countStatus(rows, 'paid'); 
    final rejected = _countStatus(rows, 'reject');

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 6))
        ],
      ),
      child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
                color: accent.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600))),
          Text(rows.length.toString(),
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: accent)),
        ]),
        const SizedBox(height: 18),
        Divider(color: Colors.grey.shade200, height: 1),
        const SizedBox(height: 14),
        _DotRow(label: 'Under Review', value: review, color: _kAmber),
        const SizedBox(height: 10),
        _DotRow(label: 'Approved', value: approved, color: _kEmerald),
        const SizedBox(height: 10),
        _DotRow(label: 'Paid', value: paid, color: _kBlue),
        const SizedBox(height: 10),
        _DotRow(label: 'Rejected', value: rejected, color: _kRose),
      ]),
    );
  }
}

class _DotRow extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _DotRow(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
          width: 9,
          height: 9,
          decoration:
              BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 10),
      Text(label, style: const TextStyle(fontSize: 13, color: _kSlate)),
      const Spacer(),
      Text(value.toString(),
          style:
              const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
    ]);
  }
}

/* ── Recent Card ── */

class _RecentCard extends StatelessWidget {
  final List<PermitRow> rows;
  const _RecentCard({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 6))
        ],
      ),
      child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.history_rounded, color: _kSlate, size: 20),
          const SizedBox(width: 8),
          const Text('Recent Applications',
              style:
                  TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text('${rows.length} latest',
              style: TextStyle(
                  fontSize: 12, color: _kSlate.withOpacity(0.7))),
        ]),
        const SizedBox(height: 16),
        ...rows.map((r) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                  color: _kBg, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: _kSidebarGreen.withOpacity(0.15),
                  child: Text(
                      r.applicant.isNotEmpty
                          ? r.applicant[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          color: Color(0xFF15803D),
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ),
                const SizedBox(width: 12),
                Expanded(
                    flex: 2,
                    child: Text(r.applicant,
                        style: const TextStyle(
                            fontWeight: FontWeight.w500, fontSize: 13),
                        overflow: TextOverflow.ellipsis)),
                Expanded(
                    flex: 2,
                    child: Text(r.permitType,
                        style: const TextStyle(
                            color: _kSlate, fontSize: 12))),
                _StatusBadge(status: r.status),
                const SizedBox(width: 16),
                Text(_fmtDate(r.createdAt),
                    style:
                        const TextStyle(color: _kSlate, fontSize: 11)),
              ]),
            )),
      ]),
    );
  }
}

/* ═══════════════════════ APPLICATIONS VIEW ═══════════════════════ */

class _ApplicationsView extends StatefulWidget {
  final List<PermitRow> rows;
  final ValueChanged<PermitRow> onRowTap;
  const _ApplicationsView(
      {super.key, required this.rows, required this.onRowTap});

  @override
  State<_ApplicationsView> createState() => _ApplicationsViewState();
}

class _ApplicationsViewState extends State<_ApplicationsView> {
  String _search = '';
  String _statusFilter = 'All';
  String _typeFilter = 'All';

  List<PermitRow> get _filtered {
    return widget.rows.where((r) {
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        if (!r.applicant.toLowerCase().contains(q) &&
            !r.permitType.toLowerCase().contains(q)) return false;
      }
      if (_statusFilter != 'All') {
        final s = r.status.toLowerCase();
        if (_statusFilter == 'Under Review' &&
            (s.contains('approve') || s.contains('reject') || s.contains('paid'))) return false;
        if (_statusFilter == 'Approved' && !s.contains('approve'))
          return false;
        if (_statusFilter == 'Paid' && !s.contains('paid')) 
          return false;
        if (_statusFilter == 'Rejected' && !s.contains('reject'))
          return false;
      }
      if (_typeFilter != 'All') {
        if (r.typeKey != _typeKeyFromLabel(_typeFilter)) return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Applications',
          style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: _kSlate900)),
      const SizedBox(height: 16),

      Row(children: [
        Expanded(
          flex: 3,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by name or permit type…',
                hintStyle: TextStyle(
                    color: _kSlate.withOpacity(0.45), fontSize: 14),
                prefixIcon:
                    const Icon(Icons.search_rounded, color: _kSlate),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
        ),
        const SizedBox(width: 12),
        _FilterChip(
            value: _typeFilter,
            items: const ['All', 'Plants', 'Animals'],
            onChanged: (v) => setState(() => _typeFilter = v ?? 'All')),
        const SizedBox(width: 12),
        _FilterChip(
            value: _statusFilter,
            items: const [
              'All',
              'Under Review',
              'Approved',
              'Paid', 
              'Rejected'
            ],
            onChanged: (v) =>
                setState(() => _statusFilter = v ?? 'All')),
      ]),
      const SizedBox(height: 12),
      Text(
          '${rows.length} result${rows.length != 1 ? 's' : ''}',
          style: TextStyle(
              color: _kSlate.withOpacity(0.7), fontSize: 13)),
      const SizedBox(height: 8),

      Expanded(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 6))
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Column(children: [
              Container(
                color: const Color(0xFFF8FAFC),
                padding: const EdgeInsets.symmetric(
                    horizontal: 22, vertical: 14),
                child: const Row(children: [
                  Expanded(
                      flex: 3,
                      child: Text('Applicant',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _kSlate,
                              fontSize: 12,
                              letterSpacing: 0.5))),
                  Expanded(
                      flex: 3,
                      child: Text('Permit Type',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _kSlate,
                              fontSize: 12,
                              letterSpacing: 0.5))),
                  Expanded(
                      flex: 2,
                      child: Text('Status',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _kSlate,
                              fontSize: 12,
                              letterSpacing: 0.5))),
                  Expanded(
                      flex: 2,
                      child: Text('Date',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _kSlate,
                              fontSize: 12,
                              letterSpacing: 0.5))),
                  SizedBox(
                      width: 70,
                      child: Text('Ref #',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _kSlate,
                              fontSize: 12,
                              letterSpacing: 0.5))),
                ]),
              ),
              const Divider(height: 1),

              Expanded(
                child: rows.isEmpty
                    ? Center(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                            Icon(Icons.search_off_rounded,
                                size: 48,
                                color: _kSlate.withOpacity(0.25)),
                            const SizedBox(height: 8),
                            const Text('No applications found',
                                style: TextStyle(color: _kSlate)),
                          ]))
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: Colors.grey.shade100,
                            indent: 22,
                            endIndent: 22),
                        itemBuilder: (_, i) {
                          final r = rows[i];
                          final ref = (rows.length - i)
                              .toString()
                              .padLeft(6, '0');
                          return InkWell(
                            onTap: () => widget.onRowTap(r),
                            hoverColor: const Color(0xFFF0FDF4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 22, vertical: 14),
                              child: Row(children: [
                                Expanded(
                                  flex: 3,
                                  child: Row(children: [
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor:
                                          _kSidebarGreen.withOpacity(0.12),
                                      child: Text(
                                          r.applicant.isNotEmpty
                                              ? r.applicant[0]
                                                  .toUpperCase()
                                              : '?',
                                          style: const TextStyle(
                                              color: Color(0xFF15803D),
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13)),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                        child: Text(r.applicant,
                                            style: const TextStyle(
                                                fontWeight:
                                                    FontWeight.w500,
                                                fontSize: 13),
                                            overflow:
                                                TextOverflow.ellipsis)),
                                  ]),
                                ),
                                Expanded(
                                    flex: 3,
                                    child: Text(r.permitType,
                                        style: const TextStyle(
                                            color: _kSlate,
                                            fontSize: 13))),
                                Expanded(
                                    flex: 2,
                                    child: Align(
                                        alignment:
                                            Alignment.centerLeft,
                                        child: _StatusBadge(
                                            status: r.status))),
                                Expanded(
                                    flex: 2,
                                    child: Text(
                                        _fmtDate(r.createdAt),
                                        style: const TextStyle(
                                            color: _kSlate,
                                            fontSize: 13))),
                                SizedBox(
                                  width: 70,
                                  child: Text(ref,
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(
                                          fontFamily: 'monospace',
                                          color: _kSlate,
                                          fontSize: 13)),
                                ),
                              ]),
                            ),
                          );
                        },
                      ),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}

class _FilterChip extends StatelessWidget {
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  const _FilterChip(
      {required this.value,
      required this.items,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          items: items
              .map((e) => DropdownMenuItem(
                  value: e,
                  child:
                      Text(e, style: const TextStyle(fontSize: 14))))
              .toList(),
          onChanged: onChanged,
          icon: const Icon(Icons.expand_more_rounded,
              color: _kSlate, size: 20),
          style: const TextStyle(color: _kSlate900),
        ),
      ),
    );
  }
}

/* ═══════════════════════ REPORTS VIEW ═══════════════════════ */

class _ReportsView extends StatefulWidget {
  final List<PermitRow> rows;
  const _ReportsView({super.key, required this.rows});

  @override
  State<_ReportsView> createState() => _ReportsViewState();
}

class _ReportsViewState extends State<_ReportsView> {
  String _typeFilter = 'All';
  String _statusFilter = 'All';

  List<PermitRow> get _filtered {
    return widget.rows.where((r) {
      if (_typeFilter != 'All' &&
          r.typeKey != _typeKeyFromLabel(_typeFilter)) return false;
      if (_statusFilter != 'All') {
        final s = r.status.toLowerCase();
        if (_statusFilter == 'Under Review' &&
            (s.contains('approve') || s.contains('reject') || s.contains('paid'))) return false;
        if (_statusFilter == 'Approved' && !s.contains('approve'))
          return false;
        if (_statusFilter == 'Paid' && !s.contains('paid')) 
          return false;
        if (_statusFilter == 'Rejected' && !s.contains('reject'))
          return false;
      }
      return true;
    }).toList();
  }

  /* ── Build PDF bytes ── */

  Future<Uint8List> _buildPdf() async {
    final data = List<PermitRow>.from(_filtered)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final total = data.length;
    final review = _countReview(data);
    final approved = _countStatus(data, 'approve');
    final paid = _countStatus(data, 'paid'); 
    final rejected = _countStatus(data, 'reject');

    final plantsAll = data.where((r) => r.typeKey == 'plants').toList();
    final animalsAll = data.where((r) => r.typeKey == 'animals').toList();

    final greenDark = PdfColor.fromHex('#166534');
    final greyBg = PdfColor.fromHex('#F8FAFC');
    final greyText = PdfColor.fromHex('#64748B');

    final titleStyle = pw.TextStyle(
        fontSize: 18, fontWeight: pw.FontWeight.bold, color: greenDark);
    final headStyle = pw.TextStyle(
        fontSize: 13, fontWeight: pw.FontWeight.bold, color: greenDark);
    final tinyStyle = pw.TextStyle(fontSize: 8, color: greyText);
    final cellStyle = pw.TextStyle(fontSize: 9);

    final pdf = pw.Document(
      title: 'Permit Applications Report',
      author: 'Admin',
    );

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(36),

      /* HEADER */
      header: (ctx) => pw.Column(children: [
        pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('MUNICIPAL AGRICULTURE OFFICE',
                        style: pw.TextStyle(
                            fontSize: 14,
                            fontWeight: pw.FontWeight.bold,
                            color: greenDark)),
                    pw.SizedBox(height: 3),
                    pw.Text('Permit Applications Report',
                        style: titleStyle),
                  ]),
              pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                        'Generated: ${_fmtDate(DateTime.now().millisecondsSinceEpoch)}',
                        style: tinyStyle),
                    pw.SizedBox(height: 2),
                    pw.Text(
                        'Filters — Type: $_typeFilter  |  Status: $_statusFilter',
                        style: tinyStyle),
                  ]),
            ]),
        pw.SizedBox(height: 8),
        pw.Divider(color: greenDark, thickness: 2),
        pw.SizedBox(height: 14),
      ]),

      /* FOOTER */
      footer: (ctx) => pw.Column(children: [
        pw.Divider(color: PdfColors.grey400),
        pw.SizedBox(height: 4),
        pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Generated by e-Permitting System',
                  style: tinyStyle),
              pw.Text(
                  'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                  style: tinyStyle),
            ]),
      ]),

      /* BODY */
      build: (ctx) => [
        pw.Text('SUMMARY', style: headStyle),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(
              vertical: 14, horizontal: 24),
          decoration: pw.BoxDecoration(
              color: greyBg,
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
              children: [
                _pdfStat(
                    'Total Applications', '$total', greenDark),
                _pdfStat('Under Review', '$review',
                    PdfColor.fromHex('#D97706')),
                _pdfStat('Approved', '$approved',
                    PdfColor.fromHex('#059669')),
                _pdfStat('Paid', '$paid',
                    PdfColor.fromHex('#2563EB')),
                _pdfStat('Rejected', '$rejected',
                    PdfColor.fromHex('#DC2626')),
              ]),
        ),
        pw.SizedBox(height: 22),

        pw.Text('BREAKDOWN BY TYPE', style: headStyle),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          context: ctx,
          headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 10,
              color: PdfColors.white),
          headerDecoration: pw.BoxDecoration(color: greenDark),
          cellStyle: cellStyle,
          cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 10, vertical: 7),
          headers: [
            'Permit Type',
            'Total',
            'Under Review',
            'Approved',
            'Paid', 
            'Rejected'
          ],
          data: [
            _typeRow('Plants & Products', plantsAll),
            _typeRow('Animals & Livestock', animalsAll),
            ['TOTAL', '$total', '$review', '$approved', '$paid', '$rejected'],
          ],
        ),
        pw.SizedBox(height: 22),

        pw.Text('DETAILED APPLICATIONS  ($total)',
            style: headStyle),
        pw.SizedBox(height: 8),
        pw.TableHelper.fromTextArray(
          context: ctx,
          headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 9,
              color: PdfColors.white),
          headerDecoration: pw.BoxDecoration(color: greenDark),
          cellStyle: cellStyle,
          cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 8, vertical: 6),
          columnWidths: {
            0: const pw.FixedColumnWidth(55),
            1: const pw.FlexColumnWidth(3),
            2: const pw.FlexColumnWidth(3),
            3: const pw.FixedColumnWidth(80),
            4: const pw.FixedColumnWidth(90),
          },
          headers: [
            'Ref #',
            'Applicant',
            'Permit Type',
            'Status',
            'Date Submitted'
          ],
          data: data.asMap().entries.map((e) {
            final i = e.key;
            final r = e.value;
            return [
              (data.length - i).toString().padLeft(6, '0'),
              r.applicant,
              r.permitType,
              _statusLabel(r.status), 
              _fmtDate(r.createdAt),
            ];
          }).toList(),
        ),
      ],
    ));

    return pdf.save();
  }

  pw.Widget _pdfStat(String label, String value, PdfColor color) {
    return pw.Column(children: [
      pw.Text(value,
          style: pw.TextStyle(
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
              color: color)),
      pw.SizedBox(height: 4),
      pw.Text(label,
          style: pw.TextStyle(
              fontSize: 9, color: PdfColor.fromHex('#64748B'))),
    ]);
  }

  List<String> _typeRow(String name, List<PermitRow> list) {
    return [
      name,
      '${list.length}',
      '${_countReview(list)}',
      '${_countStatus(list, 'approve')}',
      '${_countStatus(list, 'paid')}',
      '${_countStatus(list, 'reject')}',
    ];
  }

  /* ── Navigate to preview ── */

  void _openPreview() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PdfPreviewPage(buildPdf: _buildPdf),
      ),
    );
  }

  /* ── UI ── */

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final total = filtered.length;
    final review = _countReview(filtered);
    final approved = _countStatus(filtered, 'approve');
    final paid = _countStatus(filtered, 'paid'); 
    final rejected = _countStatus(filtered, 'reject');

    return SingleChildScrollView(
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Generate Report',
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: _kSlate900)),
            const SizedBox(height: 6),
            Text(
                'Configure filters and preview the PDF report before printing.',
                style: TextStyle(
                    color: _kSlate.withOpacity(0.8), fontSize: 14)),
            const SizedBox(height: 28),

            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 6))
                ],
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.tune_rounded,
                          color: _kSlate, size: 20),
                      SizedBox(width: 8),
                      Text('Report Filters',
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 22),

                    Row(children: [
                      Expanded(
                          child: _buildDropdown(
                              'Permit Type',
                              _typeFilter,
                              const [
                                'All',
                                'Plants',
                                'Animals',
                              ], (v) {
                        setState(() => _typeFilter = v ?? 'All');
                      })),
                      const SizedBox(width: 20),
                      Expanded(
                          child: _buildDropdown(
                              'Status',
                              _statusFilter,
                              const [
                                'All',
                                'Under Review',
                                'Approved',
                                'Paid', 
                                'Rejected'
                              ], (v) {
                        setState(
                            () => _statusFilter = v ?? 'All');
                      })),
                      const SizedBox(width: 20),
                      const Expanded(child: SizedBox()),
                    ]),
                    const SizedBox(height: 28),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: _kBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            const Row(children: [
                              Icon(Icons.preview_rounded,
                                  size: 18, color: _kSlate),
                              SizedBox(width: 8),
                              Text('Preview Summary',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15)),
                            ]),
                            const SizedBox(height: 20),
                            Row(children: [
                              _PreviewNum(
                                  label: 'Total',
                                  value: total,
                                  color: const Color(0xFF8B5CF6)), 
                              const SizedBox(width: 30),
                              _PreviewNum(
                                  label: 'Review',
                                  value: review,
                                  color: _kAmber),
                              const SizedBox(width: 30),
                              _PreviewNum(
                                  label: 'Approved',
                                  value: approved,
                                  color: _kEmerald),
                              const SizedBox(width: 30),
                              _PreviewNum(
                                  label: 'Paid',
                                  value: paid,
                                  color: _kBlue), 
                              const SizedBox(width: 30),
                              _PreviewNum(
                                  label: 'Rejected',
                                  value: rejected,
                                  color: _kRose),
                            ]),
                          ]),
                    ),
                    const SizedBox(height: 28),

                    Row(children: [
                      SizedBox(
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed:
                              filtered.isEmpty ? null : _openPreview,
                          icon: const Icon(
                              Icons.visibility_rounded,
                              size: 20),
                          label: const Text(
                              'Preview & Print Report',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kSidebarGreen,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor:
                                Colors.grey.shade300,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(14)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 28),
                            elevation: 2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      if (filtered.isEmpty)
                        const Text(
                          'No data matches the selected filters.',
                          style: TextStyle(
                              color: _kSlate, fontSize: 13),
                        ),
                    ]),
                  ]),
            ),

            const SizedBox(height: 24),

            if (filtered.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 6))
                  ],
                ),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.table_chart_rounded,
                            color: _kSlate, size: 20),
                        const SizedBox(width: 8),
                        const Text('Data Preview',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: _kBlue.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                              '${filtered.length} record${filtered.length != 1 ? 's' : ''}',
                              style: const TextStyle(
                                  color: _kBlue,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ]),
                      const SizedBox(height: 16),

                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(children: [
                          SizedBox(
                              width: 70,
                              child: Text('Ref #',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: _kSlate,
                                      fontSize: 11))),
                          Expanded(
                              flex: 3,
                              child: Text('Applicant',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: _kSlate,
                                      fontSize: 11))),
                          Expanded(
                              flex: 3,
                              child: Text('Permit Type',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: _kSlate,
                                      fontSize: 11))),
                          Expanded(
                              flex: 2,
                              child: Text('Status',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: _kSlate,
                                      fontSize: 11))),
                          Expanded(
                              flex: 2,
                              child: Text('Date',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: _kSlate,
                                      fontSize: 11))),
                        ]),
                      ),
                      const SizedBox(height: 4),

                      ...filtered.take(10).toList().asMap().entries.map(
                            (e) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                border: Border(
                                    bottom: BorderSide(
                                        color: Colors.grey.shade100)),
                              ),
                              child: Row(children: [
                                SizedBox(
                                  width: 70,
                                  child: Text(
                                      (filtered.length - e.key)
                                          .toString()
                                          .padLeft(6, '0'),
                                      style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 12,
                                          color: _kSlate)),
                                ),
                                Expanded(
                                    flex: 3,
                                    child: Text(e.value.applicant,
                                        style: const TextStyle(
                                            fontSize: 12),
                                        overflow:
                                            TextOverflow.ellipsis)),
                                Expanded(
                                    flex: 3,
                                    child: Text(e.value.permitType,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: _kSlate))),
                                Expanded(
                                    flex: 2,
                                    child: Align(
                                        alignment:
                                            Alignment.centerLeft,
                                        child: _StatusBadge(
                                            status:
                                                e.value.status))),
                                Expanded(
                                    flex: 2,
                                    child: Text(
                                        _fmtDate(
                                            e.value.createdAt),
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: _kSlate))),
                              ]),
                            ),
                          ),

                      if (filtered.length > 10)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                              '… and ${filtered.length - 10} more record${filtered.length - 10 != 1 ? 's' : ''}',
                              style: TextStyle(
                                  color: _kSlate.withOpacity(0.7),
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic)),
                        ),
                    ]),
              ),
            ],
          ]),
    );
  }

  Widget _buildDropdown(String label, String value,
      List<String> items, ValueChanged<String?> onChanged) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: _kSlate)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              border:
                  Border.all(color: const Color(0xFFCBD5E1)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                items: items
                    .map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(e,
                            style:
                                const TextStyle(fontSize: 14))))
                    .toList(),
                onChanged: onChanged,
                icon: const Icon(Icons.expand_more_rounded,
                    color: _kSlate),
                style: const TextStyle(color: _kSlate900),
              ),
            ),
          ),
        ]);
  }
}

class _PreviewNum extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  const _PreviewNum(
      {required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value.toString(),
              style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: color)),
          const SizedBox(height: 2),
          Text(label,
              style:
                  const TextStyle(color: _kSlate, fontSize: 13)),
        ]);
  }
}

/* ═══════════════════════ PDF PREVIEW PAGE ═══════════════════════ */

class _PdfPreviewPage extends StatelessWidget {
  final Future<Uint8List> Function() buildPdf;
  const _PdfPreviewPage({required this.buildPdf});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: _kSidebarGreen,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Row(
          children: [
            Icon(Icons.picture_as_pdf_rounded, size: 22),
            SizedBox(width: 10),
            Text(
              'Report Preview',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                'Use the print button below to save or print',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.black.withOpacity(0.5)),
              ),
            ),
          ),
        ],
      ),
      body: PdfPreview(
        build: (_) => buildPdf(),
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        pdfFileName:
            'Permit_Report_${DateTime.now().millisecondsSinceEpoch}',
        loadingWidget: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: _kSidebarGreen),
              SizedBox(height: 16),
              Text('Generating report…',
                  style: TextStyle(color: _kSlate, fontSize: 14)),
            ],
          ),
        ),
        actions: const [
          PdfPreviewAction(
            icon: Icon(Icons.save_alt_rounded),
            onPressed: null,
          ),
        ],
      ),
    );
  }
}

/* ═══════════════════════ ABOUT VIEW ═══════════════════════ */

class _AboutView extends StatelessWidget {
  const _AboutView({super.key});

  @override
  Widget build(BuildContext context) {
    const devs = [
      _Dev(
          'Jelly D. Eldo',
          'Lead Developer',
          'BSIT 4 Student of Palawan State University – Taytay Campus. Lead developer of this application.',
          'assets/dev1.jpg',
          'jeljeleldo@gmail.com'), // Left blank as email was not provided
      _Dev(
          'Kimverlie M. Eldo',
          'Backend Developer',
          'BSIT 4 Student of Palawan State University – Taytay Campus. Assisted in backend integration and testing.',
          'assets/dev2.jpg',
          'eldokimverlie@gmail.com'),
      _Dev(
          'Luwela P. Espinosa',
          'UI / UX Designer',
          'BSIT 4 Student of Palawan State University – Taytay Campus. Designed the user interface and user experience.',
          'assets/dev3.jpg',
          'luwelaespinosa3@gmail.com'),
      _Dev(
          'Nelvy M. Ortega',
          'Data Analyst',
          'BSIT 4 Student of Palawan State University – Taytay Campus. Handled data management and analysis.',
          'assets/dev4.jpg',
          'orteganelvy18@gmail.com'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('About System',
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: _kSlate900)),
        const SizedBox(height: 6),
        Text('Information about the e-Permitting System and its developers.',
            style: TextStyle(
                color: _kSlate.withOpacity(0.8), fontSize: 14)),
        const SizedBox(height: 24),
        
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              // System Info Card
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 6))
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _kSidebarGreen.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12)
                          ),
                          child: const Icon(Icons.verified_user_rounded, color: _kSidebarGreen, size: 26),
                        ),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('e-Permitting System', 
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _kSlate900)),
                              SizedBox(height: 2),
                              Text('Version 1.0.0', 
                                  style: TextStyle(color: _kSlate, fontSize: 13)),
                            ]
                          )
                        )
                      ]
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'OMA administration is a Windows application that manages the Office of the Municipal Agriculturist Transport permit applications.',
                      style: TextStyle(color: _kSlate, fontSize: 14, height: 1.6),
                    ),
                  ]
                )
              ),
              const SizedBox(height: 24),

              // Admin Role Information Card
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 6))
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.admin_panel_settings_rounded, color: _kBlue, size: 26),
                        SizedBox(width: 12),
                        Text('Administrator Role', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _kSlate900)),
                      ]
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'The admin is responsible for managing and monitoring the OMA application. The admin can oversee user activities, update system information, manage records, and ensure that the application runs smoothly and securely. This role has full access to important features such as user management, reports, settings, and system maintenance.',
                      style: TextStyle(color: _kSlate, fontSize: 14, height: 1.6),
                    ),
                    const SizedBox(height: 24),
                    const Text('Admin Features:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: _kSlate900)),
                    const SizedBox(height: 12),
                    _FeatureBullet('Manage users and accounts'),
                    _FeatureBullet('Monitor app activities'),
                    _FeatureBullet('Update announcements and information'),
                    _FeatureBullet('Ensure smooth operation of the application'),
                    _FeatureBullet('Handle system settings and maintenance'),
                  ]
                )
              ),
              const SizedBox(height: 32),

              const Text('Development Team',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _kSlate900)),
              const SizedBox(height: 16),

              // Developer Grid
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 2.2, // Increased vertically to fit emails properly
                ),
                itemCount: devs.length,
                itemBuilder: (_, i) {
                  final d = devs[i];
                  return Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 6))
                      ],
                    ),
                    child: Row(children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: _kSidebarGreen.withOpacity(0.5),
                              width: 2.5),
                          boxShadow: [
                            BoxShadow(
                                color:
                                    _kSidebarGreen.withOpacity(0.12),
                                blurRadius: 10,
                                offset: const Offset(0, 4))
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 38,
                          backgroundColor: Colors.grey.shade100,
                          backgroundImage: AssetImage(d.image),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            mainAxisAlignment:
                                MainAxisAlignment.center,
                            children: [
                              Text(d.name,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                  color: _kSidebarGreen
                                      .withOpacity(0.12),
                                  borderRadius:
                                      BorderRadius.circular(20),
                                ),
                                child: Text(d.role,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF15803D))),
                              ),
                              const SizedBox(height: 8),
                              Text(d.desc,
                                  style: const TextStyle(
                                      color: _kSlate,
                                      fontSize: 12,
                                      height: 1.4),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis),
                              if (d.email.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Row(
                                    children: [
                                      Icon(Icons.email_rounded, size: 13, color: _kSlate.withOpacity(0.7)),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(d.email, 
                                          style: const TextStyle(fontSize: 11, color: _kBlue), 
                                          overflow: TextOverflow.ellipsis),
                                      )
                                    ]
                                  )
                                )
                            ]),
                      ),
                    ]),
                  );
                },
              ),
            ],
          ),
        ),
      ]
    );
  }
}

class _FeatureBullet extends StatelessWidget {
  final String text;
  const _FeatureBullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5),
            child: Icon(Icons.check_circle_rounded, size: 14, color: _kSidebarGreen),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(color: _kSlate, fontSize: 14)),
          )
        ]
      )
    );
  }
}

class _Dev {
  final String name, role, desc, image, email;
  const _Dev(this.name, this.role, this.desc, this.image, this.email);
}