import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:selecta_ops/controllers/payslip_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/expenses.dart';
import 'package:selecta_ops/models/payslip.dart';
import 'package:selecta_ops/models/users.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';
import 'package:selecta_ops/views/widgets/attendance/weekly_timesheet_card.dart';

class PayslipGeneratorPage extends StatefulWidget {
  final String dealerName;
  final Payslip? existingPayslip;

  const PayslipGeneratorPage({
    super.key,
    required this.dealerName,
    this.existingPayslip,
  });

  @override
  State<PayslipGeneratorPage> createState() => _PayslipGeneratorPageState();
}

class _PayslipGeneratorPageState extends State<PayslipGeneratorPage> {
  final PayslipController _controller = PayslipController();
  final NumberFormat _currencyFormat =
      NumberFormat.currency(symbol: '₱', decimalDigits: 2);
  final DateFormat _dateFormat = DateFormat('MMM dd, yyyy');

  final _formKey = GlobalKey<FormState>();

  // Week selection
  DateTime _referenceDate = DateTime.now();
  late DateTime _weekStart;
  late DateTime _weekEnd;
  late String _weekLabel;

  // Salesmen list & selection
  List<Users> _salesmen = [];
  Users? _selectedSalesman;
  bool _isLoadingSalesmen = true;

  // Form Controllers
  final TextEditingController _daysWorkedController =
      TextEditingController(text: '5.5');
  final TextEditingController _dailyRateController =
      TextEditingController(text: '700.00');
  final TextEditingController _incentiveAmountController =
      TextEditingController();
  final TextEditingController _incentiveRemarksController =
      TextEditingController();
  final TextEditingController _otherDeductionsController =
      TextEditingController();
  final TextEditingController _otherDeductionsRemarksController =
      TextEditingController();
  final TextEditingController _remarksController = TextEditingController();

  bool _saveAsDefaultDailyRate = true;
  bool _isLoadingExpenses = false;
  bool _isSaving = false;

  // Expenses found for the salesman for this week
  List<Expenses> _weekExpenses = [];
  final Set<String> _selectedExpenseIds = {};

  @override
  void initState() {
    super.initState();
    _computeWeekRange(_referenceDate);
    _loadSalesmen();
  }

  @override
  void dispose() {
    _daysWorkedController.dispose();
    _dailyRateController.dispose();
    _incentiveAmountController.dispose();
    _incentiveRemarksController.dispose();
    _otherDeductionsController.dispose();
    _otherDeductionsRemarksController.dispose();
    _remarksController.dispose();
    super.dispose();
  }

  void _computeWeekRange(DateTime date) {
    final range = PayslipController.getWeekRange(date);
    setState(() {
      _weekStart = range.start;
      _weekEnd = range.end;
      _weekLabel = range.label;
    });
  }

  void _shiftWeek(int offsetWeeks) {
    setState(() {
      _referenceDate = _referenceDate.add(Duration(days: 7 * offsetWeeks));
      _computeWeekRange(_referenceDate);
    });
    if (_selectedSalesman != null) {
      _fetchExpensesForSelectedSalesman();
    }
  }

  Future<void> _loadSalesmen() async {
    setState(() => _isLoadingSalesmen = true);
    try {
      final list = await _controller.getSalesmenForDealer(widget.dealerName);
      if (mounted) {
        setState(() {
          _salesmen = list;
          if (list.isNotEmpty) {
            _selectedSalesman = list.first;
            _applySalesmanDefaults(list.first);
          }
          _isLoadingSalesmen = false;
        });
        if (_selectedSalesman != null) {
          _fetchExpensesForSelectedSalesman();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingSalesmen = false);
        ShowMessage.error(context, 'Failed to load salesmen: $e');
      }
    }
  }

  void _applySalesmanDefaults(Users salesman) {
    if (salesman.dailyRate > 0) {
      _dailyRateController.text =
          Helperfunctions.formatDoubleAmountForField(salesman.dailyRate);
    }
  }

  Future<void> _fetchExpensesForSelectedSalesman() async {
    if (_selectedSalesman == null) return;
    setState(() {
      _isLoadingExpenses = true;
      _weekExpenses.clear();
      _selectedExpenseIds.clear();
    });

    try {
      final expenses = await _controller.getSalesmanExpensesForWeek(
        salesmanUsername: _selectedSalesman!.username,
        startDate: _weekStart,
        endDate: _weekEnd,
      );

      if (mounted) {
        setState(() {
          _weekExpenses = expenses;
          // By default, select all detected salesman expenses
          for (int i = 0; i < expenses.length; i++) {
            _selectedExpenseIds.add('$i-${expenses[i].description}');
          }
          _isLoadingExpenses = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingExpenses = false);
      }
    }
  }

  // Live Calculations
  double get _daysWorked =>
      double.tryParse(_daysWorkedController.text.trim()) ?? 0.0;
  double get _dailyRate =>
      Helperfunctions.formatStringAmountToDouble(_dailyRateController.text);
  double get _baseSalary => _daysWorked * _dailyRate;

  double get _incentiveAmount =>
      Helperfunctions.formatStringAmountToDouble(_incentiveAmountController.text);

  double get _grossPay => _baseSalary + _incentiveAmount;

  double get _selectedExpensesTotal {
    double total = 0.0;
    for (int i = 0; i < _weekExpenses.length; i++) {
      if (_selectedExpenseIds.contains('$i-${_weekExpenses[i].description}')) {
        total += _weekExpenses[i].expenseAmount;
      }
    }
    return total;
  }

  double get _otherDeductionsAmount =>
      Helperfunctions.formatStringAmountToDouble(_otherDeductionsController.text);

  double get _totalDeductions =>
      _selectedExpensesTotal + _otherDeductionsAmount;

  double get _netPay => _grossPay - _totalDeductions;

  Future<void> _submitPayslip(String status) async {
    if (!_formKey.currentState!.validate()) {
      ShowMessage.error(context, 'Please fill in all required fields.');
      return;
    }

    if (_selectedSalesman == null) {
      ShowMessage.error(context, 'Please select a salesman.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      // 1. Optionally update salesman's default daily rate
      if (_saveAsDefaultDailyRate && _dailyRate > 0) {
        await _controller.updateSalesmanDailyRate(
          _selectedSalesman!.username,
          _dailyRate,
        );
      }

      // 2. Build list of deducted items
      final List<PayslipDeductionItem> deductionItems = [];
      for (int i = 0; i < _weekExpenses.length; i++) {
        if (_selectedExpenseIds.contains('$i-${_weekExpenses[i].description}')) {
          final exp = _weekExpenses[i];
          deductionItems.add(
            PayslipDeductionItem(
              title: exp.description.isNotEmpty ? exp.description : 'Snacks/Expense',
              amount: exp.expenseAmount,
              date: exp.expenseDate,
              category: 'Expense',
            ),
          );
        }
      }

      // Generate a clean Payslip Number: PS-YYWW-USERNAME
      final weekOfYear = ((_weekStart.difference(DateTime(_weekStart.year, 1, 1)).inDays) / 7).ceil();
      final payslipNumber = 'PS-${_weekStart.year}-W$weekOfYear-${_selectedSalesman!.username.toUpperCase().replaceAll(' ', '')}';

      final user = await _controller.getCurrentUser();
      final creatorName = user?.username ?? 'Dealer';

      final newPayslip = Payslip(
        payslipNumber: payslipNumber,
        dealerName: widget.dealerName,
        salesmanUsername: _selectedSalesman!.username,
        salesmanEmail: _selectedSalesman!.email,
        periodStart: Timestamp.fromDate(_weekStart),
        periodEnd: Timestamp.fromDate(_weekEnd),
        cutoffWeekLabel: _weekLabel,
        dailyRate: _dailyRate,
        daysWorked: _daysWorked,
        basePay: _baseSalary,
        incentiveAmount: _incentiveAmount,
        incentiveRemarks: _incentiveRemarksController.text.trim(),
        grossPay: _grossPay,
        expensesDeduction: _selectedExpensesTotal,
        deductions: deductionItems,
        otherDeductions: _otherDeductionsAmount,
        otherDeductionsRemarks: _otherDeductionsRemarksController.text.trim(),
        totalDeductions: _totalDeductions,
        netPay: _netPay,
        status: status,
        remarks: _remarksController.text.trim(),
        createdBy: creatorName,
        lastUpdatedBy: creatorName,
        createdDate: Timestamp.now(),
        lastUpdatedDate: Timestamp.now(),
        issuedDate: status == PayslipStatus.issued ? Timestamp.now() : null,
      );

      await _controller.createPayslip(newPayslip);

      if (mounted) {
        ShowMessage.success(
          context,
          status == PayslipStatus.issued
              ? 'Payslip issued to ${_selectedSalesman!.username}!'
              : 'Payslip saved as draft.',
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Failed to save payslip: $e');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  bool get _hasUnsavedChanges {
    return _incentiveAmountController.text.trim().isNotEmpty ||
        _incentiveRemarksController.text.trim().isNotEmpty ||
        _otherDeductionsController.text.trim().isNotEmpty ||
        _otherDeductionsRemarksController.text.trim().isNotEmpty ||
        _remarksController.text.trim().isNotEmpty ||
        _daysWorkedController.text.trim() != '5.5';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_isSaving) return;
        if (_hasUnsavedChanges) {
          final shouldDiscard = await ShowMessage.confirm(
            context,
            title: 'Discard Changes?',
            message: 'You have unsaved changes in this payslip. Are you sure you want to discard them?',
            confirmText: 'Discard',
            cancelText: 'Keep Editing',
            isDestructive: true,
            icon: Icons.warning_amber_rounded,
          );
          if (shouldDiscard && context.mounted) {
            Navigator.pop(context);
          }
        } else {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: const CustomAppbar(title: 'Generate Weekly Payslip'),
      body: _isLoadingSalesmen
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Week Selector Banner
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left_rounded),
                            tooltip: 'Previous Week',
                            onPressed: () => _shiftWeek(-1),
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                const Text(
                                  'PAYROLL CUTOFF WEEK',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _weekLabel,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right_rounded),
                            tooltip: 'Next Week',
                            onPressed: () => _shiftWeek(1),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 2. Salesman Selection
                    Card(
                      elevation: 0,
                      color: colorScheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Select Salesman',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 10),
                            if (_salesmen.isEmpty)
                              Text(
                                'No salesmen found under dealer "${widget.dealerName}". Please ensure salesmen accounts have dealerName assigned.',
                                style: TextStyle(color: colorScheme.error, fontSize: 13),
                              )
                            else
                              DropdownButtonFormField<Users>(
                                initialValue: _selectedSalesman,
                                decoration: InputDecoration(
                                  prefixIcon: const Icon(Icons.person_outline_rounded),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                ),
                                items: _salesmen.map((user) {
                                  return DropdownMenuItem<Users>(
                                    value: user,
                                    child: Text(
                                      user.username,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (user) {
                                  if (user != null) {
                                    setState(() => _selectedSalesman = user);
                                    _applySalesmanDefaults(user);
                                    _fetchExpensesForSelectedSalesman();
                                  }
                                },
                              ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 3. Compensation & Attendance (Days & Rate)
                    Card(
                      elevation: 0,
                      color: colorScheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Base Compensation',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 14),

                            // Daily Rate
                            TextFormField(
                              controller: _dailyRateController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Daily Rate (₱)',
                                prefixText: '₱ ',
                                prefixIcon: const Icon(Icons.payments_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return 'Daily rate is required';
                                if ((double.tryParse(val) ?? 0) <= 0) return 'Must be greater than 0';
                                return null;
                              },
                              onChanged: (_) => setState(() {}),
                            ),

                            const SizedBox(height: 10),

                            Row(
                              children: [
                                Checkbox(
                                  value: _saveAsDefaultDailyRate,
                                  onChanged: (val) => setState(() => _saveAsDefaultDailyRate = val ?? false),
                                ),
                                const Expanded(
                                  child: Text(
                                    'Save as default rate for this salesman',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 14),

                            if (_selectedSalesman != null) ...[
                              WeeklyTimesheetCard(
                                salesmanUsername: _selectedSalesman!.username,
                                startDate: _weekStart,
                                endDate: _weekEnd,
                                onApplyCalculatedDays: (calculatedDays) {
                                  setState(() {
                                    _daysWorkedController.text = calculatedDays.toString();
                                  });
                                },
                              ),
                              const SizedBox(height: 14),
                            ],

                            // Days Worked
                            TextFormField(
                              controller: _daysWorkedController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Days Worked this Week',
                                prefixIcon: const Icon(Icons.calendar_today_outlined),
                                helperText: 'e.g. 5.0, 5.5, or 6.0 days',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) return 'Days worked is required';
                                final num = double.tryParse(val);
                                if (num == null || num < 0 || num > 7) return 'Enter a valid number (0 - 7)';
                                return null;
                              },
                              onChanged: (_) => setState(() {}),
                            ),

                            const SizedBox(height: 10),

                            // Preset Days Chips
                            Wrap(
                              spacing: 8,
                              children: [5.0, 5.5, 6.0].map((d) {
                                final isSelected = _daysWorked == d;
                                return ChoiceChip(
                                  label: Text('$d days'),
                                  selected: isSelected,
                                  onSelected: (_) {
                                    setState(() {
                                      _daysWorkedController.text = d.toString();
                                    });
                                  },
                                );
                              }).toList(),
                            ),

                            const SizedBox(height: 14),

                            // Base salary calculation pill
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Computed Base Pay:', style: TextStyle(fontWeight: FontWeight.w600)),
                                  Text(
                                    _currencyFormat.format(_baseSalary),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 4. Weekly Expenses (Snacks Deductions)
                    Card(
                      elevation: 0,
                      color: colorScheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Weekly Snacks & Expenses',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                ),
                                if (_isLoadingExpenses)
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                else
                                  Text(
                                    '-${_currencyFormat.format(_selectedExpensesTotal)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.redAccent,
                                      fontSize: 14,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Auto-fetched from Expenses logged for this salesman within the week.',
                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(height: 12),

                            if (_weekExpenses.isEmpty && !_isLoadingExpenses)
                              Container(
                                padding: const EdgeInsets.all(12),
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'No expenses recorded for ${_selectedSalesman?.username ?? "salesman"} this week.',
                                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _weekExpenses.length,
                                separatorBuilder: (context, index) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final exp = _weekExpenses[index];
                                  final key = '$index-${exp.description}';
                                  final isChecked = _selectedExpenseIds.contains(key);
                                  final dateStr = _dateFormat.format(exp.expenseDate.toDate());

                                  return CheckboxListTile(
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    value: isChecked,
                                    title: Text(
                                      exp.description.isNotEmpty ? exp.description : 'Expense',
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                    ),
                                    subtitle: Text(dateStr, style: const TextStyle(fontSize: 11)),
                                    secondary: Text(
                                      _currencyFormat.format(exp.expenseAmount),
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent),
                                    ),
                                    onChanged: (val) {
                                      setState(() {
                                        if (val == true) {
                                          _selectedExpenseIds.add(key);
                                        } else {
                                          _selectedExpenseIds.remove(key);
                                        }
                                      });
                                    },
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 5. Incentive & Other Deductions
                    Card(
                      elevation: 0,
                      color: colorScheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Incentives & Adjustments',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 14),

                            // Incentive
                            TextFormField(
                              controller: _incentiveAmountController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Sales Incentive / Bonus (₱)',
                                prefixText: '₱ ',
                                prefixIcon: const Icon(Icons.star_outline_rounded, color: Colors.teal),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _incentiveRemarksController,
                              decoration: InputDecoration(
                                labelText: 'Incentive Remarks (optional)',
                                hintText: 'e.g. Sales quota achievement bonus',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Other Deductions
                            TextFormField(
                              controller: _otherDeductionsController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Other Deductions (₱)',
                                prefixText: '₱ ',
                                prefixIcon: const Icon(Icons.money_off_rounded, color: Colors.redAccent),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _otherDeductionsRemarksController,
                              decoration: InputDecoration(
                                labelText: 'Deductions Remarks (optional)',
                                hintText: 'e.g. Cash advance / short',
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // 6. Live Payroll Summary Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.teal.shade800,
                            const Color(0xFF042F2E),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.teal.withValues(alpha: 0.25),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _buildSummaryLine('Basic Pay', _currencyFormat.format(_baseSalary), Colors.white70),
                          if (_incentiveAmount > 0)
                            _buildSummaryLine('Incentive', '+${_currencyFormat.format(_incentiveAmount)}', Colors.tealAccent),
                          _buildSummaryLine('Gross Pay', _currencyFormat.format(_grossPay), Colors.white, isBold: true),
                          const Divider(color: Colors.white24, height: 20),
                          _buildSummaryLine('Expenses Deducted', '-${_currencyFormat.format(_selectedExpensesTotal)}', Colors.orangeAccent),
                          if (_otherDeductionsAmount > 0)
                            _buildSummaryLine('Other Deductions', '-${_currencyFormat.format(_otherDeductionsAmount)}', Colors.orangeAccent),
                          _buildSummaryLine('Total Deductions', '-${_currencyFormat.format(_totalDeductions)}', Colors.redAccent, isBold: true),
                          const Divider(color: Colors.white38, height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'NET TAKE-HOME PAY',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  Text(
                                    'Weekly payout',
                                    style: TextStyle(color: Colors.white54, fontSize: 11),
                                  ),
                                ],
                              ),
                              Text(
                                _currencyFormat.format(_netPay),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // 7. Actions (Draft vs Issue)
                    Row(
                      children: [
                        Expanded(
                          child: AsyncOutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            loadingLabel: 'Saving Draft...',
                            onPressed: () => _submitPayslip(PayslipStatus.draft),
                            child: const Text('Save as Draft'),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: AsyncFilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.teal,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.send_rounded),
                            label: const Text('Issue Payslip', style: TextStyle(fontWeight: FontWeight.bold)),
                            loadingLabel: 'Issuing...',
                            onPressed: () => _submitPayslip(PayslipStatus.issued),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    ),
    );
  }

  Widget _buildSummaryLine(String title, String value, Color color, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              color: isBold ? Colors.white : Colors.white70,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
