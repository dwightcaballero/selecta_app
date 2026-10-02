import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/hapistore_dropdown.dart';

/// Result returned when user confirms the Store & Delivery Date selection modal.
class StoreDateModalResult {
  final String storeName;
  final DateTime selectedDate;
  final String remarks;

  const StoreDateModalResult({
    required this.storeName,
    required this.selectedDate,
    required this.remarks,
  });
}

/// Bottom sheet modal allowing salesmen/dealers to select the target Hapi Store,
/// scheduled delivery date (Today, Tomorrow, Custom), and optional remarks.
class StoreDateModal extends StatefulWidget {
  final String initialStoreName;
  final DateTime initialDate;
  final String initialRemarks;

  const StoreDateModal({
    super.key,
    required this.initialStoreName,
    required this.initialDate,
    required this.initialRemarks,
  });

  /// Static helper to display the modal bottom sheet and return the chosen configuration.
  static Future<StoreDateModalResult?> show({
    required BuildContext context,
    required String initialStoreName,
    required DateTime initialDate,
    required String initialRemarks,
  }) {
    return showModalBottomSheet<StoreDateModalResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StoreDateModal(
        initialStoreName: initialStoreName,
        initialDate: initialDate,
        initialRemarks: initialRemarks,
      ),
    );
  }

  @override
  State<StoreDateModal> createState() => _StoreDateModalState();
}

class _StoreDateModalState extends State<StoreDateModal> {
  late final TextEditingController _storeController;
  late final TextEditingController _remarksController;
  late DateTime _tempDate;

  @override
  void initState() {
    super.initState();
    _storeController = TextEditingController(text: widget.initialStoreName);
    _remarksController = TextEditingController(text: widget.initialRemarks);
    _tempDate = widget.initialDate;
  }

  @override
  void dispose() {
    _storeController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final currentDay = DateTime(_tempDate.year, _tempDate.month, _tempDate.day);
    final isToday = currentDay == today;
    final isTomorrow = currentDay == tomorrow;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag Handle
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.storefront_outlined, color: colorScheme.primary, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _storeController.text.trim().isEmpty ? 'Select Store & Date' : 'Order Details',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Choose store and delivery schedule',
                            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Store Selection
                Text(
                  'Hapi Store *',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                ),
                const SizedBox(height: 6),
                HapistorePickerField(
                  controller: _storeController,
                  label: 'Hapi Store',
                  validator: (val) => (val == null || val.trim().isEmpty) ? 'Please select a Hapi Store' : null,
                  onChanged: () {
                    setState(() {});
                  },
                ),

                const SizedBox(height: 18),

                // Delivery Date Selection
                Text(
                  'Delivery Date *',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                ),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _tempDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() {
                        _tempDate = picked;
                      });
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today_outlined, color: colorScheme.primary, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                DateFormat('EEEE, MMMM d, y').format(_tempDate),
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                              ),
                              Text(
                                isToday ? 'Today' : (isTomorrow ? 'Tomorrow' : 'Scheduled Delivery'),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  color: (isToday || isTomorrow) ? colorScheme.primary : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.edit_calendar_outlined, color: colorScheme.primary, size: 20),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // Quick Date Chips
                Row(
                  children: [
                    ChoiceChip(
                      label: Text(
                        'Today',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isToday ? Colors.white : colorScheme.onSurface,
                        ),
                      ),
                      selected: isToday,
                      selectedColor: colorScheme.primary,
                      onSelected: (_) => setState(() => _tempDate = today),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(
                        'Tomorrow',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isTomorrow ? Colors.white : colorScheme.onSurface,
                        ),
                      ),
                      selected: isTomorrow,
                      selectedColor: colorScheme.primary,
                      onSelected: (_) => setState(() => _tempDate = tomorrow),
                    ),
                    const SizedBox(width: 8),
                    ActionChip(
                      avatar: Icon(Icons.calendar_month_outlined, size: 16, color: colorScheme.primary),
                      label: Text(
                        'Custom',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _tempDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setState(() {
                            _tempDate = picked;
                          });
                        }
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // Remarks / Special Instructions
                Text(
                  'Remarks (Optional)',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _remarksController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'e.g. Deliver before 10 AM...',
                    hintStyle: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: colorScheme.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Confirm Button
                FilledButton(
                  onPressed: () {
                    final store = _storeController.text.trim();
                    if (store.isEmpty) {
                      ShowMessage.error(context, 'Please select a Hapi Store first.');
                      return;
                    }
                    Navigator.pop(
                      context,
                      StoreDateModalResult(
                        storeName: store,
                        selectedDate: _tempDate,
                        remarks: _remarksController.text.trim(),
                      ),
                    );
                  },
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Continue to Products', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
