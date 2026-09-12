import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/expenses.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/expenses_services.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:intl/intl.dart';

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key, required this.recID, required this.expense});

  final String recID;
  final Expenses expense;

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  final ExpensesService db = ExpensesService();
  final _formKey = GlobalKey<FormState>();

  DateTime _selectedDate = DateTime.now();
  final TextEditingController txtDescription = TextEditingController();
  final TextEditingController txtAmount = TextEditingController();

  @override
  void initState() {
    super.initState();
    prefetchData();
  }

  void prefetchData() {
    if (widget.recID.isNotEmpty) {
      txtDescription.text = widget.expense.description;
      txtAmount.text = widget.expense.expenseAmount == 0 ? '' : Helperfunctions.formatDoubleAmountForDisplay(widget.expense.expenseAmount);
      _selectedDate = widget.expense.expenseDate.toDate();
    }
  }

  @override
  void dispose() {
    txtDescription.dispose();
    txtAmount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppbar(title: 'Expense Details', subtitle: widget.recID.isEmpty ? 'New Record' : widget.expense.description),
      bottomNavigationBar: _buildStickyBottomBar(),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 16,
            children: [
              // 1. Expense Details Card
              _buildExpenseDetailsCard(),

              // 2. Audit & History Card (if editing)
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

  Widget _buildExpenseDetailsCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return _buildSectionCard(
      title: 'Expense Information',
      icon: Icons.receipt_long_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          TextFormField(
            controller: txtDescription,
            decoration: InputDecoration(
              labelText: 'Expense Description',
              hintText: 'e.g. Fuel, Toll, Vehicle maintenance, Meals...',
              prefixIcon: Icon(Icons.edit_note_outlined, size: 20, color: colorScheme.primary),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
            autovalidateMode: AutovalidateMode.onUnfocus,
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Description should not be blank';
              return null;
            },
          ),
          _buildMoneyField(label: 'Expense Amount', controller: txtAmount, prefixIcon: Icons.payments_outlined),
          _buildDatePickerField(label: 'Expense Date', selectedDate: _selectedDate, onTap: onChangeDate),
        ],
      ),
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
                _buildAuditRow('Created By', widget.expense.createdBy),
                _buildAuditRow('Created Date', DateFormat('E, d MMM yyyy, hh:mm a').format(widget.expense.createdDate.toDate())),
                const Divider(height: 12),
                _buildAuditRow('Last Updated By', widget.expense.lastUpdatedBy),
                _buildAuditRow('Last Updated Date', DateFormat('E, d MMM yyyy, hh:mm a').format(widget.expense.lastupdatedDate.toDate())),
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
                          message: 'Are you sure you want to delete this expense record for [${widget.expense.description}]?',
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
                          message: 'Save changes to this expense record for [${txtDescription.text}]?',
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
                      label: const Text('Update Expense', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              )
            : FilledButton.icon(
                onPressed: () async {
                  final confirmed = await ShowMessage.confirm(
                    context,
                    title: ConfirmTitle.save,
                    message: 'Save this expense record for [${txtDescription.text}]?',
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
                label: const Text('Save Expense', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
      ),
    );
  }

  void onSave() async {
    if (_formKey.currentState!.validate()) {
      Expenses newRecord = Expenses(
        description: txtDescription.text,
        expenseAmount: Helperfunctions.formatStringAmountToDouble(txtAmount.text),
        expenseDate: Timestamp.fromDate(_selectedDate),
        createdBy: authService.value.currentUser!.displayName!,
        lastUpdatedBy: authService.value.currentUser!.displayName!,
        createdDate: Timestamp.now(),
        lastupdatedDate: Timestamp.now(),
      );
      db.addExpenses(newRecord);

      if (mounted) {
        ShowMessage.success(context, 'Successfully created expense record for [${txtDescription.text}]!');
        Navigator.pop(context);
      }
    } else {
      ShowMessage.error(context, 'Please fill up all required fields');
    }
  }

  void onUpdate() async {
    if (_formKey.currentState!.validate()) {
      Expenses expenses = widget.expense.copyWith(
        description: txtDescription.text,
        expenseAmount: Helperfunctions.formatStringAmountToDouble(txtAmount.text),
        expenseDate: Timestamp.fromDate(_selectedDate),
        createdBy: widget.expense.createdBy,
        lastUpdatedBy: authService.value.currentUser!.displayName!,
        createdDate: widget.expense.createdDate,
        lastupdatedDate: Timestamp.now(),
      );
      db.updateExpenses(widget.recID, expenses);

      if (mounted) {
        ShowMessage.success(context, 'Successfully updated expense record for [${expenses.description}]!');
        Navigator.pop(context);
      }
    } else {
      ShowMessage.error(context, 'Please fill up all required fields');
    }
  }

  void onDelete() async {
    db.deleteExpenses(widget.recID);

    if (mounted) {
      ShowMessage.success(context, 'Successfully deleted expense record for [${widget.expense.description}]!');
      Navigator.pop(context);
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
