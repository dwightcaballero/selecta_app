import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/credit_controller.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';

/// Interactive modal dialog allowing salesmen and dealers to review, edit,
/// and dispatch overdue credit SMS reminders via native SMS app or direct Telephony.
class CreditSmsDialog extends StatefulWidget {
  final String storeName;
  final double creditAmount;
  final DateTime? creditDate;
  final int daysOverdue;
  final String? initialPhoneNumber;

  const CreditSmsDialog({
    super.key,
    required this.storeName,
    required this.creditAmount,
    required this.creditDate,
    required this.daysOverdue,
    this.initialPhoneNumber,
  });

  /// Displays the CreditSmsDialog modal.
  static Future<void> show({
    required BuildContext context,
    required String storeName,
    required double creditAmount,
    required DateTime? creditDate,
    required int daysOverdue,
    String? initialPhoneNumber,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => CreditSmsDialog(
        storeName: storeName,
        creditAmount: creditAmount,
        creditDate: creditDate,
        daysOverdue: daysOverdue,
        initialPhoneNumber: initialPhoneNumber,
      ),
    );
  }

  @override
  State<CreditSmsDialog> createState() => _CreditSmsDialogState();
}

class _CreditSmsDialogState extends State<CreditSmsDialog> {
  final CreditController _controller = CreditController();

  late final TextEditingController _phoneController;
  late final TextEditingController _messageController;

  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(text: widget.initialPhoneNumber ?? '');
    _messageController = TextEditingController();
    _initData();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    try {
      String contact = widget.initialPhoneNumber ?? '';
      if (contact.trim().isEmpty) {
        contact = await _controller.getStoreContact(widget.storeName);
      }

      final template = await _controller.getCreditReminderTemplate();
      final renderedMessage = _controller.buildReminderMessage(
        template: template,
        storeName: widget.storeName,
        creditAmount: widget.creditAmount,
        creditDate: widget.creditDate,
        daysOverdue: widget.daysOverdue,
      );

      if (mounted) {
        setState(() {
          _phoneController.text = contact;
          _messageController.text = renderedMessage;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleLaunchSmsApp() async {
    final phone = _phoneController.text.trim();
    final message = _messageController.text.trim();

    if (phone.isEmpty) {
      ShowMessage.error(context, 'Please specify a recipient phone number.');
      return;
    }
    if (message.isEmpty) {
      ShowMessage.error(context, 'Message cannot be empty.');
      return;
    }

    final launched = await _controller.launchSmsApp(phone: phone, message: message);
    if (!launched && mounted) {
      ShowMessage.error(context, 'Unable to open messaging application.');
    } else if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleSendDirectSms() async {
    final phone = _phoneController.text.trim();
    final message = _messageController.text.trim();

    if (phone.isEmpty) {
      ShowMessage.error(context, 'Please specify a recipient phone number.');
      return;
    }
    if (message.isEmpty) {
      ShowMessage.error(context, 'Message cannot be empty.');
      return;
    }

    setState(() => _isSending = true);

    try {
      final success = await _controller.sendDirectSms(phone: phone, message: message);
      if (!mounted) return;

      if (success) {
        ShowMessage.success(context, 'Credit reminder SMS sent successfully to ${widget.storeName}!');
        Navigator.of(context).pop();
      } else {
        setState(() => _isSending = false);
        ShowMessage.error(context, 'Failed to send SMS. Ensure SMS permissions are granted.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ShowMessage.error(context, 'Error sending SMS: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final charCount = _messageController.text.length;
    final segmentCount = (charCount == 0) ? 1 : ((charCount - 1) ~/ 153) + 1;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF97316).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.sms_rounded, color: Color(0xFFF97316), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Credit SMS Reminder', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  widget.storeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
      content: _isLoading
          ? const SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Credit metrics summary bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              Text('Credit Amount', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                              const SizedBox(height: 2),
                              Text(
                                Helperfunctions.formatDoubleAmountForDisplay(widget.creditAmount),
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red.shade700),
                              ),
                            ],
                          ),
                          Container(width: 1, height: 24, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                          Column(
                            children: [
                              Text('Aging', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                              const SizedBox(height: 2),
                              Text(
                                '${widget.daysOverdue} days',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: widget.daysOverdue >= 30 ? Colors.red.shade700 : Colors.orange.shade800,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Recipient phone number field
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Recipient Phone Number *',
                        prefixIcon: const Icon(Icons.phone_iphone_rounded, size: 20),
                        hintText: 'e.g. 09171234567',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Editable message content
                    TextField(
                      controller: _messageController,
                      maxLines: 5,
                      minLines: 3,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(fontSize: 13, height: 1.35),
                      decoration: InputDecoration(
                        labelText: 'Message Body *',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '$charCount chars • ~$segmentCount SMS segment${segmentCount > 1 ? 's' : ''}',
                            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Review before sending',
                          style: TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isSending ? null : _handleLaunchSmsApp,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Open App', style: TextStyle(fontSize: 12.5)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: _isSending ? null : _handleSendDirectSms,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF97316),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: _isSending
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 16),
                label: Text(_isSending ? 'Sending...' : 'Send SMS', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
