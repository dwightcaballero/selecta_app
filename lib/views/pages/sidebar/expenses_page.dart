import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/controllers/expenses_controller.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/expenses.dart';
import 'package:flutter_app/services/error_log_service.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:flutter_app/views/widgets/audithistory_widget.dart';

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({super.key, required this.recID, required this.expense});

  final Expenses expense;
  final String recID;

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  // Controller managing data mutations, role verification, and audit logging
  final ExpensesController _controller = ExpensesController();

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
      txtDescription.text = widget.expense.description;
      txtAmount.text = Helperfunctions.formatDoubleAmountForField(widget.expense.expenseAmount);
      _selectedDate = widget.expense.expenseDate.toDate();
    }
    if (mounted) setState(() {});
  }

  // Create new expense record through controller
  Future<void> onSave() async {
    if (_formKey.currentState!.validate()) {
      try {
        await _controller.createExpense(
          description: txtDescription.text,
          amount: Helperfunctions.formatStringAmountToDouble(txtAmount.text),
          selectedDate: _selectedDate,
        );
        if (mounted) {
          ShowMessage.success(context, 'Successfully created expense record for [${txtDescription.text}]!');
          Navigator.pop(context);
        }
      } catch (e, s) {
        ErrorLogService.logError(
          page: 'ExpensesPage',
          action: 'Create Expense Record',
          error: e,
          stackTrace: s,
          extraData: {'description': txtDescription.text, 'amount': txtAmount.text},
        );
        if (mounted) {
          ShowMessage.error(context, 'Failed to create record: $e');
        }
      }
    } else {
      ShowMessage.error(context, 'Please fill up all required fields');
    }
  }

  // Update existing expense record through controller (dealer only)
  Future<void> onUpdate() async {
    if (!_isDealer) {
      ShowMessage.error(context, 'Only dealers are authorized to edit expense records.');
      return;
    }
    if (_formKey.currentState!.validate()) {
      try {
        await _controller.updateExpense(
          recID: widget.recID,
          existingRecord: widget.expense,
          description: txtDescription.text,
          amount: Helperfunctions.formatStringAmountToDouble(txtAmount.text),
          selectedDate: _selectedDate,
        );
        if (mounted) {
          ShowMessage.success(context, 'Successfully updated expense record for [${txtDescription.text}]!');
          Navigator.pop(context);
        }
      } catch (e, s) {
        ErrorLogService.logError(
          page: 'ExpensesPage',
          action: 'Update Expense Record',
          error: e,
          stackTrace: s,
          extraData: {'recID': widget.recID, 'description': txtDescription.text},
        );
        if (mounted) {
          ShowMessage.error(context, 'Failed to update record: $e');
        }
      }
    } else {
      ShowMessage.error(context, 'Please fill up all required fields');
    }
  }

  // Delete expense record through controller (dealer only)
  Future<void> onDelete() async {
    if (!_isDealer) {
      ShowMessage.error(context, 'Only dealers are authorized to delete expense records.');
      return;
    }
    try {
      await _controller.deleteExpense(
        recID: widget.recID,
        existingRecord: widget.expense,
      );
      if (mounted) {
        ShowMessage.success(context, 'Successfully deleted expense record for [${widget.expense.description}]!');
        Navigator.pop(context);
      }
    } catch (e, s) {
      ErrorLogService.logError(
        page: 'ExpensesPage',
        action: 'Delete Expense Record',
        error: e,
        stackTrace: s,
        extraData: {'recID': widget.recID, 'description': widget.expense.description},
      );
      if (mounted) {
        ShowMessage.error(context, 'Failed to delete record: $e');
      }
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
            readOnly: isReadOnly,
            decoration: InputDecoration(
              labelText: 'Expense Description',
              hintText: isReadOnly ? '' : 'e.g. Fuel, Toll, Vehicle maintenance, Meals...',
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
            if (!isReadOnly) Icon(Icons.edit_calendar_outlined, size: 18, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }



  Widget _buildStickyBottomBar() {
    final colorScheme = Theme.of(context).colorScheme;
    bool isUpdating = widget.recID.isNotEmpty;

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
                  ],
                  Expanded(
                    flex: _isDealer ? 2 : 1,
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
                          'View-Only: Only dealers are authorized to edit or delete existing expense records.',
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

              // 1. Expense Details Card
              _buildExpenseDetailsCard(),

              // 2. Audit & History Card (if editing)
              if (widget.recID.isNotEmpty)
                AuditHistoryWidget(
                  createdBy: widget.expense.createdBy,
                  createdDate: widget.expense.createdDate,
                  createdPage: widget.expense.createdPage,
                  lastUpdatedBy: widget.expense.lastUpdatedBy,
                  lastUpdatedDate: widget.expense.lastupdatedDate,
                  lastUpdatedPage: widget.expense.lastUpdatedPage,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
