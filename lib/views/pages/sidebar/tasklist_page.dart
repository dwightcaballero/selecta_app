import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/data/variables.dart';
import 'package:flutter_app/models/tasks.dart';
import 'package:flutter_app/services/tasks_services.dart';
import 'package:flutter_app/views/pages/sidebar/tasks_page.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:intl/intl.dart';

enum TaskFilter { all, pending, completed, overdue }

class TasklistPage extends StatefulWidget {
  const TasklistPage({super.key, this.initialStoreName});

  final String? initialStoreName;

  @override
  State<TasklistPage> createState() => _TasklistPageState();
}

// Convenient alias for alternate naming convention
typedef TaskListPage = TasklistPage;

class _TasklistPageState extends State<TasklistPage> {
  final TasksService db = TasksService();

  bool _isDealer = false;
  late final Stream<QuerySnapshot> _tasksStream;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  TaskFilter _selectedFilter = TaskFilter.all;

  @override
  void initState() {
    super.initState();
    _checkDealerRole();
    _tasksStream = db.getListTasks();
    if (widget.initialStoreName != null && widget.initialStoreName!.isNotEmpty) {
      _searchController.text = widget.initialStoreName!;
      _searchQuery = widget.initialStoreName!.trim().toLowerCase();
    }
  }

  void _checkDealerRole() async {
    final isDealer = await KVariables.getIsDealer();
    if (mounted) {
      setState(() {
        _isDealer = isDealer;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _navigateToAddTask() {
    if (!_isDealer) return;
    Helperfunctions.navigateTo(
      context,
      TasksPage(
        taskID: '',
        task: Tasks.empty().copyWith(storeName: widget.initialStoreName ?? ''),
      ),
    );
  }

  void _navigateToEditTask(String taskID, Tasks task) {
    Helperfunctions.navigateTo(
      context,
      TasksPage(taskID: taskID, task: task),
    );
  }

  Future<void> _toggleTaskStatus(String taskID, Tasks task) async {
    final newStatus = !task.isTaskDone;
    if (task.isTaskDone && !_isDealer) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Completed tasks can only be reopened by dealers.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    try {
      final updatedTask = task.copyWith(isTaskDone: newStatus);
      await db.updateTasks(taskID, updatedTask);
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus ? 'Task completed!' : 'Task marked as pending.',
            ),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () => _toggleTaskStatus(taskID, updatedTask),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update task: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildFilterChips({
    required int totalCount,
    required int pendingCount,
    required int completedCount,
    required int overdueCount,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget buildChip({
      required String label,
      required int count,
      required TaskFilter filter,
    }) {
      final isSelected = _selectedFilter == filter;
      final isOverdueFilter = filter == TaskFilter.overdue;
      final hasOverdue = isOverdueFilter && count > 0;

      final selectedBgColor = isOverdueFilter
          ? (isDark ? Colors.red.shade900 : Colors.red.shade700)
          : colorScheme.primary;

      return Padding(
        padding: const EdgeInsets.only(right: 8.0),
        child: FilterChip(
          selected: isSelected,
          showCheckmark: false,
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : (hasOverdue
                          ? (isDark ? Colors.red.shade300 : Colors.red.shade700)
                          : colorScheme.onSurface),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.25)
                      : (hasOverdue
                          ? (isDark ? Colors.red.shade900.withValues(alpha: 0.35) : Colors.red.shade50)
                          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? Colors.white
                        : (hasOverdue
                            ? (isDark ? Colors.red.shade300 : Colors.red.shade700)
                            : colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          ),
          selectedColor: selectedBgColor,
          backgroundColor: colorScheme.surface,
          side: BorderSide(
            color: isSelected
                ? Colors.transparent
                : (hasOverdue
                    ? (isDark ? Colors.red.shade800.withValues(alpha: 0.6) : Colors.red.shade200)
                    : colorScheme.outlineVariant.withValues(alpha: 0.5)),
            width: 1,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onSelected: (_) {
            setState(() {
              if (_selectedFilter == filter && filter != TaskFilter.all) {
                _selectedFilter = TaskFilter.all;
              } else {
                _selectedFilter = filter;
              }
            });
          },
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          buildChip(label: 'All', count: totalCount, filter: TaskFilter.all),
          buildChip(label: 'Overdue', count: overdueCount, filter: TaskFilter.overdue),
          buildChip(label: 'Pending', count: pendingCount, filter: TaskFilter.pending),
          buildChip(label: 'Completed', count: completedCount, filter: TaskFilter.completed),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onChanged: (val) => setState(() => _searchQuery = val.trim()),
        decoration: InputDecoration(
          hintText: 'Search tasks by title or store...',
          hintStyle: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          prefixIcon: Icon(Icons.search, size: 20, color: colorScheme.onSurfaceVariant),
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
          fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
          ),
        ),
      ),
    );
  }



  String _formatDeadline(DateTime deadline, {required bool isDone}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final deadlineDate = DateTime(deadline.year, deadline.month, deadline.day);
    final diffDays = deadlineDate.difference(today).inDays;
    final timeStr = DateFormat('h:mm a').format(deadline);

    if (isDone) {
      return DateFormat('EEE, d MMM • h:mm a').format(deadline);
    }

    if (diffDays == 0) {
      if (deadline.isBefore(now)) {
        final hoursAgo = now.difference(deadline).inHours;
        if (hoursAgo == 0) {
          final minutesAgo = now.difference(deadline).inMinutes;
          return 'Overdue by ${minutesAgo <= 1 ? 1 : minutesAgo}m • $timeStr';
        }
        return 'Overdue by ${hoursAgo}h • $timeStr';
      }
      return 'Today • $timeStr';
    } else if (diffDays == 1) {
      return 'Tomorrow • $timeStr';
    } else if (diffDays == -1) {
      return 'Yesterday • $timeStr';
    } else if (diffDays < -1) {
      return '${(-diffDays)}d overdue • $timeStr';
    } else if (diffDays < 7) {
      return DateFormat('EEEE • h:mm a').format(deadline);
    } else {
      return DateFormat('EEE, d MMM • h:mm a').format(deadline);
    }
  }

  Widget _buildTaskCard({required String taskID, required Tasks task}) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final deadlineDate = task.taskDeadline.toDate();
    final isDone = task.isTaskDone;
    final isOverdue = !isDone && deadlineDate.isBefore(DateTime.now());
    final isDueToday = !isDone && !isOverdue &&
        deadlineDate.year == DateTime.now().year &&
        deadlineDate.month == DateTime.now().month &&
        deadlineDate.day == DateTime.now().day;
    final deadlineFormatted = _formatDeadline(deadlineDate, isDone: isDone);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: isDone
          ? (isDark ? colorScheme.surfaceContainerLow : colorScheme.surfaceContainerHighest.withValues(alpha: 0.25))
          : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isOverdue
              ? (isDark ? Colors.red.withValues(alpha: 0.4) : Colors.red.withValues(alpha: 0.3))
              : colorScheme.outlineVariant.withValues(alpha: 0.45),
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _navigateToEditTask(taskID, task),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 11.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Checkbox / Toggle Status Button
              IconButton(
                icon: Icon(
                  isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: isDone
                      ? (isDark ? Colors.green.shade400 : Colors.green.shade600)
                      : (isOverdue ? (isDark ? Colors.red.shade300 : Colors.red.shade400) : colorScheme.outline),
                  size: 24,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: isDone
                    ? (_isDealer ? 'Mark as Pending' : 'Completed (View Only)')
                    : 'Mark as Completed',
                onPressed: (isDone && !_isDealer) ? null : () => _toggleTaskStatus(taskID, task),
              ),
              const SizedBox(width: 10),

              // Task Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Title
                    Text(
                      task.taskTitle,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                        color: isDone ? colorScheme.outline : colorScheme.onSurface,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),

                    // Meta: Store (Left) & Deadline (Right)
                    Row(
                      children: [
                        if (task.storeName.isNotEmpty) ...[
                          Icon(Icons.storefront_outlined, size: 13, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              task.storeName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ] else
                          const Spacer(),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isOverdue
                                  ? Icons.warning_amber_rounded
                                  : (isDueToday ? Icons.access_time_rounded : Icons.calendar_today_outlined),
                              size: 13,
                              color: isOverdue
                                  ? (isDark ? Colors.red.shade300 : Colors.red.shade700)
                                  : (isDueToday ? colorScheme.primary : colorScheme.onSurfaceVariant),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              deadlineFormatted,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: (isOverdue || isDueToday) ? FontWeight.w600 : FontWeight.normal,
                                color: isOverdue
                                    ? (isDark ? Colors.red.shade300 : Colors.red.shade700)
                                    : (isDueToday ? colorScheme.primary : colorScheme.onSurfaceVariant),
                              ),
                            ),
                          ],
                        ),
                      ],
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

  Widget _buildSectionHeader(String headerKey, {int count = 0}) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final String label;
    final Color color;

    switch (headerKey) {
      case '_header_overdue':
        label = count > 0 ? 'Overdue ($count)' : 'Overdue';
        color = isDark ? Colors.red.shade300 : Colors.red.shade700;
        break;
      case '_header_pending':
        label = count > 0 ? 'Pending ($count)' : 'Pending';
        color = colorScheme.onSurfaceVariant;
        break;
      case '_header_completed':
        label = count > 0 ? 'Completed ($count)' : 'Completed';
        color = colorScheme.outline;
        break;
      default:
        label = count > 0 ? '$headerKey ($count)' : headerKey;
        color = colorScheme.primary;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6, left: 2),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.assignment_outlined, color: colorScheme.primary, size: 50),
            ),
            const SizedBox(height: 16),
            Text(
              'No Tasks Created',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
            ),
            const SizedBox(height: 6),
            Text(
              _isDealer
                  ? 'Keep track of assignments and store duties by adding your first task.'
                  : 'No tasks currently assigned or scheduled.',
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (_isDealer) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _navigateToAddTask,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add First Task'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNoSearchResultsState() {
    final colorScheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32.0),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No tasks matching "$_searchQuery"'
                  : 'No tasks found with the selected filter',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: colorScheme.onSurface),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                  _selectedFilter = TaskFilter.all;
                });
              },
              child: const Text('Reset Search & Filters'),
            ),
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
          Text('Unable to load task list'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppbar(
        title: 'Tasks',
        subtitle: 'Store & Operational Tasks',
      ),
      floatingActionButton: _isDealer
          ? FloatingActionButton.extended(
              onPressed: _navigateToAddTask,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Add Task',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              backgroundColor: Theme.of(context).colorScheme.primary,
            )
          : null,
      body: StreamBuilder<QuerySnapshot>(
        stream: _tasksStream,
        builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.hasError) {
            return _buildErrorState();
          }
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allDocs = snapshot.data?.docs ?? [];
          if (allDocs.isEmpty) {
            return _buildEmptyState();
          }

          final now = DateTime.now();
          int pendingCount = 0;
          int completedCount = 0;
          int overdueCount = 0;

          final List<QueryDocumentSnapshot> overdueDocs = [];
          final List<QueryDocumentSnapshot> pendingDocs = [];
          final List<QueryDocumentSnapshot> completedDocs = [];

          for (var doc in allDocs) {
            final task = doc.data() as Tasks;
            final isDone = task.isTaskDone;
            final isOverdue = !isDone && task.taskDeadline.toDate().isBefore(now);

            if (isDone) {
              completedCount++;
              completedDocs.add(doc);
            } else if (isOverdue) {
              overdueCount++;
              overdueDocs.add(doc);
            } else {
              pendingCount++;
              pendingDocs.add(doc);
            }
          }

          // Sort overdue: nearest deadline first
          overdueDocs.sort((a, b) {
            final taskA = a.data() as Tasks;
            final taskB = b.data() as Tasks;
            return taskA.taskDeadline.compareTo(taskB.taskDeadline);
          });

          // Sort pending: nearest deadline first (most urgent at the top)
          pendingDocs.sort((a, b) {
            final taskA = a.data() as Tasks;
            final taskB = b.data() as Tasks;
            return taskA.taskDeadline.compareTo(taskB.taskDeadline);
          });

          // Sort completed: most recently updated / completed first
          completedDocs.sort((a, b) {
            final taskA = a.data() as Tasks;
            final taskB = b.data() as Tasks;
            return taskB.lastupdatedDate.compareTo(taskA.lastupdatedDate);
          });

          // Apply search filter across all groups
          bool matchesSearch(QueryDocumentSnapshot doc) {
            if (_searchQuery.isEmpty) return true;
            final task = doc.data() as Tasks;
            final query = _searchQuery.toLowerCase();
            return task.taskTitle.toLowerCase().contains(query) ||
                task.storeName.toLowerCase().contains(query) ||
                task.taskDescription.toLowerCase().contains(query);
          }

          // Build display items based on selected filter
          final bool isShowingAll = _selectedFilter == TaskFilter.all;

          // Each entry is either a header String or a QueryDocumentSnapshot
          final List<dynamic> displayItems = [];
          final Map<String, int> headerCounts = {};

          if (_selectedFilter == TaskFilter.overdue || isShowingAll) {
            final filtered = overdueDocs.where(matchesSearch).toList();
            if (filtered.isNotEmpty) {
              if (isShowingAll) {
                displayItems.add('_header_overdue');
                headerCounts['_header_overdue'] = filtered.length;
              }
              displayItems.addAll(filtered);
            }
          }

          if (_selectedFilter == TaskFilter.pending || isShowingAll) {
            final filtered = pendingDocs.where(matchesSearch).toList();
            if (filtered.isNotEmpty) {
              if (isShowingAll) {
                displayItems.add('_header_pending');
                headerCounts['_header_pending'] = filtered.length;
              }
              displayItems.addAll(filtered);
            }
          }

          if (_selectedFilter == TaskFilter.completed || isShowingAll) {
            final filtered = completedDocs.where(matchesSearch).toList();
            if (filtered.isNotEmpty) {
              if (isShowingAll) {
                displayItems.add('_header_completed');
                headerCounts['_header_completed'] = filtered.length;
              }
              displayItems.addAll(filtered);
            }
          }

          final colorScheme = Theme.of(context).colorScheme;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Search Field
              _buildSearchBar(),

              // 2. Filter Chips
              _buildFilterChips(
                totalCount: allDocs.length,
                pendingCount: pendingCount,
                completedCount: completedCount,
                overdueCount: overdueCount,
              ),

              const SizedBox(height: 8),

              // 3. Tasks List View
              Expanded(
                child: displayItems.isEmpty
                    ? _buildNoSearchResultsState()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                        itemCount: displayItems.length,
                        itemBuilder: (context, index) {
                          final item = displayItems[index];

                          if (item is String) {
                            // Section header
                            return _buildSectionHeader(item, count: headerCounts[item] ?? 0);
                          }

                          final doc = item as QueryDocumentSnapshot;
                          final task = doc.data() as Tasks;
                          final taskID = task.taskID.isNotEmpty ? task.taskID : doc.id;

                          // Add spacing between items (not after headers)
                          final isLastItem = index == displayItems.length - 1;
                          return Padding(
                            padding: EdgeInsets.only(bottom: isLastItem ? 0 : 8),
                            child: _buildTaskCard(taskID: taskID, task: task),
                          );
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
