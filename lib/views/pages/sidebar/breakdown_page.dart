import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:selecta_ops/controllers/endofday_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/breakdown.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/audithistory_widget.dart';

class BreakdownPage extends StatefulWidget {
  const BreakdownPage({super.key, required this.breakdownID, required this.breakdown});

  final Breakdown breakdown;
  final String breakdownID;

  @override
  State<BreakdownPage> createState() => _BreakdownPageState();
}

class _BreakdownPageState extends State<BreakdownPage> {
  // Controller managing calculations, verification, and audit logging
  final EndOfDayController _controller = EndOfDayController();
  BreakdownTotal breakdownTotal = BreakdownTotal();
  bool isDealer = false;
  bool _isVerifying = false;
  final TextEditingController txt1 = TextEditingController();
  final TextEditingController txt10 = TextEditingController();
  final TextEditingController txt100 = TextEditingController();
  final TextEditingController txt1000 = TextEditingController();
  final TextEditingController txt200 = TextEditingController();
  final TextEditingController txt5 = TextEditingController();
  final TextEditingController txt50 = TextEditingController();
  final TextEditingController txt500 = TextEditingController();
  final TextEditingController txtB20 = TextEditingController();
  final TextEditingController txtBankDeposit = TextEditingController();
  final TextEditingController txtC20 = TextEditingController();
  final TextEditingController txtCent = TextEditingController();
  bool withBankDeposit = false;

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
  void initState() {
    super.initState();
    _checkDealer();

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
        txtBankDeposit.text = Helperfunctions.formatDoubleAmountForField(widget.breakdown.bankDepositAmount);
        withBankDeposit = true;
      }

      recompute();

    }
  }

  void _checkDealer() async {
    final dealer = await _controller.checkIsDealer();
    if (mounted) {
      setState(() {
        isDealer = dealer;
      });
    }
  }

  void onVerify() async {
    if (!isDealer || widget.breakdownID.isEmpty || _isVerifying) return;
    if (widget.breakdown.isVerifiedByDealer) {
      ShowMessage.info(context, 'This breakdown has already been verified by the dealer.');
      return;
    }

    final date = widget.breakdown.breakdownDate.toDate();
    final snapshot = await _controller.fetchEndOfDayData(date);
    if (!mounted) return;
    if (snapshot.endOfDayData.pendingstatus > 0) {
      ShowMessage.error(
        context,
        'Cannot verify breakdown: There are still ${snapshot.endOfDayData.pendingstatus} delivery record(s) pending "For Delivery" on this date.\n\nAll deliveries must be completed (Delivered or Returned) before verifying the breakdown.',
      );
      return;
    }
    if (snapshot.endOfDayData.pendingPicklistStatus > 0) {
      ShowMessage.error(
        context,
        'Cannot verify breakdown: There are still ${snapshot.endOfDayData.pendingPicklistStatus} order(s) pending picklist on this date.\n\nPlease complete or reschedule them first.',
      );
      return;
    }

    final confirmed = await ShowMessage.confirm(
      context,
      title: 'Verify Cash Breakdown',
      message: 'Once verified, this day\'s cash breakdown and delivery records will be permanently locked to protect inventory and financial accuracy.\n\nAre you sure you want to verify?',
      confirmText: 'Verify & Lock',
      icon: Icons.verified_outlined,
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isVerifying = true);

    try {
      await _controller.verifyAndSettleBreakdown(
        breakdownId: widget.breakdownID,
        currentRecord: widget.breakdown,
        date: date,
      );

      setState(() {
        widget.breakdown.isVerifiedByDealer = true;
      });

      if (mounted) {
        ShowMessage.success(
          context,
          'Breakdown verified! Cash closed and delivery records for this day are now locked.',
        );
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Failed to verify breakdown: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isVerifying = false);
      }
    }
  }

  void onSave() async {
    recompute();
    final newRecord = Breakdown(
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
      createdBy: _controller.currentUserName,
      lastUpdatedBy: _controller.currentUserName,
      createdDate: Timestamp.now(),
      lastupdatedDate: Timestamp.now(),
      createdPage: AppPages.breakdown,
      lastUpdatedPage: AppPages.breakdown,
    );

    await _controller.saveBreakdown(record: newRecord);

    if (mounted) {
      ShowMessage.success(context, 'Successfully created a new breakdown record!');
      Navigator.pop(context);
    }
  }

  void onUpdate() async {
    recompute();
    final updatedRecord = widget.breakdown.copyWith(
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
      lastUpdatedBy: _controller.currentUserName,
      createdDate: widget.breakdown.createdDate,
      lastupdatedDate: Timestamp.now(),
      createdPage: widget.breakdown.createdPage,
      lastUpdatedPage: AppPages.breakdown,
    );

    await _controller.updateBreakdown(
      breakdownId: widget.breakdownID,
      originalRecord: widget.breakdown,
      updatedRecord: updatedRecord,
    );

    if (mounted) {
      ShowMessage.success(context, 'Successfully updated breakdown record!');
      Navigator.pop(context);
    }
  }

  void recompute() {
    final double bankAmt = txtBankDeposit.text.isEmpty ? 0 : Helperfunctions.formatStringAmountToDouble(txtBankDeposit.text);
    if (!withBankDeposit) {
      txtBankDeposit.text = '';
    }

    final result = _controller.recompute(
      withBankDeposit: withBankDeposit,
      bankDepositAmount: bankAmt,
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
      cent: txtCent.text.isEmpty ? 0 : int.parse(txtCent.text),
      expectedAmount: widget.breakdown.expectedAmount,
    );

    breakdownTotal = result.breakdownTotal;
    widget.breakdown.bankDepositAmount = withBankDeposit ? bankAmt : 0;
    widget.breakdown.breakdownAmount = result.breakdownAmount;
    widget.breakdown.discrepancy = result.discrepancy;

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

  void _clearAllDenominations() {
    txt1000.clear();
    txt500.clear();
    txt200.clear();
    txt100.clear();
    txt50.clear();
    txtB20.clear();
    txtC20.clear();
    txt10.clear();
    txt5.clear();
    txt1.clear();
    txtCent.clear();
    recompute();
  }

  Widget _buildReconciliationSummary() {
    final colorScheme = Theme.of(context).colorScheme;
    double totalCollected = widget.breakdown.breakdownAmount + widget.breakdown.bankDepositAmount;
    double expected = widget.breakdown.expectedAmount;
    double discrepancy = widget.breakdown.discrepancy;
    bool isBalanced = discrepancy.abs() < 0.005;
    bool isOver = discrepancy >= 0.005;

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
                    Text('Total Counted', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(
                      Helperfunctions.formatDoubleAmountForDisplay(totalCollected),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
              ),
              Container(height: 32, width: 1, color: colorScheme.outlineVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Expected Amount', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
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
                        ? 'Balanced'
                        : (isOver
                              ? 'Over by ${Helperfunctions.formatDoubleAmountForDisplay(discrepancy.abs())}'
                              : 'Short by ${Helperfunctions.formatDoubleAmountForDisplay(discrepancy.abs())}'),
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
          if (widget.breakdown.isVerifiedByDealer) ...[
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.verified, size: 16, color: Colors.green.shade700),
                const SizedBox(width: 6),
                Text(
                  'Verified by Dealer',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade800,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color, letterSpacing: 0.3),
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
                const Spacer(),
                TextButton.icon(
                  onPressed: widget.breakdown.isVerifiedByDealer ? null : _clearAllDenominations,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                  icon: const Icon(Icons.restart_alt, size: 16),
                  label: const Text('Clear All', style: TextStyle(fontSize: 12)),
                ),
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
            const SizedBox(height: 8),
            _buildCategoryHeader('Banknotes (Bills)', Icons.money_rounded, Colors.green.shade700),
            _buildDenominationRow('₱1,000', txt1000, breakdownTotal.total1000, isBill: true),
            _buildDenominationRow('₱500', txt500, breakdownTotal.total500, isBill: true),
            _buildDenominationRow('₱200', txt200, breakdownTotal.total200, isBill: true),
            _buildDenominationRow('₱100', txt100, breakdownTotal.total100, isBill: true),
            _buildDenominationRow('₱50', txt50, breakdownTotal.total50, isBill: true),
            _buildDenominationRow('₱20 (Bill)', txtB20, breakdownTotal.totalB20, isBill: true),
            const SizedBox(height: 10),
            _buildCategoryHeader('Coins & Centavos', Icons.monetization_on_outlined, Colors.amber.shade800),
            _buildDenominationRow('₱20 (Coin)', txtC20, breakdownTotal.totalC20, isBill: false),
            _buildDenominationRow('₱10', txt10, breakdownTotal.total10, isBill: false),
            _buildDenominationRow('₱5', txt5, breakdownTotal.total5, isBill: false),
            _buildDenominationRow('₱1', txt1, breakdownTotal.total1, isBill: false),
            _buildDenominationRow('Centavos', txtCent, breakdownTotal.totalCent, isBill: false, isLast: true),
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

  Widget _buildDenominationRow(String label, TextEditingController controller, double subtotal, {required bool isBill, bool isLast = false}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
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
                textInputAction: isLast ? TextInputAction.done : TextInputAction.next,
                textAlign: TextAlign.center,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                enabled: !widget.breakdown.isVerifiedByDealer,
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
              onChanged: widget.breakdown.isVerifiedByDealer
                  ? null
                  : (val) {
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
                          enabled: !widget.breakdown.isVerifiedByDealer,
                          controller: txtBankDeposit,
                          textAlign: TextAlign.end,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
                          onChanged: (_) => recompute(),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            if (isDealer && isUpdating)
              OutlinedButton.icon(
                onPressed: (widget.breakdown.isVerifiedByDealer || _isVerifying) ? null : onVerify,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48.0),
                  foregroundColor: widget.breakdown.isVerifiedByDealer ? Colors.green.shade700 : colorScheme.primary,
                  side: BorderSide(
                    color: widget.breakdown.isVerifiedByDealer ? Colors.green.shade400 : colorScheme.primary,
                    width: 1.5,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: _isVerifying
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
                      )
                    : Icon(
                        widget.breakdown.isVerifiedByDealer ? Icons.check_circle : Icons.verified_outlined,
                        size: 20,
                        color: widget.breakdown.isVerifiedByDealer ? Colors.green.shade700 : colorScheme.primary,
                      ),
                label: Text(
                  _isVerifying
                      ? 'Verifying Breakdown...'
                      : (widget.breakdown.isVerifiedByDealer ? 'Verified by Dealer' : 'Verify Cash Breakdown'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: widget.breakdown.isVerifiedByDealer ? Colors.green.shade700 : colorScheme.primary,
                  ),
                ),
              ),
            FilledButton.icon(
              onPressed: widget.breakdown.isVerifiedByDealer
                  ? null
                  : () async {
                      final bool isBalanced = widget.breakdown.discrepancy.abs() < 0.005;
                      final double disc = widget.breakdown.discrepancy.abs();
                      final String baseMsg = isUpdating ? ConfirmMessage.update : ConfirmMessage.save;
                      final String message = isBalanced
                          ? baseMsg
                          : '$baseMsg\n\n⚠️ Note: Discrepancy is ${Helperfunctions.formatDoubleAmountForDisplay(disc)} (${widget.breakdown.discrepancy >= 0.005 ? "Overpaid" : "Shortage"}).';

                      final confirmed = await ShowMessage.confirm(
                        context,
                        title: isUpdating ? ConfirmTitle.update : ConfirmTitle.save,
                        message: message,
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
              icon: Icon(
                widget.breakdown.isVerifiedByDealer
                    ? Icons.lock_outline
                    : (isUpdating ? Icons.check_circle_outline : Icons.save_outlined),
                size: 20,
              ),
              label: Text(
                widget.breakdown.isVerifiedByDealer
                    ? 'Locked (Breakdown Verified)'
                    : (isUpdating ? 'Update Breakdown Record' : 'Save Breakdown Record'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppbar(title: 'Cash Breakdown', subtitle: Helperfunctions.formatTimestampForDisplay(widget.breakdown.breakdownDate)),
      bottomNavigationBar: _buildStickyBottomBar(),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 16,
          children: [
            if (widget.breakdown.isVerifiedByDealer)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade300, width: 1.2),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: Colors.green.shade900, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Verified: Daily cash breakdown has been verified by the dealer. All delivery records for this date are locked to protect inventory accuracy.',
                        style: TextStyle(fontSize: 13.5, color: Colors.green.shade900, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),

            // 1. Reconciliation Summary Banner
            _buildReconciliationSummary(),

            // 2. Denominations Table Card
            _buildDenominationsCard(),

            // 3. Bank Deposit Card
            _buildBankDepositCard(),

            // 4. Audit & History Card (when viewing existing breakdown)
            if (widget.breakdownID.isNotEmpty)
              AuditHistoryWidget(
                createdBy: widget.breakdown.createdBy,
                createdDate: widget.breakdown.createdDate,
                createdPage: widget.breakdown.createdPage,
                lastUpdatedBy: widget.breakdown.lastUpdatedBy,
                lastUpdatedDate: widget.breakdown.lastupdatedDate,
                lastUpdatedPage: widget.breakdown.lastUpdatedPage,
                additionalRows: [
                  AuditHistoryRow(
                    label: 'Verified by Dealer',
                    value: widget.breakdown.isVerifiedByDealer ? 'Yes' : 'No',
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
