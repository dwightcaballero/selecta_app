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

  late Stream<QuerySnapshot> _logsStream;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  String _selectedActionFilter = 'All';
  DateTime _selectedDate = DateTime.now();

  // Set of expanded log document IDs for progressive disclosure
  final Set<String> _expandedLogIds = <String>{};

  @override
  void initState() {
    super.initState();
    _logsStream = db.getLogsForDay(_selectedDate);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _setDate(DateTime date) {
    setState(() {
      _selectedDate = date;
      _expandedLogIds.clear();
      _logsStream = db.getLogsForDay(_selectedDate);
    });
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      _setDate(picked);
    }
  }

  void _previousDay() {
    _setDate(_selectedDate.subtract(const Duration(days: 1)));
  }

  void _nextDay() {
    final tomorrow = _selectedDate.add(const Duration(days: 1));
    if (!tomorrow.isAfter(DateTime.now())) {
      _setDate(tomorrow);
    }
  }

  Widget _buildDateNavigator(ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final bool isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());
    final bool canGoNext = !isToday;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 22),
            visualDensity: VisualDensity.compact,
            tooltip: 'Previous Day',
            onPressed: _previousDay,
          ),
          Expanded(
            child: InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 16, color: colorScheme.primary),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        isToday
                            ? 'Today, ${DateFormat('d MMM yyyy').format(_selectedDate)}'
                            : DateFormat('EEE, d MMM yyyy').format(_selectedDate),
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 22),
            visualDensity: VisualDensity.compact,
            tooltip: 'Next Day',
            onPressed: canGoNext ? _nextDay : null,
          ),
          if (!isToday) ...[
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ActionChip(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                label: const Text('Today', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                onPressed: () => _setDate(DateTime.now()),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterChips({
    required int totalCount,
    required int createCount,
    required int updateCount,
    required int deleteCount,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildFilterChip('All', 'All ($totalCount)', null),
          const SizedBox(width: 8),
          _buildFilterChip(LogAction.create, 'Created ($createCount)', Icons.add_circle_outline, color: Colors.green),
          const SizedBox(width: 8),
          _buildFilterChip(LogAction.update, 'Updated ($updateCount)', Icons.edit_outlined, color: Colors.orange.shade800),
          const SizedBox(width: 8),
          _buildFilterChip(LogAction.delete, 'Deleted ($deleteCount)', Icons.delete_outline, color: Colors.red),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String actionKey, String label, IconData? icon, {Color? color}) {
    final bool isSelected = _selectedActionFilter == actionKey;
    final theme = Theme.of(context);

    return ChoiceChip(
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      avatar: icon != null
          ? Icon(
              icon,
              size: 14,
              color: isSelected ? theme.colorScheme.onPrimary : color,
            )
          : null,
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedActionFilter = actionKey),
    );
  }

  Widget _buildSearchBar(ThemeData theme) {
    final colorScheme = theme.colorScheme;

    return SizedBox(
      height: 42,
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onChanged: (val) => setState(() => _searchQuery = val.trim()),
        style: const TextStyle(fontSize: 13.5),
        decoration: InputDecoration(
          hintText: 'Search user, store, message...',
          hintStyle: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8)),
          prefixIcon: Icon(Icons.search, size: 18, color: colorScheme.primary),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  splashRadius: 16,
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildLogCard(String docId, TransactionLog log) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final bool isExpanded = _expandedLogIds.contains(docId);
    final bool hasDetails = log.details.trim().isNotEmpty;

    Color actionColor = Colors.blue;
    IconData actionIcon = Icons.info_outline;

    if (log.logAction == LogAction.create) {
      actionColor = Colors.green.shade700;
      actionIcon = Icons.add_circle_outline;
    } else if (log.logAction == LogAction.update) {
      actionColor = Colors.orange.shade800;
      actionIcon = Icons.edit_outlined;
    } else if (log.logAction == LogAction.delete) {
      actionColor = Colors.red.shade700;
      actionIcon = Icons.delete_outline;
    }

    final timeStr = DateFormat('hh:mm a').format(log.loggedDate.toDate());

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: hasDetails
            ? () {
                setState(() {
                  if (isExpanded) {
                    _expandedLogIds.remove(docId);
                  } else {
                    _expandedLogIds.add(docId);
                  }
                });
              }
            : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Main Header Row
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Action Icon with subtle background
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: actionColor.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(actionIcon, color: actionColor, size: 16),
                    ),
                    const SizedBox(width: 10),

                    // Log Content Area
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Message
                          Text(
                            log.message,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.25),
                          ),
                          const SizedBox(height: 6),

                          // Metadata: User & Role
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 8,
                                backgroundColor: colorScheme.primaryContainer,
                                child: Text(
                                  log.loggedBy.isNotEmpty ? log.loggedBy[0].toUpperCase() : '?',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                log.loggedBy,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              if (log.loggedRole.isNotEmpty) ...[
                                Text(
                                  ' • ${log.loggedRole}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Timestamp & Expand Indicator
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (hasDetails) ...[
                          const SizedBox(height: 4),
                          Icon(
                            isExpanded ? Icons.expand_less : Icons.expand_more,
                            size: 18,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Expandable Details (Progressive Disclosure)
              if (hasDetails && isExpanded) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                    border: Border(
                      top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.article_outlined, size: 13, color: colorScheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            'CHANGE DETAILS',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SelectableText(
                        log.details,
                        style: TextStyle(fontSize: 12, height: 1.4, color: colorScheme.onSurface),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.history_toggle_off_rounded, color: theme.colorScheme.primary, size: 44),
            ),
            const SizedBox(height: 16),
            Text(
              isToday ? 'No Activity Recorded Today' : 'No Activity on This Date',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Changes to deliveries, store records, and orders will appear here automatically.',
              style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoSearchResultsState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 44, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              'No logs match "$_searchQuery"',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                  _selectedActionFilter = 'All';
                });
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Reset filters'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, color: Theme.of(context).colorScheme.error, size: 36),
          const SizedBox(height: 8),
          const Text('Unable to load audit logs'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: const CustomAppbar(
        title: 'Audit Logs',
        subtitle: 'System Activity & Changes',
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _logsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildErrorState();
          }
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allDocs = snapshot.data?.docs ?? [];

          // Calculate activity counts for the selected day
          int createCount = 0;
          int updateCount = 0;
          int deleteCount = 0;

          final List<QueryDocumentSnapshot> filteredLogs = [];

          for (var doc in allDocs) {
            final log = doc.data() as TransactionLog;

            if (log.logAction == LogAction.create) createCount++;
            if (log.logAction == LogAction.update) updateCount++;
            if (log.logAction == LogAction.delete) deleteCount++;

            final bool matchesAction = _selectedActionFilter == 'All' || log.logAction == _selectedActionFilter;
            final bool matchesSearch = _searchQuery.isEmpty ||
                log.message.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                log.details.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                log.loggedBy.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                log.loggedRole.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                log.dealerName.toLowerCase().contains(_searchQuery.toLowerCase());

            if (matchesAction && matchesSearch) {
              filteredLogs.add(doc);
            }
          }

          return Column(
            children: [
              // Sticky Filter Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  children: [
                    _buildDateNavigator(theme),
                    const SizedBox(height: 8),
                    _buildSearchBar(theme),
                    const SizedBox(height: 8),
                    _buildFilterChips(
                      totalCount: allDocs.length,
                      createCount: createCount,
                      updateCount: updateCount,
                      deleteCount: deleteCount,
                    ),
                  ],
                ),
              ),

              const Divider(height: 1, thickness: 0.5),

              // Activity Feed List
              Expanded(
                child: allDocs.isEmpty
                    ? _buildEmptyState()
                    : filteredLogs.isEmpty
                        ? _buildNoSearchResultsState()
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                            itemCount: filteredLogs.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final doc = filteredLogs[index];
                              final log = doc.data() as TransactionLog;
                              return _buildLogCard(doc.id, log);
                            },
                          ),
              ),
            ],
          );
        },
      ),
    );
  }
}
