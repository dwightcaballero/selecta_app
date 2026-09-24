import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/purchaseorder.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/purchaseorder_service.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:flutter_app/views/widgets/imageviewer_page.dart';
import 'package:flutter_doc_scanner/flutter_doc_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

class PurchaseorderPage extends StatefulWidget {
  const PurchaseorderPage({super.key, required this.purchaseorderID, required this.purchaseorder});

  final Purchaseorder purchaseorder;
  final String purchaseorderID;

  @override
  State<PurchaseorderPage> createState() => _PurchaseorderPageState();
}

class _PurchaseorderPageState extends State<PurchaseorderPage> {
  final PurchaseOrderService db = PurchaseOrderService();
  final TextEditingController invoiceAmountController = TextEditingController();
  final TextEditingController orderAmountController = TextEditingController();
  final TextEditingController orderNumberController = TextEditingController();

  bool isNewRecord = false;
  String networkImagePath = '';
  final _formKey = GlobalKey<FormState>();
  File? _pickedImage;
  final ImagePicker _picker = ImagePicker();
  DateTime _selectedInvoiceDate = DateTime.now();
  DateTime _selectedOrderDate = DateTime.now();

  @override
  void dispose() {
    orderAmountController.dispose();
    orderNumberController.dispose();
    invoiceAmountController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    isNewRecord = widget.purchaseorderID.isEmpty;

    if (!isNewRecord) {
      orderNumberController.text = widget.purchaseorder.invoiceNumber;
      orderAmountController.text = Helperfunctions.formatDoubleAmountForField(widget.purchaseorder.orderAmount);
      invoiceAmountController.text = Helperfunctions.formatDoubleAmountForField(widget.purchaseorder.invoiceAmount);
      _selectedOrderDate = widget.purchaseorder.orderDate.toDate();
      // Fix: correctly restore saved invoice date
      _selectedInvoiceDate = widget.purchaseorder.invoiceDate.toDate();
      networkImagePath = widget.purchaseorder.imagePath;
    }
  }

  double get _currentOrderAmount {
    if (isNewRecord) {
      return Helperfunctions.formatStringAmountToDouble(orderAmountController.text);
    }
    return widget.purchaseorder.orderAmount;
  }

  double get _currentInvoiceAmount {
    return Helperfunctions.formatStringAmountToDouble(invoiceAmountController.text);
  }


  Future<void> pickImage(ImageSource? source) async {
    if (source == null) {
      setState(() {
        _pickedImage = null;
        networkImagePath = '';
      });
      return;
    }

    final XFile? pickedFile = await _picker.pickImage(source: source);
    if (pickedFile != null) {
      setState(() {
        _pickedImage = File(pickedFile.path);
        networkImagePath = '';
      });
    }
  }

  void onSave() async {
    if (_formKey.currentState!.validate()) {
      String imageFilePath = '';
      if (_pickedImage != null) {
        imageFilePath = await Helperfunctions.saveImage(context, _pickedImage!);
      }

      final newPurchaseorder = Purchaseorder(
        invoiceNumber: '',
        orderAmount: Helperfunctions.formatStringAmountToDouble(orderAmountController.text),
        orderDate: Timestamp.fromDate(_selectedOrderDate),
        overpayment: 0,
        isSettled: null,
        createdBy: authService.value.currentUser?.displayName ?? 'User',
        lastUpdatedBy: authService.value.currentUser?.displayName ?? 'User',
        createdDate: Timestamp.now(),
        lastupdatedDate: Timestamp.now(),
        invoiceAmount: 0,
        imagePath: imageFilePath,
        invoiceDate: Timestamp.fromDate(_selectedInvoiceDate),
      );

      db.addPurchaseorder(newPurchaseorder);
      await Helperfunctions.logCreate(
        Helperfunctions.formatTimestampForDisplay(newPurchaseorder.orderDate),
        newPurchaseorder.toJson(),
      );

      if (mounted) {
        ShowMessage.success(context, 'Purchase order saved successfully!');
        Navigator.pop(context);
      }
    }
  }

  void onUpdate() async {
    if (_formKey.currentState!.validate()) {
      final double invoiceAmount = Helperfunctions.formatStringAmountToDouble(invoiceAmountController.text);
      final double overpayment = widget.purchaseorder.orderAmount - invoiceAmount;

      if (invoiceAmount > widget.purchaseorder.orderAmount) {
        ShowMessage.error(context, 'Invoice amount cannot exceed the order amount.');
        return;
      }

      final String imageFilePath = await Helperfunctions.updateImage(
        context,
        _pickedImage,
        networkImagePath,
        widget.purchaseorder.imagePath,
      );

      final updatedPurchaseorder = Purchaseorder(
        invoiceNumber: orderNumberController.text.trim().toUpperCase(),
        orderAmount: widget.purchaseorder.orderAmount,
        orderDate: Timestamp.fromDate(_selectedOrderDate),
        overpayment: overpayment > 0 ? overpayment : 0,
        isSettled: overpayment > 0 ? (widget.purchaseorder.isSettled ?? false) : null,
        createdBy: widget.purchaseorder.createdBy,
        lastUpdatedBy: authService.value.currentUser?.displayName ?? 'User',
        createdDate: widget.purchaseorder.createdDate,
        lastupdatedDate: Timestamp.now(),
        invoiceAmount: invoiceAmount,
        imagePath: imageFilePath,
        invoiceDate: Timestamp.fromDate(_selectedInvoiceDate),
      );

      db.updatePurchaseorder(widget.purchaseorderID, updatedPurchaseorder);
      await Helperfunctions.logUpdate(
        updatedPurchaseorder.invoiceNumber.isNotEmpty
            ? updatedPurchaseorder.invoiceNumber
            : Helperfunctions.formatTimestampForDisplay(updatedPurchaseorder.orderDate),
        widget.purchaseorder.toJson(),
        updatedPurchaseorder.toJson(),
      );

      if (mounted) {
        ShowMessage.success(context, 'Purchase order updated successfully!');
        Navigator.pop(context);
      }
    }
  }

  void onDelete() async {
    if (widget.purchaseorder.imagePath.isNotEmpty) {
      await Helperfunctions.deleteImage(context, widget.purchaseorder.imagePath);
    }

    db.deletePurchaseorder(widget.purchaseorderID);
    await Helperfunctions.logDelete(
      widget.purchaseorder.invoiceNumber.isNotEmpty
          ? widget.purchaseorder.invoiceNumber
          : Helperfunctions.formatTimestampForDisplay(widget.purchaseorder.orderDate),
      widget.purchaseorder.toJson(),
    );

    if (mounted) {
      ShowMessage.success(context, 'Purchase order deleted successfully!');
      Navigator.pop(context);
    }
  }

  Future<void> onChangeDate() async {
    final dateTime = await showDatePicker(
      context: context,
      initialDate: _selectedOrderDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(3000),
    );

    if (dateTime != null) {
      setState(() => _selectedOrderDate = dateTime);
    }
  }

  Future<void> onChangeInvoiceDate() async {
    final dateTime = await showDatePicker(
      context: context,
      initialDate: _selectedInvoiceDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(3000),
    );

    if (dateTime != null) {
      setState(() => _selectedInvoiceDate = dateTime);
    }
  }

  void onFocusChange(bool hasFocus, TextEditingController controller) {
    if (controller.text.isNotEmpty) {
      setState(() {
        controller.text = hasFocus
            ? Helperfunctions.formatStringAmountForEditing(controller.text)
            : Helperfunctions.formatStringAmountForDisplay(controller.text);
      });
    }
  }

  Future<void> pickImageFromFile(File file) async {
    setState(() {
      _pickedImage = file;
      networkImagePath = '';
    });
  }

  InputDecoration _inputDecoration({required String label, required IconData icon, String? hintText}) {
    final colorScheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      prefixIcon: Icon(icon, size: 20, color: colorScheme.primary),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
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

  Widget _buildMoneyField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    bool enabled = true,
    ValueChanged<String>? onChanged,
    bool validate = true,
  }) {
    return Focus(
      onFocusChange: enabled ? (hasFocus) => onFocusChange(hasFocus, controller) : null,
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        onChanged: onChanged,
        textAlign: TextAlign.end,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
        decoration: _inputDecoration(label: label, icon: icon).copyWith(
          prefixText: '₱ ',
          prefixStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        autovalidateMode: AutovalidateMode.onUnfocus,
        validator: validate
            ? (value) {
                if (Helperfunctions.formatStringAmountToDouble(controller.text) <= 0) {
                  return '$label should be greater than 0';
                }
                return null;
              }
            : null,
      ),
    );
  }

  Widget _buildDateField({
    required String label,
    required DateTime selectedDate,
    required VoidCallback? onTap,
    required IconData icon,
  }) {
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
            Icon(icon, size: 20, color: colorScheme.primary),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                Text(
                  Helperfunctions.formatDateForDisplay(selectedDate),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const Spacer(),
            if (onTap != null) Icon(Icons.edit_calendar_outlined, size: 18, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderDetailsCard() {
    return _buildSectionCard(
      title: 'Order Information',
      icon: Icons.shopping_bag_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 16,
        children: [
          _buildDateField(
            label: 'Order Date',
            selectedDate: _selectedOrderDate,
            onTap: isNewRecord ? onChangeDate : null,
            icon: Icons.calendar_month_outlined,
          ),
          _buildMoneyField(
            label: 'Order Amount',
            controller: orderAmountController,
            icon: Icons.payments_outlined,
            enabled: isNewRecord,
            onChanged: isNewRecord ? (_) => setState(() {}) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildSettlementBreakdown() {
    final double orderAmt = _currentOrderAmount;
    final double invoiceAmt = _currentInvoiceAmount;
    final double overpayment = orderAmt - invoiceAmt;
    final bool isExactMatch = invoiceAmt > 0 && overpayment == 0;
    final bool hasOverpayment = overpayment > 0 && invoiceAmt > 0;
    final bool isOverInvoice = invoiceAmt > orderAmt;

    Color badgeColor = Colors.grey;
    String badgeText = 'Awaiting Invoice';
    IconData badgeIcon = Icons.hourglass_empty;

    if (isOverInvoice) {
      badgeColor = Colors.red.shade700;
      badgeText = 'Invoice exceeds Order by ${Helperfunctions.formatDoubleAmountForDisplay(invoiceAmt - orderAmt)}';
      badgeIcon = Icons.error_outline;
    } else if (isExactMatch) {
      badgeColor = Colors.green.shade700;
      badgeText = 'Balanced (No Overpayment)';
      badgeIcon = Icons.check_circle_outline;
    } else if (hasOverpayment) {
      if (widget.purchaseorder.isSettled == true) {
        badgeColor = Colors.green.shade700;
        badgeText = 'Overpayment Settled';
        badgeIcon = Icons.verified_outlined;
      } else {
        badgeColor = Colors.orange.shade800;
        badgeText = 'Overpayment: ${Helperfunctions.formatDoubleAmountForDisplay(overpayment)} (Unsettled)';
        badgeIcon = Icons.warning_amber_rounded;
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Order Target', style: TextStyle(fontSize: 11, color: Colors.black54)),
                  Text(
                    Helperfunctions.formatDoubleAmountForDisplay(orderAmt),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
              const Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Invoice Amount', style: TextStyle(fontSize: 11, color: Colors.black54)),
                  Text(
                    invoiceAmt > 0 ? Helperfunctions.formatDoubleAmountForDisplay(invoiceAmt) : '₱ 0.00',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 16),
          Row(
            children: [
              Icon(badgeIcon, size: 16, color: badgeColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  badgeText,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: badgeColor),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInvoiceCard() {
    final bool canEditInvoice = widget.purchaseorder.isSettled != true;

    return _buildSectionCard(
      title: 'Invoice & Settlement',
      icon: Icons.receipt_long_outlined,
      child: Column(
        spacing: 16,
        children: [
          _buildInvoiceDateField(),
          TextFormField(
            controller: orderNumberController,
            decoration: _inputDecoration(
              label: 'Invoice Reference Number',
              icon: Icons.tag_outlined,
              hintText: 'e.g. HM30471505',
            ),
            textCapitalization: TextCapitalization.characters,
            validator: (value) =>
                value == null || value.trim().isEmpty ? 'Invoice reference number should not be blank' : null,
            autovalidateMode: AutovalidateMode.onUnfocus,
          ),
          _buildMoneyField(
            label: 'Invoice Amount',
            enabled: canEditInvoice,
            controller: invoiceAmountController,
            icon: Icons.receipt_outlined,
            onChanged: (_) => setState(() {}),
          ),
          _buildSettlementBreakdown(),
        ],
      ),
    );
  }

  Widget _buildInvoiceDateField() {
    return _buildDateField(
      label: 'Invoice Date',
      selectedDate: _selectedInvoiceDate,
      onTap: onChangeInvoiceDate,
      icon: Icons.calendar_today_outlined,
    );
  }

  Widget _buildAttachmentCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final hasImageData = _pickedImage != null || networkImagePath.isNotEmpty;

    Future<void> startScan() async {
      ImageScanResult? scannedData;
      try {
        scannedData = await FlutterDocScanner().getScannedDocumentAsImages(page: 1);
      } on PlatformException catch (error) {
        if (mounted) {
          ShowMessage.error(context, error.message ?? 'Error while scanning document');
        }
      }

      if (scannedData != null && scannedData.images.isNotEmpty) {
        final filePath = scannedData.images.first.replaceFirst('file://', '');
        await pickImageFromFile(File(filePath));
      }
    }

    return _buildSectionCard(
      title: 'Supporting Document',
      icon: Icons.receipt_long_outlined,
      child: hasImageData
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      height: 200,
                      color: Colors.black12,
                      child: _pickedImage != null
                          ? Image.file(_pickedImage!, fit: BoxFit.cover)
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
                        onPressed: () => Helperfunctions.navigateTo(
                          context,
                          ImageViewerPage(image: _pickedImage, networkImagePath: networkImagePath),
                        ),
                        icon: const Icon(Icons.fullscreen, size: 18),
                        label: const Text('View Fullscreen'),
                      ),
                      OutlinedButton.icon(
                        onPressed: startScan,
                        icon: const Icon(Icons.replay, size: 18),
                        label: const Text('Replace'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => pickImage(null),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                          side: BorderSide(color: Colors.red.shade300),
                        ),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('Remove'),
                      ),
                    ],
                  ),
                ],
              ),
            )
          : InkWell(
              onTap: startScan,
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
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.document_scanner_outlined, size: 32, color: colorScheme.primary),
                    ),
                    const SizedBox(height: 10),
                    const Text('Tap to scan or attach document', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      'Scan the invoice or purchase order receipt',
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
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
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.history, size: 18, color: colorScheme.primary),
        ),
        title: const Text('Audit & History', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        initiallyExpanded: false,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                _buildAuditRow('Created By', widget.purchaseorder.createdBy),
                _buildAuditRow(
                  'Created Date',
                  DateFormat('E, d MMM yyyy, hh:mm a').format(widget.purchaseorder.createdDate.toDate()),
                ),
                const Divider(height: 12),
                _buildAuditRow('Last Updated By', widget.purchaseorder.lastUpdatedBy),
                _buildAuditRow(
                  'Last Updated Date',
                  DateFormat('E, d MMM yyyy, hh:mm a').format(widget.purchaseorder.lastupdatedDate.toDate()),
                ),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6))),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              offset: const Offset(0, -2),
              blurRadius: 6,
            ),
          ],
        ),
        child: isNewRecord
            ? FilledButton.icon(
                onPressed: () async {
                  final confirmed = await ShowMessage.confirm(
                    context,
                    title: 'Save Purchase Order',
                    message: 'Save this purchase order?',
                    icon: Icons.save_outlined,
                    confirmText: 'Save',
                  );
                  if (confirmed) onSave();
                },
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save Purchase Order', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              )
            : Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final confirmed = await ShowMessage.confirm(
                          context,
                          title: 'Delete Purchase Order',
                          message: 'Delete this purchase order?',
                          isDestructive: true,
                          icon: Icons.delete_outline,
                          confirmText: 'Delete',
                        );
                        if (confirmed) onDelete();
                      },
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 50),
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade300),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.delete_outline),
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
                          title: 'Update Purchase Order',
                          message: 'Save changes to this purchase order?',
                          icon: Icons.check_circle_outline,
                          confirmText: 'Update',
                        );
                        if (confirmed) onUpdate();
                      },
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Update Order', style: TextStyle(fontWeight: FontWeight.bold)),
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
      appBar: CustomAppbar(
        title: 'Purchase Order Details',
        subtitle: isNewRecord ? 'New Order' : orderNumberController.text,
      ),
      bottomNavigationBar: _buildStickyBottomBar(),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 16,
            children: [
              _buildOrderDetailsCard(),
              if (!isNewRecord) _buildInvoiceCard(),
              _buildAttachmentCard(),
              if (!isNewRecord) _buildAuditCard(),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
