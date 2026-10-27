import 'package:flutter/material.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/models/return_proof.dart';

/// Modal dialog showing the details, photo, and audit status of a Return Proof.
class ViewReturnProofDialog extends StatelessWidget {
  final ReturnProof proof;

  const ViewReturnProofDialog({super.key, required this.proof});

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
        return 'Confirmed by Warehouse';
      case ReturnProofStatus.submitted:
        return 'Awaiting Warehouse Confirmation';
      case ReturnProofStatus.rejected:
        return 'Rejected';
      case ReturnProofStatus.overridden:
        return 'Dealer Overridden';
      default:
        return 'Proof Required';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = _getStatusColor(proof.status);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 550, maxHeight: 750),
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
                          proof.storeName,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Return Proof • ${proof.dayKey}',
                          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(25),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: statusColor.withAlpha(80)),
                    ),
                    child: Text(
                      _getStatusLabel(proof.status),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Image display
              if (proof.imageUrl.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    proof.imageUrl,
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
                      height: 160,
                      color: colorScheme.surfaceContainerHighest,
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.broken_image_outlined, size: 40, color: Colors.grey),
                            SizedBox(height: 8),
                            Text('Failed to load proof image', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Submission details
              _buildInfoRow('Submitted By', proof.submittedBy.isNotEmpty ? proof.submittedBy : 'N/A'),
              if (proof.submittedDate != null)
                _buildInfoRow('Submitted Date', Helperfunctions.formatTimestampForDisplay(proof.submittedDate!)),
              if (proof.confirmedBy.isNotEmpty)
                _buildInfoRow('Confirmed By', proof.confirmedBy),
              if (proof.confirmedDate != null)
                _buildInfoRow('Confirmed Date', Helperfunctions.formatTimestampForDisplay(proof.confirmedDate!)),
              if (proof.overrideBy.isNotEmpty) ...[
                _buildInfoRow('Overridden By', proof.overrideBy),
                if (proof.overrideReason.isNotEmpty)
                  _buildInfoRow('Override Reason', proof.overrideReason),
              ],
              if (proof.rejectReason.isNotEmpty) ...[
                _buildInfoRow('Rejection Reason', proof.rejectReason, isWarning: true),
              ],
              if (proof.notes.isNotEmpty)
                _buildInfoRow('Salesman Notes', proof.notes),

              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // Return Items and Variances
              Text(
                'Items Summary (${proof.items.length})',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withAlpha(80),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.outlineVariant.withAlpha(60)),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: proof.items.length,
                  separatorBuilder: (context, index) => Divider(
                    height: 1,
                    color: colorScheme.outlineVariant.withAlpha(40),
                  ),
                  itemBuilder: (context, idx) {
                    final item = proof.items[idx];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.productName,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ),
                          Text(
                            'Ret: ${item.returnedQuantity}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          if (proof.isConfirmed) ...[
                            const SizedBox(width: 8),
                            Text(
                              'Rec: ${item.receivedQuantity}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: item.hasVariance ? Colors.red : Colors.green.shade700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),

              // Close button
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isWarning = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isWarning ? Colors.red : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
