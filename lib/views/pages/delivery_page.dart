import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/models/delivery.dart';
import 'package:flutter_app/models/hapistore.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/delivery_service.dart';
import 'package:flutter_app/services/hapistore_service.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:flutter_app/views/widgets/imageviewer_page.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:another_telephony/telephony.dart';
import 'package:intl/intl.dart';

class DeliveryPage extends StatefulWidget {
  const DeliveryPage({super.key, required this.deliveryID, required this.delivery});

  final String deliveryID;
  final Delivery delivery;

  @override
  State<DeliveryPage> createState() => _DeliveryPageState();
}

class _DeliveryPageState extends State<DeliveryPage> {
  final DeliveryService db = DeliveryService();
  TextEditingController txtOrderAmount = TextEditingController();
  TextEditingController txtCashAmount = TextEditingController();
  TextEditingController txtOnlineAmount = TextEditingController();
  TextEditingController txtCreditAmount = TextEditingController();
  TextEditingController txtReturnAmount = TextEditingController();
  TextEditingController txtRemarks = TextEditingController();
  TextEditingController txtSMS = TextEditingController();
  TextEditingController dropdownStatus = TextEditingController();
  TextEditingController dropdownHapiStore = TextEditingController();
  DateTime _selectedDate = DateTime.now();

  List<DropdownMenuEntry<String>> listDropdownStatus = [];
  List<DropdownMenuEntry<String>> listDropdownStore = [];
  double discrepancy = 0;
  bool isDealer = true;
  final _formkey = KVariables.formkey;
  File? image;
  final picker = ImagePicker();
  String networkImagePath = '';
  bool sendText = false;
  String simDetails = '';

  @override
  Widget build(BuildContext context) {
    bool isDelivered = dropdownStatus.text == DeliveryStatus.delivered;
    bool isReturned = dropdownStatus.text == DeliveryStatus.returned;
    bool showRemarks = isReturned || (isDelivered && txtReturnAmount.text.isNotEmpty);

    return Scaffold(
      appBar: CustomAppbar(title: 'Delivery', subtitle: widget.deliveryID.isEmpty ? 'New Record' : widget.delivery.storeName),
      bottomNavigationBar: _buildStickyBottomBar(),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Form(
            key: _formkey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 16,
              children: [
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

                // 4. Receipt & Documents Card
                _buildReceiptCard(),

                // 5. SMS Notification Card (when creating new delivery)
                if (widget.deliveryID.isEmpty) _buildSmsCard(),

                // 6. Audit & History Card (when updating existing record)
                if (widget.deliveryID.isNotEmpty) _buildAuditCard(),
              ],
            ),
          ),
        ),
      ),
    );
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
                  child: Icon(icon, size: 18, color: colorScheme.primary),
                ),
                const SizedBox(width: 10),
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                if (trailing != null) ...[const Spacer(), trailing],
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
            isEnabled: isDealer,
          ),
          if (widget.deliveryID.isEmpty)
            _buildDatePickerField(label: 'Delivery Date', selectedDate: _selectedDate, onTap: onChangeDate)
          else
            _buildDeliveryStatusSelector(),
        ],
      ),
    );
  }

  Widget _buildDeliveryStatusSelector() {
    String currentStatus = dropdownStatus.text.isNotEmpty ? dropdownStatus.text : DeliveryStatus.pending;
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Delivery Status',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            segments: [
              ButtonSegment<String>(
                value: DeliveryStatus.pending,
                label: const Text(DeliveryStatus.pending, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                icon: Icon(
                  Icons.pending_actions,
                  size: 18,
                  color: currentStatus == DeliveryStatus.pending ? Colors.orange.shade800 : colorScheme.onSurfaceVariant,
                ),
              ),
              ButtonSegment<String>(
                value: DeliveryStatus.delivered,
                label: const Text(DeliveryStatus.delivered, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                icon: Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: currentStatus == DeliveryStatus.delivered ? Colors.green.shade800 : colorScheme.onSurfaceVariant,
                ),
              ),
              ButtonSegment<String>(
                value: DeliveryStatus.returned,
                label: const Text(DeliveryStatus.returned, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                icon: Icon(
                  Icons.assignment_return_outlined,
                  size: 18,
                  color: currentStatus == DeliveryStatus.returned ? Colors.red.shade800 : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            selected: {currentStatus},
            onSelectionChanged: (Set<String> newSelection) {
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
          ),
          _buildMoneyField(
            label: 'Online Amount',
            controller: txtOnlineAmount,
            prefixIcon: Icons.account_balance_outlined,
            iconColor: Colors.blue,
            isRequired: false,
          ),
          _buildMoneyField(
            label: 'Credit Amount',
            controller: txtCreditAmount,
            prefixIcon: Icons.credit_card_outlined,
            iconColor: Colors.purple,
            isRequired: false,
          ),
          _buildMoneyField(
            label: 'Return Amount',
            controller: txtReturnAmount,
            prefixIcon: Icons.assignment_return_outlined,
            iconColor: Colors.red,
            isRequired: false,
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
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(prefixIcon, size: 20, color: iconColor ?? colorScheme.primary),
          prefixText: '₱ ',
          prefixStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
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

  Widget _buildQuickFillChips() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.bolt, size: 16, color: Colors.amber[800]),
            const SizedBox(width: 4),
            Text(
              'Quick-Fill Total Order:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
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
                avatar: const Icon(Icons.payments_outlined, size: 16),
                label: const Text('Full Cash'),
                onPressed: () => _quickFillPayment(target: 'cash'),
              ),
              ActionChip(
                avatar: const Icon(Icons.account_balance_outlined, size: 16),
                label: const Text('Full Online'),
                onPressed: () => _quickFillPayment(target: 'online'),
              ),
              ActionChip(
                avatar: const Icon(Icons.credit_card_outlined, size: 16),
                label: const Text('Full Credit'),
                onPressed: () => _quickFillPayment(target: 'credit'),
              ),
              ActionChip(
                avatar: const Icon(Icons.restart_alt, size: 16),
                label: const Text('Clear All'),
                onPressed: () => _quickFillPayment(target: 'clear'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _quickFillPayment({required String target}) {
    String formattedOrder = widget.delivery.orderAmount == 0 ? '' : Helperfunctions.formatDoubleAmountForDisplay(widget.delivery.orderAmount);

    setState(() {
      txtCashAmount.text = target == 'cash' ? formattedOrder : '';
      txtOnlineAmount.text = target == 'online' ? formattedOrder : '';
      txtCreditAmount.text = target == 'credit' ? formattedOrder : '';
      txtReturnAmount.text = '';
      computeDiscrepancy();
    });
  }

  Widget _buildPaymentSummary() {
    Decimal cashAmount = Helperfunctions.formatStringAmountToDecimal(txtCashAmount.text);
    Decimal onlineAmount = Helperfunctions.formatStringAmountToDecimal(txtOnlineAmount.text);
    Decimal creditAmount = Helperfunctions.formatStringAmountToDecimal(txtCreditAmount.text);
    Decimal returnAmount = Helperfunctions.formatStringAmountToDecimal(txtReturnAmount.text);
    Decimal totalCollected = cashAmount + onlineAmount + creditAmount + returnAmount;
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
                    const Text('Total Accounted', style: TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 2),
                    Text(
                      Helperfunctions.formatDoubleAmountForDisplay(totalCollected.toDouble()),
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
                    const Text('Target Order Amount', style: TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 2),
                    Text(Helperfunctions.formatDoubleAmountForDisplay(orderAmt), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                  isOver ? 'Overpaid' : 'Unsettled',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: badgeColor),
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
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.multiline,
      minLines: minLines,
      maxLines: null,
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: true,
        prefixIcon: Icon(prefixIcon, size: 20, color: colorScheme.primary),
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

  Widget _buildReceiptCard() {
    final colorScheme = Theme.of(context).colorScheme;
    bool hasImageData = image != null || networkImagePath.isNotEmpty;

    Future<void> startScan() async {
      ImageScanResult? scannedData;
      try {
        scannedData = await FlutterDocScanner().getScannedDocumentAsImages(page: 1);
      } on PlatformException catch (e) {
        scannedData = null;
        if (mounted) {
          ShowMessage.error(context, e.message ?? 'There was an error upon scanning a document');
        }
      }

      if (scannedData != null && scannedData.images.isNotEmpty) {
        String filepath = scannedData.images.first.replaceFirst('file://', '');
        scanDocs(File(filepath.toString()));
      }
    }

    return _buildSectionCard(
      title: 'Receipt & Documents',
      icon: Icons.receipt_long_outlined,
      child: hasImageData
          ? Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      height: 200,
                      width: double.infinity,
                      decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(10)),
                      child: image != null
                          ? Image.file(image!, fit: BoxFit.cover)
                          : Image.network(
                              networkImagePath,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return const Center(child: CircularProgressIndicator());
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.spaceEvenly,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => Helperfunctions.navigateTo(context, ImageViewerPage(image: image, networkImagePath: networkImagePath)),
                        icon: const Icon(Icons.fullscreen, size: 18),
                        label: const Text('View Fullscreen'),
                      ),
                      if (isDealer) ...[
                        OutlinedButton.icon(onPressed: startScan, icon: const Icon(Icons.replay, size: 18), label: const Text('Retake / Replace')),
                        OutlinedButton.icon(
                          onPressed: () => scanDocs(null),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade700,
                            side: BorderSide(color: Colors.red.shade300),
                          ),
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Delete Receipt'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            )
          : InkWell(
              onTap: isDealer ? startScan : null,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant, width: 1.2),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                      child: Icon(Icons.document_scanner_outlined, size: 32, color: colorScheme.primary),
                    ),
                    const SizedBox(height: 10),
                    const Text('Tap to scan or attach receipt', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Scan receipt document for order verification', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
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
              title: const Text('Send Text Message?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: const Text('Notify store contact about the pending order', style: TextStyle(fontSize: 12)),
              value: sendText,
              onChanged: (val) => setState(() => sendText = val),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: sendText
                ? Padding(
                    padding: const EdgeInsets.only(top: 14.0),
                    child: _buildTextAreaField(label: 'Text Message', controller: txtSMS, prefixIcon: Icons.message_outlined, minLines: 4),
                  )
                : const SizedBox.shrink(),
          ),
        ],
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
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 1),
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
                _buildAuditRow('Created By', widget.delivery.createdBy),
                _buildAuditRow('Created Date', DateFormat('E, d MMM yyyy, hh:mm a').format(widget.delivery.createdDate.toDate())),
                const Divider(height: 12),
                _buildAuditRow('Last Updated By', widget.delivery.lastUpdatedBy),
                _buildAuditRow('Last Updated Date', DateFormat('E, d MMM yyyy, hh:mm a').format(widget.delivery.lastupdatedDate.toDate())),
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
                onPressed: () async {
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
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save Delivery Record', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              )
            : Row(
                children: [
                  if (isDealer) ...[
                    Expanded(
                      flex: 1,
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
                    flex: isDealer ? 2 : 1,
                    child: FilledButton.icon(
                      onPressed: () async {
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
                        minimumSize: const Size(0, 50.0),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.check_circle_outline, size: 20),
                      label: const Text('Update Delivery', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void onSave() async {
    if (_formkey.currentState!.validate()) {
      // save image
      String imageFilePath = '';
      if (image != null) {
        imageFilePath = await Helperfunctions.saveImage(context, image!);
      }

      Delivery newRecord = Delivery(
        storeName: dropdownHapiStore.text,
        remarks: '',
        transactionStatus: DeliveryStatus.pending,
        imagePath: imageFilePath,
        orderAmount: Helperfunctions.formatStringAmountToDouble(txtOrderAmount.text),
        returnAmount: 0,
        creditAmount: 0,
        cashAmount: 0,
        onlineAmount: 0,
        deliveryDate: Timestamp.fromDate(_selectedDate),
        creditStatus: CreditStatus.unpaid,
        createdBy: authService.value.currentUser!.displayName!,
        lastUpdatedBy: authService.value.currentUser!.displayName!,
        createdDate: Timestamp.now(),
        lastupdatedDate: Timestamp.now(),
      );
      db.addDelivery(newRecord);

      // log transaction
      await Helperfunctions.logTransaction(
        dropdownHapiStore.text,
        'Order Amount: ${Helperfunctions.formatDoubleAmountForDisplay(newRecord.orderAmount)}',
        LogAction.create,
      );

      // send text message to the store if user opted to send a text message
      if (sendText) {
        String storeContact = await HapiStoreService.getContactByStoreName(dropdownHapiStore.text);
        storeContact = storeContact.replaceFirst('09', '+639');

        final Telephony telephony = Telephony.instance;
        bool? permissionsGranted = await telephony.requestPhoneAndSmsPermissions;

        if (permissionsGranted ?? false) {
          telephony.sendSms(to: storeContact, message: txtSMS.text, isMultipart: true);
        }
      }

      if (mounted) {
        ShowMessage.success(context, 'Successfully created a new delivery record!\n[${dropdownHapiStore.text}]');
        Navigator.pop(context); // go back to previous page
      }

      setState(() {});
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
    }
  }

  void prefetchData() async {
    if (widget.deliveryID.isNotEmpty) {
      isDealer = await KVariables.getIsDealer();
      networkImagePath = widget.delivery.imagePath;

      listDropdownStatus = [
        DropdownMenuEntry(label: DeliveryStatus.pending, value: DeliveryStatus.pending),
        DropdownMenuEntry(label: DeliveryStatus.delivered, value: DeliveryStatus.delivered),
        DropdownMenuEntry(label: DeliveryStatus.returned, value: DeliveryStatus.returned),
      ];

      dropdownHapiStore.text = widget.delivery.storeName;
      dropdownStatus.text = widget.delivery.transactionStatus;
      txtRemarks.text = widget.delivery.remarks;
      txtOrderAmount.text = widget.delivery.orderAmount == 0 ? '' : Helperfunctions.formatDoubleAmountForDisplay(widget.delivery.orderAmount);
      txtCashAmount.text = widget.delivery.cashAmount == 0 ? '' : Helperfunctions.formatDoubleAmountForDisplay(widget.delivery.cashAmount);
      txtOnlineAmount.text = widget.delivery.onlineAmount == 0 ? '' : Helperfunctions.formatDoubleAmountForDisplay(widget.delivery.onlineAmount);
      txtCreditAmount.text = widget.delivery.creditAmount == 0 ? '' : Helperfunctions.formatDoubleAmountForDisplay(widget.delivery.creditAmount);
      txtReturnAmount.text = widget.delivery.returnAmount == 0 ? '' : Helperfunctions.formatDoubleAmountForDisplay(widget.delivery.returnAmount);

      computeDiscrepancy();
    } else {
      composeSMS();
    }

    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    prefetchData();
  }

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

  List<String> validate() {
    List<String> listError = [];
    Decimal cashAmount = Helperfunctions.formatStringAmountToDecimal(txtCashAmount.text);
    Decimal onlineAmount = Helperfunctions.formatStringAmountToDecimal(txtOnlineAmount.text);
    Decimal creditAmount = Helperfunctions.formatStringAmountToDecimal(txtCreditAmount.text);
    Decimal returnAmount = Helperfunctions.formatStringAmountToDecimal(txtReturnAmount.text);

    Decimal totalAmount = cashAmount + onlineAmount + creditAmount + returnAmount;
    Decimal orderAmount = Decimal.parse(widget.delivery.orderAmount.toString());

    if (dropdownStatus.text == DeliveryStatus.delivered && totalAmount != orderAmount) {
      listError.add('Total amount does not match the order amount!');
    }
    if ((returnAmount != Decimal.zero || dropdownStatus.text == DeliveryStatus.returned) && txtRemarks.text.isEmpty) {
      listError.add('Please enter a remark for return details!');
    }

    return listError;
  }

  void onUpdate() async {
    var listError = validate();
    if (listError.isEmpty) {
      double returnAmount = 0;
      double creditAmount = 0;
      double onlineAmount = 0;
      double cashAmount = 0;
      String remark = txtRemarks.text;

      switch (dropdownStatus.text) {
        case DeliveryStatus.pending:
          widget.delivery.orderAmount = Helperfunctions.formatStringAmountToDouble(txtOrderAmount.text);
          remark = '';
          break;

        case DeliveryStatus.delivered:
          returnAmount = Helperfunctions.formatStringAmountToDouble(txtReturnAmount.text);
          creditAmount = Helperfunctions.formatStringAmountToDouble(txtCreditAmount.text);
          onlineAmount = Helperfunctions.formatStringAmountToDouble(txtOnlineAmount.text);
          cashAmount = Helperfunctions.formatStringAmountToDouble(txtCashAmount.text);
          break;

        case DeliveryStatus.returned:
          returnAmount = widget.delivery.orderAmount;
          break;
        default:
      }

      // update image data
      String imageFilePath = await Helperfunctions.updateImage(context, image, networkImagePath, widget.delivery.imagePath);

      Delivery updatedDelivery = widget.delivery.copyWith(
        storeName: dropdownHapiStore.text,
        remarks: remark,
        transactionStatus: dropdownStatus.text,
        imagePath: imageFilePath,
        orderAmount: widget.delivery.orderAmount,
        returnAmount: returnAmount,
        creditAmount: creditAmount,
        cashAmount: cashAmount,
        onlineAmount: onlineAmount,
        deliveryDate: widget.delivery.deliveryDate,
        createdBy: widget.delivery.createdBy,
        lastUpdatedBy: authService.value.currentUser!.displayName!,
        createdDate: widget.delivery.createdDate,
        lastupdatedDate: Timestamp.now(),
      );
      db.updateDelivery(widget.deliveryID, updatedDelivery);

      // log transaction
      await Helperfunctions.logTransaction(
        dropdownHapiStore.text,
        'Status: ${updatedDelivery.transactionStatus}\nOrder Amount: ${Helperfunctions.formatDoubleAmountForDisplay(updatedDelivery.orderAmount)}',
        LogAction.update,
      );

      if (mounted) {
        ShowMessage.success(context, 'Successfully updated delivery record!\n[${widget.delivery.storeName}]');
        Navigator.pop(context); // go back to previous page
      }

      setState(() {});
    } else {
      if (mounted) ShowMessage.listError(context, listError);
    }
  }

  void onDelete() async {
    if (widget.delivery.imagePath.isNotEmpty) {
      await Helperfunctions.deleteImage(context, widget.delivery.imagePath);
    }
    db.deleteDelivery(widget.deliveryID);

    // log transaction
    await Helperfunctions.logTransaction(
      dropdownHapiStore.text,
      'Order Amount: ${Helperfunctions.formatDoubleAmountForDisplay(widget.delivery.orderAmount)}',
      LogAction.delete,
    );

    if (mounted) {
      ShowMessage.success(context, 'Successfully deleted a delivery record!\n[${widget.delivery.storeName}]');
      Navigator.pop(context); // go back to previous page
    }

    setState(() {});
  }

  void onFocusChange(bool hasFocus, TextEditingController controller) {
    if (controller.text.isNotEmpty) {
      if (!hasFocus) {
        computeDiscrepancy();
        setState(() => controller.text = Helperfunctions.formatStringAmountForDisplay(controller.text));
        composeSMS();
      } else {
        setState(() => controller.text = Helperfunctions.formatStringAmountForEditing(controller.text));
      }
    } else {
      if (!hasFocus) {
        setState(() => computeDiscrepancy());
      }
    }
  }

  void computeDiscrepancy() {
    Decimal cashAmount = Helperfunctions.formatStringAmountToDecimal(txtCashAmount.text);
    Decimal onlineAmount = Helperfunctions.formatStringAmountToDecimal(txtOnlineAmount.text);
    Decimal creditAmount = Helperfunctions.formatStringAmountToDecimal(txtCreditAmount.text);
    Decimal returnAmount = Helperfunctions.formatStringAmountToDecimal(txtReturnAmount.text);

    Decimal totalAmount = cashAmount + onlineAmount + creditAmount + returnAmount;
    Decimal orderAmount = Decimal.parse(widget.delivery.orderAmount.toString());

    discrepancy = (totalAmount - orderAmount).toDouble();

    setState(() {});
  }

  Widget hapistoreDropdown() {
    final HapiStoreService dbHS = HapiStoreService();
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
          controller: dropdownHapiStore,
          enabled: isDealer,
          initialSelection: dropdownHapiStore.text,
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
          onSelected: (String? newValue) {
            composeSMS();
          },
        );
      },
    );
  }

  void scanDocs(File? scannedImage) {
    setState(() {
      networkImagePath = '';
      scannedImage == null ? image = null : image = scannedImage;
    });
  }

  void composeSMS() async {
    txtSMS.text =
        '[SELECTA DELIVERY]\n\nGood day ${dropdownHapiStore.text}! This is to confirm that your order worth (${txtOrderAmount.text}) is now pending for delivery.\n\nPlease expect your stocks to arrive in a few hours. Thank you for choosing Selecta Ice Cream. Have a sweet day!';
  }
}
