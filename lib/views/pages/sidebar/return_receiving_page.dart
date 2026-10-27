import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/responsive.dart';
import 'package:selecta_ops/models/return_proof.dart';
import 'package:selecta_ops/services/auth_service.dart';
import 'package:selecta_ops/services/return_proof_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:selecta_ops/views/widgets/async_button.dart';

/// Presentation view for warehouse staff & dealers to review submitted return proofs,
/// verify received physical quantities, flag variances, and confirm or reject receipt.
class ReturnReceivingPage extends StatefulWidget {
  const ReturnReceivingPage({super.key});

  @override
  State<ReturnReceivingPage> createState() => _ReturnReceivingPageState();
}

class _ReturnReceivingPageState extends State<ReturnReceivingPage> {
  final ReturnProofService _service = ReturnProofService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedTab = 'Pending'; // 'Pending' | 'Confirmed' | 'All'

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _currentUserName {
    return authService.value.currentUser?.displayName ??
        authService.value.currentUser?.email ??
        'Warehouse/Dealer';
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case ReturnProofStatus.confirmed:
        return Colors.green;
      case ReturnProofStatus.submitted:
        return Colors.amber.shade800;
      case ReturnProofStatus.rejected:
        return Colors.red;
      case ReturnProofStatus.overridden:
        return Colors.blue.shade700;
      default:
        return Colors.orange;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case ReturnProofStatus.confirmed:
        return 'Confirmed';
      case ReturnProofStatus.submitted:
        return 'Pending Review';
      case ReturnProofStatus.rejected:
        return 'Rejected';
      case ReturnProofStatus.overridden:
        return 'Overridden';
      default:
        return 'Proof Required';
    }
  }

  void _openReviewDialog(ReturnProof proof) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ReturnReviewDialog(
        proof: proof,
        service: _service,
        currentUserName: _currentUserName,
        onProcessed: () {
          if (mounted) setState(() {});
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDesktop = ScreenSize.isDesktop(context);

    return Scaffold(
      appBar: CustomAppbar(
        title: 'Return Receiving',
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search store name, salesman...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest.withAlpha(120),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Filter Tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                _buildTabChip('Pending', Icons.hourglass_top_rounded),
                const SizedBox(width: 8),
                _buildTabChip('Confirmed', Icons.check_circle_outline_rounded),
                const SizedBox(width: 8),
                _buildTabChip('All', Icons.list_alt_rounded),
              ],
            ),
          ),
          const Divider(height: 1),

          // Main Queue Stream
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection(RETURN_PROOFS_COLLECTION_REF)
                  .orderBy('proofDate', descending: true)
                  .limit(100)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text('Error loading returns queue: ${snapshot.error}'),
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                var proofs = docs.map((d) => ReturnProof.fromSnapshot(d)).toList();

                // Apply tab filter
                if (_selectedTab == 'Pending') {
                  proofs = proofs.where((p) => p.status == ReturnProofStatus.submitted).toList();
                } else if (_selectedTab == 'Confirmed') {
                  proofs = proofs.where((p) => p.status == ReturnProofStatus.confirmed || p.status == ReturnProofStatus.overridden).toList();
                }

                // Apply search filter
                if (_searchQuery.isNotEmpty) {
                  proofs = proofs.where((p) {
                    final sName = p.storeName.toLowerCase();
                    final sBy = p.submittedBy.toLowerCase();
                    final dKey = p.dayKey.toLowerCase();
                    return sName.contains(_searchQuery) ||
                        sBy.contains(_searchQuery) ||
                        dKey.contains(_searchQuery);
                  }).toList();
                }

                if (proofs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox_outlined, size: 56, color: colorScheme.outlineVariant),
                        const SizedBox(height: 12),
                        Text(
                          _selectedTab == 'Pending'
                              ? 'No returns awaiting review'
                              : 'No return proof records found',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                if (isDesktop) {
                  return GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 2.4,
                    ),
                    itemCount: proofs.length,
                    itemBuilder: (ctx, idx) => _buildProofCard(proofs[idx]),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: proofs.length,
                  itemBuilder: (ctx, idx) => _buildProofCard(proofs[idx]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabChip(String label, IconData icon) {
    final isSelected = _selectedTab == label;
    final colorScheme = Theme.of(context).colorScheme;

    return ChoiceChip(
      selected: isSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
      onSelected: (_) => setState(() => _selectedTab = label),
    );
  }

  Widget _buildProofCard(ReturnProof proof) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = _getStatusColor(proof.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: proof.isSubmitted
              ? Colors.amber.shade400
              : colorScheme.outlineVariant.withAlpha(100),
          width: proof.isSubmitted ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openReviewDialog(proof),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      proof.storeName,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: statusColor.withAlpha(80)),
                    ),
                    child: Text(
                      _getStatusLabel(proof.status),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined, size: 13, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    proof.dayKey,
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 12),
                  Icon(Icons.person_outline_rounded, size: 14, color: colorScheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      proof.submittedBy.isNotEmpty ? proof.submittedBy : 'Salesman',
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withAlpha(120),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${proof.items.length} items • ${proof.totalReturnedQuantity} units',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (proof.hasVariance) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.red.withAlpha(30),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Variance Flagged',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  FilledButton.tonalIcon(
                    onPressed: () => _openReviewDialog(proof),
                    icon: Icon(
                      proof.isSubmitted ? Icons.fact_check_rounded : Icons.visibility_outlined,
                      size: 15,
                    ),
                    label: Text(proof.isSubmitted ? 'Review & Confirm' : 'View Details'),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Interactive Review & Confirmation Dialog for Warehouse/Dealer
class _ReturnReviewDialog extends StatefulWidget {
  final ReturnProof proof;
  final ReturnProofService service;
  final String currentUserName;
  final VoidCallback onProcessed;

  const _ReturnReviewDialog({
    required this.proof,
    required this.service,
    required this.currentUserName,
    required this.onProcessed,
  });

  @override
  State<_ReturnReviewDialog> createState() => _ReturnReviewDialogState();
}

class _ReturnReviewDialogState extends State<_ReturnReviewDialog> {
  late final List<TextEditingController> _receivedQtyControllers;
  bool _isProcessing = false;
  bool _autoRestock = true;

  @override
  void initState() {
    super.initState();
    _receivedQtyControllers = widget.proof.items.map((item) {
      return TextEditingController(text: item.receivedQuantity.toString());
    }).toList();
  }

  @override
  void dispose() {
    for (final c in _receivedQtyControllers) {
      c.dispose();
    }
    super.dispose();
  }

  List<ReturnProofItem> _buildReceivedItems() {
    final updated = <ReturnProofItem>[];
    for (int i = 0; i < widget.proof.items.length; i++) {
      final base = widget.proof.items[i];
      final recQty = int.tryParse(_receivedQtyControllers[i].text.trim()) ?? base.returnedQuantity;
      updated.add(base.copyWith(receivedQuantity: recQty));
    }
    return updated;
  }

  bool get _hasAnyVariance {
    for (int i = 0; i < widget.proof.items.length; i++) {
      final base = widget.proof.items[i];
      final recQty = int.tryParse(_receivedQtyControllers[i].text.trim()) ?? base.returnedQuantity;
      if (recQty != base.returnedQuantity) return true;
    }
    return false;
  }

  Future<void> _confirmReceipt() async {
    setState(() => _isProcessing = true);
    try {
      final receivedItems = _buildReceivedItems();
      await widget.service.confirmProof(
        proofId: widget.proof.id,
        receivedItems: receivedItems,
        confirmedBy: widget.currentUserName,
        autoRestock: _autoRestock,
      );

      if (!mounted) return;
      ShowMessage.success(context, 'Return proof confirmed and stock replenished!');
      widget.onProcessed();
      Navigator.pop(context);
    } catch (e) {
      if (mounted) ShowMessage.error(context, 'Failed to confirm return: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _rejectProof() async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Return Proof'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter reason for rejecting this return proof (required):'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'e.g. Photo unreadable, missing physical items, incorrect store',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                ShowMessage.error(ctx, 'Rejection reason is required');
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed == true && reasonController.text.trim().isNotEmpty) {
      setState(() => _isProcessing = true);
      try {
        await widget.service.rejectProof(
          proofId: widget.proof.id,
          rejectReason: reasonController.text.trim(),
          rejectedBy: widget.currentUserName,
        );

        if (!mounted) return;
        ShowMessage.info(context, 'Return proof rejected');
        widget.onProcessed();
        Navigator.pop(context);
      } catch (e) {
        if (mounted) ShowMessage.error(context, 'Failed to reject return: $e');
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _overrideGate() async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Emergency Override Return Gate'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter reason for dealer override (required for audit logging):'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                hintText: 'e.g. Inspected goods at warehouse directly',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                ShowMessage.error(ctx, 'Override reason is required');
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Override Gate'),
          ),
        ],
      ),
    );

    if (confirmed == true && reasonController.text.trim().isNotEmpty) {
      setState(() => _isProcessing = true);
      try {
        await widget.service.overrideProof(
          proofId: widget.proof.id,
          overrideReason: reasonController.text.trim(),
          overriddenBy: widget.currentUserName,
        );

        if (!mounted) return;
        ShowMessage.success(context, 'Return gate overridden');
        widget.onProcessed();
        Navigator.pop(context);
      } catch (e) {
        if (mounted) ShowMessage.error(context, 'Failed to override: $e');
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isGated = widget.proof.isSubmitted;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 800),
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.proof.storeName,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Delivery Date: ${widget.proof.dayKey} • By ${widget.proof.submittedBy}',
                          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Image display
              if (widget.proof.imageUrl.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    widget.proof.imageUrl,
                    width: double.infinity,
                    height: 220,
                    fit: BoxFit.cover,
                    loadingBuilder: (ctx, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        height: 220,
                        color: colorScheme.surfaceContainerHighest,
                        child: const Center(child: CircularProgressIndicator()),
                      );
                    },
                    errorBuilder: (ctx, err, stack) => Container(
                      height: 140,
                      color: colorScheme.surfaceContainerHighest,
                      child: const Center(child: Icon(Icons.broken_image_outlined, size: 40)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              if (widget.proof.notes.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withAlpha(80),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Salesman Notes:',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                      ),
                      const SizedBox(height: 2),
                      Text(widget.proof.notes, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Return Items and editable Received Quantities
              Row(
                children: [
                  const Text(
                    'Verify Received Quantities',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  if (_hasAnyVariance)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.withAlpha(40),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Variance Detected',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withAlpha(60),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorScheme.outlineVariant.withAlpha(60)),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: widget.proof.items.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    color: colorScheme.outlineVariant.withAlpha(40),
                  ),
                  itemBuilder: (context, idx) {
                    final item = widget.proof.items[idx];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.productName,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                                Text(
                                  'Reported returned: ${item.returnedQuantity} units',
                                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 90,
                            child: TextField(
                              controller: _receivedQtyControllers[idx],
                              keyboardType: TextInputType.number,
                              enabled: isGated,
                              textAlign: TextAlign.center,
                              decoration: InputDecoration(
                                labelText: 'Received',
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Auto restock toggle
              if (isGated) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _autoRestock,
                  title: const Text('Auto-replenish warehouse stock', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Restocks salvageable returned units to inventory upon confirmation', style: TextStyle(fontSize: 11)),
                  onChanged: (val) => setState(() => _autoRestock = val),
                ),
                const SizedBox(height: 16),
              ],

              // Actions
              if (isGated) ...[
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isProcessing ? null : _rejectProof,
                      icon: const Icon(Icons.cancel_outlined, size: 16, color: Colors.red),
                      label: const Text('Reject', style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _isProcessing ? null : _overrideGate,
                      icon: const Icon(Icons.lock_open_rounded, size: 16),
                      label: const Text('Override'),
                    ),
                    const Spacer(),
                    AsyncFilledButton.icon(
                      onPressed: _isProcessing ? null : _confirmReceipt,
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      label: const Text('Confirm Receipt'),
                    ),
                  ],
                ),
              ] else ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
