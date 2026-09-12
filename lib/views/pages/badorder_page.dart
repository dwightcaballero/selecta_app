import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/badorder.dart';
import 'package:flutter_app/models/hapistore.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/badorder_service.dart';
import 'package:flutter_app/services/hapistore_service.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:intl/intl.dart';

class BadOrderPage extends StatefulWidget {
  const BadOrderPage({super.key, required this.recID, required this.badorder});

  final String recID;
  final BadOrder badorder;

  @override
  State<BadOrderPage> createState() => _BadOrderPageState();
}

class _BadOrderPageState extends State<BadOrderPage> {
  final BadOrderService db = BadOrderService();
  final HapiStoreService dbHS = HapiStoreService();
  final _formKey = GlobalKey<FormState>();

  DateTime _selectedDate = DateTime.now();
  final TextEditingController txtDescription = TextEditingController();
  final TextEditingController txtAmount = TextEditingController();
  final TextEditingController dropDownController = TextEditingController();

  @override
  void initState() {
    super.initState();
    prefetchData();
  }

  void prefetchData() {
    if (widget.recID.isNotEmpty) {
      txtDescription.text = widget.badorder.description;
      txtAmount.text = widget.badorder.badorderAmount == 0 ? '' : Helperfunctions.formatDoubleAmountForDisplay(widget.badorder.badorderAmount);
      _selectedDate = widget.badorder.badorderDate.toDate();
      dropDownController.text = widget.badorder.hapistore;
    }
  }

  @override
  void dispose() {
    txtDescription.dispose();
    txtAmount.dispose();
    dropDownController.dispose();
    super.dispose();
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
              // 1. Incident Details Card
              _buildIncidentDetailsCard(),

              // 2. Damage Description Card
              _buildDescriptionCard(),

              // 3. Audit & History Card (if updating)
              if (widget.recID.isNotEmpty) _buildAuditCard(),
            ],
          ),
        ),
      ),
    );
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
        keyboardType: TextInputType.multiline,
        minLines: 3,
        maxLines: null,
        decoration: InputDecoration(
          labelText: 'Description / Remarks',
          hintText: 'Specify damaged items, expiry dates, or batch details...',
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
      stream: dbHS.getListHapiStoresAsStream(),
      builder: (BuildContext context, AsyncSnapshot snapshot) {
        final listHapiStore = snapshot.data?.docs ?? [];
        List<DropdownMenuEntry<String>> listDropdownItems = [];
        for (int i = 0; i < listHapiStore.length; i++) {
          Hapistore hapistore = listHapiStore[i].data();
          listDropdownItems.add(DropdownMenuEntry(value: hapistore.storeName, label: hapistore.storeName));
        }

        return DropdownMenuFormField<String>(
          controller: dropDownController,
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
      onFocusChange: (hasFocus) => onFocusChange(hasFocus, controller),
      child: TextFormField(
        controller: controller,
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
      onTap: onTap,
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

  Widget _buildAuditCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(Icons.history, size: 18, color: colorScheme.primary),
        ),
        title: const Text('Audit & History', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        initiallyExpanded: false,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                _buildAuditRow('Created By', widget.badorder.createdBy),
                _buildAuditRow('Created Date', DateFormat('E, d MMM yyyy, hh:mm a').format(widget.badorder.createdDate.toDate())),
                const Divider(height: 12),
                _buildAuditRow('Last Updated By', widget.badorder.lastUpdatedBy),
                _buildAuditRow('Last Updated Date', DateFormat('E, d MMM yyyy, hh:mm a').format(widget.badorder.lastupdatedDate.toDate())),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditRow(String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
        ),
      ],
    );
  }

  Widget _buildStickyBottomBar() {
    final colorScheme = Theme.of(context).colorScheme;
    bool isUpdating = widget.recID.isNotEmpty;

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
                  Expanded(
                    flex: 2,
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

  void onSave() {
    if (_formKey.currentState!.validate()) {
      BadOrder newRecord = BadOrder(
        description: txtDescription.text,
        hapistore: dropDownController.text,
        badorderAmount: Helperfunctions.formatStringAmountToDouble(txtAmount.text),
        badorderDate: Timestamp.fromDate(_selectedDate),
        createdBy: authService.value.currentUser!.displayName!,
        lastUpdatedBy: authService.value.currentUser!.displayName!,
        createdDate: Timestamp.now(),
        lastupdatedDate: Timestamp.now(),
      );
      db.addBadOrder(newRecord);
      ShowMessage.success(context, 'Successfully created bad order record for [${dropDownController.text}]!');
      Navigator.pop(context);
    } else {
      ShowMessage.error(context, 'Please fill up all required fields');
    }
  }

  void onDelete() {
    db.deleteBadOrder(widget.recID);
    ShowMessage.success(context, 'Successfully deleted bad order record for [${widget.badorder.hapistore}]!');
    Navigator.pop(context);
  }

  void onUpdate() {
    if (_formKey.currentState!.validate()) {
      BadOrder newRecord = widget.badorder.copyWith(
        description: txtDescription.text,
        hapistore: dropDownController.text,
        badorderAmount: Helperfunctions.formatStringAmountToDouble(txtAmount.text),
        badorderDate: Timestamp.fromDate(_selectedDate),
        createdBy: widget.badorder.createdBy,
        lastUpdatedBy: authService.value.currentUser!.displayName!,
        createdDate: widget.badorder.createdDate,
        lastupdatedDate: Timestamp.now(),
      );
      db.updateBadOrder(widget.recID, newRecord);
      ShowMessage.success(context, 'Successfully updated bad order record for [${dropDownController.text}]!');
      Navigator.pop(context);
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
}
