import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:selecta_ops/controllers/expenses_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/expenses.dart';
import 'package:selecta_ops/services/error_log_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/audithistory_widget.dart';

class ExpensesPage extends StatefulWidget {
  const ExpensesPage({
    super.key,
    required this.recID,
    required this.expense,
    this.initialExpenseType,
  });

  final Expenses expense;
  final String recID;
  final String? initialExpenseType;

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
  String _selectedExpenseType = ExpenseType.dealer;
  String _selectedPaymentMethod = ExpensePaymentMethod.cash;

  bool get isReadOnly {
    if (widget.recID.isNotEmpty) {
      // Existing records can only be edited or deleted by dealers
      return !_isDealer;
    }
    // New records: salesmen can only create Salesman expenses
    if (!_isDealer && _selectedExpenseType != ExpenseType.salesman) {
      return true;
    }
    return false;
  }

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
    final isDealer = await _controller.checkIsDealer();
    if (widget.recID.isNotEmpty) {
      txtDescription.text = widget.expense.description;
      txtAmount.text = Helperfunctions.formatDoubleAmountForField(widget.expense.expenseAmount);
      final date = widget.expense.expenseDate.toDate();
      final expType = widget.expense.expenseType;
      final payMethod = (expType == ExpenseType.salesman)
          ? ExpensePaymentMethod.cash
          : widget.expense.paymentMethod;

      if (mounted) {
        setState(() {
          _isDealer = isDealer;
          _selectedDate = date;
          _selectedExpenseType = expType;
          _selectedPaymentMethod = payMethod;
        });
      }
    } else {
      // New record creation
      final expType = isDealer
          ? (widget.initialExpenseType ?? ExpenseType.dealer)
          : ExpenseType.salesman;
      final payMethod = ExpensePaymentMethod.cash;

      if (mounted) {
        setState(() {
          _isDealer = isDealer;
          _selectedExpenseType = expType;
          _selectedPaymentMethod = payMethod;
        });
      }
    }
  }

  // Create new expense record through controller
  Future<void> onSave() async {
    if (_formKey.currentState!.validate()) {
      try {
        await _controller.createExpense(
          description: txtDescription.text,
          amount: Helperfunctions.formatStringAmountToDouble(txtAmount.text),
          selectedDate: _selectedDate,
          expenseType: _selectedExpenseType,
          paymentMethod: _selectedExpenseType == ExpenseType.salesman
              ? ExpensePaymentMethod.cash
              : _selectedPaymentMethod,
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
          extraData: {
            'description': txtDescription.text,
            'amount': txtAmount.text,
            'expenseType': _selectedExpenseType,
            'paymentMethod': _selectedPaymentMethod,
          },
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
          expenseType: _selectedExpenseType,
          paymentMethod: _selectedExpenseType == ExpenseType.salesman
              ? ExpensePaymentMethod.cash
              : _selectedPaymentMethod,
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
          extraData: {
            'recID': widget.recID,
            'description': txtDescription.text,
            'expenseType': _selectedExpenseType,
            'paymentMethod': _selectedPaymentMethod,
          },
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

  Widget _buildExpenseTypeSelector() {
    final colorScheme = Theme.of(context).colorScheme;
    final isSalesmanType = _selectedExpenseType == ExpenseType.salesman;

    if (!_isDealer || isReadOnly) {
      // Read-only indicator for salesman or view-only mode
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSalesmanType
              ? Colors.orange.withValues(alpha: 0.08)
              : colorScheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSalesmanType
                ? Colors.orange.shade300
                : colorScheme.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSalesmanType ? Icons.lunch_dining_outlined : Icons.storefront_outlined,
              size: 20,
              color: isSalesmanType ? Colors.orange.shade800 : colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Expense Category',
                    style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                  ),
                  Text(
                    isSalesmanType
                        ? 'Salesman Expense (Snacks / Meals)'
                        : 'Dealer Expense (Operations / Fuel)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isSalesmanType ? Colors.orange.shade900 : colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Dealer has full toggle ability between Salesman Expense and Dealer Expense
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Expense Category',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: ExpenseType.salesman,
              icon: Icon(Icons.lunch_dining_outlined, size: 18),
              label: Text('Salesman (Snacks)'),
            ),
            ButtonSegment(
              value: ExpenseType.dealer,
              icon: Icon(Icons.storefront_outlined, size: 18),
              label: Text('Dealer (Ops/Gas)'),
            ),
          ],
          selected: {_selectedExpenseType},
          onSelectionChanged: (newSelection) {
            setState(() {
              _selectedExpenseType = newSelection.first;
              if (_selectedExpenseType == ExpenseType.salesman) {
                _selectedPaymentMethod = ExpensePaymentMethod.cash;
              }
            });
          },
        ),
      ],
    );
  }

  Widget _buildPaymentMethodSelector() {
    final colorScheme = Theme.of(context).colorScheme;
    final isSalesmanType = _selectedExpenseType == ExpenseType.salesman;

    if (isSalesmanType) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            Icon(Icons.payments_outlined, size: 20, color: Colors.green.shade700),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Payment Method: ',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Cash (Fixed)',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Salesman expenses are always paid in cash and deducted from End of Day cash on hand.',
                    style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (isReadOnly) {
      final isOnline = _selectedPaymentMethod == ExpensePaymentMethod.online;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isOnline ? Colors.blue.withValues(alpha: 0.08) : Colors.green.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isOnline ? Colors.blue.shade300 : Colors.green.shade300),
        ),
        child: Row(
          children: [
            Icon(
              isOnline ? Icons.account_balance_outlined : Icons.payments_outlined,
              size: 20,
              color: isOnline ? Colors.blue.shade700 : Colors.green.shade700,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Payment Method', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                  Text(
                    _selectedPaymentMethod,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isOnline ? Colors.blue.shade800 : Colors.green.shade800,
                    ),
                  ),
                  Text(
                    isOnline
                        ? 'Non-cash: Not deducted from End of Day cash. Reflected in Business Analytics.'
                        : 'Cash: Deducted from End of Day cash & reflected in Business Analytics.',
                    style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Payment Method',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: ExpensePaymentMethod.cash,
              icon: Icon(Icons.payments_outlined, size: 18),
              label: Text('Cash'),
            ),
            ButtonSegment(
              value: ExpensePaymentMethod.online,
              icon: Icon(Icons.account_balance_outlined, size: 18),
              label: Text('Online / Bank'),
            ),
          ],
          selected: {_selectedPaymentMethod},
          onSelectionChanged: (newSelection) {
            setState(() {
              _selectedPaymentMethod = newSelection.first;
            });
          },
        ),
        const SizedBox(height: 6),
        Text(
          _selectedPaymentMethod == ExpensePaymentMethod.cash
              ? '• Deducted from End of Day cash-on-hand & reflected in Business Analytics.'
              : '• Non-cash: NOT deducted from End of Day cash-on-hand. Reflected in Business Analytics.',
          style: TextStyle(
            fontSize: 11.5,
            color: _selectedPaymentMethod == ExpensePaymentMethod.cash ? Colors.green.shade700 : Colors.blue.shade700,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  bool _isChipSelected(String presetLabel) {
    return txtDescription.text.trim().toLowerCase() == presetLabel.trim().toLowerCase();
  }

  void _onSelectPreset(String presetLabel) {
    setState(() {
      if (_isChipSelected(presetLabel)) {
        txtDescription.clear();
      } else {
        txtDescription.text = presetLabel;
        txtDescription.selection = TextSelection.fromPosition(
          TextPosition(offset: txtDescription.text.length),
        );
      }
    });
  }

  Widget _buildPresetChips() {
    final colorScheme = Theme.of(context).colorScheme;
    final isSalesman = _selectedExpenseType == ExpenseType.salesman;
    final presets = isSalesman ? _salesmanPresets : _dealerPresets;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome, size: 14, color: colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              'Quick Presets (${isSalesman ? "Salesman" : "Dealer"})',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: presets.map((preset) {
            final isSelected = _isChipSelected(preset.label);
            return FilterChip(
              showCheckmark: false,
              avatar: Icon(
                preset.icon,
                size: 16,
                color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.primary,
              ),
              label: Text(preset.label),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? colorScheme.onPrimaryContainer : colorScheme.onSurface,
              ),
              selected: isSelected,
              selectedColor: colorScheme.primaryContainer,
              backgroundColor: colorScheme.surface,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: isSelected ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.8),
                  width: isSelected ? 1.4 : 1.0,
                ),
              ),
              onSelected: (_) => _onSelectPreset(preset.label),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildExpenseDetailsCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final isSalesmanType = _selectedExpenseType == ExpenseType.salesman;

    return _buildSectionCard(
      title: 'Expense Information',
      icon: Icons.receipt_long_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          _buildExpenseTypeSelector(),
          _buildPaymentMethodSelector(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: txtDescription,
                readOnly: isReadOnly,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Expense Description',
                  hintText: isReadOnly
                      ? ''
                      : (isSalesmanType
                          ? 'e.g. Snacks, Cash Advance, Meals...'
                          : 'e.g. Fuel, Toll, Vehicle maintenance, Utilities...'),
                  prefixIcon: Icon(Icons.edit_note_outlined, size: 20, color: colorScheme.primary),
                  suffixIcon: txtDescription.text.isNotEmpty && !isReadOnly
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          tooltip: 'Clear description',
                          onPressed: () {
                            setState(() {
                              txtDescription.clear();
                            });
                          },
                        )
                      : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
                autovalidateMode: AutovalidateMode.onUnfocus,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) return 'Description should not be blank';
                  return null;
                },
              ),
              if (!isReadOnly) ...[
                const SizedBox(height: 10),
                _buildPresetChips(),
              ],
            ],
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

    if (isReadOnly) {
      return const SizedBox.shrink();
    }

    final saveButtonLabel = _selectedExpenseType == ExpenseType.salesman
        ? 'Save Salesman Expense'
        : 'Save Dealer Expense';

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
                      flex: 2,
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
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          foregroundColor: Colors.red.shade700,
                          side: BorderSide(color: Colors.red.shade300, width: 1.2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Delete',
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    flex: _isDealer ? 3 : 1,
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
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Update Expense',
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
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
                label: Text(saveButtonLabel, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppbar(
        title: 'Expense Details',
        subtitle: widget.recID.isEmpty
            ? 'New ${_selectedExpenseType == ExpenseType.salesman ? "Salesman" : "Dealer"} Record'
            : widget.expense.description,
      ),
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
                          widget.recID.isNotEmpty
                              ? 'View-Only: Only dealers are authorized to edit or delete existing expense records.'
                              : 'View-Only: Salesmen are only permitted to log Salesman Expenses.',
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

class _ExpensePreset {
  final String label;
  final IconData icon;

  const _ExpensePreset(this.label, this.icon);
}

const List<_ExpensePreset> _salesmanPresets = [
  _ExpensePreset('Snacks', Icons.cookie_outlined),
  _ExpensePreset('Cash Advance', Icons.price_change_outlined),
  _ExpensePreset('Meals', Icons.lunch_dining_outlined),
  _ExpensePreset('Refreshments', Icons.local_drink_outlined),
  _ExpensePreset('Phone Load', Icons.phone_android_outlined),
  _ExpensePreset('Parking / Toll', Icons.local_parking_outlined),
  _ExpensePreset('Emergency Van Repair', Icons.car_repair_outlined),
];

const List<_ExpensePreset> _dealerPresets = [
  _ExpensePreset('Fuel / Diesel', Icons.local_gas_station_outlined),
  _ExpensePreset('Vehicle Maintenance', Icons.car_repair_outlined),
  _ExpensePreset('Toll & Parking', Icons.toll_outlined),
  _ExpensePreset('Electricity / Utilities', Icons.bolt_outlined),
  _ExpensePreset('Freezer Repair', Icons.ac_unit_outlined),
  _ExpensePreset('Store Supplies', Icons.inventory_2_outlined),
  _ExpensePreset('Staff Wages', Icons.badge_outlined),
  _ExpensePreset('Permits & Taxes', Icons.receipt_long_outlined),
];
