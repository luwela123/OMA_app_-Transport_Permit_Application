import 'dart:async';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:oma/login.dart';
import 'package:oma/permit_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:oma/all_status_messages_page.dart';
import 'firebase_service.dart';
import 'widgets/dashboard_background.dart';
import 'permits/plants_products_form.dart';
import 'permits/animals_livestock_form.dart';
import 'profile_page.dart';
import 'tutorial_overlay.dart';

class UserDashboard extends StatefulWidget {
  const UserDashboard({super.key});
  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  int _navIndex = 0;
  void _switchToApplications() => setState(() => _navIndex = 1);

  final _keyUserCard = GlobalKey();
  final _keyNotificationBell = GlobalKey();
  final _keyPermitSection = GlobalKey();
  final _keyBottomNav = GlobalKey();

  late TutorialController _tutorialCtrl;

  @override
  void initState() {
    super.initState();

    _tutorialCtrl = TutorialController(
      tutorialId: 'user_dashboard_v1',
      steps: [
        TutorialStep(
          targetKey: _keyUserCard,
          title: 'Your Profile',
          description:
              'This card shows your name, email, and phone number. '
              'You can update these in Settings.',
          icon: Icons.person_rounded,
          preferredPosition: TooltipPosition.below,
        ),
        TutorialStep(
          targetKey: _keyNotificationBell,
          title: 'Notifications',
          description:
              'Tap the bell to see updates on your permits. '
              'A red dot appears when there\'s something new!',
          icon: Icons.notifications_rounded,
          preferredPosition: TooltipPosition.below,
        ),
        TutorialStep(
          targetKey: _keyPermitSection,
          title: 'Apply for Permits',
          description:
              'Choose a permit type to start your application. '
              'Tap the speaker icon 🔊 to hear it read aloud.',
          icon: Icons.description_rounded,
          preferredPosition: TooltipPosition.below,
        ),
        TutorialStep(
          targetKey: _keyBottomNav,
          title: 'Navigation',
          description:
              'Use these tabs to switch between:\n'
              '• Home – Apply for permits\n'
              '• Applications – Track your submissions\n'
              '• Settings – Edit profile & sign out',
          icon: Icons.navigation_rounded,
          preferredPosition: TooltipPosition.above,
        ),
      ],
    );

    _tutorialCtrl.startIfFirstTime();
  }

  @override
  void dispose() {
    _tutorialCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final svc = FirebaseService.instance;
    final user = svc.auth.currentUser!;
    final uid = user.uid;

    String titleForTab(int i) => switch (i) {
      0 => 'Dashboard',
      1 => 'Applications',
      _ => 'Settings',
    };

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: TutorialOverlay(
        controller: _tutorialCtrl,
        child: Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(
              titleForTab(_navIndex),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 22,
              ),
            ),
            actions: [
              Container(
                key: _keyNotificationBell,
                child: StreamBuilder<DatabaseEvent>(
                  stream: FirebaseDatabase.instance.ref('permits/$uid').onValue,
                  builder: (context, snapshot) {
                    bool hasUnread = false;
                    if (snapshot.hasData &&
                        snapshot.data?.snapshot.value != null) {
                      final allPermits = snapshot.data!.snapshot.value as Map;
                      for (var typeEntry in allPermits.entries) {
                        final permitsOfType = typeEntry.value as Map;
                        for (var permitEntry in permitsOfType.entries) {
                          final permitData = permitEntry.value as Map;
                          if (permitData['isNewStatusUpdate'] == true) {
                            hasUnread = true;
                            break;
                          }
                        }
                        if (hasUnread) break;
                      }
                    }

                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(
                            Icons.notifications_outlined,
                            color: Colors.white,
                            size: 28,
                          ),
                          tooltip: 'Notifications',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AllStatusMessagesPage(uid: uid),
                              ),
                            );
                          },
                        ),
                        if (hasUnread)
                          Positioned(
                            top: 10,
                            right: 10,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 10,
                                minHeight: 10,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: Stack(
            children: [
              const DashboardBackground(),
              SafeArea(
                child: StreamBuilder<DatabaseEvent>(
                  stream: svc.userRef(uid).onValue,
                  builder: (context, snap) {
                    final s = snap.data?.snapshot;
                    final dbUsername =
                        s?.child('username').value as String? ?? '';
                    final dbFirstName =
                        s?.child('firstName').value as String? ?? '';
                    final dbMiddleName =
                        s?.child('middleName').value as String? ?? '';
                    final dbLastName =
                        s?.child('lastName').value as String? ?? '';
                    final dbEmail = s?.child('email').value as String?;
                    final dbPhone = s?.child('phone').value as String?;

                    // --- 1. GET IMAGE URL FROM DATABASE ---
                    final dbProfileImg =
                        s?.child('profileImageUrl').value as String?;

                    final fullNameFromDb = '$dbFirstName $dbLastName'.trim();
                    final displayName = fullNameFromDb.isNotEmpty
                        ? fullNameFromDb
                        : (user.displayName?.trim().isNotEmpty == true
                              ? user.displayName!.trim()
                              : (dbUsername.trim().isNotEmpty
                                    ? dbUsername.trim()
                                    : 'User'));

                    final email = (user.email?.trim().isNotEmpty == true)
                        ? user.email!.trim()
                        : (dbEmail?.trim().isNotEmpty == true
                              ? dbEmail!.trim()
                              : '');
                    final phone = dbPhone?.trim() ?? '';

                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 1),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            key: _keyUserCard,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(.95),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(.06),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        displayName,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      if (email.isNotEmpty)
                                        Text(
                                          email,
                                          style: TextStyle(
                                            fontStyle: FontStyle.italic,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      if (phone.isNotEmpty)
                                        Text(
                                          phone,
                                          style: TextStyle(
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // --- 2. DISPLAY IMAGE IF EXISTS ---
                                CircleAvatar(
                                  radius: 26,
                                  backgroundColor: Colors.grey.shade200,
                                  // If image exists, use it as background
                                  backgroundImage:
                                      (dbProfileImg != null &&
                                          dbProfileImg.isNotEmpty)
                                      ? NetworkImage(dbProfileImg)
                                      : null,
                                  // If no image, show the Icon
                                  child:
                                      (dbProfileImg != null &&
                                          dbProfileImg.isNotEmpty)
                                      ? null
                                      : const Icon(
                                          Icons.account_circle,
                                          size: 36,
                                          color: Colors.black54,
                                        ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          Expanded(
                            child: switch (_navIndex) {
                              1 => _ApplicationsSection(uid: uid),
                              2 => _SettingsSection(
                                email: email,
                                username: dbUsername,
                                firstName: dbFirstName,
                                middleName: dbMiddleName,
                                lastName: dbLastName,
                                phone: phone,
                                // --- 3. PASS URL TO SETTINGS ---
                                profileImageUrl: dbProfileImg,
                                onLogout: () async {},
                                onOpenMyApplications: _switchToApplications,
                              ),
                              _ => _HomeSection(
                                permitSectionKey: _keyPermitSection,
                              ),
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          bottomNavigationBar: _DashboardNavBar(
            key: _keyBottomNav,
            currentIndex: _navIndex,
            onTap: (i) => setState(() => _navIndex = i),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════
// _HomeSection
// ═══════════════════════════════════════════

class _HomeSection extends StatefulWidget {
  final GlobalKey permitSectionKey;
  const _HomeSection({required this.permitSectionKey});
  @override
  State<_HomeSection> createState() => _HomeSectionState();
}

class _HomeSectionState extends State<_HomeSection> {
  late FlutterTts flutterTts;

  @override
  void initState() {
    super.initState();
    flutterTts = FlutterTts();
    _setupTts();
  }

  // --- SETUP TAGALOG TTS ---
  Future<void> _setupTts() async {
    await flutterTts.setSharedInstance(true);
    await flutterTts.setLanguage(
      "fil-PH",
    ); // Sets the language to Filipino/Tagalog
    await flutterTts.setSpeechRate(0.5); // Adjusts the speed (0.5 is normal)
  }

  Future<void> _speak(String text) async {
    await flutterTts.speak(text);
  }

  @override
  void dispose() {
    flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TRANSPORT PERMITS',
            style: TextStyle(
              color: const Color(0xFF1FAB64),
              fontWeight: FontWeight.w800,
              letterSpacing: .8,
            ),
          ),
          const SizedBox(height: 6),
          Container(height: 2, color: const Color(0xFF1FAB64)),
          const SizedBox(height: 12),
          Column(
            key: widget.permitSectionKey,
            children: [
              _PermitTile(
                title: 'Plants and products',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PlantsProductsFormPage(),
                  ),
                ),
                // --- TRANSLATED TO TAGALOG ---
                onSpeak: () => _speak('Mga halaman at produkto'),
              ),
              const SizedBox(height: 10),
              _PermitTile(
                title: 'Animals and Livestocks',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AnimalsLivestockFormPage(),
                  ),
                ),
                // --- TRANSLATED TO TAGALOG ---
                onSpeak: () => _speak('Mga hayop at alagang hayop'),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════
// _SettingsSection
// ═══════════════════════════════════════════

class _SettingsSection extends StatelessWidget {
  final String email, username, firstName, middleName, lastName, phone;
  final String? profileImageUrl;
  final VoidCallback onLogout, onOpenMyApplications;

  const _SettingsSection({
    required this.email,
    required this.username,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.phone,
    this.profileImageUrl,
    required this.onLogout,
    required this.onOpenMyApplications,
  });

  Future<void> _sendResetEmail(BuildContext context) async {
    try {
      await FirebaseService.instance.auth.sendPasswordResetEmail(email: email);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Password reset email sent to $email.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send email: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('SIGN OUT'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FirebaseService.instance.auth.signOut();
      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const purpleColor = Color(0xFF9C27B0);

    final items = <Widget>[
      _SettingTile(
        icon: Icons.account_circle_rounded,
        title: 'Edit Profile',
        subtitle: 'Update your name and phone number',
        iconColor: purpleColor,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProfilePage(
                currentUsername: username,
                currentFirstName: firstName,
                currentMiddleName: middleName,
                currentLastName: lastName,
                currentPhone: phone,
                currentEmail: email,
                currentImageUrl: profileImageUrl,
              ),
            ),
          );
        },
      ),
      _SettingTile(
        icon: Icons.lock_reset_rounded,
        title: 'Change password',
        subtitle: 'Send a password reset email',
        iconColor: purpleColor,
        onTap: () => _sendResetEmail(context),
      ),
      _SettingTile(
        icon: Icons.list_alt_rounded,
        title: 'My applications',
        subtitle: 'View all your submitted permits',
        iconColor: purpleColor,
        onTap: onOpenMyApplications,
      ),
      const Divider(height: 24),
      _SettingTile(
        icon: Icons.logout_rounded,
        title: 'Sign out',
        subtitle: 'End the current session',
        iconColor: purpleColor,
        onTap: () => _confirmSignOut(context),
      ),
      _SettingTile(
        icon: Icons.info_outline_rounded,
        title: 'About',
        subtitle: 'Office of the Municipal Agriculturist',
        iconColor: purpleColor,
        onTap: () => showAboutDialog(
          context: context,
          applicationName: 'OMA',
          applicationVersion: '1.0.0',
          children: const [Text('Apply for transport permits digitally.')],
        ),
      ),
    ];

    return SingleChildScrollView(
      child: Column(
        children: items
            .map(
              (w) =>
                  Padding(padding: const EdgeInsets.only(bottom: 10), child: w),
            )
            .toList(),
      ),
    );
  }
}

// ═══════════════════════════════════════════
// ALL REMAINING WIDGETS
// ═══════════════════════════════════════════

class _ApplicationsSection extends StatelessWidget {
  final String uid;
  const _ApplicationsSection({required this.uid});

  @override
  Widget build(BuildContext context) {
    final ref = FirebaseDatabase.instance.ref('permits/$uid');
    return StreamBuilder<DatabaseEvent>(
      stream: ref.onValue,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final root = snap.data?.snapshot.value;
        final items = _flattenPermits(root);
        items.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        if (items.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.file_copy_outlined,
                  size: 60,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                const Text(
                  'No Applications Found',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Submit a permit to see it here.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final permit = items[i];
            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PermitDetailPage(
                      uid: uid,
                      permitId: permit.id,
                      typeKey: permit.typeKey,
                    ),
                  ),
                );
              },
              child: _ApplicationCard(permit: permit),
            );
          },
        );
      },
    );
  }

  static List<_UserPermitRow> _flattenPermits(dynamic root) {
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
        final applicant = (data['applicant'] as Map?) ?? {};
        final request = (data['request'] as Map?) ?? {};
        final prettyType = switch (typeKey.toString()) {
          'plants' => 'Plants and Products',
          'animals' => 'Animals and Livestock',
          'fishery' => 'Fishery Shipping',
          _ => typeKey.toString(),
        };
        final detail =
            (request['productType'] ??
                    request['animalType'] ??
                    request['product'] ??
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
            kilos: (request['kilos'] ?? '').toString(),
            heads: (request['heads'] ?? '').toString(),
            source: (request['source'] ?? '').toString(),
            destination: (request['destination'] ?? '').toString(),
            transportation: (request['transportation'] ?? '').toString(),
            sender: (applicant['sender'] ?? '').toString(),
            receiver: (applicant['receiver'] ?? '').toString(),
          ),
        );
      });
    });
    return out;
  }
}

class _ApplicationCard extends StatelessWidget {
  final _UserPermitRow permit;
  const _ApplicationCard({required this.permit});

  IconData _getIconForType(String typeKey) {
    return switch (typeKey) {
      'plants' => Icons.local_florist_outlined,
      'animals' => Icons.pets_outlined,
      'fishery' => Icons.sailing_outlined,
      _ => Icons.description_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    String quantityText = '';
    if (permit.heads.isNotEmpty) {
      quantityText = '${permit.heads} Heads';
      if (permit.kilos.isNotEmpty) {
        quantityText += ' (~${permit.kilos} Kilos)';
      }
    } else if (permit.kilos.isNotEmpty) {
      quantityText = '${permit.kilos} Kilos';
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.25),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(0, 0),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getIconForType(permit.typeKey),
                  color: const Color(0xFF1FAB64),
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        permit.permitType,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                          color: Colors.black87,
                        ),
                      ),
                      if (permit.detail.isNotEmpty)
                        Text(
                          permit.detail,
                          style: TextStyle(color: Colors.grey.shade700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            if (quantityText.isNotEmpty)
              _InfoRow(icon: Icons.monitor_weight_outlined, text: quantityText),
            if (permit.sender.isNotEmpty)
              _InfoRow(
                icon: Icons.person_outline,
                text: 'Sender: ${permit.sender}',
              ),
            if (permit.receiver.isNotEmpty)
              _InfoRow(
                icon: Icons.person_pin_outlined,
                text: 'Receiver: ${permit.receiver}',
              ),
            if (permit.source.isNotEmpty)
              _InfoRow(
                icon: Icons.pin_drop_outlined,
                text: 'From: ${permit.source}',
              ),
            if (permit.destination.isNotEmpty)
              _InfoRow(
                icon: Icons.flag_outlined,
                text: 'To: ${permit.destination}',
              ),
            if (permit.transportation.isNotEmpty)
              _InfoRow(
                icon: Icons.local_shipping_outlined,
                text: 'Via: ${permit.transportation}',
              ),
            const Divider(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: _StatusChip(status: permit.status),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserPermitRow {
  final String id, typeKey, permitType, status, detail;
  final int createdAt;
  final String kilos,
      heads,
      source,
      destination,
      transportation,
      sender,
      receiver;

  _UserPermitRow({
    required this.id,
    required this.typeKey,
    required this.permitType,
    required this.status,
    required this.detail,
    required this.createdAt,
    required this.kilos,
    required this.heads,
    required this.source,
    required this.destination,
    required this.transportation,
    required this.sender,
    required this.receiver,
  });
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  final Color iconColor;

  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: iconColor.withOpacity(.12),
                foregroundColor: iconColor,
                child: Icon(icon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: iconColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermitTile extends StatelessWidget {
  final String title;
  final VoidCallback onTap, onSpeak;
  const _PermitTile({
    required this.title,
    required this.onTap,
    required this.onSpeak,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFEAE6F3),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.volume_up_rounded,
                  color: Colors.black54,
                ),
                onPressed: onSpeak,
                tooltip: 'Read aloud',
                splashRadius: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  Color _color(String s) {
    final low = s.toLowerCase();
    if (low.contains('approve')) return const Color(0xFF1FAB64);
    if (low.contains('reject')) return Colors.red.shade700;
    if (low.contains('cancel')) return Colors.grey.shade600;
    return const Color(0xFFB3A400);
  }

  String _label(String s) {
    final low = s.toLowerCase();
    if (low.contains('approve')) return 'Approved';
    if (low.contains('reject')) return 'Rejected';
    if (low.contains('review')) return 'Under Review';
    if (low.contains('submit')) return 'Under Review';
    if (low.contains('cancel')) return 'Cancelled';
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

class _DashboardNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _DashboardNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: onTap,
      type: BottomNavigationBarType.fixed,
      backgroundColor: Colors.white,
      selectedItemColor: const Color(0xFF1FAB64),
      unselectedItemColor: Colors.black54,
      showUnselectedLabels: true,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
        BottomNavigationBarItem(
          icon: Icon(Icons.list_alt_rounded),
          label: 'Applications',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings_rounded),
          label: 'Settings',
        ),
      ],
    );
  }
}
