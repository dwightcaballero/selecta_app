import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:selecta_ops/controllers/badorder_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/badorder.dart';
import 'package:selecta_ops/models/hapistore.dart';
import 'package:selecta_ops/services/error_log_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/audithistory_widget.dart';

class BadOrderPage extends StatefulWidget {
  const BadOrderPage({super.key, required this.recID, required this.badorder});

  final BadOrder badorder;
  final String recID;

  @override
  State<BadOrderPage> createState() => _BadOrderPageState();
}

class _BadOrderPageState extends State<BadOrderPage> {
  // Controller managing data mutations, role verification, and store streams
  final BadOrderController _controller = BadOrderController();

  final TextEditingController dropDownController = TextEditingController();
  final TextEditingController txtAmount = TextEditingController();
  final TextEditingController txtDescription = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  bool _isDealer = false;
  DateTime _selectedDate = DateTime.now();

  bool get isReadOnly => widget.recID.isNotEmpty && !_isDealer;

  @override
  void dispose() {
    txtDescription.dispose();
    txtAmount.dispose();
    dropDownController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    prefetchData();
  }

  // Load user role and initial form values
  void prefetchData() async {
    _isDealer = await _controller.checkIsDealer();
    if (widget.recID.isNotEmpty) {
      txtDescription.text = widget.badorder.description;
      txtAmount.text = Helperfunctions.formatDoubleAmountForField(widget.badorder.badorderAmount);
      _selectedDate = widget.badorder.badorderDate.toDate();
      dropDownController.text = widget.badorder.hapistore;
    }
    if (mounted) setState(() {});
  }

  // Create new bad order record through controller
  Future<void> onSave() async {
    if (_formKey.currentState!.validate()) {
      try {
        await _controller.createBadOrder(
          hapistore: dropDownController.text,
          description: txtDescription.text,
          amount: Helperfunctions.formatStringAmountToDouble(txtAmount.text),
          selectedDate: _selectedDate,
        );
        if (mounted) {
          ShowMessage.success(context, 'Successfully created bad order record for [${dropDownController.text}]!');
          Navigator.pop(context);
        }
      } catch (e, s) {
        ErrorLogService.logError(
          page: 'BadOrderPage',
          action: 'Create Bad Order Record',
          error: e,
          stackTrace: s,
          extraData: {'hapistore': dropDownController.text, 'amount': txtAmount.text},
        );
        if (mounted) {
          ShowMessage.error(context, 'Failed to create record: $e');
        }
      }
    } else {
      ShowMessage.error(context, 'Please fill up all required fields');
    }
  }

  // Delete bad order record through controller (dealer only)
  Future<void> onDelete() async {
    if (!_isDealer) {
      ShowMessage.error(context, 'Only dealers are authorized to delete bad order records.');
      return;
    }
    try {
      await _controller.deleteBadOrder(recID: widget.recID, existingRecord: widget.badorder);
      if (mounted) {
        ShowMessage.success(context, 'Successfully deleted bad order record for [${widget.badorder.hapistore}]!');
        Navigator.pop(context);
      }
    } catch (e, s) {
      ErrorLogService.logError(
        page: 'BadOrderPage',
        action: 'Delete Bad Order Record',
        error: e,
        stackTrace: s,
        extraData: {'recID': widget.recID, 'hapistore': widget.badorder.hapistore},
      );
      if (mounted) {
        ShowMessage.error(context, 'Failed to delete record: $e');
      }
    }
  }

  // Update existing bad order record through controller (dealer only)
  Future<void> onUpdate() async {
    if (!_isDealer) {
      ShowMessage.error(context, 'Only dealers are authorized to update bad order records.');
      return;
    }
    if (_formKey.currentState!.validate()) {
      try {
        await _controller.updateBadOrder(
          recID: widget.recID,
          existingRecord: widget.badorder,
          hapistore: dropDownController.text,
          description: txtDescription.text,
          amount: Helperfunctions.formatStringAmountToDouble(txtAmount.text),
          selectedDate: _selectedDate,
        );
        if (mounted) {
          ShowMessage.success(context, 'Successfully updated bad order record for [${dropDownController.text}]!');
          Navigator.pop(context);
        }
      } catch (e, s) {
        ErrorLogService.logError(
          page: 'BadOrderPage',
          action: 'Update Bad Order Record',
          error: e,
          stackTrace: s,
          extraData: {'recID': widget.recID, 'hapistore': dropDownController.text},
        );
        if (mounted) {
          ShowMessage.error(context, 'Failed to update record: $e');
        }
      }
    } else {
      ShowMessage.error(context, 'Please fill up all required fields');
    }
  }

  void onChangeDate() async {
    final DateTime? dateTime = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(3000),
    );

    if (dateTime != null) {
      setState(() {
        _selectedDate = dateTime;
      });
    }
  }

  void onFocusChange(bool hasFocus, TextEditingController controller) {
    if (controller.text.isNotEmpty) {
      if (!hasFocus) {
        setState(() => controller.text = Helperfunctions.formatStringAmountForDisplay(controller.text));
      } else {
        setState(() => controller.text = Helperfunctions.formatStringAmountForEditing(controller.text));
      }
    }
  }

  Widget _buildSectionCard({required String title, required IconData icon, required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, size: 18, color: colorScheme.primary),
                ),
                const SizedBox(width: 10),
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 24),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildIncidentDetailsCard() {
    return _buildSectionCard(
      title: 'Incident Details',
      icon: Icons.remove_shopping_cart_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          _buildHapistoreDropdown(),
          _buildMoneyField(label: 'Bad Order Amount', controller: txtAmount, prefixIcon: Icons.payments_outlined),
          _buildDatePickerField(label: 'Incident Date', selectedDate: _selectedDate, onTap: onChangeDate),
        ],
      ),
    );
  }

  Widget _buildDescriptionCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return _buildSectionCard(
      title: 'Item Damage Description',
      icon: Icons.notes_outlined,
      child: TextFormField(
        controller: txtDescription,
        readOnly: isReadOnly,
        keyboardType: TextInputType.multiline,
        minLines: 3,
        maxLines: null,
        decoration: InputDecoration(
          labelText: 'Description / Remarks',
          hintText: isReadOnly ? '' : 'Specify damaged items, expiry dates, or batch details...',
          alignLabelWithHint: true,
          prefixIcon: Icon(Icons.notes_outlined, size: 20, color: colorScheme.primary),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
        autovalidateMode: AutovalidateMode.onUnfocus,
        validator: (value) {
          if (value == null || value.trim().isEmpty) return 'Description should not be blank';
          return null;
        },
      ),
    );
  }

  Widget _buildHapistoreDropdown() {
    return StreamBuilder(
      stream: _controller.getHapiStoresStream(),
      builder: (BuildContext context, AsyncSnapshot snapshot) {
        final listHapiStore = snapshot.data?.docs ?? [];
        List<DropdownMenuEntry<String>> listDropdownItems = [];
        for (int i = 0; i < listHapiStore.length; i++) {
          Hapistore hapistore = listHapiStore[i].data();
          listDropdownItems.add(DropdownMenuEntry(value: hapistore.storeName, label: hapistore.storeName));
        }

        return DropdownMenuFormField<String>(
          controller: dropDownController,
          enabled: !isReadOnly,
          initialSelection: dropDownController.text,
          label: const Text('Hapi Store'),
          leadingIcon: const Icon(Icons.storefront_outlined, size: 20),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
          validator: (value) => value == null || value.isEmpty ? 'Please select a Hapi Store' : null,
          autovalidateMode: AutovalidateMode.onUnfocus,
          dropdownMenuEntries: listDropdownItems,
          enableSearch: true,
          enableFilter: true,
          requestFocusOnTap: true,
          expandedInsets: EdgeInsets.zero,
          menuHeight: 300,
        );
      },
    );
  }

  Widget _buildMoneyField({required String label, required TextEditingController controller, required IconData prefixIcon}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Focus(
      onFocusChange: isReadOnly ? null : (hasFocus) => onFocusChange(hasFocus, controller),
      child: TextFormField(
        controller: controller,
        readOnly: isReadOnly,
        textAlign: TextAlign.end,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
        autovalidateMode: AutovalidateMode.onUnfocus,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(prefixIcon, size: 20, color: colorScheme.primary),
          prefixText: '₱ ',
          prefixStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
        validator: (value) {
          double amount = Helperfunctions.formatStringAmountToDouble(controller.text);
          if (amount <= 0) return '$label should be greater than 0';
          return null;
        },
      ),
    );
  }

  Widget _buildDatePickerField({required String label, required DateTime selectedDate, required VoidCallback onTap}) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: isReadOnly ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_month_outlined, size: 20, color: colorScheme.primary),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                Text(Helperfunctions.formatDateForDisplay(selectedDate), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
            const Spacer(),
            Icon(Icons.edit_calendar_outlined, size: 18, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }



  Widget _buildStickyBottomBar() {
    final colorScheme = Theme.of(context).colorScheme;
    final bool isUpdating = widget.recID.isNotEmpty;
    if (isUpdating && !_isDealer) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 1.0)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), offset: const Offset(0, -2), blurRadius: 6)],
        ),
        child: isUpdating
            ? Row(
                children: [
                  if (_isDealer) ...[
                    Expanded(
                      flex: 1,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final confirmed = await ShowMessage.confirm(
                            context,
                            title: ConfirmTitle.delete,
                            message: 'Are you sure you want to delete this bad order record for [${widget.badorder.hapistore}]?',
                            isDestructive: true,
                            icon: Icons.delete_outline,
                            confirmText: 'Delete',
                          );
                          if (confirmed) onDelete();
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 50.0),
                          foregroundColor: Colors.red.shade700,
                          side: BorderSide(color: Colors.red.shade300, width: 1.2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.delete_outline, size: 20),
                        label: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    flex: _isDealer ? 2 : 1,
                    child: FilledButton.icon(
                      onPressed: () async {
                        final confirmed = await ShowMessage.confirm(
                          context,
                          title: ConfirmTitle.update,
                          message: 'Save changes to this bad order record for [${dropDownController.text}]?',
                          icon: Icons.check_circle_outline,
                          confirmText: 'Update',
                        );
                        if (confirmed) onUpdate();
                      },
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 50.0),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.check_circle_outline, size: 20),
                      label: const Text('Update Record', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              )
            : FilledButton.icon(
                onPressed: () async {
                  final confirmed = await ShowMessage.confirm(
                    context,
                    title: ConfirmTitle.save,
                    message: 'Save this bad order record for [${dropDownController.text}]?',
                    icon: Icons.save_outlined,
                    confirmText: 'Save',
                  );
                  if (confirmed) onSave();
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50.0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save Bad Order', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppbar(title: 'Bad Order', subtitle: widget.recID.isEmpty ? 'New Record' : widget.badorder.hapistore),
      bottomNavigationBar: _buildStickyBottomBar(),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 16,
            children: [
              if (isReadOnly)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade300, width: 1.2),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline, color: Colors.amber.shade900, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'View-Only: Only dealers are authorized to edit or delete existing bad order records.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.amber.shade900,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // 1. Incident Details Card
              _buildIncidentDetailsCard(),

              // 2. Damage Description Card
              _buildDescriptionCard(),

              // 3. Audit & History Card (if updating)
              if (widget.recID.isNotEmpty)
                AuditHistoryWidget(
                  createdBy: widget.badorder.createdBy,
                  createdDate: widget.badorder.createdDate,
                  createdPage: widget.badorder.createdPage,
                  lastUpdatedBy: widget.badorder.lastUpdatedBy,
                  lastUpdatedDate: widget.badorder.lastupdatedDate,
                  lastUpdatedPage: widget.badorder.lastUpdatedPage,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
