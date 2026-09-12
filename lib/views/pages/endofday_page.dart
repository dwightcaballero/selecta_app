import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/dto/endofday_dto.dart';
import 'package:flutter_app/models/breakdown.dart';
import 'package:flutter_app/services/breakdown_service.dart';
import 'package:flutter_app/services/endofday_services.dart';
import 'package:flutter_app/views/pages/breakdown_page.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:intl/intl.dart';

class EndofdayPage extends StatefulWidget {
  const EndofdayPage({super.key});

  @override
  State<EndofdayPage> createState() => _EndofdayPageState();
}

class _EndofdayPageState extends State<EndofdayPage> {
  DateTime _selectedDate = DateTime.now();
  final EndofdayServices db = EndofdayServices();
  final BreakdownService dbBS = BreakdownService();
  EndOfDayDTO endOfDayData = EndOfDayDTO.empty();
  Breakdown? breakdown = Breakdown.empty();
  String breakdownID = '';
  bool _isDealer = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      getData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppbar(title: 'End of Day Report', subtitle: DateFormat('EEEE, d MMM yyyy').format(_selectedDate)),
      bottomNavigationBar: _buildStickyBottomBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 16,
          children: [
            // 1. Date Navigation Header
            _buildDateNavigator(),

            // 2. Pending Status Warning (if any)
            if (endOfDayData.pendingstatus > 0) _buildPendingWarningBanner(),

            // 3. Delivery Volume & Status Grid
            _buildDeliveryStatusGrid(),

            // 4. Sales & Collections Card
            _buildSalesAndCollectionsCard(),

            // 5. Deductions & Returns Card
            _buildDeductionsCard(),

            // 6. Cash Reconciliation Summary Card
            _buildCashReconciliationCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildDateNavigator() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(icon: const Icon(Icons.chevron_left), tooltip: 'Previous Day', onPressed: _isDealer ? () => _changeDate(-1) : null),
          InkWell(
            onTap: _isDealer ? onChangeDate : null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.calendar_month_outlined, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(DateFormat('E, d MMM yyyy').format(_selectedDate), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.chevron_right), tooltip: 'Next Day', onPressed: _isDealer ? () => _changeDate(1) : null),
        ],
      ),
    );
  }

  Widget _buildPendingWarningBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade400),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${endOfDayData.pendingstatus} delivery is currently pending. Please settle all deliveries before viewing the cash breakdown.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.amber.shade900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryStatusGrid() {
    return Row(
      spacing: 8,
      children: [
        _buildCountTile(label: 'Total', count: endOfDayData.totaldelivery, color: Colors.blue, icon: Icons.local_shipping_outlined),
        _buildCountTile(label: 'Delivered', count: endOfDayData.deliveredstatus, color: Colors.green, icon: Icons.check_circle_outline),
        _buildCountTile(label: 'Pending', count: endOfDayData.pendingstatus, color: Colors.orange, icon: Icons.pending_actions),
        _buildCountTile(label: 'Returned', count: endOfDayData.returnedstatus, color: Colors.red, icon: Icons.assignment_return_outlined),
      ],
    );
  }

  Widget _buildCountTile({required String label, required int count, required MaterialColor color, required IconData icon}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color.shade800),
            const SizedBox(height: 4),
            Text(
              '$count',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color.shade900),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color.shade700),
            ),
          ],
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
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
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
            const Divider(height: 22),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildSalesAndCollectionsCard() {
    return _buildSectionCard(
      title: 'Sales & Collections',
      icon: Icons.payments_outlined,
      child: Column(
        spacing: 10,
        children: [
          _buildAmountRow('Total Order Amount', endOfDayData.totalorderamount, isBold: true),
          _buildAmountRow('Total Delivered Amount', endOfDayData.totaldeliveredamount, isBold: true),
          const Divider(height: 14),
          _buildAmountRow('Cash Collected', endOfDayData.cashamount, icon: Icons.payments_outlined, color: Colors.green),
          _buildAmountRow('Online Payment', endOfDayData.onlineamount, icon: Icons.account_balance_outlined, color: Colors.blue),
          _buildAmountRow('Credit / Receivables', endOfDayData.creditamount, icon: Icons.credit_card_outlined, color: Colors.purple),
        ],
      ),
    );
  }

  Widget _buildDeductionsCard() {
    return _buildSectionCard(
      title: 'Deductions & Adjustments',
      icon: Icons.trending_down_outlined,
      child: Column(
        spacing: 10,
        children: [
          _buildAmountRow('Total Returns', endOfDayData.returnedAmount, color: Colors.orange.shade800),
          _buildAmountRow('Bad Orders', endOfDayData.badorderAmount, color: Colors.red.shade700),
          _buildAmountRow('Operating Expenses', endOfDayData.expenseAmount, color: Colors.red.shade700),
        ],
      ),
    );
  }

  Widget _buildCashReconciliationCard() {
    bool hasBreakdown = endOfDayData.actualcashonhand != 0;
    bool isBalanced = endOfDayData.discrepancy == 0;
    bool isOver = endOfDayData.discrepancy > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: isBalanced
            ? Colors.green.withValues(alpha: 0.05)
            : (isOver ? Colors.orange.withValues(alpha: 0.05) : Colors.red.withValues(alpha: 0.05)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isBalanced ? Colors.green.shade200 : (isOver ? Colors.orange.shade200 : Colors.red.shade200), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Expected Cash-On-Hand', style: TextStyle(fontSize: 13, color: Colors.black54)),
              Text(
                Helperfunctions.formatDoubleAmountForDisplay(endOfDayData.expectedcashonhand),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
              ),
            ],
          ),
          if (hasBreakdown) ...[
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Salesman Actual Cash', style: TextStyle(fontSize: 13, color: Colors.black54)),
                Text(
                  Helperfunctions.formatDoubleAmountForDisplay(endOfDayData.actualcashonhand),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      isBalanced ? Icons.check_circle : (isOver ? Icons.error_outline : Icons.warning_amber_rounded),
                      size: 18,
                      color: isBalanced ? Colors.green : (isOver ? Colors.orange : Colors.red),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isBalanced ? 'Balanced' : (isOver ? 'Overpaid' : 'Shortage'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isBalanced ? Colors.green.shade700 : (isOver ? Colors.orange.shade800 : Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
                Text(
                  Helperfunctions.formatDoubleAmountForDisplay(endOfDayData.discrepancy.abs()),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: isBalanced ? Colors.green.shade700 : (isOver ? Colors.orange.shade800 : Colors.red.shade700),
                  ),
                ),
              ],
            ),
            if (endOfDayData.bankdeposit > 0) ...[
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Bank Deposit', style: TextStyle(fontSize: 13, color: Colors.black54)),
                  Text(
                    Helperfunctions.formatDoubleAmountForDisplay(endOfDayData.bankdeposit),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blue),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildAmountRow(String label, double amount, {bool isBold = false, IconData? icon, Color? color}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        if (icon != null) ...[Icon(icon, size: 16, color: color ?? colorScheme.onSurfaceVariant), const SizedBox(width: 6)],
        Text(
          label,
          style: TextStyle(fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.w500, color: colorScheme.onSurface),
        ),
        const Spacer(),
        Text(
          Helperfunctions.formatDoubleAmountForDisplay(amount),
          style: TextStyle(fontSize: isBold ? 15 : 14, fontWeight: isBold ? FontWeight.bold : FontWeight.w600, color: color ?? colorScheme.onSurface),
        ),
      ],
    );
  }

  Widget _buildStickyBottomBar() {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 1.0)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), offset: const Offset(0, -2), blurRadius: 6)],
        ),
        child: FilledButton.icon(
          onPressed: validateBeforeBreakdown,
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 50.0),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: const Icon(Icons.calculate_outlined, size: 20),
          label: const Text('View Cash Breakdown', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  void _changeDate(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
    getData();
  }

  void onChangeDate() async {
    final DateTime? dateTime = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(3000),
    );

    if (dateTime != null) {
      _selectedDate = dateTime;
      getData();
    }
  }

  void getData() async {
    showLoading(true);
    _isDealer = await KVariables.getIsDealer();
    endOfDayData = await db.getListDeliveryForEndOfDay(_selectedDate);
    breakdown = await dbBS.getDocumentsBySpecificDate(_selectedDate) ?? Breakdown.empty();
    breakdownID = await dbBS.getIDofBreakdown(_selectedDate);

    breakdown!.breakdownDate = Timestamp.fromDate(_selectedDate);
    breakdown!.expectedAmount = endOfDayData.expectedcashonhand;

    showLoading(false);
  }

  void validateBeforeBreakdown() async {
    if (endOfDayData.pendingstatus > 0) {
      ShowMessage.error(context, 'There should be no transaction that is pending for delivery');
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => BreakdownPage(breakdown: breakdown!, breakdownID: breakdownID),
        ),
      );
      getData();
    }
  }

  void showLoading(bool showLoading) async {
    if (mounted) await Helperfunctions.showLoading(context: context, showLoading: showLoading);
    if (!showLoading) setState(() {});
  }
}
