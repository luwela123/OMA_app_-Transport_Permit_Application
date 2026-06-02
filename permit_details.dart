import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Required for rootBundle.load
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../firebase_service.dart';
import '../models/permit_row.dart';

// ══════════════════ HELPERS ══════════════════

String prettyLabel(String key) {
  if (key.isEmpty) return '';
  if (key == 'contact') return 'Email/Cellphone';
  if (key == 'source') return 'From (Source)';
  if (key == 'destination') return 'To (Destination)';
  if (key == 'receiver') return 'Receiver/Consignee';
  if (key == 'barangayCert') return 'Certificate of Origin';
  if (key == 'healthCert') return 'Veterinary Health Certificate/Quarantine certificate';
  if (key == 'proxyId') return 'Proxy ID';
  if (key == 'validId') return 'Valid ID';
  if (key == 'officialReceipt') return 'Official Receipt (OR)';
  if (key == 'permanentAddress') return 'Permanent Address';
  if (key == 'deliveryDate') return 'Date of Delivery';
  
  final result = key.replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(1)}');
  return result[0].toUpperCase() + result.substring(1);
}

const _kGreen = Color(0xFF00C853);
const _kSlate = Color(0xFF64748B);
const _kSlate900 = Color(0xFF0F172A);
const _kBg = Color(0xFFF1F5F9);
const _kEmerald = Color(0xFF10B981);
const _kRose = Color(0xFFEF4444);
const _kBlue = Color(0xFF2563EB); // Used for Paid status

// ══════════════════ MAIN PAGE ══════════════════

class PermitDetailsPage extends StatefulWidget {
  final PermitRow row;
  const PermitDetailsPage({super.key, required this.row});

  @override
  State<PermitDetailsPage> createState() => _PermitDetailsPageState();
}

class _PermitDetailsPageState extends State<PermitDetailsPage> {
  bool _loading = true;
  bool _posting = false;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final path = 'permits/${widget.row.uid}/${widget.row.typeKey}/${widget.row.id}';
      final d = await FirebaseService.instance.dbGet(path);
      if (!mounted) return;
      if (d is Map) {
        setState(() { _data = d.cast<String, dynamic>(); _loading = false; });
      } else {
        setState(() { _error = 'Invalid data'; _loading = false; });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = 'Failed to load: $e'; _loading = false; });
    }
  }

  // ── Success Dialog ──
  Future<void> _showSuccessDialog(String status) async {
    final isApprove = status == 'approved';
    final isPaid = status == 'paid';
    
    final Color color = isPaid ? _kBlue : isApprove ? const Color(0xFF1FAB64) : Colors.red;
    final IconData icon = isPaid ? Icons.receipt_long : isApprove ? Icons.check_circle : Icons.cancel;
    final String title = isPaid ? 'Payment Recorded' : isApprove ? 'Approval Successful' : 'Rejection Successful';
    final String msg = isPaid 
        ? 'The permit has been marked as paid and the receipt details have been saved.' 
        : 'The application has been ${status.toLowerCase()} successfully.';

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.all(24),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 64),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(msg, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey[700])),
        ]),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: color, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Actions ──
  Future<void> _onAction(String newStatus) async {
    Map<String, dynamic> approvalData = {};
    Map<String, String>? paymentData;
    String? reasonForRejection;

    if (newStatus == 'approved') {
      final result = await _askForApprovalDetails(context);
      if (result == null) return;
      approvalData = result;
    }
    if (newStatus == 'rejected') {
      reasonForRejection = await _askForRejectionReason(context);
      if (reasonForRejection == null) return;
    }
    if (newStatus == 'paid') {
      paymentData = await _askForPaymentDetails(context);
      if (paymentData == null) return;
    }

    final user = FirebaseService.instance.auth.currentUser!;
    final email = user.email ?? '';
    final pass = await _askPassword(context, email, newStatus == 'paid' ? 'Payment' : newStatus);
    if (pass == null || pass.isEmpty) return;

    if (!mounted) return;
    setState(() => _posting = true);

    try {
      final ok = await FirebaseService.instance.verifyPassword(email, pass);
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Incorrect password')));
        setState(() => _posting = false);
        return;
      }

      final path = 'permits/${widget.row.uid}/${widget.row.typeKey}/${widget.row.id}';
      
      Map<String, dynamic> patchData = {
        'status': newStatus,
        'reviewerUid': user.uid,
        'reviewerEmail': email,
        'isNewStatusUpdate': true,
      };

      if (newStatus == 'rejected' && reasonForRejection != null) {
        patchData['statusReason'] = reasonForRejection;
        patchData['reviewedAt'] = {'.sv': 'timestamp'};
      } else if (newStatus == 'approved') {
        patchData['claimDate'] = approvalData['claimDate'];
        patchData['statusReason'] = approvalData['instructions'];
        patchData['reviewedAt'] = {'.sv': 'timestamp'};
      } else if (newStatus == 'paid' && paymentData != null) {
        patchData['orAmount'] = paymentData['orAmount'];
        patchData['orNumber'] = paymentData['orNumber'];
        patchData['paidAt'] = {'.sv': 'timestamp'};
      }

      await FirebaseService.instance.dbPatch(path, patchData);

      if (!mounted) return;
      await _showSuccessDialog(newStatus);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  // ── Payment Dialog ──
  Future<Map<String, String>?> _askForPaymentDetails(BuildContext context) async {
    final amtCtrl = TextEditingController();
    final orCtrl = TextEditingController();
    final fk = GlobalKey<FormState>();

    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Enter Payment Details'),
        content: Form(
          key: fk,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter the Official Receipt details to mark this permit as paid.', style: TextStyle(color: Colors.black54, fontSize: 13)),
              const SizedBox(height: 16),
              TextFormField(
                controller: amtCtrl,
                decoration: const InputDecoration(labelText: 'Amount Paid (₱)', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: orCtrl,
                decoration: const InputDecoration(labelText: 'O.R. Number', border: OutlineInputBorder()),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, null), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kBlue),
            onPressed: () {
              if (fk.currentState!.validate()) {
                Navigator.pop(c, {'orAmount': amtCtrl.text.trim(), 'orNumber': orCtrl.text.trim()});
              }
            },
            child: const Text('Confirm Payment'),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>?> _askForApprovalDetails(BuildContext context) async {
    final ic = TextEditingController();
    DateTime? selectedDate;
    String dateText = 'Select Date';

    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: const Text('Set Claim Details'),
          content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Select a date for the user to claim the permit:'),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.calendar_today),
                  label: Text(dateText),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setD(() {
                        selectedDate = picked;
                        dateText = DateFormat('MMMM d, yyyy').format(picked);
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: ic,
                  decoration: const InputDecoration(
                    labelText: 'Additional Instructions (Optional)',
                    hintText: 'e.g., Bring a valid ID.',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, null), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (selectedDate == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please select a claim date.')));
                  return;
                }
                Navigator.pop(c, {
                  'claimDate': selectedDate!.toIso8601String(),
                  'instructions': ic.text.trim(),
                });
              },
              child: const Text('Confirm Approval'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _askForRejectionReason(BuildContext context) async {
    final rc = TextEditingController();
    final fk = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Reason for Rejection'),
        content: Form(
          key: fk,
          child: TextFormField(
            controller: rc, autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Reason', hintText: 'e.g., Incomplete documents',
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'A reason is required.' : null,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, null), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (fk.currentState!.validate()) Navigator.pop(c, rc.text.trim());
            },
            child: const Text('Confirm Rejection'),
          ),
        ],
      ),
    );
  }

  Future<String?> _askPassword(BuildContext context, String email, String action) async {
    final ctrl = TextEditingController();
    bool obscure = true;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: Text('Confirm $action'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Re-enter admin password for $email'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl, obscureText: obscure, autofocus: true,
              onChanged: (_) => setS(() {}),
              onSubmitted: (_) { if (ctrl.text.isNotEmpty) Navigator.pop(c, ctrl.text); },
              decoration: InputDecoration(
                labelText: 'Password',
                suffixIcon: IconButton(
                  icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setS(() => obscure = !obscure),
                ),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, null), child: const Text('Cancel')),
            FilledButton(
              onPressed: ctrl.text.isEmpty ? null : () => Navigator.pop(c, ctrl.text),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Open Permit Document ──
  void _openPermitDocument() {
    final d = _data!;
    final typeKey = widget.row.typeKey;

    if (typeKey == 'plants') {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => _PermitDocumentPreviewPage(
          title: 'Plant Permit Document',
          pdfBuilder: () => _generatePlantPermitPdf(d, widget.row.id),
          fileName: 'Plant_Permit_${widget.row.id}',
        ),
      ));
    } else if (typeKey == 'animals') {
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => _PermitDocumentPreviewPage(
          title: 'Animal Transport Permit',
          pdfBuilder: () => _generateAnimalPermitPdf(d, widget.row.id),
          fileName: 'Animal_Permit_${widget.row.id}',
        ),
      ));
    }
  }

  // ══════════════════ BUILD ══════════════════

  @override
  Widget build(BuildContext context) {
    final user = FirebaseService.instance.auth.currentUser!;
    return Scaffold(
      backgroundColor: _kBg,
      body: Row(
        children: [
          _SideBar(
            email: user.email ?? user.uid,
            onBack: () => Navigator.pop(context),
            onLogout: () async {
              await FirebaseService.instance.signOut();
              if (!mounted) return;
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
          Expanded(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: _kGreen))
                    : _error != null
                        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.error_outline_rounded, size: 48, color: _kRose.withOpacity(0.6)),
                            const SizedBox(height: 12),
                            Text(_error!, style: const TextStyle(color: _kRose)),
                          ]))
                        : _buildContent(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final d = _data!;
    final applicant = (d['applicant'] as Map?)?.cast<String, String>() ?? {};
    final req = (d['request'] as Map?)?.cast<String, String>() ?? {};
    final files = (d['files'] as Map?)?.cast<String, String>() ?? {};

    final status = (d['status'] as String? ?? 'submitted').toLowerCase();
    final isActionable = status == 'submitted' || status.contains('review');
    final isApproved = status == 'approved';
    final isPaid = status == 'paid';
    final isRejected = status == 'rejected';
    final isPlant = widget.row.typeKey == 'plants';
    final isAnimal = widget.row.typeKey == 'animals';
    
    // Document can be viewed if it's either approved or paid
    final hasDocument = (isApproved || isPaid) && (isPlant || isAnimal);

    final applicantDetails = {
      'lastName': applicant['lastName'] ?? '',
      'firstName': applicant['firstName'] ?? '',
      'middleName': applicant['middleName'] ?? '',
      'contact': applicant['contact'] ?? '',
      'permanentAddress': applicant['permanentAddress'] ?? '', 
    };
    final shipmentDetails = {
      'receiver': applicant['receiver'] ?? '',
      'deliveryDate': req['deliveryDate'] ?? '', 
      'source': req['source'] ?? '',
      'destination': req['destination'] ?? '',
      'transportation': req['transportation'] ?? '',
    };

    final claimDateStr = d['claimDate'] as String?;
    String claimDateDisplay = '';
    if (claimDateStr != null) {
      try { claimDateDisplay = DateFormat('MMMM d, yyyy').format(DateTime.parse(claimDateStr)); } catch (_) {}
    }

    final topValue = (req['productType'] ?? req['animalType'] ?? req['product'] ?? '').toString();

    String quantityText = '';
    final heads = req['heads']?.toString() ?? '';
    final kilos = req['kilos']?.toString() ?? req['quantity']?.toString() ?? '';
    if (heads.isNotEmpty) {
      quantityText = '$heads Heads';
      if (kilos.isNotEmpty) quantityText += ' (~$kilos Kilos)';
    } else if (kilos.isNotEmpty) {
      quantityText = '$kilos Kilos';
    }

    final reason = (req['reason'] ?? '').toString();

    String permitLabel = isPlant ? 'Plant Permit' : isAnimal ? 'Transport Permit' : 'Permit';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──
        Row(children: [
          InkWell(
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(8),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)],
              ),
              child: const Icon(Icons.arrow_back_rounded, size: 20),
            ),
          ),
          const SizedBox(width: 16),
          const Text('Application Details',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: _kSlate900)),
          const Spacer(),
          _StatusChip(status: status),
        ]),
        const SizedBox(height: 20),

        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasDocument)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: isPaid 
                          ? [const Color(0xFF1D4ED8), const Color(0xFF3B82F6)] 
                          : [const Color(0xFF059669), const Color(0xFF10B981)] 
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: (isPaid ? _kBlue : _kEmerald).withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 6))],
                    ),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isPaid ? Icons.receipt_long : (isPlant ? Icons.eco_rounded : Icons.pets_rounded),
                          color: Colors.white, size: 32,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(isPaid ? 'Payment Received' : '$permitLabel Approved',
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 4),
                          Text(isPaid ? 'This permit process is now officially complete.' : 'The permit document is ready for viewing and printing.',
                              style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 13)),
                          if (claimDateDisplay.isNotEmpty && !isPaid) ...[
                            const SizedBox(height: 4),
                            Text('Claim date: $claimDateDisplay',
                                style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12, fontWeight: FontWeight.w600)),
                          ],
                        ]),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _openPermitDocument,
                        icon: const Icon(Icons.description_rounded, size: 18),
                        label: const Text('View Document'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: isPaid ? _kBlue : const Color(0xFF059669),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                      ),
                    ]),
                  ),

                if ((isApproved || isPaid) && !hasDocument)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isPaid ? _kBlue.withOpacity(0.08) : _kEmerald.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isPaid ? _kBlue.withOpacity(0.3) : _kEmerald.withOpacity(0.3)),
                    ),
                    child: Row(children: [
                      Icon(isPaid ? Icons.receipt : Icons.check_circle_rounded, color: isPaid ? _kBlue : _kEmerald, size: 24),
                      const SizedBox(width: 12),
                      Expanded(child: Text(
                        isPaid ? 'Payment received successfully.' : 'This application has been approved.${claimDateDisplay.isNotEmpty ? ' Claim date: $claimDateDisplay' : ''}',
                        style: TextStyle(color: isPaid ? const Color(0xFF1E3A8A) : const Color(0xFF065F46), fontWeight: FontWeight.w500),
                      )),
                    ]),
                  ),

                if (isRejected)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _kRose.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _kRose.withOpacity(0.3)),
                    ),
                    child: Row(children: [
                      Icon(Icons.cancel_rounded, color: _kRose, size: 24),
                      const SizedBox(width: 12),
                      const Expanded(child: Text('This application has been rejected.',
                          style: TextStyle(color: Color(0xFF9F1239), fontWeight: FontWeight.w500))),
                    ]),
                  ),

                _InfoBlock(
                  title: 'Request Details',
                  icon: Icons.assignment_rounded,
                  child: _DetailSection(data: {
                    'Permit Type': topValue,
                    if (quantityText.isNotEmpty) 'Quantity': quantityText,
                    if (reason.isNotEmpty) 'Reason': reason,
                    if (claimDateDisplay.isNotEmpty) 'Date to Claim': claimDateDisplay,
                    if (d['orNumber'] != null) 'O.R. Number': d['orNumber'].toString(),
                    if (d['orAmount'] != null) 'Amount Paid': '₱${d['orAmount'].toString()}',
                  }),
                ),

                _InfoBlock(
                  title: 'Applicant Information',
                  icon: Icons.person_rounded,
                  child: _DetailSection(data: applicantDetails),
                ),

                _InfoBlock(
                  title: 'Shipment Details',
                  icon: Icons.local_shipping_rounded,
                  child: _DetailSection(data: shipmentDetails),
                ),

                if (files.entries.any((e) => e.value.startsWith('http')))
                  _InfoBlock(
                    title: 'Attachments',
                    icon: Icons.attach_file_rounded,
                    child: Column(
                      children: files.entries
                          .where((e) => e.value.toString().startsWith('http'))
                          .map((e) => _FileCard(
                              title: prettyLabel(e.key.replaceAll('Url', '')),
                              url: e.value.toString()))
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        if (isActionable)
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_rounded, size: 20),
                label: const Text('APPROVE', style: TextStyle(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669), foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
                onPressed: (!_loading && !_posting) ? () => _onAction('approved') : null,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.close_rounded, size: 20),
                label: const Text('REJECT', style: TextStyle(fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
                onPressed: (!_loading && !_posting) ? () => _onAction('rejected') : null,
              ),
            ),
          ]),

        if (isApproved)
          Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.receipt_long_rounded, size: 20),
                label: const Text('MARK AS PAID', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kBlue, foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 3,
                ),
                onPressed: (!_loading && !_posting) ? () => _onAction('paid') : null,
              ),
            ),
          ]),
      ],
    );
  }
}

// ══════════════════ STATUS CHIP ══════════════════

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final low = status.toLowerCase();
    final Color bg, fg;
    final IconData icon;
    final String text;
    
    if (low == 'paid') {
      bg = _kBlue.withOpacity(0.12); fg = _kBlue;
      icon = Icons.receipt_long_rounded; text = 'Paid';
    } else if (low == 'approved') {
      bg = _kEmerald.withOpacity(0.12); fg = const Color(0xFF059669);
      icon = Icons.check_circle_rounded; text = 'Approved';
    } else if (low == 'rejected') {
      bg = _kRose.withOpacity(0.12); fg = const Color(0xFFDC2626);
      icon = Icons.cancel_rounded; text = 'Rejected';
    } else {
      bg = const Color(0xFFF59E0B).withOpacity(0.12); fg = const Color(0xFFD97706);
      icon = Icons.schedule_rounded; text = 'Under Review';
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(24)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: fg, size: 16), const SizedBox(width: 6),
        Text(text, style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

// ══════════════════ INFO BLOCK ══════════════════

class _InfoBlock extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _InfoBlock({required this.title, required this.child, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _kGreen.withOpacity(0.10), borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF15803D), size: 18),
          ),
          const SizedBox(width: 12),
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: _kSlate900)),
        ]),
        const SizedBox(height: 12),
        Divider(color: Colors.grey.shade200, height: 1),
        const SizedBox(height: 16),
        child,
      ]),
    );
  }
}

// ══════════════════ DETAIL SECTION ══════════════════

class _DetailSection extends StatelessWidget {
  final Map<String, String> data;
  const _DetailSection({required this.data});

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.where((e) => e.value.trim().isNotEmpty).toList();
    return Column(
      children: List.generate(entries.length, (i) {
        final e = entries[i];
        return Padding(
          padding: EdgeInsets.only(bottom: i < entries.length - 1 ? 14 : 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 160, child: Text(prettyLabel(e.key),
                style: const TextStyle(fontWeight: FontWeight.w600, color: _kSlate, fontSize: 13))),
            Expanded(child: Text(e.value,
                style: const TextStyle(fontSize: 15, color: _kSlate900, fontWeight: FontWeight.w500))),
          ]),
        );
      }),
    );
  }
}

// ══════════════════ FILE CARD ══════════════════

class _FileCard extends StatelessWidget {
  final String title;
  final String url;
  const _FileCard({required this.title, required this.url});

  bool _isImage(String u) {
    final l = u.toLowerCase();
    return l.endsWith('.png') || l.endsWith('.jpg') || l.endsWith('.jpeg') ||
        l.endsWith('.gif') || l.endsWith('.webp') || l.contains('/image/upload/');
  }

  @override
  Widget build(BuildContext context) {
    final isUrl = url.startsWith('http');
    final isImage = isUrl && _isImage(url);
    final h = (MediaQuery.of(context).size.height * 0.28).clamp(160.0, 360.0);

    return Container(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$title:', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        const SizedBox(height: 8),
        if (!isUrl) const Text('—')
        else if (isImage)
          GestureDetector(
            onTap: () => _viewImage(context, url, title),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: h, width: double.infinity,
                child: Image.network(url, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _BrokenImage(url: url),
                    loadingBuilder: (_, child, p) {
                      if (p == null) return child;
                      return const Center(child: SizedBox(width: 28, height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2)));
                    }),
              ),
            ),
          )
        else
          Row(children: [
            Expanded(child: Text(url.split('/').last, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () async {
                if (!await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open link')));
                }
              },
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Open'),
            ),
          ]),
        if (isImage) ...[
          const SizedBox(height: 6),
          Text('(Click image to enlarge)', style: TextStyle(color: Colors.black.withOpacity(.5), fontSize: 12)),
        ],
      ]),
    );
  }

  void _viewImage(BuildContext context, String url, String title) {
    showDialog(
      context: context,
      builder: (c) => Dialog(
        insetPadding: const EdgeInsets.all(16), clipBehavior: Clip.antiAlias,
        child: Stack(children: [
          InteractiveViewer(minScale: 0.5, maxScale: 4,
              child: Image.network(url, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => _BrokenImage(url: url))),
          Positioned(top: 8, right: 8,
              child: IconButton(onPressed: () => Navigator.pop(c), icon: const Icon(Icons.close))),
        ]),
      ),
    );
  }
}

class _BrokenImage extends StatelessWidget {
  final String url;
  const _BrokenImage({required this.url});
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black12, alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.broken_image_outlined, size: 32, color: Colors.black45),
        const SizedBox(height: 8),
        Text("Couldn't load image", style: TextStyle(color: Colors.black.withOpacity(.6))),
      ]),
    );
  }
}

// ══════════════════ SIDEBAR ══════════════════

class _SideBar extends StatelessWidget {
  final String email;
  final VoidCallback onBack;
  final VoidCallback onLogout;
  const _SideBar({required this.email, required this.onBack, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260, color: _kGreen,
      child: SafeArea(
        child: Column(children: [
          const SizedBox(height: 30),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
            child: ClipOval(child: Image.asset('assets/logo.png', width: 90, height: 90, fit: BoxFit.cover)),
          ),
          const SizedBox(height: 12),
          const Text('ADMIN', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(email,
                style: TextStyle(color: Colors.black.withOpacity(0.55), fontSize: 11),
                overflow: TextOverflow.ellipsis, maxLines: 1),
          ),
          const SizedBox(height: 40),
          _SideBtn(icon: Icons.arrow_back_rounded, label: 'Back to Dashboard', onTap: onBack),
          const Spacer(),
          _SideBtn(icon: Icons.logout_rounded, label: 'Log out', onTap: onLogout),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }
}

class _SideBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SideBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Material(
        color: Colors.white.withOpacity(0.95), borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12), onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(icon, color: Colors.black87, size: 20), const SizedBox(width: 12),
              Text(label, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 14)),
            ]),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  SHARED PDF PREVIEW PAGE
// ═══════════════════════════════════════════════════════════════

class _PermitDocumentPreviewPage extends StatelessWidget {
  final String title;
  final Future<Uint8List> Function() pdfBuilder;
  final String fileName;

  const _PermitDocumentPreviewPage({
    required this.title,
    required this.pdfBuilder,
    required this.fileName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kGreen,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          const Icon(Icons.description_rounded, size: 22),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text('Preview → Print / Save',
                  style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.5))),
            ),
          ),
        ],
      ),
      body: PdfPreview(
        build: (_) => pdfBuilder(),
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        pdfFileName: fileName,
        loadingWidget: const Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(color: _kGreen),
            SizedBox(height: 16),
            Text('Generating permit document…', style: TextStyle(color: _kSlate, fontSize: 14)),
          ]),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  SHARED PDF HELPERS
// ═══════════════════════════════════════════════════════════════

final _pdfBlue = PdfColor.fromHex('#1565C0');
final _pdfMagenta = PdfColor.fromHex('#C2185B');
final _pdfGreen = PdfColor.fromHex('#2E7D32');
final _pdfBlack = PdfColors.black;
final _pdfGrey = PdfColors.grey600;

pw.TextStyle _headerStyle() => pw.TextStyle(fontSize: 11, color: _pdfBlack);
pw.TextStyle _headerBold() => pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _pdfBlack);
pw.TextStyle _titleBlue() => pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _pdfBlue);
pw.TextStyle _titleMagenta() => pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _pdfMagenta);
pw.TextStyle _titleGreen() => pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _pdfGreen);
pw.TextStyle _bodyStyle() => pw.TextStyle(fontSize: 10, color: _pdfBlack);
pw.TextStyle _bodyBold() => pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _pdfBlack);
pw.TextStyle _fieldLabel() => pw.TextStyle(fontSize: 10, color: _pdfBlack);
pw.TextStyle _fieldValue() => pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _pdfBlack);
pw.TextStyle _smallGrey() => pw.TextStyle(fontSize: 9, color: _pdfGrey);

String _permitDate(Map<String, dynamic> data) {
  final claimDateStr = data['claimDate'] as String?;
  if (claimDateStr != null) {
    try { return DateFormat('MMMM d, yyyy').format(DateTime.parse(claimDateStr)); } catch (_) {}
  }
  return DateFormat('MMMM d, yyyy').format(DateTime.now());
}

String _permitRef(String permitId) => permitId.hashCode.abs().toString().padLeft(6, '0');

String _fullName(Map applicant) {
  return '${applicant['firstName'] ?? ''} ${applicant['middleName'] ?? ''} ${applicant['lastName'] ?? ''}'
      .replaceAll(RegExp(r'\s+'), ' ').trim();
}

// ── Asset Image Loader ──
Future<pw.ImageProvider?> _loadPdfImage(String path) async {
  try {
    final data = await rootBundle.load(path);
    return pw.MemoryImage(data.buffer.asUint8List());
  } catch (e) {
    return null; 
  }
}

// ── Shared header (with real images) ──
pw.Widget _pdfHeader({
  String? subtitle,
  pw.ImageProvider? leftLogo,
  pw.ImageProvider? rightLogo,
}) {
  
  pw.Widget buildLogo(pw.ImageProvider? img) {
    if (img != null) {
      return pw.Image(img, width: 60, height: 60, fit: pw.BoxFit.contain);
    }
    // Fallback if image asset is missing
    return pw.Container(
      width: 60, height: 60,
      decoration: pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        border: pw.Border.all(color: PdfColors.grey400, width: 1.5),
      ),
      child: pw.Center(child: pw.Text('SEAL', style: pw.TextStyle(fontSize: 7, color: PdfColors.grey400))),
    );
  }

  return pw.Column(children: [
    pw.Row(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
      buildLogo(leftLogo),
      pw.SizedBox(width: 24),
      pw.Column(children: [
        pw.Text('Republic of the Philippines', style: _headerStyle()),
        pw.Text('Province of Palawan', style: _headerStyle()),
        pw.Text('Municipality of Taytay', style: _headerBold()),
      ]),
      pw.SizedBox(width: 24),
      buildLogo(rightLogo),
    ]),
    pw.SizedBox(height: 6),
    pw.Text('OFFICE OF THE MUNICIPAL AGRICULTURIST', style: _titleBlue()),
    if (subtitle != null) ...[
      pw.SizedBox(height: 2),
      pw.Text(subtitle, style: _titleMagenta(), textAlign: pw.TextAlign.center),
    ],
  ]);
}

// ── Underline field ──
pw.Widget _uField(String label, String value, {double labelWidth = 200}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 10),
    child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
      pw.SizedBox(width: labelWidth, child: pw.Text(label, style: _fieldLabel())),
      pw.Expanded(
        child: pw.Container(
          decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black))),
          padding: const pw.EdgeInsets.only(bottom: 2, left: 4),
          child: pw.Text(value, style: _fieldValue()),
        ),
      ),
    ]),
  );
}

// ── Underline only ──
pw.Widget _uOnly(String value, {double width = 150}) {
  return pw.Container(
    width: width,
    decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black))),
    padding: const pw.EdgeInsets.only(bottom: 2, left: 4),
    child: pw.Text(value, style: _fieldValue()),
  );
}

// ── Signature block ──
pw.Widget _signatureBlock({required String title, required String name, required String position}) {
  return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
    pw.Text(title, style: _bodyStyle()),
    pw.SizedBox(height: 28),
    pw.Container(
      decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black))),
      child: pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2, left: 4, right: 4),
        child: pw.Text(name, style: pw.TextStyle(
            fontSize: 11, fontWeight: pw.FontWeight.bold, decoration: pw.TextDecoration.underline)),
      ),
    ),
    pw.SizedBox(height: 4),
    pw.Text(position, style: _bodyStyle()),
  ]);
}

// ── Payment footer ──
pw.Widget _paymentFooter(Map<String, dynamic> data) {
  final orNumber = data['orNumber']?.toString() ?? ' ';
  final orAmount = data['orAmount']?.toString() != null ? 'PHP ${data['orAmount']}' : ' ';
  
  String dateDisplay = ' ';
  if (data['paidAt'] != null && data['paidAt'] is int) {
    dateDisplay = DateFormat('MMMM d, yyyy').format(DateTime.fromMillisecondsSinceEpoch(data['paidAt']));
  }

  return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
    pw.Divider(color: PdfColors.grey300),
    pw.SizedBox(height: 8),
    pw.Row(children: [
      pw.Text('Paid under O.R No. ', style: _smallGrey()),
      pw.Container(width: 100,
          decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400))),
          child: pw.Text(orNumber, style: _smallGrey())),
    ]),
    pw.SizedBox(height: 6),
    pw.Row(children: [
      pw.Text('Amount: ', style: _smallGrey()),
      pw.Container(width: 100,
          decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400))),
          child: pw.Text(orAmount, style: _smallGrey())),
    ]),
    pw.SizedBox(height: 6),
    pw.Row(children: [
      pw.Text('Date: ', style: _smallGrey()),
      pw.Container(width: 100,
          decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400))),
          child: pw.Text(dateDisplay, style: _smallGrey())),
    ]),
    pw.SizedBox(height: 6),
    pw.Row(children: [
      pw.Text('Place Issued: ', style: _smallGrey()),
      pw.Container(width: 100,
          decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400))),
          child: pw.Text('Taytay, Palawan', style: _smallGrey())),
    ]),
  ]);
}

// ═══════════════════════════════════════════════════════════════
//  PLANT PERMIT PDF
// ═══════════════════════════════════════════════════════════════

Future<Uint8List> _generatePlantPermitPdf(Map<String, dynamic> data, String permitId) async {
  final pdf = pw.Document(title: 'Plant Permit - $permitId', author: 'Municipal Agriculture Office');

  // Load the logos
  final leftLogo = await _loadPdfImage('assets/municipal.jpg');
  final rightLogo = await _loadPdfImage('assets/logo.png');

  final applicant = (data['applicant'] as Map?)?.cast<String, dynamic>() ?? {};
  final req = (data['request'] as Map?)?.cast<String, dynamic>() ?? {};

  final senderName = _fullName(applicant);
  final senderAddress = applicant['contact']?.toString() ?? '';
  final receiver = applicant['receiver']?.toString() ?? '';
  final source = req['source']?.toString() ?? '';
  final destination = req['destination']?.toString() ?? '';
  final productType = req['productType']?.toString() ?? req['product']?.toString() ?? '';
  final kilos = req['kilos']?.toString() ?? req['quantity']?.toString() ?? '';
  final transportation = req['transportation']?.toString() ?? '';
  final dateStr = _permitDate(data);
  final refNum = _permitRef(permitId);

  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.symmetric(horizontal: 50, vertical: 40),
    build: (ctx) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        // ═══ HEADER ═══
        _pdfHeader(
          subtitle: 'PERMIT FOR DOMESTIC TRANSPORT OF PLANT/PLANT PRODUCTS',
          leftLogo: leftLogo,
          rightLogo: rightLogo,
        ),
        pw.SizedBox(height: 20),

        // ═══ PERMIT NO & DATE ═══
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Row(children: [pw.Text('Permit No.', style: _bodyBold()), _uOnly(refNum, width: 120)]),
          pw.Row(children: [pw.Text('Date: ', style: _bodyStyle()), _uOnly(dateStr, width: 130)]),
        ]),
        pw.SizedBox(height: 14),

        // ═══ TO WHOM IT MAY CONCERN ═══
        pw.Align(alignment: pw.Alignment.centerLeft,
            child: pw.Text('TO WHOM IT MAY CONCERN:', style: _bodyBold())),
        pw.SizedBox(height: 12),

        pw.RichText(text: pw.TextSpan(style: _bodyStyle(), children: [
          const pw.TextSpan(text: 'This is to certify that the plants/plant products described below have been inspected by the under assigned and were found to be substantially free any plant pest and disease, '),
          pw.TextSpan(text: 'and that said plant products are hereby allowed to be transport from', style: _bodyBold()),
        ])),
        pw.SizedBox(height: 8),

        // ═══ FROM → TO ═══
        pw.Row(children: [
          pw.Expanded(child: pw.Container(
            decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black))),
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Text(source, style: _fieldValue(), textAlign: pw.TextAlign.center),
          )),
          pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 12),
              child: pw.Text('to', style: _bodyStyle())),
          pw.Expanded(child: pw.Container(
            decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black))),
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Text(destination, style: _fieldValue(), textAlign: pw.TextAlign.center),
          )),
        ]),
        pw.SizedBox(height: 20),

        // ═══ DETAILS ═══
        _uField('Name and Address of Sender', senderName.isNotEmpty ? '$senderName, $senderAddress' : senderAddress),
        _uField('Name and Address of Consignee', receiver),
        _uField('Kind/ Quality of Plants/ Plant Product', productType),
        _uField('Number of Kilos', kilos),
        _uField('Source of Plants/Plant Product', source),
        _uField('Declared means of Conveyance', transportation),
        pw.SizedBox(height: 24),

        // ═══ DISINFECTION ═══
        pw.Text('DISINFECTION AND / OR DISINFECTION TREATMENT',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _pdfMagenta)),
        pw.SizedBox(height: 14),
        _uField('Treatment', '', labelWidth: 220),
        _uField('Chemical (active ingredients)', '', labelWidth: 220),
        _uField('Concentration / Dosage', '', labelWidth: 220),
        _uField('Additional Information', '', labelWidth: 220),
        pw.SizedBox(height: 30),

        // ═══ APPROVED BY ═══
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
          _signatureBlock(
            title: 'Approved by:',
            name: 'HERNAN P. FENIX, LAgr, REA, EnP',
            position: 'Municipal Agriculturist',
          ),
        ]),
        pw.Spacer(),

        // ═══ PAYMENT ═══
        _paymentFooter(data),
      ],
    ),
  ));

  return pdf.save();
}

// ═══════════════════════════════════════════════════════════════
//  ANIMAL TRANSPORT PERMIT PDF
// ═══════════════════════════════════════════════════════════════

Future<Uint8List> _generateAnimalPermitPdf(Map<String, dynamic> data, String permitId) async {
  final pdf = pw.Document(title: 'Animal Transport Permit - $permitId', author: 'Municipal Agriculture Office');

  // Load the logos
  final leftLogo = await _loadPdfImage('assets/municipal.jpg');
  final rightLogo = await _loadPdfImage('assets/logo.png');

  final applicant = (data['applicant'] as Map?)?.cast<String, dynamic>() ?? {};
  final req = (data['request'] as Map?)?.cast<String, dynamic>() ?? {};

  final shipperName = _fullName(applicant);
  final source = req['source']?.toString() ?? '';
  final destination = req['destination']?.toString() ?? '';
  final animalType = req['animalType']?.toString() ?? req['productType']?.toString() ?? '';
  final heads = req['heads']?.toString() ?? '';
  final dateStr = _permitDate(data);
  final refNum = _permitRef(permitId);

  // Determine which animal types to check
  final animalLower = animalType.toLowerCase();

  // Calculate validity (30 days from claim date or now)
  String validUntil = '';
  final claimStr = data['claimDate'] as String?;
  if (claimStr != null) {
    try {
      final claimDate = DateTime.parse(claimStr);
      validUntil = DateFormat('MMMM d, yyyy').format(claimDate.add(const Duration(days: 30)));
    } catch (_) {}
  }
  if (validUntil.isEmpty) {
    validUntil = DateFormat('MMMM d, yyyy').format(DateTime.now().add(const Duration(days: 30)));
  }

  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.symmetric(horizontal: 50, vertical: 40),
    build: (ctx) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // ═══ HEADER ═══
        _pdfHeader(
          leftLogo: leftLogo,
          rightLogo: rightLogo,
        ),
        pw.SizedBox(height: 16),

        // ═══ PERMIT NO ═══
        pw.Row(children: [
          pw.Text('Permit No.', style: _bodyBold()),
          _uOnly(refNum, width: 120),
        ]),
        pw.SizedBox(height: 10),

        // ═══ DATE ═══
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
            pw.Text('Date:', style: _bodyStyle()),
            _uOnly(dateStr, width: 130),
          ]),
        ),
        pw.SizedBox(height: 6),

        // ═══ TRANSPORT PERMIT TITLE ═══
        pw.Center(
          child: pw.Text('TRANSPORT PERMIT', style: _titleGreen()),
        ),
        pw.SizedBox(height: 16),

        // ═══ THIS IS TO ALLOW ═══
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text('This is to allow', style: _bodyStyle()),
          pw.SizedBox(width: 4),
          pw.Expanded(child: pw.Container(
            decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black))),
            padding: const pw.EdgeInsets.only(bottom: 2, left: 4),
            child: pw.Text(shipperName, style: _fieldValue()),
          )),
          pw.SizedBox(width: 4),
          pw.Text('to ship from', style: _bodyStyle()),
          pw.SizedBox(width: 4),
          pw.Expanded(child: pw.Container(
            decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black))),
            padding: const pw.EdgeInsets.only(bottom: 2, left: 4),
            child: pw.Text(source, style: _fieldValue()),
          )),
        ]),
        pw.SizedBox(height: 2),
        pw.Align(alignment: pw.Alignment.centerRight,
            child: pw.Text('Shipper / Owner', style: _smallGrey())),
        pw.SizedBox(height: 2),
        pw.Align(alignment: pw.Alignment.centerRight,
            child: pw.Text('Point of Origin', style: _smallGrey())),
        pw.SizedBox(height: 6),

        // ═══ TO / DESTINATION / HEADS ═══
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.SizedBox(width: 80),
          pw.Text('to ', style: _bodyStyle()),
          pw.SizedBox(width: 4),
          pw.Expanded(child: pw.Container(
            decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black))),
            padding: const pw.EdgeInsets.only(bottom: 2, left: 4),
            child: pw.Text(destination, style: _fieldValue()),
          )),
          pw.SizedBox(width: 8),
          pw.Text('No. of heads', style: _bodyStyle()),
          pw.SizedBox(width: 4),
          pw.Container(
            width: 80,
            decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black))),
            padding: const pw.EdgeInsets.only(bottom: 2, left: 4),
            child: pw.Text(heads, style: _fieldValue()),
          ),
        ]),
        pw.SizedBox(height: 2),
        pw.Padding(
          padding: const pw.EdgeInsets.only(left: 100),
          child: pw.Text('Point of Destination', style: _smallGrey()),
        ),
        pw.SizedBox(height: 12),

        // ═══ ANIMAL TYPE CHECKBOXES ═══
        _animalTypeRow(animalLower),
        pw.SizedBox(height: 8),

        // ═══ OTHER ═══
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text('Other( Pls. Specify) :', style: _bodyStyle()),
          pw.SizedBox(width: 4),
          pw.Expanded(child: pw.Container(
            decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black))),
            padding: const pw.EdgeInsets.only(bottom: 2, left: 4),
            child: pw.Text(
              _isOther(animalLower) ? animalType : '',
              style: _fieldValue(),
            ),
          )),
        ]),
        pw.SizedBox(height: 12),

        // ═══ REQUIREMENTS CHECKLIST ═══
        pw.Text('The said shipper/ owner satisfied all the requirements as imposed by laws, to wit:',
            style: _bodyStyle()),
        pw.SizedBox(height: 10),

        _checkItem('Barangay Clearance ( Point Origin )'),
        _checkItem("Mayor's Business Permit"),
        _checkItem("Shipper's Permit (Livestock Handler's License)"),
        _checkItem('Certificate of Ownership of Large Cattle ( COLC- Credential)'),
        _checkItem('Certificate of transfer of Ownership of Large Cattle (COLC)'),
        _checkItem('Police Clearance'),
        _checkItem('Official Receipt(s)'),
        pw.SizedBox(height: 16),

        // ═══ VALIDITY ═══
        pw.RichText(text: pw.TextSpan(style: _bodyStyle(), children: [
          const pw.TextSpan(text: 'This permit is valid until '),
          pw.TextSpan(text: validUntil, style: _fieldValue()),
          const pw.TextSpan(text: ' and is subject to cancellation should be dangerous communicable animal disease break out the place of origin or may be revoked at anytime before the said date if the interest of the government so requires.'),
        ])),
        pw.SizedBox(height: 28),

        // ═══ AUTHORITY ═══
        pw.Text('BY AUTHORITY OF THE PROVINCIAL VETERINARIAN:', style: _bodyBold()),
        pw.SizedBox(height: 8),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: _signatureBlock(
            title: '',
            name: 'HERNAN P. FENIX',
            position: 'Municipal Agriculturist',
          ),
        ),
        pw.Spacer(),

        // ═══ PAYMENT FOOTER ═══
        _paymentFooter(data),
      ],
    ),
  ));

  return pdf.save();
}

// ── Animal type checkbox row ──
pw.Widget _animalTypeRow(String animalLower) {
  final types = [
    {'label': 'Cattle', 'key': 'cattle'},
    {'label': 'Carabao', 'key': 'carabao'},
    {'label': 'Goat', 'key': 'goat'},
    {'label': 'Swine', 'key': 'swine'},
    {'label': 'Poultry', 'key': 'poultry'},
    {'label': 'Dog/ Cat', 'key': 'dog'},
  ];

  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.start,
    children: types.map((t) {
      final checked = animalLower.contains(t['key']!);
      return pw.Padding(
        padding: const pw.EdgeInsets.only(right: 12),
        child: pw.Row(children: [
          pw.Container(
            width: 14, height: 14,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 1),
            ),
            child: checked
                ? pw.Center(child: pw.Text('✓', style: pw.TextStyle(
                    fontSize: 10, fontWeight: pw.FontWeight.bold)))
                : pw.SizedBox(),
          ),
          pw.SizedBox(width: 3),
          pw.Text(t['label']!, style: pw.TextStyle(fontSize: 9)),
        ]),
      );
    }).toList(),
  );
}

// ── Check if "other" animal ──
bool _isOther(String animalLower) {
  final known = ['cattle', 'carabao', 'goat', 'swine', 'poultry', 'dog', 'cat', 'chicken'];
  return !known.any((k) => animalLower.contains(k));
}

// ── Checklist item ──
pw.Widget _checkItem(String label) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6, left: 30),
    child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Container(
        width: 14, height: 14,
        margin: const pw.EdgeInsets.only(top: 1),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.black, width: 1),
        ),
        child: pw.Center(child: pw.Text('✓', style: pw.TextStyle(
            fontSize: 9, fontWeight: pw.FontWeight.bold))),
      ),
      pw.SizedBox(width: 8),
      pw.Expanded(child: pw.Text(label, style: pw.TextStyle(fontSize: 10))),
    ]),
  );
}