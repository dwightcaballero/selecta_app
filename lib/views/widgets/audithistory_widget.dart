import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Reusable card widget displaying creation and audit trail history.
///
/// Standardizes the "Audit & History" collapsible card used throughout the app
/// (e.g. Credit, Delivery, Expenses, Bad Orders, Tasks, etc.).
class AuditHistoryWidget extends StatelessWidget {
  /// The user/admin identifier who originally created this record.
  final String createdBy;

  /// The timestamp or DateTime when this record was created.
  final dynamic createdDate;

  /// Optional page/screen name where this record was created.
  final String? createdPage;

  /// The user/admin identifier who most recently modified this record.
  final String lastUpdatedBy;

  /// The timestamp or DateTime when this record was last modified.
  final dynamic lastUpdatedDate;

  /// Optional page/screen name where this record was last modified.
  final String? lastUpdatedPage;

  /// Optional additional custom audit rows to append.
  final List<Widget>? additionalRows;

  /// Header title for the card (defaults to 'Audit & History').
  final String title;

  /// Initial expansion state for the collapsible tile.
  final bool initiallyExpanded;

  const AuditHistoryWidget({
    super.key,
    required this.createdBy,
    required this.createdDate,
    this.createdPage,
    required this.lastUpdatedBy,
    required this.lastUpdatedDate,
    this.lastUpdatedPage,
    this.additionalRows,
    this.title = 'Audit & History',
    this.initiallyExpanded = false,
  });

  /// Formats a [Timestamp], [DateTime], or fallback value into a standard readable date string.
  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    if (date is Timestamp) {
      return DateFormat('E, d MMM yyyy, hh:mm a').format(date.toDate());
    }
    if (date is DateTime) {
      return DateFormat('E, d MMM yyyy, hh:mm a').format(date);
    }
    return date.toString();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: 1,
        ),
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
        title: Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
        initiallyExpanded: initiallyExpanded,
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
              spacing: 8,
              children: [
                AuditHistoryRow(label: 'Created By', value: createdBy),
                AuditHistoryRow(
                  label: 'Created Date',
                  value: _formatDate(createdDate),
                ),
                if (createdPage != null && createdPage!.trim().isNotEmpty)
                  AuditHistoryRow(
                    label: 'Created On Page',
                    value: createdPage!,
                  ),
                const Divider(height: 12),
                AuditHistoryRow(label: 'Last Updated By', value: lastUpdatedBy),
                AuditHistoryRow(
                  label: 'Last Updated Date',
                  value: _formatDate(lastUpdatedDate),
                ),
                if (lastUpdatedPage != null && lastUpdatedPage!.trim().isNotEmpty)
                  AuditHistoryRow(
                    label: 'Last Updated Page',
                    value: lastUpdatedPage!,
                  ),
                if (additionalRows != null && additionalRows!.isNotEmpty) ...[
                  const Divider(height: 12),
                  ...additionalRows!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Reusable individual row inside an audit history list.
class AuditHistoryRow extends StatelessWidget {
  final String label;
  final String value;

  const AuditHistoryRow({
    super.key,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
          ),
        ),
      ],
    );
  }
}
