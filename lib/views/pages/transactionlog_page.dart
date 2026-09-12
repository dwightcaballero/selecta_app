import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/models/transactionlog.dart';
import 'package:flutter_app/services/transactionlog_service.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:intl/intl.dart';

class TransactionLogPage extends StatefulWidget {
  const TransactionLogPage({super.key});

  @override
  State<TransactionLogPage> createState() => _TransactionLogPageState();
}

class _TransactionLogPageState extends State<TransactionLogPage> {
  final TransactionLogService db = TransactionLogService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedActionFilter = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppbar(title: 'Audit Logs', subtitle: 'System Activity & Changes'),
      body: Column(
        children: [
          // 1. Search Bar & Action Filter Chips
          _buildFilterHeader(),

          // 2. Logs Stream List
          Expanded(child: _buildLogsList()),
        ],
      ),
    );
  }

  Widget _buildFilterHeader() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        children: [
          // Search Bar
          TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _searchQuery = val.trim()),
            decoration: InputDecoration(
              hintText: 'Search logs by user, store, or details...',
              hintStyle: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
              prefixIcon: Icon(Icons.search, size: 20, color: colorScheme.primary),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colorScheme.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Action Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: 8,
              children: [
                _buildFilterChip('All', null),
                _buildFilterChip(LogAction.create, Icons.add_circle_outline, color: Colors.green),
                _buildFilterChip(LogAction.update, Icons.edit_outlined, color: Colors.orange),
                _buildFilterChip(LogAction.delete, Icons.delete_outline, color: Colors.red),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String action, IconData? icon, {Color? color}) {
    bool isSelected = _selectedActionFilter == action;

    return ChoiceChip(
      showCheckmark: false,
      avatar: icon != null ? Icon(icon, size: 16, color: isSelected ? Colors.white : color) : null,
      label: Text(action),
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedActionFilter = action),
    );
  }

  Widget _buildLogsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: db.getListLogs(),
      builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
        if (snapshot.hasError) {
          return _buildErrorState();
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final allDocs = snapshot.data?.docs ?? [];
        if (allDocs.isEmpty) {
          return _buildEmptyState();
        }

        final List<QueryDocumentSnapshot> filteredLogs = [];

        for (var doc in allDocs) {
          final log = doc.data() as TransactionLog;

          bool matchesAction = _selectedActionFilter == 'All' || log.logAction == _selectedActionFilter;
          bool matchesSearch =
              _searchQuery.isEmpty ||
              log.message.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              log.details.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              log.loggedBy.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              log.loggedRole.toLowerCase().contains(_searchQuery.toLowerCase());

          if (matchesAction && matchesSearch) {
            filteredLogs.add(doc);
          }
        }

        if (filteredLogs.isEmpty) {
          return _buildNoSearchResultsState();
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          itemCount: filteredLogs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final log = filteredLogs[index].data() as TransactionLog;
            return _buildLogCard(log);
          },
        );
      },
    );
  }

  Widget _buildLogCard(TransactionLog log) {
    final colorScheme = Theme.of(context).colorScheme;

    Color actionColor = Colors.blue;
    IconData actionIcon = Icons.info_outline;

    if (log.logAction == LogAction.create) {
      actionColor = Colors.green;
      actionIcon = Icons.add_circle_outline;
    } else if (log.logAction == LogAction.update) {
      actionColor = Colors.orange.shade800;
      actionIcon = Icons.edit_outlined;
    } else if (log.logAction == LogAction.delete) {
      actionColor = Colors.red;
      actionIcon = Icons.delete_outline;
    }

    final dateStr = DateFormat('EEE, d MMM yyyy • hh:mm a').format(log.loggedDate.toDate());

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Action Badge + Message + Role/User
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: actionColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                  child: Icon(actionIcon, color: actionColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(log.message, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.person_outline, size: 14, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            '${log.loggedBy} (${log.loggedRole})',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: actionColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                  child: Text(
                    log.logAction.toUpperCase(),
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: actionColor),
                  ),
                ),
              ],
            ),

            // Details Container (if available)
            if (log.details.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                ),
                child: Text(log.details, style: const TextStyle(fontSize: 13, height: 1.35)),
              ),
            ],

            const SizedBox(height: 10),

            // Footer Timestamp
            Row(
              children: [
                Icon(Icons.access_time, size: 13, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(dateStr, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.history_toggle_off_rounded, color: Colors.blue, size: 50),
            ),
            const SizedBox(height: 16),
            const Text('No Logs Available', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text(
              'Audit entries will appear here as transactions and records are modified.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoSearchResultsState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off_rounded, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text('No logs matching "$_searchQuery"', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.red, size: 40),
          SizedBox(height: 8),
          Text('Unable to load audit logs'),
        ],
      ),
    );
  }
}
