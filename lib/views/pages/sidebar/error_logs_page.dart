import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:selecta_ops/services/error_log_service.dart';
import 'package:selecta_ops/views/widgets/alert_widget.dart';
import 'package:selecta_ops/views/widgets/appbar_widget.dart';
import 'package:intl/intl.dart';

/// Developer-facing Error Logs Viewer allowing inspection, search,
/// and management of Cloud Firestore and offline queued error logs.
class ErrorLogsPage extends StatefulWidget {
  const ErrorLogsPage({super.key});

  @override
  State<ErrorLogsPage> createState() => _ErrorLogsPageState();
}

class _ErrorLogsPageState extends State<ErrorLogsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedPageFilter = 'All';
  int _pendingLocalCount = 0;
  bool _isUploadingPending = false;
  final Set<String> _expandedLogIds = <String>{};

  @override
  void initState() {
    super.initState();
    _refreshPendingLocalCount();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshPendingLocalCount() async {
    final count = await ErrorLogService.getPendingLogCount();
    if (mounted) {
      setState(() => _pendingLocalCount = count);
    }
  }

  Future<void> _handleUploadPendingLogs() async {
    setState(() => _isUploadingPending = true);
    try {
      final count = await ErrorLogService.uploadPendingLogs();
      await _refreshPendingLocalCount();
      if (!mounted) return;

      if (count > 0) {
        ShowMessage.success(context, 'Successfully uploaded $count pending log${count == 1 ? "" : "s"} to Firestore');
      } else {
        ShowMessage.alert(context, title: 'Error Logs', message: 'All local error logs are already synchronized.');
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Failed to upload offline logs: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingPending = false);
      }
    }
  }

  Future<void> _handleCopyAllLogs(List<ErrorLogItem> logs) async {
    if (logs.isEmpty) {
      ShowMessage.alert(context, title: 'Export Logs', message: 'No error logs available to copy.');
      return;
    }

    final text = ErrorLogService.formatLogsAsText(logs, title: 'FIRESTORE CLOUD ERROR LOGS REPORT');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ShowMessage.success(context, 'Copied ${logs.length} diagnostic logs to clipboard');
    }
  }

  Future<void> _handleClearAllCloudLogs() async {
    final confirmed = await ShowMessage.confirm(
      context,
      title: 'Clear All Cloud Logs',
      message: 'Are you sure you want to permanently delete ALL error logs from Cloud Firestore? This cannot be undone.',
      confirmText: 'Delete All',
      isDestructive: true,
      icon: Icons.delete_forever_rounded,
    );

    if (!confirmed) return;

    try {
      final count = await ErrorLogService.clearAllFirestoreLogs();
      if (mounted) {
        ShowMessage.success(context, 'Cleared $count error log records from Firestore.');
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Failed to clear cloud logs: $e');
      }
    }
  }

  Future<void> _handleClearLocalQueue() async {
    final confirmed = await ShowMessage.confirm(
      context,
      title: 'Clear Local Queue',
      message: 'Clear all locally cached error logs on this device?',
      confirmText: 'Clear Local',
      isDestructive: true,
      icon: Icons.cleaning_services_rounded,
    );

    if (!confirmed) return;

    await ErrorLogService.clearLocalLogs();
    await _refreshPendingLocalCount();
    if (mounted) {
      ShowMessage.success(context, 'Local error log queue cleared.');
    }
  }

  Future<void> _handleDeleteSingleLog(ErrorLogItem item) async {
    final confirmed = await ShowMessage.confirm(
      context,
      title: 'Delete Error Log',
      message: 'Delete log entry "${item.id}" permanently?',
      confirmText: 'Delete',
      isDestructive: true,
      icon: Icons.delete_outline_rounded,
    );

    if (!confirmed) return;

    try {
      await ErrorLogService.deleteFirestoreLog(item.id);
      if (mounted) {
        ShowMessage.success(context, 'Error log removed.');
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Failed to delete log: $e');
      }
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ShowMessage.success(context, 'Copied $label to clipboard');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return StreamBuilder<List<ErrorLogItem>>(
      stream: ErrorLogService.streamFirestoreLogs(),
      builder: (context, snapshot) {
        final allLogs = snapshot.data ?? [];
        final isLoading = snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData;

        // Extract available unique page names for filtering
        final pageSet = <String>{'All'};
        for (final l in allLogs) {
          if (l.page.isNotEmpty) pageSet.add(l.page);
        }
        final pageList = pageSet.toList()..sort();

        // Apply filters
        final query = _searchController.text.trim().toLowerCase();
        final filteredLogs = allLogs.where((l) {
          final matchesPage = _selectedPageFilter == 'All' || l.page == _selectedPageFilter;
          if (!matchesPage) return false;

          if (query.isEmpty) return true;
          return l.error.toLowerCase().contains(query) ||
              l.action.toLowerCase().contains(query) ||
              l.page.toLowerCase().contains(query) ||
              (l.userEmail?.toLowerCase().contains(query) ?? false) ||
              (l.stackTrace?.toLowerCase().contains(query) ?? false);
        }).toList();

        return Scaffold(
          appBar: CustomAppbar(
            title: 'Error Logs',
            subtitle: 'Firebase Cloud & Device Diagnostics',
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (value) {
                  switch (value) {
                    case 'upload_pending':
                      _handleUploadPendingLogs();
                      break;
                    case 'copy_all':
                      _handleCopyAllLogs(allLogs);
                      break;
                    case 'clear_local':
                      _handleClearLocalQueue();
                      break;
                    case 'clear_cloud':
                      _handleClearAllCloudLogs();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'upload_pending',
                    child: Row(
                      children: [
                        Icon(Icons.cloud_upload_outlined, size: 20, color: colorScheme.primary),
                        const SizedBox(width: 10),
                        Text('Sync Offline Logs ($_pendingLocalCount)'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'copy_all',
                    child: Row(children: [Icon(Icons.copy_all_rounded, size: 20), SizedBox(width: 10), Text('Copy All Diagnostic Logs')]),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'clear_local',
                    child: Row(
                      children: [
                        Icon(Icons.cleaning_services_rounded, size: 20, color: Colors.orange.shade700),
                        const SizedBox(width: 10),
                        const Text('Clear Local Queue'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'clear_cloud',
                    child: Row(
                      children: [
                        Icon(Icons.delete_forever_rounded, size: 20, color: Colors.red.shade700),
                        const SizedBox(width: 10),
                        Text('Clear Cloud Logs (${allLogs.length})', style: TextStyle(color: Colors.red.shade700)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              await _refreshPendingLocalCount();
            },
            child: Column(
              children: [
                // Top Diagnostics Header Card
                Container(
                  color: colorScheme.surface,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    children: [
                      // Status Stats Row
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricTile(
                              icon: Icons.cloud_done_rounded,
                              iconColor: Colors.blue.shade600,
                              title: 'Firestore Logs',
                              value: allLogs.length.toString(),
                              subtitle: 'Live in Cloud',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: InkWell(
                              onTap: _pendingLocalCount > 0 && !_isUploadingPending ? _handleUploadPendingLogs : null,
                              borderRadius: BorderRadius.circular(12),
                              child: _buildMetricTile(
                                icon: Icons.offline_pin_rounded,
                                iconColor: _pendingLocalCount > 0 ? Colors.orange.shade700 : Colors.green.shade600,
                                title: 'Local Queue',
                                value: _pendingLocalCount.toString(),
                                subtitle: _isUploadingPending ? 'Uploading...' : (_pendingLocalCount > 0 ? 'Tap to sync' : 'Up to date'),
                                showAction: _pendingLocalCount > 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Search Input Field
                      TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Search by error, screen, action, or user...',
                          prefixIcon: const Icon(Icons.search_rounded, size: 20),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {});
                                  },
                                )
                              : null,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                          ),
                        ),
                      ),

                      // Filter Chips by Screen / Page
                      if (pageList.length > 2) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 36,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: pageList.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final page = pageList[index];
                              final isSelected = _selectedPageFilter == page;
                              return ChoiceChip(
                                label: Text(
                                  page,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                    color: isSelected ? Colors.white : colorScheme.onSurface,
                                  ),
                                ),
                                selected: isSelected,
                                selectedColor: colorScheme.primary,
                                onSelected: (val) {
                                  if (val) setState(() => _selectedPageFilter = page);
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const Divider(height: 1),

                // Main Logs Content
                Expanded(
                  child: isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : snapshot.hasError
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.error_outline_rounded, size: 48, color: colorScheme.error),
                                const SizedBox(height: 12),
                                Text(
                                  'Failed to load error logs',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: colorScheme.error),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${snapshot.error}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                        )
                      : filteredLogs.isEmpty
                      ? _buildEmptyState(context, hasFilter: query.isNotEmpty || _selectedPageFilter != 'All')
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                          itemCount: filteredLogs.length,
                          itemBuilder: (context, index) {
                            final log = filteredLogs[index];
                            final isExpanded = _expandedLogIds.contains(log.id);
                            return _buildLogCard(context, log, isExpanded);
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String subtitle,
    bool showAction = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w500),
                ),
                Row(
                  children: [
                    Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    if (showAction) ...[const SizedBox(width: 4), Icon(Icons.arrow_forward_ios_rounded, size: 10, color: colorScheme.primary)],
                  ],
                ),
                Text(subtitle, style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, {required bool hasFilter}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: (hasFilter ? Colors.orange : Colors.green).withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(
                hasFilter ? Icons.filter_alt_off_rounded : Icons.verified_rounded,
                size: 48,
                color: hasFilter ? Colors.orange.shade700 : Colors.green.shade600,
              ),
            ),
            const SizedBox(height: 16),
            Text(hasFilter ? 'No Matching Error Logs' : 'All Systems Operational', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              hasFilter
                  ? 'No error logs match your search filters. Try clearing the search query or screen filter.'
                  : 'There are no captured error logs in Firestore. The app is healthy with zero unhandled exceptions.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
            ),
            if (hasFilter) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _searchController.clear();
                    _selectedPageFilter = 'All';
                  });
                },
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Reset Filters'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLogCard(BuildContext context, ErrorLogItem log, bool isExpanded) {
    final colorScheme = Theme.of(context).colorScheme;
    final dateFormat = DateFormat('MMM dd, yyyy • hh:mm:ss a');
    final formattedDate = dateFormat.format(log.timestamp);

    final isFrameworkOrFatal =
        log.action.toLowerCase().contains('unhandled') || log.error.toLowerCase().contains('exception') || log.error.toLowerCase().contains('failed');

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: isFrameworkOrFatal ? Colors.red.withValues(alpha: 0.3) : colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          setState(() {
            if (isExpanded) {
              _expandedLogIds.remove(log.id);
            } else {
              _expandedLogIds.add(log.id);
            }
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row: Icon, Error Title, Timestamp, and Chevron
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (isFrameworkOrFatal ? Colors.red : Colors.orange).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isFrameworkOrFatal ? Icons.bug_report_rounded : Icons.warning_amber_rounded,
                      size: 20,
                      color: isFrameworkOrFatal ? Colors.red.shade700 : Colors.orange.shade800,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          log.error,
                          maxLines: isExpanded ? null : 2,
                          overflow: isExpanded ? null : TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(formattedDate, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: colorScheme.onSurfaceVariant),
                    onPressed: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedLogIds.remove(log.id);
                        } else {
                          _expandedLogIds.add(log.id);
                        }
                      });
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Badges Row: Page, Action, User, Platform
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildTagBadge(Icons.web_stories_rounded, log.page, colorScheme.primary),
                  _buildTagBadge(Icons.play_arrow_rounded, log.action, colorScheme.secondary),
                  if (log.userEmail != null && log.userEmail!.isNotEmpty)
                    _buildTagBadge(Icons.person_outline_rounded, log.userEmail!, colorScheme.tertiary),
                  if (log.platform.isNotEmpty) _buildTagBadge(Icons.devices_rounded, log.platform.toUpperCase(), Colors.blueGrey),
                ],
              ),

              // Expanded Diagnostic Details Section
              if (isExpanded) ...[
                const Divider(height: 24),

                // Error String Monospace Box
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Error Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    TextButton.icon(
                      onPressed: () => _copyToClipboard(log.error, 'error message'),
                      icon: const Icon(Icons.copy_rounded, size: 14),
                      label: const Text('Copy Error', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    ),
                  ],
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                  ),
                  child: SelectableText(
                    log.error,
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.red.shade900, fontWeight: FontWeight.w600),
                  ),
                ),

                // Stack Trace Monospace Box
                if (log.stackTrace != null && log.stackTrace!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Stack Trace', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      TextButton.icon(
                        onPressed: () => _copyToClipboard(log.stackTrace!, 'stack trace'),
                        icon: const Icon(Icons.copy_rounded, size: 14),
                        label: const Text('Copy Stack Trace', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      ),
                    ],
                  ),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 220),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                    ),
                    child: Scrollbar(
                      child: SingleChildScrollView(
                        child: SelectableText(
                          log.stackTrace!,
                          style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: colorScheme.onSurfaceVariant, height: 1.35),
                        ),
                      ),
                    ),
                  ),
                ],

                // Action Bar Footer
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () =>
                          _copyToClipboard(ErrorLogService.formatLogsAsText([log], title: 'ERROR LOG #${log.id}'), 'full diagnostic log'),
                      icon: const Icon(Icons.copy_all_rounded, size: 16),
                      label: const Text('Copy Full Log', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: () => _handleDeleteSingleLog(log),
                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                      label: const Text('Delete', style: TextStyle(fontSize: 12)),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTagBadge(IconData icon, String text, Color accentColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: accentColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: accentColor),
            ),
          ),
        ],
      ),
    );
  }
}
