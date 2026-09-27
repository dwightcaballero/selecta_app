import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/controllers/tasks_controller.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/tasks.dart';
import 'package:flutter_app/views/pages/sidebar/tasks_page.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:intl/intl.dart';

/// Presentation page for viewing, filtering, searching, and managing operational tasks.
class TasklistPage extends StatefulWidget {
  const TasklistPage({super.key, this.initialStoreName});

  final String? initialStoreName;

  @override
  State<TasklistPage> createState() => _TasklistPageState();
}

// Convenient alias for alternate naming convention
typedef TaskListPage = TasklistPage;

class _TasklistPageState extends State<TasklistPage> {
  // Controller managing task operations and filtering
  final TasksController _controller = TasksController();

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
    _tasksStream = _controller.getTasksStream();
    if (widget.initialStoreName != null && widget.initialStoreName!.isNotEmpty) {
      _searchController.text = widget.initialStoreName!;
      _searchQuery = widget.initialStoreName!.trim().toLowerCase();
    }
  }

  /// Checks dealer privileges via controller
  void _checkDealerRole() async {
    final isDealer = await _controller.checkIsDealer();
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
    Helperfunctions.navigateTo(context, TasksPage(taskID: taskID, task: task));
  }

  /// Toggles completion status using controller
  Future<void> _toggleTaskStatus(String taskID, Tasks task) async {
    try {
      final updatedTask = await _controller.toggleTaskStatus(
        taskID: taskID,
        task: task,
        isDealer: _isDealer,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(updatedTask.isTaskDone ? 'Task completed!' : 'Task marked as pending.'),
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
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Builds the top filter chips
  Widget _buildFilterChips({required int totalCount, required int pendingCount, required int completedCount, required int overdueCount}) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget buildChip({required String label, required int count, required TaskFilter filter}) {
      final isSelected = _selectedFilter == filter;
      final isOverdueFilter = filter == TaskFilter.overdue;
      final hasOverdue = isOverdueFilter && count > 0;

      final selectedBgColor = isOverdueFilter ? (isDark ? Colors.red.shade900 : Colors.red.shade700) : colorScheme.primary;

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
                  color: isSelected ? Colors.white : (hasOverdue ? (isDark ? Colors.red.shade300 : Colors.red.shade700) : colorScheme.onSurface),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.25)
                      : (hasOverdue
                          ? (isDark ? Colors.red.shade900.withValues(alpha: 0.5) : Colors.red.shade100)
                          : colorScheme.surfaceContainerHighest),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : (hasOverdue ? (isDark ? Colors.red.shade300 : Colors.red.shade700) : colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          ),
          selectedColor: selectedBgColor,
          backgroundColor: hasOverdue
              ? (isDark ? Colors.red.shade900.withValues(alpha: 0.25) : Colors.red.shade50)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: isSelected
                  ? Colors.transparent
                  : (hasOverdue ? (isDark ? Colors.red.shade700 : Colors.red.shade300) : colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
          ),
          onSelected: (_) => setState(() => _selectedFilter = filter),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Row(
        children: [
          buildChip(label: 'All', count: totalCount, filter: TaskFilter.all),
          buildChip(label: 'Pending', count: pendingCount, filter: TaskFilter.pending),
          buildChip(label: 'Overdue', count: overdueCount, filter: TaskFilter.overdue),
          buildChip(label: 'Completed', count: completedCount, filter: TaskFilter.completed),
        ],
      ),
    );
  }

  /// Builds the search input field
  Widget _buildSearchBar() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
        decoration: InputDecoration(
          hintText: 'Search tasks, stores, or descriptions...',
          hintStyle: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          prefixIcon: Icon(Icons.search, size: 20, color: colorScheme.primary),
          suffixIcon: _searchController.text.isNotEmpty
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
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: colorScheme.outlineVariant)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
          ),
        ),
      ),
    );
  }

  /// Builds an individual task card
  Widget _buildTaskCard({required String taskID, required Tasks task}) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final now = DateTime.now();
    final deadlineDate = task.taskDeadline.toDate();
    final isDone = task.isTaskDone;
    final isOverdue = !isDone && deadlineDate.isBefore(now);
    final isDueToday = !isDone && !isOverdue && deadlineDate.year == now.year && deadlineDate.month == now.month && deadlineDate.day == now.day;

    final deadlineFormatted = DateFormat('MMM d, yyyy  h:mm a').format(deadlineDate);

    Color cardBorderColor;
    if (isDone) {
      cardBorderColor = colorScheme.outlineVariant.withValues(alpha: 0.3);
    } else if (isOverdue) {
      cardBorderColor = isDark ? Colors.red.shade700 : Colors.red.shade300;
    } else if (isDueToday) {
      cardBorderColor = colorScheme.primary.withValues(alpha: 0.5);
    } else {
      cardBorderColor = colorScheme.outlineVariant.withValues(alpha: 0.6);
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: isDone ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.2) : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cardBorderColor, width: isOverdue ? 1.2 : 1.0),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _navigateToEditTask(taskID, task),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Checkbox button
              Padding(
                padding: const EdgeInsets.only(top: 2.0, right: 10.0),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: isDone,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    activeColor: Colors.green.shade600,
                    onChanged: (isDone && !_isDealer) ? null : (_) => _toggleTaskStatus(taskID, task),
                  ),
                ),
              ),

              // Task Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      task.taskTitle,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: isDone ? colorScheme.onSurfaceVariant : colorScheme.onSurface,
                        decoration: isDone ? TextDecoration.lineThrough : null,
                        decorationColor: colorScheme.onSurfaceVariant,
                      ),
                    ),

                    // Description (if present)
                    if (task.taskDescription.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        task.taskDescription,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: isDone ? colorScheme.outline : colorScheme.onSurfaceVariant,
                          decoration: isDone ? TextDecoration.lineThrough : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],

                    const SizedBox(height: 6),

                    // Store tag + Deadline
                    Row(
                      children: [
                        if (task.storeName.isNotEmpty) ...[
                          Icon(Icons.storefront_outlined, size: 13, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              task.storeName,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: colorScheme.onSurfaceVariant),
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
                              isOverdue ? Icons.warning_amber_rounded : (isDueToday ? Icons.access_time_rounded : Icons.calendar_today_outlined),
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
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.8),
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
              decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(Icons.assignment_outlined, color: colorScheme.primary, size: 50),
            ),
            const SizedBox(height: 16),
            Text(
              'No Tasks Created',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
            ),
            const SizedBox(height: 6),
            Text(
              _isDealer ? 'Keep track of assignments and store duties by adding your first task.' : 'No tasks currently assigned or scheduled.',
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (_isDealer) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _navigateToAddTask,
                icon: const Icon(Icons.add),
                label: const Text('Add First Task'),
              ),
            ],
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
            Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'No tasks found',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              _searchQuery.isNotEmpty ? 'No tasks match "$_searchQuery" under current filters.' : 'No tasks in this category.',
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
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
      appBar: const CustomAppbar(title: 'Tasks', subtitle: 'Store & Operational Tasks'),
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

          // Process, categorize, and sort tasks via controller
          final groupResult = _controller.processTasks(
            allDocs: allDocs,
            selectedFilter: _selectedFilter,
            searchQuery: _searchQuery,
          );

          final counts = groupResult.counts;
          final displayItems = groupResult.displayItems;
          final headerCounts = groupResult.headerCounts;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Search Field
              _buildSearchBar(),

              // 2. Filter Chips
              _buildFilterChips(
                totalCount: counts.total,
                pendingCount: counts.pending,
                completedCount: counts.completed,
                overdueCount: counts.overdue,
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
