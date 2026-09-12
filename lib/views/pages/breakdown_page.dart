import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/breakdown.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/breakdown_service.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:intl/intl.dart';

class BreakdownPage extends StatefulWidget {
  const BreakdownPage({super.key, required this.breakdownID, required this.breakdown});
  final String breakdownID;
  final Breakdown breakdown;

  @override
  State<BreakdownPage> createState() => _BreakdownPageState();
}

class _BreakdownPageState extends State<BreakdownPage> {
  final TextEditingController txt1000 = TextEditingController();
  final TextEditingController txt500 = TextEditingController();
  final TextEditingController txt200 = TextEditingController();
  final TextEditingController txt100 = TextEditingController();
  final TextEditingController txt50 = TextEditingController();
  final TextEditingController txtB20 = TextEditingController();
  final TextEditingController txtC20 = TextEditingController();
  final TextEditingController txt10 = TextEditingController();
  final TextEditingController txt5 = TextEditingController();
  final TextEditingController txt1 = TextEditingController();
  final TextEditingController txtCent = TextEditingController();
  final TextEditingController txtBankDeposit = TextEditingController();

  final BreakdownTotal breakdownTotal = BreakdownTotal();
  final BreakdownService db = BreakdownService();
  bool withBankDeposit = false;

  @override
  void initState() {
    super.initState();

    if (widget.breakdownID.isNotEmpty) {
      txt1000.text = widget.breakdown.b1000 != 0 ? widget.breakdown.b1000.toString() : '';
      txt500.text = widget.breakdown.b500 != 0 ? widget.breakdown.b500.toString() : '';
      txt200.text = widget.breakdown.b200 != 0 ? widget.breakdown.b200.toString() : '';
      txt100.text = widget.breakdown.b100 != 0 ? widget.breakdown.b100.toString() : '';
      txt50.text = widget.breakdown.b50 != 0 ? widget.breakdown.b50.toString() : '';
      txtB20.text = widget.breakdown.b20 != 0 ? widget.breakdown.b20.toString() : '';
      txtC20.text = widget.breakdown.c20 != 0 ? widget.breakdown.c20.toString() : '';
      txt10.text = widget.breakdown.c10 != 0 ? widget.breakdown.c10.toString() : '';
      txt5.text = widget.breakdown.c5 != 0 ? widget.breakdown.c5.toString() : '';
      txt1.text = widget.breakdown.c1 != 0 ? widget.breakdown.c1.toString() : '';
      txtCent.text = widget.breakdown.cent != 0 ? widget.breakdown.cent.toString() : '';

      if (widget.breakdown.bankDepositAmount > 0) {
        txtBankDeposit.text = Helperfunctions.formatDoubleAmountForDisplay(widget.breakdown.bankDepositAmount);
        withBankDeposit = true;
      }

      recompute();
    }
  }

  @override
  void dispose() {
    txt1000.dispose();
    txt500.dispose();
    txt200.dispose();
    txt100.dispose();
    txt50.dispose();
    txtB20.dispose();
    txtC20.dispose();
    txt10.dispose();
    txt5.dispose();
    txt1.dispose();
    txtCent.dispose();
    txtBankDeposit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppbar(title: 'Cash Breakdown', subtitle: Helperfunctions.formatTimestampForDisplay(widget.breakdown.breakdownDate)),
      bottomNavigationBar: _buildStickyBottomBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 16,
          children: [
            // 1. Reconciliation Summary Banner
            _buildReconciliationSummary(),

            // 2. Denominations Table Card
            _buildDenominationsCard(),

            // 3. Bank Deposit Card
            _buildBankDepositCard(),

            // 4. Audit & History Card (when viewing existing breakdown)
            if (widget.breakdownID.isNotEmpty) _buildAuditCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildReconciliationSummary() {
    double totalCollected = widget.breakdown.breakdownAmount + widget.breakdown.bankDepositAmount;
    double expected = widget.breakdown.expectedAmount;
    double discrepancy = widget.breakdown.discrepancy;
    bool isBalanced = discrepancy == 0;
    bool isOver = discrepancy > 0;

    Color badgeColor = isBalanced ? Colors.green : (isOver ? Colors.orange.shade800 : Colors.red.shade700);
    Color bgColor = isBalanced
        ? Colors.green.withValues(alpha: 0.08)
        : (isOver ? Colors.orange.withValues(alpha: 0.08) : Colors.red.withValues(alpha: 0.08));
    Color borderColor = isBalanced ? Colors.green.shade300 : (isOver ? Colors.orange.shade300 : Colors.red.shade300);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total Counted', style: TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 2),
                    Text(
                      Helperfunctions.formatDoubleAmountForDisplay(totalCollected),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
              ),
              Container(height: 32, width: 1, color: Colors.grey.shade300),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Expected Amount', style: TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 2),
                    Text(Helperfunctions.formatDoubleAmountForDisplay(expected), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(isBalanced ? Icons.check_circle : (isOver ? Icons.error_outline : Icons.warning_amber_rounded), size: 20, color: badgeColor),
                  const SizedBox(width: 6),
                  Text(
                    isBalanced
                        ? '✓ Balanced'
                        : (isOver
                              ? '⚠️ Over by ${Helperfunctions.formatDoubleAmountForDisplay(discrepancy.abs())}'
                              : '⚠️ Short by ${Helperfunctions.formatDoubleAmountForDisplay(discrepancy.abs())}'),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: badgeColor),
                  ),
                ],
              ),
              if (!isBalanced)
                Text(
                  isOver ? 'Overpaid' : 'Shortage',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: badgeColor),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDenominationsCard() {
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
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.pin_outlined, size: 18, color: colorScheme.primary),
                ),
                const SizedBox(width: 10),
                const Text('Cash Denominations', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 22),
            // Header
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Denomination',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Center(
                    child: Text(
                      'Qty',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Subtotal',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildDenominationRow('₱1,000', txt1000, breakdownTotal.total1000, isBill: true),
            _buildDenominationRow('₱500', txt500, breakdownTotal.total500, isBill: true),
            _buildDenominationRow('₱200', txt200, breakdownTotal.total200, isBill: true),
            _buildDenominationRow('₱100', txt100, breakdownTotal.total100, isBill: true),
            _buildDenominationRow('₱50', txt50, breakdownTotal.total50, isBill: true),
            _buildDenominationRow('₱20 (Bill)', txtB20, breakdownTotal.totalB20, isBill: true),
            _buildDenominationRow('₱20 (Coin)', txtC20, breakdownTotal.totalC20, isBill: false),
            _buildDenominationRow('₱10', txt10, breakdownTotal.total10, isBill: false),
            _buildDenominationRow('₱5', txt5, breakdownTotal.total5, isBill: false),
            _buildDenominationRow('₱1', txt1, breakdownTotal.total1, isBill: false),
            _buildDenominationRow('Centavos', txtCent, breakdownTotal.totalCent, isBill: false),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Cash in Hand', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text(
                  Helperfunctions.formatDoubleAmountForDisplay(widget.breakdown.breakdownAmount),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDenominationRow(String label, TextEditingController controller, double subtotal, {required bool isBill}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(
                  isBill ? Icons.money_rounded : Icons.monetization_on_outlined,
                  size: 16,
                  color: isBill ? Colors.green.shade700 : Colors.amber.shade800,
                ),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Container(
              height: 38,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              child: TextFormField(
                controller: controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  filled: true,
                  fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                ),
                onChanged: (_) => recompute(),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(Helperfunctions.formatDoubleAmountForDisplay(subtotal), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBankDepositCard() {
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
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.account_balance_outlined, color: Colors.blue, size: 20),
              ),
              title: const Text('Bank Deposit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: const Text('Include bank deposit in reconciliation', style: TextStyle(fontSize: 12)),
              value: withBankDeposit,
              onChanged: (val) {
                setState(() {
                  withBankDeposit = val;
                  recompute();
                });
              },
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: withBankDeposit
                  ? Padding(
                      padding: const EdgeInsets.only(top: 12.0),
                      child: Focus(
                        onFocusChange: (hasFocus) => onFocusChange(hasFocus, txtBankDeposit),
                        child: TextFormField(
                          controller: txtBankDeposit,
                          textAlign: TextAlign.end,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                          decoration: InputDecoration(
                            labelText: 'Bank Deposit Amount',
                            prefixIcon: const Icon(Icons.account_balance_outlined, color: Colors.blue, size: 20),
                            prefixText: '₱ ',
                            prefixStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
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
                _buildAuditRow('Created By', widget.breakdown.createdBy),
                _buildAuditRow('Created Date', DateFormat('E, d MMM yyyy, hh:mm a').format(widget.breakdown.createdDate.toDate())),
                const Divider(height: 12),
                _buildAuditRow('Last Updated By', widget.breakdown.lastUpdatedBy),
                _buildAuditRow('Last Updated Date', DateFormat('E, d MMM yyyy, hh:mm a').format(widget.breakdown.lastupdatedDate.toDate())),
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
    bool isUpdating = widget.breakdownID.isNotEmpty;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 1.0)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), offset: const Offset(0, -2), blurRadius: 6)],
        ),
        child: FilledButton.icon(
          onPressed: () async {
            final confirmed = await ShowMessage.confirm(
              context,
              title: isUpdating ? ConfirmTitle.update : ConfirmTitle.save,
              message: isUpdating ? ConfirmMessage.update : ConfirmMessage.save,
              icon: isUpdating ? Icons.check_circle_outline : Icons.save_outlined,
              confirmText: isUpdating ? 'Update' : 'Save',
            );
            if (confirmed) {
              isUpdating ? onUpdate() : onSave();
            }
          },
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 50.0),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: Icon(isUpdating ? Icons.check_circle_outline : Icons.save_outlined, size: 20),
          label: Text(
            isUpdating ? 'Update Breakdown Record' : 'Save Breakdown Record',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  void onSave() {
    recompute();
    Breakdown newRecord = Breakdown(
      breakdownDate: widget.breakdown.breakdownDate,
      bankDepositAmount: txtBankDeposit.text.isEmpty ? 0 : Helperfunctions.formatStringAmountToDouble(txtBankDeposit.text),
      breakdownAmount: widget.breakdown.breakdownAmount,
      expectedAmount: widget.breakdown.expectedAmount,
      discrepancy: widget.breakdown.discrepancy,
      cent: txtCent.text.isEmpty ? 0 : int.parse(txtCent.text),
      b1000: txt1000.text.isEmpty ? 0 : int.parse(txt1000.text),
      b500: txt500.text.isEmpty ? 0 : int.parse(txt500.text),
      b200: txt200.text.isEmpty ? 0 : int.parse(txt200.text),
      b100: txt100.text.isEmpty ? 0 : int.parse(txt100.text),
      b50: txt50.text.isEmpty ? 0 : int.parse(txt50.text),
      b20: txtB20.text.isEmpty ? 0 : int.parse(txtB20.text),
      c20: txtC20.text.isEmpty ? 0 : int.parse(txtC20.text),
      c10: txt10.text.isEmpty ? 0 : int.parse(txt10.text),
      c5: txt5.text.isEmpty ? 0 : int.parse(txt5.text),
      c1: txt1.text.isEmpty ? 0 : int.parse(txt1.text),
      createdBy: authService.value.currentUser!.displayName!,
      lastUpdatedBy: authService.value.currentUser!.displayName!,
      createdDate: Timestamp.now(),
      lastupdatedDate: Timestamp.now(),
    );

    db.addBreakdown(newRecord);
    ShowMessage.success(context, 'Successfully created a new breakdown record!');
    Navigator.pop(context);
  }

  void onUpdate() {
    recompute();
    Breakdown newRecord = widget.breakdown.copyWith(
      breakdownDate: widget.breakdown.breakdownDate,
      breakdownAmount: widget.breakdown.breakdownAmount,
      expectedAmount: widget.breakdown.expectedAmount,
      discrepancy: widget.breakdown.discrepancy,
      bankDepositAmount: txtBankDeposit.text.isEmpty ? 0 : Helperfunctions.formatStringAmountToDouble(txtBankDeposit.text),
      cent: txtCent.text.isEmpty ? 0 : int.parse(txtCent.text),
      b1000: txt1000.text.isEmpty ? 0 : int.parse(txt1000.text),
      b500: txt500.text.isEmpty ? 0 : int.parse(txt500.text),
      b200: txt200.text.isEmpty ? 0 : int.parse(txt200.text),
      b100: txt100.text.isEmpty ? 0 : int.parse(txt100.text),
      b50: txt50.text.isEmpty ? 0 : int.parse(txt50.text),
      b20: txtB20.text.isEmpty ? 0 : int.parse(txtB20.text),
      c20: txtC20.text.isEmpty ? 0 : int.parse(txtC20.text),
      c10: txt10.text.isEmpty ? 0 : int.parse(txt10.text),
      c5: txt5.text.isEmpty ? 0 : int.parse(txt5.text),
      c1: txt1.text.isEmpty ? 0 : int.parse(txt1.text),
      createdBy: widget.breakdown.createdBy,
      lastUpdatedBy: authService.value.currentUser!.displayName!,
      createdDate: widget.breakdown.createdDate,
      lastupdatedDate: Timestamp.now(),
    );

    db.updateBreakdown(widget.breakdownID, newRecord);
    ShowMessage.success(context, 'Successfully updated breakdown record!');
    Navigator.pop(context);
  }

  void recompute() {
    if (withBankDeposit) {
      widget.breakdown.bankDepositAmount = txtBankDeposit.text.isEmpty ? 0 : Helperfunctions.formatStringAmountToDouble(txtBankDeposit.text);
    } else {
      widget.breakdown.bankDepositAmount = 0;
      txtBankDeposit.text = '';
    }

    breakdownTotal.total1000 = txt1000.text.isEmpty ? 0 : double.parse(txt1000.text) * 1000;
    breakdownTotal.total500 = txt500.text.isEmpty ? 0 : double.parse(txt500.text) * 500;
    breakdownTotal.total200 = txt200.text.isEmpty ? 0 : double.parse(txt200.text) * 200;
    breakdownTotal.total100 = txt100.text.isEmpty ? 0 : double.parse(txt100.text) * 100;
    breakdownTotal.total50 = txt50.text.isEmpty ? 0 : double.parse(txt50.text) * 50;
    breakdownTotal.totalB20 = txtB20.text.isEmpty ? 0 : double.parse(txtB20.text) * 20;
    breakdownTotal.totalC20 = txtC20.text.isEmpty ? 0 : double.parse(txtC20.text) * 20;
    breakdownTotal.total10 = txt10.text.isEmpty ? 0 : double.parse(txt10.text) * 10;
    breakdownTotal.total5 = txt5.text.isEmpty ? 0 : double.parse(txt5.text) * 5;
    breakdownTotal.total1 = txt1.text.isEmpty ? 0 : double.parse(txt1.text) * 1;
    breakdownTotal.totalCent = txtCent.text.isEmpty ? 0 : double.parse(txtCent.text) * .01;

    widget.breakdown.breakdownAmount =
        breakdownTotal.total1000 +
        breakdownTotal.total500 +
        breakdownTotal.total200 +
        breakdownTotal.total100 +
        breakdownTotal.total50 +
        breakdownTotal.totalB20 +
        breakdownTotal.totalC20 +
        breakdownTotal.total10 +
        breakdownTotal.total5 +
        breakdownTotal.total1 +
        breakdownTotal.totalCent;

    widget.breakdown.discrepancy = (widget.breakdown.bankDepositAmount + widget.breakdown.breakdownAmount) - widget.breakdown.expectedAmount;

    setState(() {});
  }

  void onFocusChange(bool hasFocus, TextEditingController controller) {
    if (controller.text.isNotEmpty) {
      if (!hasFocus) {
        recompute();
        setState(() => controller.text = Helperfunctions.formatStringAmountForDisplay(controller.text));
      } else {
        setState(() => controller.text = Helperfunctions.formatStringAmountForEditing(controller.text));
      }
    } else {
      if (!hasFocus) {
        setState(() => recompute());
      }
    }
  }
}

class BreakdownTotal {
  double total1000 = 0;
  double total500 = 0;
  double total200 = 0;
  double total100 = 0;
  double total50 = 0;
  double totalB20 = 0;
  double totalC20 = 0;
  double total10 = 0;
  double total5 = 0;
  double total1 = 0;
  double totalCent = 0;
}
