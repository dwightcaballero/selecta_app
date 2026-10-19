import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/credit_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/data/responsive.dart';
import 'package:selecta_ops/models/delivery.dart';
import 'package:selecta_ops/services/hapistore_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/credit/credit_sms_dialog.dart';
import 'package:selecta_ops/views/widgets/imageviewer_page.dart';
import 'package:selecta_ops/views/widgets/audithistory_widget.dart';

/// Presentation view for inspecting and updating an individual store's credit record.
///
/// Purely responsible for rendering UI widgets. Persistence, audit logging,
/// and model mutations are delegated to [CreditController].
class CreditPage extends StatefulWidget {
  const CreditPage({super.key, required this.recID, required this.delivery});

  final Delivery delivery;
  final String recID;

  @override
  State<CreditPage> createState() => _CreditPageState();
}

class _CreditPageState extends State<CreditPage> {
  /// Shared controller managing credit business logic and update operations.
  final CreditController _controller = CreditController();

  /// Currently selected status in the UI segmented control.
  late String _selectedStatus;

  /// Whether an update request is currently being processed.
  bool _isUpdating = false;

  /// Store contact number loaded asynchronously.
  String _storeContact = '';
  bool _isLoadingContact = true;

  int get _agingDays {
    final date = widget.delivery.deliveryDate?.toDate() ?? widget.delivery.createdDate.toDate();
    final days = DateTime.now().difference(date).inDays;
    return days < 0 ? 0 : days;
  }

  @override
  void initState() {
    super.initState();
    // Resolve initial status via the controller
    _selectedStatus = _controller.resolveInitialStatus(widget.delivery);
    _fetchStoreContact();
  }

  Future<void> _fetchStoreContact() async {
    try {
      final contact = await _controller.getStoreContact(widget.delivery.storeName);
      if (mounted) {
        setState(() {
          _storeContact = contact;
          _isLoadingContact = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingContact = false);
      }
    }
  }

  /// Triggers the credit update operation through the controller.
  Future<void> _onUpdate() async {
    if (_isUpdating) return;
    setState(() => _isUpdating = true);

    try {
      final updatedDelivery = await _controller.updateCreditStatus(
        deliveryId: widget.recID,
        currentDelivery: widget.delivery,
        newCreditStatus: _selectedStatus,
      );

      if (!mounted) return;
      ShowMessage.success(context, 'Successfully updated credit status!\n[${updatedDelivery.storeName}]');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _isUpdating = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating credit: $e')));
      }
    }
  }

  // ==========================================
  // UI Building Blocks
  // ==========================================

  /// Builds a stylized card section with an icon, title, and child content.
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

  /// Builds the top overview card displaying the store name and outstanding credit amount.
  Widget _buildCreditOverviewCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final isUnpaid = _selectedStatus == CreditStatus.unpaid;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: isUnpaid ? Colors.red.withValues(alpha: 0.05) : Colors.green.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isUnpaid ? Colors.red.withValues(alpha: 0.3) : Colors.green.withValues(alpha: 0.3), width: 1.2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(Icons.storefront_outlined, color: colorScheme.primary, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.delivery.storeName,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Delivery Order: ${Helperfunctions.formatDoubleAmountForDisplay(widget.delivery.orderAmount)}',
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Credit Amount', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        Helperfunctions.formatDoubleAmountForDisplay(widget.delivery.creditAmount),
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isUnpaid ? Colors.red.shade700 : Colors.green.shade700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildAgingBadge(_agingDays),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.calendar_month_outlined, size: 13, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        widget.delivery.deliveryDate != null ? Helperfunctions.formatDateForDisplay(widget.delivery.deliveryDate!.toDate()) : 'N/A',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAgingBadge(int days) {
    final Color bgColor;
    final Color textColor;
    final String text;

    if (days <= 15) {
      bgColor = Colors.green.withValues(alpha: 0.12);
      textColor = Colors.green.shade800;
      text = '$days d';
    } else if (days <= 30) {
      bgColor = Colors.amber.withValues(alpha: 0.18);
      textColor = Colors.orange.shade900;
      text = '$days d Due';
    } else {
      bgColor = Colors.red.withValues(alpha: 0.14);
      textColor = Colors.red.shade800;
      text = '$days d Overdue';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor),
      ),
    );
  }

  /// Builds customer contact card providing 1-tap Phone Call and SMS reminder options.
  Widget _buildCommunicationCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final hasContact = _storeContact.trim().isNotEmpty;

    return _buildSectionCard(
      title: 'Customer Contact & Follow-up',
      icon: Icons.contact_phone_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: hasContact
                      ? colorScheme.primary.withValues(alpha: 0.1)
                      : Colors.orange.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  hasContact ? Icons.phone_android_rounded : Icons.phone_disabled_rounded,
                  size: 20,
                  color: hasContact ? colorScheme.primary : Colors.orange.shade800,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Store Contact Number',
                      style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    _isLoadingContact
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            hasContact ? _storeContact : 'No contact registered',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: hasContact ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                            ),
                          ),
                  ],
                ),
              ),
              IconButton.outlined(
                tooltip: 'Edit Store Contact',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.edit_outlined, size: 16),
                onPressed: _openEditContactDialog,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              // 1. Call Store Button
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _handleCallStore,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.withValues(alpha: 0.14),
                    foregroundColor: Colors.green.shade800,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.phone_in_talk_rounded, size: 18),
                  label: const Text('Call Store', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 10),
              // 2. Text Reminder Button
              Expanded(
                child: FilledButton.icon(
                  onPressed: _handleTextStore,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF97316),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.sms_rounded, size: 18),
                  label: const Text('Text Reminder', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _handleCallStore() async {
    String phone = _storeContact.trim();
    if (phone.isEmpty) {
      await _openEditContactDialog();
      phone = _storeContact.trim();
      if (phone.isEmpty) return;
    }

    final success = await _controller.makePhoneCall(phone);
    if (!success && mounted) {
      ShowMessage.error(context, 'Could not initiate phone call to $phone.');
    }
  }

  void _handleTextStore() {
    CreditSmsDialog.show(
      context: context,
      storeName: widget.delivery.storeName,
      creditAmount: widget.delivery.creditAmount,
      creditDate: widget.delivery.deliveryDate?.toDate(),
      daysOverdue: _agingDays,
      initialPhoneNumber: _storeContact,
    );
  }

  Future<void> _openEditContactDialog() async {
    final textController = TextEditingController(text: _storeContact);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Store Contact Number', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: textController,
          keyboardType: TextInputType.phone,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Phone Number',
            hintText: 'e.g. 09171234567',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogCtx, true), child: const Text('Save')),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final newPhone = textController.text.trim();
      setState(() => _storeContact = newPhone);
      try {
        final query = await FirebaseFirestore.instance
            .collection(HAPISTORE_COLLECTION_REF)
            .where('storeName', isEqualTo: widget.delivery.storeName)
            .limit(1)
            .get();
        if (query.docs.isNotEmpty) {
          await query.docs.first.reference.update({'storeContact': newPhone});
          HapiStoreService.invalidateCache();
        }
      } catch (_) {}
    }
  }

  /// Builds the breakdown list showing cash, online, and returns deductions.
  Widget _buildPaymentBreakdownCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final isUnpaid = _selectedStatus == CreditStatus.unpaid;

    return _buildSectionCard(
      title: 'Payment & Order Breakdown',
      icon: Icons.receipt_long_outlined,
      child: Column(
        children: [
          _buildDetailRow('Total Order Amount', Helperfunctions.formatDoubleAmountForDisplay(widget.delivery.orderAmount)),
          if (widget.delivery.cashAmount > 0)
            _buildDetailRow('Cash Paid', Helperfunctions.formatDoubleAmountForDisplay(widget.delivery.cashAmount), valueColor: Colors.green.shade700),
          if (widget.delivery.onlineAmount > 0)
            _buildDetailRow(
              'Online Paid',
              Helperfunctions.formatDoubleAmountForDisplay(widget.delivery.onlineAmount),
              valueColor: colorScheme.primary,
            ),
          if (widget.delivery.returnAmount > 0)
            _buildDetailRow(
              'Returns Deducted',
              Helperfunctions.formatDoubleAmountForDisplay(widget.delivery.returnAmount),
              valueColor: Colors.orange.shade800,
            ),
          const Divider(height: 20),
          _buildDetailRow(
            'Remaining Credit Balance',
            Helperfunctions.formatDoubleAmountForDisplay(widget.delivery.creditAmount),
            valueColor: isUnpaid ? Colors.red.shade700 : Colors.green.shade700,
          ),
        ],
      ),
    );
  }

  /// Helper row displaying a title and value side-by-side.
  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
          Text(
            value,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: valueColor),
          ),
        ],
      ),
    );
  }

  /// Builds delivery remarks section if remarks are present.
  Widget _buildRemarksCard() {
    final remarks = widget.delivery.remarks.trim();
    if (remarks.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    return _buildSectionCard(
      title: 'Delivery Remarks',
      icon: Icons.notes_outlined,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Text(remarks, style: TextStyle(fontSize: 13, color: colorScheme.onSurface, height: 1.4)),
      ),
    );
  }

  /// Builds image thumbnail preview for the signed delivery receipt.
  Widget _buildAttachmentCard() {
    final imagePath = widget.delivery.imagePath.trim();
    if (imagePath.isEmpty) return const SizedBox.shrink();

    return _buildSectionCard(
      title: 'Proof of Delivery Receipt',
      icon: Icons.image_outlined,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Helperfunctions.navigateTo(context, ImageViewerPage(image: null, networkImagePath: imagePath)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Image.network(
                imagePath,
                height: 190,
                width: double.infinity,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    height: 190,
                    width: double.infinity,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    child: const Center(child: CircularProgressIndicator()),
                  );
                },
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 130,
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.broken_image_outlined, size: 36, color: Colors.grey),
                        SizedBox(height: 6),
                        Text('Unable to preview delivery receipt', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.75)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.zoom_in, color: Colors.white, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'Tap to inspect full delivery receipt',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the segmented status selector card (Unpaid vs Paid).
  Widget _buildStatusCard() {
    final colorScheme = Theme.of(context).colorScheme;

    return _buildSectionCard(
      title: 'Payment Status',
      icon: Icons.payments_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Select whether this credit has been fully settled:', style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              segments: [
                ButtonSegment<String>(
                  value: CreditStatus.unpaid,
                  label: const Text(CreditStatus.unpaid, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  icon: Icon(
                    Icons.hourglass_top_rounded,
                    size: 18,
                    color: _selectedStatus == CreditStatus.unpaid ? Colors.red.shade700 : colorScheme.onSurfaceVariant,
                  ),
                ),
                ButtonSegment<String>(
                  value: CreditStatus.paid,
                  label: const Text(CreditStatus.paid, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  icon: Icon(
                    Icons.check_circle_outline,
                    size: 18,
                    color: _selectedStatus == CreditStatus.paid ? Colors.green.shade700 : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              selected: {_selectedStatus},
              onSelectionChanged: (Set<String> newSelection) {
                setState(() {
                  _selectedStatus = newSelection.first;
                });
              },
            ),
          ),
        ],
      ),
    );
  }



  /// Builds the persistent bottom bar containing the submit action button.
  Widget _buildStickyBottomBar() {
    final colorScheme = Theme.of(context).colorScheme;
    final isUnchanged = _controller.isStatusUnchanged(currentStatus: widget.delivery.creditStatus, selectedStatus: _selectedStatus);

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 1.0)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), offset: const Offset(0, -2), blurRadius: 6)],
        ),
        child: FilledButton.icon(
          onPressed: _isUpdating
              ? null
              : () async {
                  if (isUnchanged) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Credit status is already set to this value'),
                        duration: Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                    return;
                  }

                  final confirmed = await ShowMessage.confirm(
                    context,
                    title: ConfirmTitle.update,
                    message: 'Update the credit status of [${widget.delivery.storeName}] to "$_selectedStatus"?',
                    icon: Icons.check_circle_outline,
                    confirmText: 'Update',
                  );

                  if (confirmed) {
                    _onUpdate();
                  }
                },
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 50.0),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          icon: _isUpdating
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_circle_outline, size: 20),
          label: Text(
            _isUpdating
                ? 'Updating...'
                : isUnchanged
                ? 'Current: $_selectedStatus'
                : 'Update Credit Record',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  bool get _hasUnsavedChanges {
    return _selectedStatus != _controller.resolveInitialStatus(widget.delivery);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_isUpdating) return;
        if (_hasUnsavedChanges) {
          final shouldDiscard = await ShowMessage.confirm(
            context,
            title: 'Discard Changes?',
            message: 'You have unsaved changes to the credit status. Are you sure you want to discard them?',
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
        appBar: CustomAppbar(title: 'Credit Settlement', subtitle: widget.delivery.storeName),
        bottomNavigationBar: ScreenSize.isTabletLandscape(context) ? null : _buildStickyBottomBar(),
        body: ScreenSize.isTabletLandscape(context)
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Pane: Credit Overview, Financial Breakdown & Proof
                  Expanded(
                    flex: 5,
                    child: SingleChildScrollView(
                      primary: false,
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: 16,
                        children: [
                          _buildCreditOverviewCard(),
                          _buildPaymentBreakdownCard(),
                          _buildAttachmentCard(),
                          AuditHistoryWidget(
                            createdBy: widget.delivery.createdBy,
                            createdDate: widget.delivery.createdDate,
                            createdPage: widget.delivery.createdPage,
                            lastUpdatedBy: widget.delivery.lastUpdatedBy,
                            lastUpdatedDate: widget.delivery.lastupdatedDate,
                            lastUpdatedPage: widget.delivery.lastUpdatedPage,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Right Pane: Collection Status, Communication & Settlement Action
                  Expanded(
                    flex: 5,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border(
                          left: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              primary: false,
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                spacing: 16,
                                children: [
                                  _buildStatusCard(),
                                  _buildCommunicationCard(),
                                  _buildRemarksCard(),
                                ],
                              ),
                            ),
                          ),
                          _buildStickyBottomBar(),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 16,
                  children: [
                    // 1. Credit Overview Card
                    _buildCreditOverviewCard(),

                    // 2. Customer Contact & Collections Follow-up Card
                    _buildCommunicationCard(),

                    // 3. Status Selector Card
                    _buildStatusCard(),

                    // 3. Payment & Order Breakdown Card
                    _buildPaymentBreakdownCard(),

                    // 4. Remarks Note Card
                    _buildRemarksCard(),

                    // 5. Proof of Delivery Receipt Card
                    _buildAttachmentCard(),

                    // 6. Audit History Card
                    AuditHistoryWidget(
                      createdBy: widget.delivery.createdBy,
                      createdDate: widget.delivery.createdDate,
                      createdPage: widget.delivery.createdPage,
                      lastUpdatedBy: widget.delivery.lastUpdatedBy,
                      lastUpdatedDate: widget.delivery.lastupdatedDate,
                      lastUpdatedPage: widget.delivery.lastUpdatedPage,
                    ),

                    const SizedBox(height: 8),
                  ],
                ),
              ),
      ),
    );
  }
}
