import 'package:another_telephony/telephony.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/pjp_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/models/hapistore.dart';
import 'package:selecta_ops/services/delivery_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';

/// Modal dialog allowing Dealers to broadcast / blast pre-order reminder SMS messages
/// to all stores scheduled on a specific PJP day (defaults to tomorrow).
class PjpSmsBroadcastDialog extends StatefulWidget {
  final String? initialDay;

  const PjpSmsBroadcastDialog({super.key, this.initialDay});

  static Future<void> show({required BuildContext context, String? initialDay}) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PjpSmsBroadcastDialog(initialDay: initialDay),
    );
  }

  @override
  State<PjpSmsBroadcastDialog> createState() => _PjpSmsBroadcastDialogState();
}

class _PjpSmsBroadcastDialogState extends State<PjpSmsBroadcastDialog> {
  final PjpController _controller = PjpController();
  final Telephony _telephony = Telephony.instance;

  late String _selectedDay;
  final TextEditingController _templateController = TextEditingController();

  bool _isLoadingStores = true;
  List<Hapistore> _stores = [];
  Set<String> _alreadyOrderedStoreNames = {};
  bool _skipAlreadyOrdered = true;

  // Sending State
  bool _isSending = false;
  int _currentSendingIndex = 0;
  int _totalToSend = 0;
  String _currentRecipientName = '';
  int _successCount = 0;
  int _failedCount = 0;
  final List<String> _failureLogs = [];

  @override
  void initState() {
    super.initState();
    _selectedDay = widget.initialDay ?? _computeTomorrowDay();
    _templateController.text =
        '[SELECTA PRE-ORDER REMINDER]\n'
        'Good day {storeName}!\n'
        'Selecta delivery is scheduled for tomorrow ({day}).\n'
        'Please reply with your ice cream orders before 4:00 PM today so we can reserve your stock.\n'
        'Thank you!';
    _loadStoresForDay();
  }

  @override
  void dispose() {
    _templateController.dispose();
    super.dispose();
  }

  String _computeTomorrowDay() {
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));
    return PjpController.weekdayNames[tomorrow.weekday - 1];
  }

  DateTime _getTargetDateForDay(String day) {
    final now = DateTime.now();
    final targetIndex = PjpController.weekdayNames.indexOf(day);
    if (targetIndex < 0) return now.add(const Duration(days: 1));

    // Calculate days ahead
    final currentWeekdayIndex = now.weekday - 1; // 0 = Mon, 6 = Sun
    int diff = targetIndex - currentWeekdayIndex;
    if (diff <= 0) diff += 7; // Target is next week if same or prior day
    return DateTime(now.year, now.month, now.day + diff);
  }

  Future<void> _loadStoresForDay() async {
    setState(() => _isLoadingStores = true);

    try {
      final snap = await _controller.getStoresForDayStream(_selectedDay).first;
      final sortedDocs = _controller.sortStoreDocs(snap.docs);

      final stores = sortedDocs
          .map((doc) {
            final raw = doc.data();
            return raw is Hapistore ? raw : Hapistore.fromJson(raw as Map<String, Object?>);
          })
          .where((s) => s.storeName.trim().isNotEmpty)
          .toList();

      // Check which stores already placed orders for this target day
      final targetDate = _getTargetDateForDay(_selectedDay);
      final startOfDay = DateTime(targetDate.year, targetDate.month, targetDate.day, 0, 0, 0);
      final endOfDay = DateTime(targetDate.year, targetDate.month, targetDate.day, 23, 59, 59);

      Set<String> orderedNames = {};
      try {
        final deliverySnap = await FirebaseFirestore.instance
            .collection(DELIVERY_COLLECTION_REF)
            .where(DeliveryModelString.deliveryDate, isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
            .where(DeliveryModelString.deliveryDate, isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
            .get();

        for (final doc in deliverySnap.docs) {
          final data = doc.data();
          final status = (data['transactionStatus'] as String? ?? '').trim();
          if (status != DeliveryStatus.voided) {
            final name = (data['storeName'] as String? ?? '').trim().toLowerCase();
            if (name.isNotEmpty) orderedNames.add(name);
          }
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _stores = stores;
        _alreadyOrderedStoreNames = orderedNames;
        _isLoadingStores = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingStores = false);
    }
  }

  bool _hasValidContact(Hapistore store) {
    final cleaned = store.storeContact.replaceAll(RegExp(r'[^\d]'), '');
    return cleaned.length >= 10;
  }

  bool _isAlreadyOrdered(Hapistore store) {
    return _alreadyOrderedStoreNames.contains(store.storeName.trim().toLowerCase());
  }

  List<Hapistore> get _targetRecipients {
    return _stores.where((store) {
      if (!_hasValidContact(store)) return false;
      if (_skipAlreadyOrdered && _isAlreadyOrdered(store)) return false;
      return true;
    }).toList();
  }

  String _formatPhoneNumber(String raw) {
    String cleaned = raw.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.startsWith('09') && cleaned.length == 11) {
      cleaned = '+63${cleaned.substring(1)}';
    } else if (cleaned.startsWith('9') && cleaned.length == 10) {
      cleaned = '+63$cleaned';
    }
    return cleaned;
  }

  String _buildPersonalizedMessage(String storeName) {
    return _templateController.text
        .replaceAll('{storeName}', storeName)
        .replaceAll('{day}', _selectedDay);
  }

  Future<void> _startBroadcast() async {
    final recipients = _targetRecipients;
    if (recipients.isEmpty) {
      ShowMessage.alert(
        context,
        title: 'No Recipients',
        message: 'There are no stores matching your broadcast criteria for $_selectedDay.',
        icon: Icons.info_outline,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.campaign_rounded, color: Theme.of(ctx).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Confirm SMS Broadcast', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ready to send pre-order reminder SMS to ${recipients.length} stores on the $_selectedDay route?'),
            const SizedBox(height: 10),
            Text(
              'Standard carrier SMS rates may apply. Messages will be sent automatically using the device\'s active SIM.',
              style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.send_rounded, size: 16),
            label: Text('Send to ${recipients.length} Stores'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Check permissions
    final bool? permissionsGranted = await _telephony.requestPhoneAndSmsPermissions;
    if (!(permissionsGranted ?? false)) {
      if (mounted) {
        ShowMessage.error(context, 'SMS permissions are required to broadcast messages.');
      }
      return;
    }

    setState(() {
      _isSending = true;
      _currentSendingIndex = 0;
      _totalToSend = recipients.length;
      _successCount = 0;
      _failedCount = 0;
      _failureLogs.clear();
    });

    for (int i = 0; i < recipients.length; i++) {
      if (!mounted) break;
      final store = recipients[i];
      final formattedNumber = _formatPhoneNumber(store.storeContact);
      final message = _buildPersonalizedMessage(store.storeName);

      setState(() {
        _currentSendingIndex = i + 1;
        _currentRecipientName = store.storeName;
      });

      try {
        await _telephony.sendSms(
          to: formattedNumber,
          message: message,
          isMultipart: true,
        );
        _successCount++;
      } catch (e) {
        _failedCount++;
        _failureLogs.add('${store.storeName} ($formattedNumber): $e');
      }

      // Small delay between sends to respect modem queue and avoid OS rate limiting
      await Future.delayed(const Duration(milliseconds: 650));
    }

    if (!mounted) return;

    setState(() => _isSending = false);

    // Show completion summary
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              _failedCount == 0 ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
              color: _failedCount == 0 ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 8),
            const Text('Broadcast Completed', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sent successfully to $_successCount store(s).'),
            if (_failedCount > 0) ...[
              const SizedBox(height: 6),
              Text('Failed to send to $_failedCount store(s):', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              ..._failureLogs.take(5).map((log) => Text('• $log', style: const TextStyle(fontSize: 11, color: Colors.red))),
            ],
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context); // Close main dialog
            },
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final recipients = _targetRecipients;

    final validPhoneCount = _stores.where(_hasValidContact).length;
    final alreadyOrderedCount = _stores.where(_isAlreadyOrdered).length;
    final missingPhoneCount = _stores.length - validPhoneCount;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _isSending ? _buildSendingProgress(colorScheme) : _buildMainForm(colorScheme, recipients, validPhoneCount, alreadyOrderedCount, missingPhoneCount),
        ),
      ),
    );
  }

  Widget _buildSendingProgress(ColorScheme colorScheme) {
    final progress = _totalToSend > 0 ? _currentSendingIndex / _totalToSend : 0.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
          child: Icon(Icons.outgoing_mail, size: 48, color: colorScheme.primary),
        ),
        const SizedBox(height: 20),
        const Text('Broadcasting Pre-Order Reminders', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          'Sending $_currentSendingIndex of $_totalToSend',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colorScheme.primary),
        ),
        const SizedBox(height: 4),
        Text(
          _currentRecipientName,
          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(value: progress, minHeight: 8),
        ),
        const SizedBox(height: 20),
        Text('Please keep the app open while SMS messages are transmitting.', style: TextStyle(fontSize: 11, color: colorScheme.outline)),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildMainForm(
    ColorScheme colorScheme,
    List<Hapistore> recipients,
    int validPhoneCount,
    int alreadyOrderedCount,
    int missingPhoneCount,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.campaign_rounded, color: colorScheme.primary, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Pre-Order SMS Broadcast', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                  Text('Blast reminder texts to scheduled PJP stores', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        const Divider(height: 20),

        // Route Day Picker
        Row(
          children: [
            const Text('Target Route Day:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: _selectedDay,
              underline: const SizedBox(),
              items: PjpController.weekdayNames.map((d) {
                final isTomorrow = d == _computeTomorrowDay();
                return DropdownMenuItem(
                  value: d,
                  child: Text('$d${isTomorrow ? ' (Tomorrow)' : ''}', style: TextStyle(fontWeight: isTomorrow ? FontWeight.bold : FontWeight.normal)),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null && val != _selectedDay) {
                  setState(() => _selectedDay = val);
                  _loadStoresForDay();
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Route Stats Chips
        if (_isLoadingStores)
          const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
        else ...[
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildStatChip(Icons.storefront_outlined, '${_stores.length} Scheduled', Colors.blue),
              _buildStatChip(Icons.phone_enabled_outlined, '$validPhoneCount With Phone', Colors.green),
              if (alreadyOrderedCount > 0)
                _buildStatChip(Icons.check_circle_outline, '$alreadyOrderedCount Ordered', Colors.purple),
              if (missingPhoneCount > 0)
                _buildStatChip(Icons.phone_disabled_outlined, '$missingPhoneCount No Phone', Colors.orange),
            ],
          ),
          const SizedBox(height: 12),

          // Skip already ordered checkbox
          if (alreadyOrderedCount > 0)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('Skip stores that already placed an order for $_selectedDay ($alreadyOrderedCount)', style: const TextStyle(fontSize: 12.5)),
              value: _skipAlreadyOrdered,
              onChanged: (val) => setState(() => _skipAlreadyOrdered = val ?? true),
              controlAffinity: ListTileControlAffinity.leading,
            ),
        ],

        const SizedBox(height: 8),
        const Text('SMS Message Template:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Tag {storeName} will be replaced with each store\'s name.', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
        const SizedBox(height: 6),

        // Template text area
        Expanded(
          child: TextField(
            controller: _templateController,
            maxLines: null,
            expands: true,
            style: const TextStyle(fontSize: 13, height: 1.35),
            decoration: InputDecoration(
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Action Buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: AsyncFilledButton.icon(
                onPressed: _isLoadingStores || recipients.isEmpty ? null : _startBroadcast,
                icon: const Icon(Icons.campaign_rounded, size: 18),
                label: Text(
                  'Send Broadcast (${recipients.length})',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatChip(IconData icon, String text, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color.shade800),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: color.shade900)),
        ],
      ),
    );
  }
}
