import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/controllers/delivery_controller.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/data.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/delivery.dart';
import 'package:flutter_app/views/pages/dashboard/picklist_page.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:flutter_app/views/widgets/digital_receipt_dialog.dart';
import 'package:flutter_app/views/widgets/hapistore_dropdown.dart';

class DeliveryPage extends StatefulWidget {
  const DeliveryPage({super.key, required this.deliveryID, required this.delivery});

  final Delivery delivery;
  final String deliveryID;

  @override
  State<DeliveryPage> createState() => _DeliveryPageState();
}

class _DeliveryPageState extends State<DeliveryPage> {
  final DeliveryController _controller = DeliveryController();
  bool hasBreakdownForDay = false;
  bool get isSalesmanLocked => !isDealer && hasBreakdownForDay;

  double discrepancy = 0;
  TextEditingController dropdownHapiStore = TextEditingController();
  TextEditingController dropdownStatus = TextEditingController();
  bool isDealer = true;
  List<DropdownMenuEntry<String>> listDropdownStatus = [];
  List<DropdownMenuEntry<String>> listDropdownStore = [];
  String networkImagePath = '';
  bool sendText = false;
  String simDetails = '';
  TextEditingController txtCashAmount = TextEditingController();
  TextEditingController txtCreditAmount = TextEditingController();
  TextEditingController txtOnlineAmount = TextEditingController();
  TextEditingController txtOrderAmount = TextEditingController();
  TextEditingController txtRemarks = TextEditingController();
  TextEditingController txtReturnAmount = TextEditingController();
  TextEditingController txtSMS = TextEditingController();
  List<KPlacement> listPlacement = [];
  String placementID = '';

  final _formkey = GlobalKey<FormState>();
  DateTime _selectedDate = DateTime.now();

  @override
  void dispose() {
    super.dispose();
    txtOrderAmount.dispose();
    txtCashAmount.dispose();
    txtOnlineAmount.dispose();
    txtCreditAmount.dispose();
    txtReturnAmount.dispose();
    txtRemarks.dispose();
    txtSMS.dispose();
    dropdownStatus.dispose();
    dropdownHapiStore.dispose();
  }

  @override
  void initState() {
    super.initState();
    prefetchData();
  }

  void onSave() async {
    if (isSalesmanLocked) {
      ShowMessage.error(context, 'Editing is disabled. A cash breakdown is already recorded for this day.');
      return;
    }
    if (_formkey.currentState!.validate()) {
      try {
        final newRecord = await _controller.createDelivery(
          context: context,
          storeName: dropdownHapiStore.text,
          orderAmountText: txtOrderAmount.text,
          selectedDate: _selectedDate,
          imageFile: null,
          placements: listPlacement,
          placementId: placementID,
          sendText: sendText,
          smsMessage: txtSMS.text,
        );

        if (mounted) {
          ShowMessage.success(context, 'Successfully created a new delivery record!\n[${newRecord.storeName}]');
          Navigator.pop(context); // go back to previous page
        }
      } catch (e) {
        if (mounted) {
          ShowMessage.error(context, 'Error creating delivery record: $e');
        }
      }
    } else {
      ShowMessage.error(context, 'Please fill up the required fields');
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
      await _checkBreakdownStatus();
    }
  }

  Future<void> _checkBreakdownStatus() async {
    DateTime dateToCheck = widget.deliveryID.isNotEmpty && widget.delivery.deliveryDate != null
        ? widget.delivery.deliveryDate!.toDate()
        : _selectedDate;
    final bool hasBreakdown = await _controller.checkBreakdownStatus(dateToCheck);
    if (mounted) {
      setState(() {
        hasBreakdownForDay = hasBreakdown;
      });
    }
  }

  void prefetchData() async {
    isDealer = await _controller.checkIsDealer();
    await _checkBreakdownStatus();

    if (widget.deliveryID.isNotEmpty) {
      networkImagePath = widget.delivery.imagePath;

      listDropdownStatus = [
        DropdownMenuEntry(label: DeliveryStatus.pending, value: DeliveryStatus.pending),
        DropdownMenuEntry(label: DeliveryStatus.delivered, value: DeliveryStatus.delivered),
        DropdownMenuEntry(label: DeliveryStatus.returned, value: DeliveryStatus.returned),
      ];

      dropdownHapiStore.text = widget.delivery.storeName;
      dropdownStatus.text = widget.delivery.transactionStatus;
      txtRemarks.text = widget.delivery.remarks;
      txtOrderAmount.text = Helperfunctions.formatDoubleAmountForField(widget.delivery.orderAmount);
      txtCashAmount.text = Helperfunctions.formatDoubleAmountForField(widget.delivery.cashAmount);
      txtOnlineAmount.text = Helperfunctions.formatDoubleAmountForField(widget.delivery.onlineAmount);
      txtCreditAmount.text = Helperfunctions.formatDoubleAmountForField(widget.delivery.creditAmount);
      txtReturnAmount.text = Helperfunctions.formatDoubleAmountForField(widget.delivery.returnAmount);

      computeDiscrepancy();
    } else {
      onStoreSelected();
    }

    if (mounted) setState(() {});
  }

  void onUpdate() async {
    if (isSalesmanLocked) {
      ShowMessage.error(context, 'Editing is disabled. A cash breakdown is already recorded for this day.');
      return;
    }
    final listError = _controller.validateDeliveryForm(
      status: dropdownStatus.text,
      orderAmount: widget.delivery.orderAmount,
      cash: txtCashAmount.text,
      online: txtOnlineAmount.text,
      credit: txtCreditAmount.text,
      returnAmount: txtReturnAmount.text,
      remarks: txtRemarks.text,
    );
    if (listError.isEmpty) {
      try {
        final updatedDelivery = await _controller.updateDelivery(
          context: context,
          deliveryId: widget.deliveryID,
          currentDelivery: widget.delivery,
          storeName: dropdownHapiStore.text,
          status: dropdownStatus.text,
          remarks: txtRemarks.text,
          orderAmountText: txtOrderAmount.text,
          cashAmountText: txtCashAmount.text,
          onlineAmountText: txtOnlineAmount.text,
          creditAmountText: txtCreditAmount.text,
          returnAmountText: txtReturnAmount.text,
          imageFile: null,
          networkImagePath: networkImagePath,
        );

        if (mounted) {
          ShowMessage.success(context, 'Successfully updated delivery record!\n[${updatedDelivery.storeName}]');
          Navigator.pop(context); // go back to previous page
        }
      } catch (e) {
        if (mounted) {
          ShowMessage.error(context, 'Error updating delivery record: $e');
        }
      }
    } else {
      if (mounted) ShowMessage.listError(context, listError);
    }
  }

  void onDelete() async {
    try {
      await _controller.deleteDelivery(context: context, deliveryId: widget.deliveryID, delivery: widget.delivery);

      if (mounted) {
        ShowMessage.success(context, 'Successfully deleted a delivery record!\n[${widget.delivery.storeName}]');
        Navigator.pop(context); // go back to previous page
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Error deleting delivery record: $e');
      }
    }
  }

  void onFocusChange(bool hasFocus, TextEditingController controller) {
    if (controller.text.isNotEmpty) {
      if (!hasFocus) {
        computeDiscrepancy();
        setState(() => controller.text = Helperfunctions.formatStringAmountForDisplay(controller.text));
        onStoreSelected();
      } else {
        setState(() => controller.text = Helperfunctions.formatStringAmountForEditing(controller.text));
      }
    } else {
      if (!hasFocus) {
        computeDiscrepancy();
      }
    }
  }

  void computeDiscrepancy() {
    discrepancy = _controller.computeDiscrepancy(
      orderAmount: widget.delivery.orderAmount,
      cash: txtCashAmount.text,
      online: txtOnlineAmount.text,
      credit: txtCreditAmount.text,
      returnAmount: txtReturnAmount.text,
    );
    if (mounted) setState(() {});
  }

  Widget hapistoreDropdown() {
    return HapistorePickerField(
      controller: dropdownHapiStore,
      enabled: isDealer && !isSalesmanLocked,
      label: 'Hapi Store',
      validator: (value) => value == null || value.isEmpty ? 'Please select a Hapi Store' : null,
      onChanged: () {
        onStoreSelected();
      },
    );
  }

  void onStoreSelected() async {
    txtSMS.text = _controller.generateSmsMessage(storeName: dropdownHapiStore.text, formattedOrderAmount: txtOrderAmount.text);

    if (dropdownHapiStore.text.isNotEmpty) {
      final result = await _controller.loadPlacementsForStore(dropdownHapiStore.text);
      if (mounted) {
        setState(() {
          placementID = result.placementId;
          listPlacement = result.placements;
        });
      }
    } else {
      if (mounted) setState(() {});
    }
  }

  Widget _buildSectionCard({required String title, required IconData icon, required Widget child, Widget? trailing}) {
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
                  child: Icon(icon, size: 20, color: colorScheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (trailing != null) ...[const SizedBox(width: 8), trailing],
              ],
            ),
            const Divider(height: 24),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildOrderAndStoreCard() {
    return _buildSectionCard(
      title: 'Order & Store Info',
      icon: Icons.storefront_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          hapistoreDropdown(),
          _buildMoneyField(
            label: 'Order Amount',
            controller: txtOrderAmount,
            prefixIcon: Icons.attach_money,
            iconColor: Colors.blue,
            isEnabled: isDealer && !isSalesmanLocked,
          ),
          if (widget.deliveryID.isEmpty)
            _buildDatePickerField(label: 'Delivery Date', selectedDate: _selectedDate, onTap: isSalesmanLocked ? () {} : onChangeDate)
          else
            _buildDeliveryStatusSelector(),
        ],
      ),
    );
  }

  Widget _buildDeliveryStatusSelector() {
    String rawStatus = dropdownStatus.text.isNotEmpty ? dropdownStatus.text : DeliveryStatus.pending;
    String currentStatus = rawStatus == DeliveryStatus.pendingPicklist ? DeliveryStatus.pending : rawStatus;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Delivery Status',
          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            segments: [
              ButtonSegment<String>(
                value: DeliveryStatus.pending,
                label: const Text(
                  'For Delivery',
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                icon: Icon(
                  Icons.local_shipping_outlined,
                  size: 18,
                  color: currentStatus == DeliveryStatus.pending ? Colors.orange.shade800 : colorScheme.onSurfaceVariant,
                ),
              ),
              ButtonSegment<String>(
                value: DeliveryStatus.delivered,
                label: const Text(
                  DeliveryStatus.delivered,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                icon: Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: currentStatus == DeliveryStatus.delivered ? Colors.green.shade800 : colorScheme.onSurfaceVariant,
                ),
              ),
              ButtonSegment<String>(
                value: DeliveryStatus.returned,
                label: const Text(
                  DeliveryStatus.returned,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                icon: Icon(
                  Icons.assignment_return_outlined,
                  size: 18,
                  color: currentStatus == DeliveryStatus.returned ? Colors.red.shade800 : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            selected: {currentStatus},
            onSelectionChanged: isSalesmanLocked
                ? null
                : (Set<String> newSelection) {
                    setState(() {
                      dropdownStatus.text = newSelection.first;
                    });
                  },
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentBreakdownCard() {
    return _buildSectionCard(
      title: 'Payment Breakdown',
      icon: Icons.payments_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          _buildPaymentSummary(),
          _buildQuickFillChips(),
          _buildMoneyField(
            label: 'Cash Amount',
            controller: txtCashAmount,
            prefixIcon: Icons.payments_outlined,
            iconColor: Colors.green,
            isRequired: false,
            isEnabled: !isSalesmanLocked,
          ),
          _buildMoneyField(
            label: 'Online Amount',
            controller: txtOnlineAmount,
            prefixIcon: Icons.account_balance_outlined,
            iconColor: Colors.blue,
            isRequired: false,
            isEnabled: !isSalesmanLocked,
          ),
          _buildMoneyField(
            label: 'Credit Amount',
            controller: txtCreditAmount,
            prefixIcon: Icons.credit_card_outlined,
            iconColor: Colors.purple,
            isRequired: false,
            isEnabled: !isSalesmanLocked,
          ),
          _buildMoneyField(
            label: 'Return Amount',
            controller: txtReturnAmount,
            prefixIcon: Icons.assignment_return_outlined,
            iconColor: Colors.red,
            isRequired: false,
            isEnabled: !isSalesmanLocked,
          ),
        ],
      ),
    );
  }

  Widget _buildMoneyField({
    required String label,
    required TextEditingController controller,
    required IconData prefixIcon,
    Color? iconColor,
    bool isRequired = true,
    bool isEnabled = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Focus(
      onFocusChange: (hasFocus) => onFocusChange(hasFocus, controller),
      child: TextFormField(
        enabled: isEnabled,
        controller: controller,
        textAlign: TextAlign.end,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
        autovalidateMode: AutovalidateMode.onUnfocus,
        onChanged: (_) => computeDiscrepancy(),
        style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontSize: 15, color: colorScheme.onSurfaceVariant),
          prefixIcon: Icon(prefixIcon, size: 22, color: iconColor ?? colorScheme.primary),
          prefixText: '₱ ',
          prefixStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
        validator: (value) {
          if (isRequired) {
            double amount = Helperfunctions.formatStringAmountToDouble(controller.text);
            if (amount <= 0) return '$label should be greater than 0';
          }
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
            Icon(Icons.calendar_month_outlined, size: 22, color: colorScheme.primary),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant)),
                Text(Helperfunctions.formatDateForDisplay(selectedDate), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
            const Spacer(),
            Icon(Icons.edit_calendar_outlined, size: 20, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickFillChips() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.bolt, size: 18, color: Colors.amber[800]),
            const SizedBox(width: 4),
            Text(
              'Quick-Fill Total Order:',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            spacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.payments_outlined, size: 18),
                label: const Text('Full Cash', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                onPressed: isSalesmanLocked ? null : () => _quickFillPayment(target: 'cash'),
              ),
              ActionChip(
                avatar: const Icon(Icons.account_balance_outlined, size: 18),
                label: const Text('Full Online', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                onPressed: isSalesmanLocked ? null : () => _quickFillPayment(target: 'online'),
              ),
              ActionChip(
                avatar: const Icon(Icons.credit_card_outlined, size: 18),
                label: const Text('Full Credit', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                onPressed: isSalesmanLocked ? null : () => _quickFillPayment(target: 'credit'),
              ),
              ActionChip(
                avatar: const Icon(Icons.restart_alt, size: 18),
                label: const Text('Clear All', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                onPressed: isSalesmanLocked ? null : () => _quickFillPayment(target: 'clear'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _quickFillPayment({required String target}) {
    String formattedOrder = Helperfunctions.formatDoubleAmountForField(widget.delivery.orderAmount);

    setState(() {
      txtCashAmount.text = target == 'cash' ? formattedOrder : '';
      txtOnlineAmount.text = target == 'online' ? formattedOrder : '';
      txtCreditAmount.text = target == 'credit' ? formattedOrder : '';
      txtReturnAmount.text = '';
      computeDiscrepancy();
    });
  }

  Widget _buildPaymentSummary() {
    final colorScheme = Theme.of(context).colorScheme;
    final double totalCollected = _controller.computeTotalCollected(
      cash: txtCashAmount.text,
      online: txtOnlineAmount.text,
      credit: txtCreditAmount.text,
      returnAmount: txtReturnAmount.text,
    );
    double orderAmt = widget.delivery.orderAmount;
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
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Column(
        children: [
          // Live Calculation Grid
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Accounted', style: TextStyle(fontSize: 13.5, color: colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(
                      Helperfunctions.formatDoubleAmountForDisplay(totalCollected),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17.5),
                    ),
                  ],
                ),
              ),
              Container(height: 34, width: 1, color: colorScheme.outlineVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Target Order Amount', style: TextStyle(fontSize: 13.5, color: colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    Text(Helperfunctions.formatDoubleAmountForDisplay(orderAmt), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17.5)),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 18),
          // Status Badge with explanation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(isBalanced ? Icons.check_circle : (isOver ? Icons.error_outline : Icons.warning_amber_rounded), size: 22, color: badgeColor),
                  const SizedBox(width: 6),
                  Text(
                    isBalanced
                        ? 'Balanced'
                        : (isOver
                              ? 'Over by ${Helperfunctions.formatDoubleAmountForDisplay(discrepancy.abs())}'
                              : 'Short by ${Helperfunctions.formatDoubleAmountForDisplay(discrepancy.abs())}'),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5, color: badgeColor),
                  ),
                ],
              ),
              if (!isBalanced)
                Text(
                  isOver ? 'Overpaid' : 'Unsettled',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: badgeColor),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRemarksCard() {
    return _buildSectionCard(
      title: 'Remarks & Return Details',
      icon: Icons.note_alt_outlined,
      child: _buildTextAreaField(
        label: 'Remarks',
        controller: txtRemarks,
        prefixIcon: Icons.notes_outlined,
        minLines: 3,
        isEnabled: !isSalesmanLocked,
        isRequired:
            (dropdownStatus.text == DeliveryStatus.returned || (dropdownStatus.text == DeliveryStatus.delivered && txtReturnAmount.text.isNotEmpty)),
      ),
    );
  }

  Widget _buildTextAreaField({
    required String label,
    required TextEditingController controller,
    required IconData prefixIcon,
    int minLines = 3,
    bool isRequired = true,
    bool isEnabled = true,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextFormField(
      enabled: isEnabled,
      controller: controller,
      keyboardType: TextInputType.multiline,
      minLines: minLines,
      maxLines: null,
      style: const TextStyle(fontSize: 15.5),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: 15, color: colorScheme.onSurfaceVariant),
        alignLabelWithHint: true,
        prefixIcon: Icon(prefixIcon, size: 22, color: colorScheme.primary),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      autovalidateMode: AutovalidateMode.onUnfocus,
      validator: (value) {
        if (isRequired && (value == null || value.trim().isEmpty)) return '$label should not be blank';
        return null;
      },
    );
  }

  Widget _buildSmsCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return _buildSectionCard(
      title: 'SMS Notification',
      icon: Icons.sms_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
            ),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Send Text Message?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5)),
              subtitle: const Text('Notify store contact about the pending order', style: TextStyle(fontSize: 13.5)),
              value: sendText,
              onChanged: isSalesmanLocked ? null : (val) => setState(() => sendText = val),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: sendText
                ? Padding(
                    padding: const EdgeInsets.only(top: 14.0),
                    child: _buildTextAreaField(
                      label: 'Text Message',
                      controller: txtSMS,
                      prefixIcon: Icons.message_outlined,
                      minLines: 4,
                      isEnabled: !isSalesmanLocked,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
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
        child: widget.deliveryID.isEmpty
            ? FilledButton.icon(
                onPressed: isSalesmanLocked
                    ? null
                    : () async {
                        final confirmed = await ShowMessage.confirm(
                          context,
                          title: ConfirmTitle.save,
                          message: ConfirmMessage.save,
                          icon: Icons.save_outlined,
                          confirmText: 'Save',
                        );
                        if (confirmed) onSave();
                      },
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50.0),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: Icon(isSalesmanLocked ? Icons.lock_outline : Icons.save_outlined),
                label: Text(
                  isSalesmanLocked ? 'Locked (Breakdown Recorded)' : 'Save Delivery Record',
                  style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold),
                ),
              )
            : Row(
                children: [
                  if (isDealer) ...[
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final confirmed = await ShowMessage.confirm(
                            context,
                            title: ConfirmTitle.delete,
                            message: ConfirmMessage.delete,
                            isDestructive: true,
                            icon: Icons.delete_outline,
                            confirmText: 'Delete',
                          );
                          if (confirmed) onDelete();
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          minimumSize: const Size(0, 50.0),
                          foregroundColor: Colors.red.shade700,
                          side: BorderSide(color: Colors.red.shade300, width: 1.2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.delete_outline, size: 20),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Delete',
                            maxLines: 1,
                            softWrap: false,
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    flex: isDealer ? 3 : 1,
                    child: FilledButton.icon(
                      onPressed: isSalesmanLocked
                          ? null
                          : () async {
                              final confirmed = await ShowMessage.confirm(
                                context,
                                title: ConfirmTitle.update,
                                message: ConfirmMessage.update,
                                icon: Icons.check_circle_outline,
                                confirmText: 'Update',
                              );
                              if (confirmed) onUpdate();
                            },
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 50.0),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: Icon(isSalesmanLocked ? Icons.lock_outline : Icons.check_circle_outline, size: 22),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          isSalesmanLocked ? 'Locked (Breakdown Recorded)' : 'Update Delivery',
                          maxLines: 1,
                          softWrap: false,
                          style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildPlacementCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final placedCount = listPlacement.where((placement) => placement.isPlaced).length;
    final unplacedCount = listPlacement.where((placement) => !placement.isPlaced).length;

    return _buildSectionCard(
      title: 'Placement Checklist',
      icon: Icons.inventory_2_outlined,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: (placedCount == 12 ? colorScheme.primary : colorScheme.onSurfaceVariant).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '$placedCount/12 placed',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: placedCount == 12 ? colorScheme.primary : colorScheme.onSurfaceVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: listPlacement.isEmpty ? 0 : placedCount / listPlacement.length,
                      minHeight: 6,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      color: placedCount == 12 ? Colors.green : colorScheme.primary,
                    ),
                  ),
                ),
                if (unplacedCount > 0) ...[
                  const SizedBox(width: 10),
                  FilledButton.tonalIcon(
                    onPressed: isSalesmanLocked
                        ? null
                        : () {
                            setState(() {
                              for (var placement in listPlacement) {
                                placement.isPlaced = true;
                              }
                            });
                          },
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    ),
                    icon: const Icon(Icons.done_all_rounded, size: 16),
                    label: const Text('Place All', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: listPlacement.length,
            separatorBuilder: (_, _) => Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            itemBuilder: (context, index) {
              final item = listPlacement[index];
              final isPlaced = item.isPlaced;
              final isLocked = item.isPlacedFromDB;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(
                  color: isLocked
                      ? colorScheme.primary.withValues(alpha: 0.08)
                      : (isPlaced ? colorScheme.primary.withValues(alpha: 0.04) : Colors.transparent),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isLocked
                        ? colorScheme.primary.withValues(alpha: 0.35)
                        : (isPlaced ? colorScheme.primary.withValues(alpha: 0.2) : Colors.transparent),
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  onTap: isSalesmanLocked
                      ? null
                      : (isLocked
                            ? () => ShowMessage.error(context, '${item.itemName} is already placed for this month.')
                            : () => setState(() => item.isPlaced = !item.isPlaced)),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      item.itemImagePath,
                      width: 60,
                      height: 50,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        width: 60,
                        height: 50,
                        color: colorScheme.surfaceContainerHighest,
                        child: Icon(Icons.image_outlined, color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                  title: Text(item.itemName, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    isLocked ? 'Locked (saved in DB)' : (isPlaced ? 'Placed and ready' : 'Pending placement'),
                    style: TextStyle(fontSize: 13, color: isPlaced ? colorScheme.primary : colorScheme.onSurfaceVariant),
                  ),
                  trailing: isLocked
                      ? Icon(Icons.lock_outline, size: 20, color: colorScheme.primary)
                      : Checkbox(
                          value: isPlaced,
                          activeColor: colorScheme.primary,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          onChanged: isSalesmanLocked
                              ? null
                              : (value) {
                                  setState(() {
                                    item.isPlaced = value ?? false;
                                  });
                                },
                        ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDelivered = dropdownStatus.text == DeliveryStatus.delivered;
    bool isReturned = dropdownStatus.text == DeliveryStatus.returned;
    bool showRemarks = isReturned || (isDelivered && txtReturnAmount.text.isNotEmpty);

    return Scaffold(
      appBar: CustomAppbar(
        title: 'Delivery',
        subtitle: widget.deliveryID.isEmpty ? 'New Record' : widget.delivery.storeName,
        actions: [
          if (widget.delivery.items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.receipt_long_rounded, color: Colors.white),
              tooltip: 'Digital Receipt & Thermal Print',
              onPressed: () => DigitalReceiptDialog.show(
                context,
                delivery: widget.delivery,
                deliveryId: widget.deliveryID,
                proceedLabel: 'Close',
              ),
            ),
        ],
      ),
      bottomNavigationBar: _buildStickyBottomBar(),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Form(
            key: _formkey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 16,
              children: [
                if (isSalesmanLocked)
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
                        Icon(Icons.lock_outline, color: Colors.amber.shade900, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'View-Only: A cash breakdown for this date has already been recorded. Salesmen cannot edit delivery records for this day.',
                            style: TextStyle(fontSize: 14.5, color: Colors.amber.shade900, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),

                if (widget.delivery.transactionStatus == DeliveryStatus.pendingPicklist && widget.deliveryID.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.fact_check_outlined, color: Color(0xFF7C3AED), size: 24),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'This order is still Pending Picklist.',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ),
                        FilledButton.tonal(
                          onPressed: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PicklistPage(
                                  deliveryID: widget.deliveryID,
                                  delivery: widget.delivery,
                                ),
                              ),
                            );
                          },
                          child: const Text('Open Picklist', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),

                // 1. Order & Store Info Card
                _buildOrderAndStoreCard(),

                // 2. Payment Breakdown Card (Animated for Delivered status)
                if (widget.deliveryID.isNotEmpty)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: isDelivered ? _buildPaymentBreakdownCard() : const SizedBox.shrink(),
                  ),

                // 3. Remarks Card (Animated for Returned or Delivered with return amount)
                if (widget.deliveryID.isNotEmpty)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    child: showRemarks ? _buildRemarksCard() : const SizedBox.shrink(),
                  ),

                // 4. Placement Card
                if (widget.deliveryID.isEmpty && dropdownHapiStore.text.isNotEmpty) _buildPlacementCard(),

                // 5. SMS Notification Card (when creating new delivery)
                if (widget.deliveryID.isEmpty) _buildSmsCard(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
