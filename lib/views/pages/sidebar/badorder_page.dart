import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/badorder_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/views/pages/sidebar/badorder_form_page.dart';
import 'package:selecta_ops/views/widgets/imageviewer_page.dart';
import 'package:selecta_ops/models/badorder.dart';
import 'package:selecta_ops/models/badorder_batch.dart';
import 'package:selecta_ops/services/error_log_service.dart';
import 'package:selecta_ops/views/pages/sidebar/badorder_batch_detail_page.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/audithistory_widget.dart';

class BadOrderPage extends StatefulWidget {
  const BadOrderPage({super.key, required this.recID, required this.badorder});

  final BadOrder badorder;
  final String recID;

  @override
  State<BadOrderPage> createState() => _BadOrderPageState();
}

class _BadOrderPageState extends State<BadOrderPage> {
  final BadOrderController _controller = BadOrderController();
  late BadOrder _badOrder;
  bool _isDealer = false;
  bool _isAdmin = false;
  bool _isLoading = false;

  bool get _canEditOrDelete => _isAdmin || _badOrder.status == BadOrderStatus.storePullout;

  @override
  void initState() {
    super.initState();
    _badOrder = widget.badorder;
    _checkRoles();
  }

  Future<void> _checkRoles() async {
    final dealer = await _controller.checkIsDealer();
    final admin = await _controller.checkIsAdmin();
    if (mounted) {
      setState(() {
        _isDealer = dealer;
        _isAdmin = admin;
      });
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case BadOrderStatus.storePullout:
        return Colors.orange.shade700;
      case BadOrderStatus.warehousePullout:
        return Colors.blue.shade700;
      case BadOrderStatus.settled:
        return Colors.green.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case BadOrderStatus.storePullout:
        return Icons.store_outlined;
      case BadOrderStatus.warehousePullout:
        return Icons.warehouse_outlined;
      case BadOrderStatus.settled:
        return Icons.check_circle_outline;
      default:
        return Icons.help_outline;
    }
  }

  int _getStatusStepIndex(String status) {
    switch (status) {
      case BadOrderStatus.storePullout:
        return 0;
      case BadOrderStatus.warehousePullout:
        return 1;
      case BadOrderStatus.settled:
        return 2;
      default:
        return 0;
    }
  }

  Future<void> _viewBatch() async {
    if (_badOrder.batchId == null || _badOrder.batchId!.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final snap = await FirebaseFirestore.instance.collection('badorder_batch').doc(_badOrder.batchId).get();
      if (snap.exists && snap.data() != null && mounted) {
        final batch = BadOrderBatch.fromJson(snap.data()!, snap.id);
        await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => BadOrderBatchDetailPage(batchId: snap.id, batch: batch),
          ),
        );
        if (mounted) {
          final boSnap = await FirebaseFirestore.instance.collection('badorder').doc(widget.recID).get();
          if (boSnap.exists && mounted) {
            setState(() {
              _badOrder = BadOrder.fromJson(boSnap.data()!, boSnap.id);
            });
          }
        }
      } else {
        if (mounted) ShowMessage.error(context, 'Batch details not found.');
      }
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Error opening batch: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onEdit() async {
    if (!_isDealer) {
      ShowMessage.error(context, 'Only dealers are authorized to edit bad order records.');
      return;
    }

    if (!_canEditOrDelete) {
      ShowMessage.error(
        context,
        'Cannot edit bad order once status is "${_badOrder.status}" in order to maintain data accuracy.',
      );
      return;
    }

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => BadOrderFormPage(existingRecord: _badOrder, recID: widget.recID),
      ),
    );

    if (result == true && mounted) {
      final snap = await FirebaseFirestore.instance.collection('badorder').doc(widget.recID).get();
      if (snap.exists && mounted) {
        setState(() {
          _badOrder = BadOrder.fromJson(snap.data()!, snap.id);
        });
      }
    }
  }

  Future<void> _onToggleStoreRefunded(bool value) async {
    if (!_isDealer) {
      ShowMessage.error(context, 'Only dealers are authorized to update store refund status.');
      return;
    }

    final confirmed = await ShowMessage.confirm(
      context,
      title: value ? 'Mark Store as Refunded' : 'Mark Store as Not Refunded',
      message: value
          ? 'Has the store [${_badOrder.hapistore}] received the refund or credit memo for this bad order (Amount: ${Helperfunctions.formatDoubleAmountForDisplay(_badOrder.totalAmount)})?'
          : 'Revert store refund status for [${_badOrder.hapistore}] back to Not Refunded?',
      icon: value ? Icons.check_circle_outline : Icons.undo_outlined,
      confirmText: value ? 'Confirm Refund' : 'Revert',
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await _controller.toggleStoreRefunded(recID: widget.recID, existingRecord: _badOrder, isRefunded: value, page: AppPages.badOrder);

      if (mounted) {
        setState(() {
          _badOrder = _badOrder.copyWith(
            isStoreRefunded: value,
            storeRefundedDate: value ? Timestamp.now() : null,
            storeRefundedBy: value ? _controller.getCurrentUserDisplayName() : null,
            lastUpdatedBy: _controller.getCurrentUserDisplayName(),
          );
        });
        ShowMessage.success(context, value ? 'Store marked as Refunded!' : 'Store marked as Not Refunded.');
      }
    } catch (e, s) {
      ErrorLogService.logError(
        page: 'BadOrderPage',
        action: 'Toggle Store Refunded',
        error: e,
        stackTrace: s,
        extraData: {'recID': widget.recID, 'isStoreRefunded': value},
      );
      if (mounted) {
        ShowMessage.error(context, 'Failed to update store refund status: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onDelete() async {
    if (!_isDealer) {
      ShowMessage.error(context, 'Only dealers are authorized to delete bad order records.');
      return;
    }

    if (!_canEditOrDelete) {
      ShowMessage.error(
        context,
        'Cannot delete bad order once status is "${_badOrder.status}" in order to maintain data accuracy.',
      );
      return;
    }
    final confirmed = await ShowMessage.confirm(
      context,
      title: ConfirmTitle.delete,
      message: 'Are you sure you want to permanently delete this bad order record for [${_badOrder.hapistore}]?',
      isDestructive: true,
      icon: Icons.delete_outline,
      confirmText: 'Delete',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await _controller.deleteBadOrder(recID: widget.recID, existingRecord: _badOrder);
      if (mounted) {
        ShowMessage.success(context, 'Successfully deleted bad order record for [${_badOrder.hapistore}]!');
        Navigator.pop(context);
      }
    } catch (e, s) {
      ErrorLogService.logError(
        page: 'BadOrderPage',
        action: 'Delete Bad Order Record',
        error: e,
        stackTrace: s,
        extraData: {'recID': widget.recID, 'hapistore': _badOrder.hapistore},
      );
      if (mounted) {
        ShowMessage.error(context, 'Failed to delete record: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
                  child: Icon(icon, size: 18, color: colorScheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    maxLines: 1,
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

  Widget _buildStatusTracker() {
    final currentStep = _getStatusStepIndex(_badOrder.status);
    final statusColor = _getStatusColor(_badOrder.status);

    final steps = [
      {'title': 'Store Pullout', 'icon': Icons.store_outlined},
      {'title': 'Warehouse Pullout', 'icon': Icons.warehouse_outlined},
      {'title': 'Settled', 'icon': Icons.check_circle_outline},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(_getStatusIcon(_badOrder.status), color: statusColor, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Status: ${_badOrder.status}',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: statusColor),
                  ),
                ],
              ),
              if (_badOrder.status == BadOrderStatus.settled)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    'Resolved',
                    style: TextStyle(color: Colors.green.shade800, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: List.generate(steps.length * 2 - 1, (index) {
              if (index.isOdd) {
                final lineIndex = index ~/ 2;
                final isPassed = lineIndex < currentStep;
                return Expanded(child: Container(height: 3, color: isPassed ? statusColor : Colors.grey.shade300));
              }

              final stepIndex = index ~/ 2;
              final isReached = stepIndex <= currentStep;
              final isCurrent = stepIndex == currentStep;

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isReached ? statusColor : Colors.grey.shade200,
                      shape: BoxShape.circle,
                      border: isCurrent ? Border.all(color: Colors.white, width: 2) : null,
                    ),
                    child: Icon(steps[stepIndex]['icon'] as IconData, size: 16, color: isReached ? Colors.white : Colors.grey.shade600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    steps[stepIndex]['title'] as String,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                      color: isReached ? statusColor : Colors.grey.shade600,
                    ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreAndDateCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return _buildSectionCard(
      title: 'Store & Incident Information',
      icon: Icons.storefront_outlined,
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.store, color: colorScheme.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Store Name', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                    Text(_badOrder.hapistore, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.calendar_today_outlined, color: colorScheme.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Incident Date', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                    Text(
                      Helperfunctions.formatDateForDisplay(_badOrder.badorderDate.toDate()),
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_badOrder.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.notes_outlined, color: colorScheme.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Remarks / Notes', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Text(_badOrder.notes, style: const TextStyle(fontSize: 13.5)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWarehouseBatchCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final hasBatch = _badOrder.batchId != null && _badOrder.batchId!.isNotEmpty;

    return _buildSectionCard(
      title: 'Warehouse Batch Information',
      icon: Icons.warehouse_outlined,
      trailing: hasBatch
          ? TextButton.icon(
              onPressed: _isLoading ? null : _viewBatch,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('View Batch'),
            )
          : null,
      child: hasBatch
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.tag, size: 18, color: Colors.blue.shade700),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Batch Number', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                          Text(
                            _badOrder.batchNumber ?? _badOrder.batchId!,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _badOrder.status == BadOrderStatus.settled
                      ? 'This record was pulled out with batch ${_badOrder.batchNumber ?? ""} and has been settled with the supplier.'
                      : 'Included in supplier warehouse pullout batch. Editing and deletion are locked to preserve batch data integrity.',
                  style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
                ),
              ],
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 18, color: Colors.blue.shade800),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Stored in dealer warehouse freezer. Will advance to Warehouse Pullout when included in a batch during the supplier pullout.',
                      style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStoreRefundCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final isRefunded = _badOrder.isStoreRefunded;
    final refundColor = isRefunded ? Colors.green.shade700 : Colors.amber.shade800;

    return _buildSectionCard(
      title: 'Store Refund Status',
      icon: Icons.payments_outlined,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: refundColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
        child: Text(
          isRefunded ? 'Store Refunded' : 'Store Not Refunded',
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: refundColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isRefunded
                ? 'The store has been refunded or credited for the pulled-out bad order items.'
                : 'Pending refund or invoice credit to the store for damaged/expired products.',
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
          if (isRefunded && _badOrder.storeRefundedDate != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.check_circle, size: 15, color: Colors.green.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Refunded on ${Helperfunctions.formatTimestampForDisplay(_badOrder.storeRefundedDate!)}'
                    '${_badOrder.storeRefundedBy != null && _badOrder.storeRefundedBy!.isNotEmpty ? ' by ${_badOrder.storeRefundedBy}' : ''}',
                    style: TextStyle(fontSize: 12, color: Colors.green.shade800, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          if (_isDealer)
            Container(
              decoration: BoxDecoration(
                color: isRefunded ? Colors.green.shade50 : Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isRefunded ? Colors.green.shade200 : Colors.amber.shade200),
              ),
              child: SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                title: Text(
                  'Mark Store as Refunded',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: isRefunded ? Colors.green.shade900 : Colors.amber.shade900),
                ),
                subtitle: Text(
                  isRefunded ? 'Toggle off to revert to Not Refunded' : 'Toggle on once store credit or cash is disbursed',
                  style: TextStyle(fontSize: 11.5, color: isRefunded ? Colors.green.shade700 : Colors.amber.shade800),
                ),
                value: isRefunded,
                activeThumbColor: Colors.green.shade700,
                onChanged: _isLoading ? null : (val) => _onToggleStoreRefunded(val),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  Icon(Icons.lock_outline, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Store refund status can only be toggled by dealers.', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPhotoCard() {
    final imagePath = _badOrder.imagePath.trim();
    final hasImage = imagePath.isNotEmpty;

    return _buildSectionCard(
      title: 'Incident Photo',
      icon: Icons.photo_camera_outlined,
      child: Center(
        child: hasImage
            ? InkWell(
                onTap: () {
                  final isNetwork = imagePath.startsWith('http://') || imagePath.startsWith('https://');
                  Helperfunctions.navigateTo(
                    context,
                    ImageViewerPage(image: isNetwork ? null : File(imagePath), networkImagePath: isNetwork ? imagePath : ''),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      imagePath.startsWith('http')
                          ? Image.network(
                              imagePath,
                              height: 220,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                height: 180,
                                color: Colors.grey.shade100,
                                alignment: Alignment.center,
                                child: const Text('Unable to load photo from storage'),
                              ),
                            )
                          : Image.file(
                              File(imagePath),
                              height: 220,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                height: 180,
                                color: Colors.grey.shade100,
                                alignment: Alignment.center,
                                child: const Text('Local photo not available'),
                              ),
                            ),
                      Container(
                        margin: const EdgeInsets.all(8),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(8)),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.zoom_in, color: Colors.white, size: 16),
                            SizedBox(width: 4),
                            Text('Tap to view', style: TextStyle(color: Colors.white, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.image_not_supported_outlined, size: 44, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    const Text('No photo attached to this record', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildItemsCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final items = _badOrder.items;

    return _buildSectionCard(
      title: 'Itemized Products (${items.length})',
      icon: Icons.inventory_2_outlined,
      trailing: Text(
        Helperfunctions.formatDoubleAmountForDisplay(_badOrder.totalAmount),
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.primary),
      ),
      child: items.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('No item details recorded.', style: TextStyle(color: Colors.grey)),
              ),
            )
          : Column(
              children: [
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Divider(height: 16),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isCase = item.category == 'By Case';

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: isCase ? Colors.purple.shade50 : Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${item.quantity}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isCase ? Colors.purple.shade800 : Colors.blue.shade800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isCase ? Colors.purple.shade50 : Colors.blue.shade50,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      item.category,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: isCase ? Colors.purple.shade700 : Colors.blue.shade700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '@ ${Helperfunctions.formatDoubleAmountForDisplay(item.pricePerPiece)} / pc',
                                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Text(
                          Helperfunctions.formatDoubleAmountForDisplay(item.subtotal),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                        ),
                      ],
                    );
                  },
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Bad Order Amount:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text(
                      Helperfunctions.formatDoubleAmountForDisplay(_badOrder.totalAmount),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.primary),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildStickyBottomBar() {
    final colorScheme = Theme.of(context).colorScheme;
    final isSettled = _badOrder.status == BadOrderStatus.settled;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 1.0)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), offset: const Offset(0, -2), blurRadius: 6)],
        ),
        child: Row(
          children: [
            if (_isDealer && _canEditOrDelete) ...[
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _onEdit,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(60, 50.0),
                  foregroundColor: colorScheme.primary,
                  side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.5), width: 1.2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.edit_outlined, size: 20),
                label: Text(
                  _isAdmin && _badOrder.status != BadOrderStatus.storePullout ? 'Edit (Admin)' : 'Edit',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: _isDealer
                  ? (isSettled
                        ? Container(
                            height: 50,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      'Settled — Fully Resolved',
                                      style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold, fontSize: 14.5),
                                      maxLines: 1,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : (_badOrder.batchId != null && _badOrder.batchId!.isNotEmpty
                            ? FilledButton.icon(
                                onPressed: _isLoading ? null : _viewBatch,
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 50.0),
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  backgroundColor: Colors.blue.shade700,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.warehouse_outlined, size: 20),
                                label: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'View Batch (${_badOrder.batchNumber ?? "Warehouse Pullout"})',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    maxLines: 1,
                                  ),
                                ),
                              )
                            : Container(
                                height: 50,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.blue.shade200),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.inventory_2_outlined, color: Colors.blue.shade800, size: 18),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          'In Warehouse (Awaiting Batch Pullout)',
                                          style: TextStyle(
                                            color: Colors.blue.shade900,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                          maxLines: 1,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )))
                  : Container(
                      height: 50,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Text(
                        'Read-Only (${_badOrder.status})',
                        style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context);
      },
      child: Scaffold(
        appBar: CustomAppbar(
          title: 'Bad Order Details',
          subtitle: _badOrder.hapistore,
          actions: [
            if (_isDealer && _canEditOrDelete)
              IconButton(
                tooltip: _isAdmin && _badOrder.status != BadOrderStatus.storePullout
                    ? 'Delete Bad Order (Admin)'
                    : 'Delete Bad Order',
                icon: const Icon(Icons.delete_outline, color: Colors.white),
                onPressed: _isLoading ? null : _onDelete,
              ),
          ],
        ),
        bottomNavigationBar: _buildStickyBottomBar(),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_isDealer)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade300, width: 1.2),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.amber.shade900, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Status updates and editing are reserved for dealers.',
                          style: TextStyle(fontSize: 13, color: Colors.amber.shade900, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),

              // 1. Status tracker
              _buildStatusTracker(),
              const SizedBox(height: 16),

              // 2. Store & Incident details
              _buildStoreAndDateCard(),
              const SizedBox(height: 16),

              // 3. Warehouse Batch Information Card
              _buildWarehouseBatchCard(),
              const SizedBox(height: 16),

              // 4. Store Refund Status Card
              _buildStoreRefundCard(),
              const SizedBox(height: 16),

              // 5. Incident Photo
              _buildPhotoCard(),
              const SizedBox(height: 16),

              // 6. Itemized bad orders table
              _buildItemsCard(),
              const SizedBox(height: 16),

              // 6. Audit History
              if (widget.recID.isNotEmpty)
                AuditHistoryWidget(
                  createdBy: _badOrder.createdBy,
                  createdDate: _badOrder.createdDate,
                  createdPage: _badOrder.createdPage,
                  lastUpdatedBy: _badOrder.lastUpdatedBy,
                  lastUpdatedDate: _badOrder.lastupdatedDate,
                  lastUpdatedPage: _badOrder.lastUpdatedPage,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
