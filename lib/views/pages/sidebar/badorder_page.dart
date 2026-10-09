import 'dart:io';

import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/badorder_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/views/widgets/imageviewer_page.dart';
import 'package:selecta_ops/models/badorder.dart';
import 'package:selecta_ops/services/error_log_service.dart';
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
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _badOrder = widget.badorder;
    _checkDealerRole();
  }

  Future<void> _checkDealerRole() async {
    final dealer = await _controller.checkIsDealer();
    if (mounted) {
      setState(() => _isDealer = dealer);
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

  Future<void> _advanceStatus() async {
    if (!_isDealer) {
      ShowMessage.error(context, 'Only dealers are authorized to update bad order status.');
      return;
    }

    String nextStatus = '';
    String confirmMessage = '';
    if (_badOrder.status == BadOrderStatus.storePullout) {
      nextStatus = BadOrderStatus.warehousePullout;
      confirmMessage =
          'Advance bad order status to "Warehouse Pullout"?\n\nThis indicates the items have been pulled from the store and received into the warehouse.';
    } else if (_badOrder.status == BadOrderStatus.warehousePullout) {
      nextStatus = BadOrderStatus.settled;
      confirmMessage =
          'Mark bad order as "Settled"?\n\nThis marks the bad order as resolved and permanently finalized.';
    } else {
      return;
    }

    final confirmed = await ShowMessage.confirm(
      context,
      title: 'Update Status',
      message: confirmMessage,
      icon: Icons.check_circle_outline,
      confirmText: 'Confirm',
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await _controller.updateStatus(
        recID: widget.recID,
        existingRecord: _badOrder,
        newStatus: nextStatus,
        page: AppPages.badOrder,
      );

      if (mounted) {
        setState(() {
          _badOrder = _badOrder.copyWith(
            status: nextStatus,
            lastUpdatedBy: _controller.getCurrentUserDisplayName(),
          );
        });
        ShowMessage.success(context, 'Status updated to "$nextStatus"!');
      }
    } catch (e, s) {
      ErrorLogService.logError(
        page: 'BadOrderPage',
        action: 'Update Status',
        error: e,
        stackTrace: s,
        extraData: {'recID': widget.recID, 'newStatus': nextStatus},
      );
      if (mounted) {
        ShowMessage.error(context, 'Failed to update status: $e');
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
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: colorScheme.primary),
                ),
                const SizedBox(width: 10),
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                if (trailing != null) ...[
                  const Spacer(),
                  trailing,
                ],
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
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
              if (_badOrder.status == BadOrderStatus.settled)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
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
                return Expanded(
                  child: Container(
                    height: 3,
                    color: isPassed ? statusColor : Colors.grey.shade300,
                  ),
                );
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
                    child: Icon(
                      steps[stepIndex]['icon'] as IconData,
                      size: 16,
                      color: isReached ? Colors.white : Colors.grey.shade600,
                    ),
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
                    Text(
                      _badOrder.hapistore,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
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
                      Text(
                        _badOrder.notes,
                        style: const TextStyle(fontSize: 13.5),
                      ),
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
                    ImageViewerPage(
                      image: isNetwork ? null : File(imagePath),
                      networkImagePath: isNetwork ? imagePath : '',
                    ),
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
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(8),
                        ),
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
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: colorScheme.primary,
        ),
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
                              Text(
                                item.productName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
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
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
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
            if (_isDealer) ...[
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _onDelete,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(60, 50.0),
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade300, width: 1.2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.delete_outline, size: 20),
                label: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
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
                              Text(
                                'Settled — Fully Resolved',
                                style: TextStyle(
                                  color: Colors.green.shade800,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        )
                      : FilledButton.icon(
                          onPressed: _isLoading ? null : _advanceStatus,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(double.infinity, 50.0),
                            backgroundColor: _badOrder.status == BadOrderStatus.storePullout
                                ? Colors.blue.shade700
                                : Colors.green.shade700,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: Icon(
                            _badOrder.status == BadOrderStatus.storePullout
                                ? Icons.warehouse_outlined
                                : Icons.check_circle_outline,
                            size: 20,
                          ),
                          label: Text(
                            _badOrder.status == BadOrderStatus.storePullout
                                ? 'Advance to Warehouse Pullout'
                                : 'Mark as Settled',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                          ),
                        ))
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
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
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
    return Scaffold(
      appBar: CustomAppbar(
        title: 'Bad Order Details',
        subtitle: _badOrder.hapistore,
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
                        'Status updates (Warehouse Pullout & Settled) are reserved for dealers.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.w600,
                        ),
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

            // 3. Incident Photo
            _buildPhotoCard(),
            const SizedBox(height: 16),

            // 4. Itemized bad orders table
            _buildItemsCard(),
            const SizedBox(height: 16),

            // 5. Audit History
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
    );
  }
}
