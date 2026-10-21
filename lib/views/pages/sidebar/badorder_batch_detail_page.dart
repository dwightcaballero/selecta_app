import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/controllers/badorder_controller.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/badorder.dart';
import 'package:selecta_ops/models/badorder_batch.dart';
import 'package:selecta_ops/services/error_log_service.dart';
import 'package:selecta_ops/views/pages/sidebar/badorder_page.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';
import 'package:selecta_ops/views/widgets/audithistory_widget.dart';

class BadOrderBatchDetailPage extends StatefulWidget {
  const BadOrderBatchDetailPage({
    super.key,
    required this.batchId,
    required this.batch,
  });

  final String batchId;
  final BadOrderBatch batch;

  @override
  State<BadOrderBatchDetailPage> createState() => _BadOrderBatchDetailPageState();
}

class _BadOrderBatchDetailPageState extends State<BadOrderBatchDetailPage> {
  final BadOrderController _controller = BadOrderController();
  late BadOrderBatch _batch;
  bool _isDealer = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _batch = widget.batch;
    _checkDealerRole();
  }

  Future<void> _checkDealerRole() async {
    final dealer = await _controller.checkIsDealer();
    if (mounted) setState(() => _isDealer = dealer);
  }

  Color _getStatusColor(String status) {
    if (status == BadOrderStatus.settled) return Colors.green.shade700;
    return Colors.blue.shade700;
  }

  Future<void> _openSettleModal() async {
    if (!_isDealer) {
      ShowMessage.error(context, 'Only dealers are authorized to settle warehouse batches.');
      return;
    }

    final cmController = TextEditingController();
    final amountController = TextEditingController(
      text: _batch.totalBatchAmount.toStringAsFixed(2),
    );
    final reasonController = TextEditingController();
    DateTime refundDate = DateTime.now();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final theme = Theme.of(context);
            final colorScheme = theme.colorScheme;
            final enteredAmount = double.tryParse(amountController.text.replaceAll(',', '')) ?? 0.0;
            final diff = enteredAmount - _batch.totalBatchAmount;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.check_circle_outline, color: Colors.green.shade700, size: 22),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Settle Batch Refund', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Record supplier credit memo or refund details for batch [${_batch.batchNumber}]. All member store orders will be marked Settled.',
                      style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Submitted Batch Total:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                          Text(
                            Helperfunctions.formatDoubleAmountForDisplay(_batch.totalBatchAmount),
                            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: colorScheme.primary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: cmController,
                      decoration: const InputDecoration(
                        labelText: 'Supplier Credit Memo # / Ref *',
                        hintText: 'e.g. CM-2026-9812',
                        prefixIcon: Icon(Icons.receipt_long_outlined, size: 20),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Actual Supplier Refund Amount *',
                        prefixText: '₱ ',
                        prefixIcon: const Icon(Icons.payments_outlined, size: 20),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        helperText: diff.abs() > 0.01
                            ? 'Variance: ${diff >= 0 ? '+' : ''}${Helperfunctions.formatDoubleAmountForDisplay(diff)}'
                            : 'Matches submitted batch amount exactly',
                        helperStyle: TextStyle(
                          color: diff.abs() > 0.01 ? (diff < 0 ? Colors.red.shade700 : Colors.green.shade700) : Colors.grey.shade600,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (diff.abs() > 0.01) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: reasonController,
                        decoration: const InputDecoration(
                          labelText: 'Adjustment / Variance Reason',
                          hintText: 'e.g. Supplier rejected 2 melted tubs',
                          prefixIcon: Icon(Icons.info_outline, size: 20),
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: refundDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 30)),
                        );
                        if (picked != null) {
                          setDialogState(() => refundDate = picked);
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Refund / Credit Date',
                          prefixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        child: Text(
                          Helperfunctions.formatDateForDisplay(refundDate),
                          style: const TextStyle(fontSize: 13.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
                  onPressed: () {
                    final cm = cmController.text.trim();
                    final parsed = double.tryParse(amountController.text.replaceAll(',', ''));
                    if (cm.isEmpty) {
                      ShowMessage.error(context, 'Please enter the supplier credit memo or reference number.');
                      return;
                    }
                    if (parsed == null || parsed < 0) {
                      ShowMessage.error(context, 'Please enter a valid refund amount.');
                      return;
                    }
                    Navigator.pop(dialogCtx, true);
                  },
                  child: const Text('Confirm Settle'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != true || !mounted) return;

    final parsedAmount = double.parse(amountController.text.replaceAll(',', ''));
    final cmNo = cmController.text.trim();
    final reason = reasonController.text.trim();

    try {
      final success = await ShowMessage.runWithLoading<bool>(
        context,
        message: 'Settling Warehouse Batch...',
        task: () async {
          await _controller.settleWarehouseBatch(
            batchId: widget.batchId,
            existingBatch: _batch,
            supplierRefundAmount: parsedAmount,
            supplierCreditMemoNo: cmNo,
            supplierRefundDate: refundDate,
            adjustmentReason: reason,
          );
          return true;
        },
      );

      if (success == true) {
        final snap = await FirebaseFirestore.instance.collection('badorder_batch').doc(widget.batchId).get();
        if (snap.exists && mounted) {
          setState(() {
            _batch = BadOrderBatch.fromJson(snap.data()!, snap.id);
          });
          ShowMessage.success(context, 'Batch [${_batch.batchNumber}] has been settled successfully!');
        }
      }
    } catch (e, s) {
      ErrorLogService.logError(
        page: 'BadOrderBatchDetailPage',
        action: 'Settle Batch',
        error: e,
        stackTrace: s,
        extraData: {'batchId': widget.batchId},
      );
      if (mounted) ShowMessage.error(context, 'Failed to settle batch: $e');
    }
  }

  Future<void> _onDeleteBatch() async {
    if (!_isDealer) {
      ShowMessage.error(context, 'Only dealers are authorized to delete warehouse batches.');
      return;
    }

    final confirmed = await ShowMessage.confirm(
      context,
      title: 'Cancel / Delete Batch',
      message:
          'Are you sure you want to delete batch [${_batch.batchNumber}]?\n\nAll ${_batch.badOrderIds.length} member bad order records will be restored to "Store Pullout" status and made available for future batches.',
      isDestructive: true,
      icon: Icons.delete_outline,
      confirmText: 'Delete Batch',
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);
    try {
      await _controller.deleteWarehouseBatch(batchId: widget.batchId, existingBatch: _batch);
      if (mounted) {
        ShowMessage.success(context, 'Batch deleted and store records restored to pending.');
        Navigator.pop(context, true);
      }
    } catch (e, s) {
      ErrorLogService.logError(
        page: 'BadOrderBatchDetailPage',
        action: 'Delete Batch',
        error: e,
        stackTrace: s,
        extraData: {'batchId': widget.batchId},
      );
      if (mounted) ShowMessage.error(context, 'Failed to delete batch: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildBatchSummaryCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = _getStatusColor(_batch.status);
    final isSettled = _batch.isSettled;

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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isSettled ? Icons.check_circle_outline : Icons.warehouse_outlined,
                          size: 20,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Batch Reference', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                            Text(
                              _batch.batchNumber,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _batch.status,
                    style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Supplier Slip / DR #', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Text(
                        _batch.supplierRefNo.isNotEmpty ? _batch.supplierRefNo : 'None recorded',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Warehouse Pullout Date', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Text(
                        Helperfunctions.formatDateForDisplay(_batch.pulloutDate.toDate()),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Stores Included', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Text(
                        '${_batch.badOrderIds.length} store pullouts',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Submitted Total Amount', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Text(
                        Helperfunctions.formatDoubleAmountForDisplay(_batch.totalBatchAmount),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.primary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_batch.notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Batch Notes', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text(_batch.notes, style: const TextStyle(fontSize: 13)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSupplierRefundCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final isSettled = _batch.isSettled;

    return Card(
      elevation: 0,
      color: isSettled ? Colors.green.shade50.withValues(alpha: 0.5) : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isSettled ? Colors.green.shade300 : colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
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
                    color: isSettled ? Colors.green.shade100 : Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isSettled ? Icons.payments_outlined : Icons.schedule,
                    size: 18,
                    color: isSettled ? Colors.green.shade800 : Colors.amber.shade900,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  isSettled ? 'Supplier Refund & Credit Memo' : 'Supplier Refund Pending',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isSettled ? Colors.green.shade900 : Colors.amber.shade900,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            if (isSettled) ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Credit Memo / Ref #', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 2),
                        Text(
                          _batch.supplierCreditMemoNo,
                          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Refund Credited Amount', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 2),
                        Text(
                          Helperfunctions.formatDoubleAmountForDisplay(_batch.supplierRefundAmount ?? _batch.totalBatchAmount),
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (_batch.supplierRefundDate != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Settled Date', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 2),
                          Text(
                            Helperfunctions.formatTimestampForDisplay(_batch.supplierRefundDate!),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  if (_batch.supplierRefundBy != null)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Recorded By', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 2),
                          Text(_batch.supplierRefundBy!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                ],
              ),
              if (_batch.varianceAmount.abs() > 0.01) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: _batch.varianceAmount < 0 ? Colors.red.shade50 : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _batch.varianceAmount < 0 ? Colors.red.shade200 : Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: _batch.varianceAmount < 0 ? Colors.red.shade800 : Colors.blue.shade800,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Variance: ${_batch.varianceAmount >= 0 ? '+' : ''}${Helperfunctions.formatDoubleAmountForDisplay(_batch.varianceAmount)}'
                          '${_batch.adjustmentReason.isNotEmpty ? ' (${_batch.adjustmentReason})' : ''}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _batch.varianceAmount < 0 ? Colors.red.shade900 : Colors.blue.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ] else ...[
              Text(
                'This batch has been pulled out from the warehouse by the supplier and is awaiting the supplier credit memo or refund reimbursement.',
                style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
              ),
              if (_isDealer) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: AsyncFilledButton.icon(
                    onPressed: _openSettleModal,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 20),
                    label: const Text('Record Supplier Refund & Settle Batch', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMemberBadOrdersSection() {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'MEMBER STORE ORDERS (${_batch.badOrderIds.length})',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        FutureBuilder<List<DocumentSnapshot<Map<String, dynamic>>>>(
          future: Future.wait(
            _batch.badOrderIds.map((id) => FirebaseFirestore.instance.collection('badorder').doc(id).get()),
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
              );
            }

            final docs = snapshot.data ?? [];
            final validBadOrders = <BadOrder>[];
            for (final doc in docs) {
              if (doc.exists && doc.data() != null) {
                validBadOrders.add(BadOrder.fromJson(doc.data()!, doc.id));
              }
            }

            if (validBadOrders.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: const Center(
                  child: Text('No store records found.', style: TextStyle(color: Colors.grey)),
                ),
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: validBadOrders.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final bo = validBadOrders[index];

                return Card(
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  color: colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            bo.hapistore,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          Helperfunctions.formatDoubleAmountForDisplay(bo.totalAmount),
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5, color: colorScheme.primary),
                        ),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Row(
                        children: [
                          Text(
                            '${Helperfunctions.formatDateForDisplay(bo.badorderDate.toDate())} • ${bo.items.length} items',
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: bo.isStoreRefunded ? Colors.green.shade50 : Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: bo.isStoreRefunded ? Colors.green.shade200 : Colors.amber.shade200,
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              bo.isStoreRefunded ? 'Store Refunded' : 'Store Unrefunded',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: bo.isStoreRefunded ? Colors.green.shade800 : Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () {
                      Helperfunctions.navigateTo(
                        context,
                        BadOrderPage(recID: bo.id, badorder: bo),
                      );
                    },
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSettled = _batch.isSettled;

    return Scaffold(
      appBar: CustomAppbar(
        title: 'Warehouse Batch',
        subtitle: _batch.batchNumber,
        actions: [
          if (_isDealer && !isSettled)
            IconButton(
              tooltip: 'Delete / Cancel Batch',
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              onPressed: _isLoading ? null : _onDeleteBatch,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBatchSummaryCard(),
            const SizedBox(height: 16),
            _buildSupplierRefundCard(),
            const SizedBox(height: 16),
            _buildMemberBadOrdersSection(),
            const SizedBox(height: 16),
            if (widget.batchId.isNotEmpty)
              AuditHistoryWidget(
                createdBy: _batch.createdBy,
                createdDate: _batch.createdDate,
                lastUpdatedBy: _batch.lastUpdatedBy,
                lastUpdatedDate: _batch.lastupdatedDate,
              ),
          ],
        ),
      ),
    );
  }
}
