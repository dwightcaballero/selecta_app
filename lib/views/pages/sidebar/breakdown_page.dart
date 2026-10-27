import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:selecta_ops/controllers/endofday_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/data/responsive.dart';
import 'package:selecta_ops/dto/endofday_dto.dart';
import 'package:selecta_ops/models/breakdown.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';
import 'package:selecta_ops/views/widgets/audithistory_widget.dart';

class BreakdownPage extends StatefulWidget {
  const BreakdownPage({
    super.key,
    required this.breakdownID,
    required this.breakdown,
    this.endOfDayData,
  });

  final Breakdown breakdown;
  final String breakdownID;
  final EndOfDayDTO? endOfDayData;

  @override
  State<BreakdownPage> createState() => _BreakdownPageState();
}

class _BreakdownPageState extends State<BreakdownPage> {
  // Controller managing calculations, verification, and audit logging
  final EndOfDayController _controller = EndOfDayController();
  BreakdownTotal breakdownTotal = BreakdownTotal();
  bool isDealer = false;
  bool _isVerifying = false;
  EndOfDayDTO? _endOfDayData;
  bool _isLoadingEndOfDay = false;
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

  bool get _hasUnsavedChanges {
    if (widget.breakdown.isVerifiedByDealer) return false;
    final b = widget.breakdown;
    if (widget.breakdownID.isNotEmpty) {
      final curB1000 = txt1000.text.isEmpty ? 0 : int.tryParse(txt1000.text) ?? 0;
      final curB500 = txt500.text.isEmpty ? 0 : int.tryParse(txt500.text) ?? 0;
      final curB200 = txt200.text.isEmpty ? 0 : int.tryParse(txt200.text) ?? 0;
      final curB100 = txt100.text.isEmpty ? 0 : int.tryParse(txt100.text) ?? 0;
      final curB50 = txt50.text.isEmpty ? 0 : int.tryParse(txt50.text) ?? 0;
      final curB20 = txtB20.text.isEmpty ? 0 : int.tryParse(txtB20.text) ?? 0;
      final curC20 = txtC20.text.isEmpty ? 0 : int.tryParse(txtC20.text) ?? 0;
      final curC10 = txt10.text.isEmpty ? 0 : int.tryParse(txt10.text) ?? 0;
      final curC5 = txt5.text.isEmpty ? 0 : int.tryParse(txt5.text) ?? 0;
      final curC1 = txt1.text.isEmpty ? 0 : int.tryParse(txt1.text) ?? 0;
      final curCent = txtCent.text.isEmpty ? 0 : int.tryParse(txtCent.text) ?? 0;
      final curBank = txtBankDeposit.text.isEmpty ? 0.0 : Helperfunctions.formatStringAmountToDouble(txtBankDeposit.text);

      return curB1000 != b.b1000 ||
          curB500 != b.b500 ||
          curB200 != b.b200 ||
          curB100 != b.b100 ||
          curB50 != b.b50 ||
          curB20 != b.b20 ||
          curC20 != b.c20 ||
          curC10 != b.c10 ||
          curC5 != b.c5 ||
          curC1 != b.c1 ||
          curCent != b.cent ||
          curBank != b.bankDepositAmount;
    }
    return txt1000.text.isNotEmpty ||
        txt500.text.isNotEmpty ||
        txt200.text.isNotEmpty ||
        txt100.text.isNotEmpty ||
        txt50.text.isNotEmpty ||
        txtB20.text.isNotEmpty ||
        txtC20.text.isNotEmpty ||
        txt10.text.isNotEmpty ||
        txt5.text.isNotEmpty ||
        txt1.text.isNotEmpty ||
        txtCent.text.isNotEmpty ||
        txtBankDeposit.text.isNotEmpty;
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
  void initState() {
    super.initState();
    _endOfDayData = widget.endOfDayData;
    _checkDealer();
    if (_endOfDayData == null) {
      _loadEndOfDayData();
    }

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

  void _verifyGateOrPop(bool dealer, EndOfDayDTO? data) {
    if (!dealer && (data?.hasUnconfirmedReturnProof ?? false)) {
      if (mounted) {
        ShowMessage.error(
          context,
          'Cannot view Cash Breakdown: Pending return proofs must be confirmed by warehouse first.',
        );
        Navigator.pop(context);
      }
    }
  }

  void _loadEndOfDayData() async {
    setState(() => _isLoadingEndOfDay = true);
    try {
      final snapshot = await _controller.fetchEndOfDayData(widget.breakdown.breakdownDate.toDate());
      if (mounted) {
        setState(() {
          _endOfDayData = snapshot.endOfDayData;
          _isLoadingEndOfDay = false;
        });
        _verifyGateOrPop(isDealer, snapshot.endOfDayData);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingEndOfDay = false);
      }
    }
  }

  void _checkDealer() async {
    final dealer = await _controller.checkIsDealer();
    if (mounted) {
      setState(() {
        isDealer = dealer;
      });
      _verifyGateOrPop(dealer, _endOfDayData);
    }
  }

  Future<void> onVerify() async {
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

  Future<void> onSave() async {
    if (!isDealer && (_endOfDayData?.hasUnconfirmedReturnProof ?? false)) {
      ShowMessage.error(context, 'Cannot save Cash Breakdown: Pending return proofs must be confirmed by warehouse first.');
      return;
    }
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

  Future<void> onUpdate() async {
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

  Widget _buildStickyBottomBar({bool isEmbedded = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    bool isUpdating = widget.breakdownID.isNotEmpty;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 8,
      children: [
        if (isDealer && isUpdating)
          AsyncOutlinedButton.icon(
            onPressed: widget.breakdown.isVerifiedByDealer ? null : onVerify,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48.0),
              foregroundColor: widget.breakdown.isVerifiedByDealer ? Colors.green.shade700 : colorScheme.primary,
              side: BorderSide(
                color: widget.breakdown.isVerifiedByDealer ? Colors.green.shade400 : colorScheme.primary,
                width: 1.5,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: Icon(
              widget.breakdown.isVerifiedByDealer ? Icons.check_circle : Icons.verified_outlined,
              size: 20,
              color: widget.breakdown.isVerifiedByDealer ? Colors.green.shade700 : colorScheme.primary,
            ),
            label: Text(
              widget.breakdown.isVerifiedByDealer ? 'Verified by Dealer' : 'Verify Cash Breakdown',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: widget.breakdown.isVerifiedByDealer ? Colors.green.shade700 : colorScheme.primary,
              ),
            ),
          ),
        AsyncFilledButton.icon(
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
                  if (confirmed == true) {
                    if (isUpdating) {
                      await onUpdate();
                    } else {
                      await onSave();
                    }
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
    );

    if (isEmbedded) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        child: content,
      );
    }

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 1.0)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), offset: const Offset(0, -2), blurRadius: 6)],
        ),
        child: content,
      ),
    );
  }

  Widget _buildVerifiedBanner() {
    return Container(
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
    );
  }

  Widget _buildExpectedCollectionsCard(ColorScheme colorScheme) {
    final eod = _endOfDayData;
    final double expected = widget.breakdown.expectedAmount;
    final double deliveredSales = eod?.totaldeliveredamount ?? expected;
    final double cashCollected = eod?.cashamount ?? expected;
    final double onlineCollected = eod?.onlineamount ?? 0.0;
    final double creditCollected = eod?.creditamount ?? 0.0;
    final double expenses = eod?.expenseAmount ?? 0.0;
    final int totalDeliveries = eod?.totaldelivery ?? 0;
    final int deliveredCount = eod?.deliveredstatus ?? 0;
    final int returnedCount = eod?.returnedstatus ?? 0;

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
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.receipt_long_outlined, size: 18, color: Colors.teal),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Expected Delivery Collections',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_isLoadingEndOfDay)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (totalDeliveries > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$totalDeliveries Orders',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
            const Divider(height: 22),

            // Order fulfillment counts pill row if available
            if (totalDeliveries > 0) ...[
              Row(
                children: [
                  _buildMiniStatChip(
                    label: 'Delivered',
                    count: deliveredCount,
                    color: Colors.green,
                    icon: Icons.check_circle_outline,
                  ),
                  const SizedBox(width: 8),
                  _buildMiniStatChip(
                    label: 'Returned',
                    count: returnedCount,
                    color: Colors.red,
                    icon: Icons.assignment_return_outlined,
                  ),
                  if (eod?.pendingstatus != null && eod!.pendingstatus > 0) ...[
                    const SizedBox(width: 8),
                    _buildMiniStatChip(
                      label: 'Pending',
                      count: eod.pendingstatus,
                      color: Colors.orange,
                      icon: Icons.pending_actions,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
            ],

            // Tender Breakdown
            _buildCollectionRow(
              'Total Delivered Sales',
              Helperfunctions.formatDoubleAmountForDisplay(deliveredSales),
              isHeader: true,
            ),
            const SizedBox(height: 8),
            _buildCollectionRow(
              'Cash Tender Collected',
              Helperfunctions.formatDoubleAmountForDisplay(cashCollected),
              valueColor: Colors.green.shade700,
              icon: Icons.payments_outlined,
            ),
            if (eod != null && (eod.preSellCashAmount > 0 || eod.vanSellCashAmount > 0))
              Padding(
                padding: const EdgeInsets.only(left: 24, top: 2, bottom: 4),
                child: Text(
                  'Pre-Sell: ${Helperfunctions.formatDoubleAmountForDisplay(eod.preSellCashAmount)}  •  Van Sell: ${Helperfunctions.formatDoubleAmountForDisplay(eod.vanSellCashAmount)}',
                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                ),
              ),
            const SizedBox(height: 6),
            _buildCollectionRow(
              'Online / Bank Transfers',
              Helperfunctions.formatDoubleAmountForDisplay(onlineCollected),
              valueColor: Colors.blue.shade700,
              icon: Icons.account_balance_outlined,
            ),
            const SizedBox(height: 6),
            _buildCollectionRow(
              'Credit / Receivables',
              Helperfunctions.formatDoubleAmountForDisplay(creditCollected),
              valueColor: Colors.purple.shade700,
              icon: Icons.credit_card_outlined,
            ),
            if (expenses > 0) ...[
              const SizedBox(height: 6),
              _buildCollectionRow(
                'Cash Expenses Deducted',
                '- ${Helperfunctions.formatDoubleAmountForDisplay(expenses)}',
                valueColor: Colors.red.shade700,
                icon: Icons.money_off_csred_outlined,
              ),
            ],
            const Divider(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.account_balance_wallet_outlined, size: 18, color: Colors.green.shade800),
                      const SizedBox(width: 8),
                      Text(
                        'Expected Cash on Hand',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade900,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    Helperfunctions.formatDoubleAmountForDisplay(expected),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStatChip({
    required String label,
    required int count,
    required MaterialColor color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color.shade700),
          const SizedBox(width: 4),
          Text(
            '$count $label',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color.shade800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionRow(
    String label,
    String value, {
    Color? valueColor,
    IconData? icon,
    bool isHeader = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: valueColor ?? colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: isHeader ? 13 : 12.5,
              fontWeight: isHeader ? FontWeight.bold : FontWeight.w500,
              color: isHeader ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isHeader ? 14 : 13,
            fontWeight: FontWeight.bold,
            color: valueColor ?? colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildTabletLandscapeLayout(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── LEFT PANE: Expected Collections, Reconciliation & Remittance Action ──
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              primary: false,
              padding: const EdgeInsets.only(right: 12.0, bottom: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 14,
                children: [
                  if (widget.breakdown.isVerifiedByDealer)
                    _buildVerifiedBanner(),
                  _buildExpectedCollectionsCard(colorScheme),
                  _buildReconciliationSummary(),
                  _buildStickyBottomBar(isEmbedded: true),
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
          ),

          // Vertical divider between panes
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),

          // ── RIGHT PANE: Denomination Counter & Bank Deposit ──
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              primary: false,
              padding: const EdgeInsets.only(left: 12.0, bottom: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 14,
                children: [
                  _buildDenominationsCard(),
                  _buildBankDepositCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortraitLayout() {
    return SingleChildScrollView(
      primary: false,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          if (widget.breakdown.isVerifiedByDealer)
            _buildVerifiedBanner(),

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
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isTabletLandscape = ScreenSize.isTabletLandscape(context);
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_hasUnsavedChanges) {
          final shouldDiscard = await ShowMessage.confirm(
            context,
            title: 'Discard Cash Breakdown?',
            message: 'You have unsaved cash breakdown entries. Are you sure you want to go back and discard them?',
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
        appBar: CustomAppbar(
          title: 'Cash Breakdown',
          subtitle: Helperfunctions.formatTimestampForDisplay(widget.breakdown.breakdownDate),
        ),
        bottomNavigationBar: isTabletLandscape ? null : _buildStickyBottomBar(),
        body: isTabletLandscape
            ? _buildTabletLandscapeLayout(colorScheme)
            : _buildPortraitLayout(),
      ),
    );
  }
}
