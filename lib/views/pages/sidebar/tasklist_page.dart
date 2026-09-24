import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/helperfunctions.dart';
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

  late final Stream<QuerySnapshot> _tasksStream;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  TaskFilter _selectedFilter = TaskFilter.all;

  @override
  void initState() {
    super.initState();
    _tasksStream = db.getListTasks();
    if (widget.initialStoreName != null && widget.initialStoreName!.isNotEmpty) {
      _searchController.text = widget.initialStoreName!;
      _searchQuery = widget.initialStoreName!.trim().toLowerCase();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _navigateToAddTask() {
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
    try {
      final updatedTask = task.copyWith(isTaskDone: newStatus);
      await db.updateTasks(taskID, updatedTask);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus ? 'Task marked as completed!' : 'Task marked as pending.',
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
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

  Widget _buildSummaryCard({
    required int totalCount,
    required int pendingCount,
    required int completedCount,
    required int overdueCount,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colorScheme.primary, colorScheme.primary.withValues(alpha: 0.82)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Operational Task Tracker',
                    style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$totalCount Total ${totalCount == 1 ? 'Task' : 'Tasks'}',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.assignment_outlined, color: Colors.white, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildFilterMetricItem(
                label: 'All',
                value: '$totalCount',
                icon: Icons.grid_view_rounded,
                filter: TaskFilter.all,
                accentColor: Colors.white,
              ),
              const SizedBox(width: 6),
              _buildFilterMetricItem(
                label: 'Overdue',
                value: '$overdueCount',
                icon: Icons.warning_amber_rounded,
                filter: TaskFilter.overdue,
                accentColor: Colors.redAccent.shade100,
              ),
              const SizedBox(width: 6),
              _buildFilterMetricItem(
                label: 'Pending',
                value: '$pendingCount',
                icon: Icons.hourglass_top_rounded,
                filter: TaskFilter.pending,
                accentColor: Colors.amber.shade200,
              ),
              const SizedBox(width: 6),
              _buildFilterMetricItem(
                label: 'Completed',
                value: '$completedCount',
                icon: Icons.check_circle_outline_rounded,
                filter: TaskFilter.completed,
                accentColor: Colors.lightGreenAccent.shade100,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterMetricItem({
    required String label,
    required String value,
    required IconData icon,
    required TaskFilter filter,
    required Color accentColor,
  }) {
    final isSelected = _selectedFilter == filter;
    final colorScheme = Theme.of(context).colorScheme;

    Color iconColor;
    if (isSelected) {
      switch (filter) {
        case TaskFilter.pending:
          iconColor = Colors.orange.shade800;
          break;
        case TaskFilter.completed:
          iconColor = Colors.green.shade700;
          break;
        case TaskFilter.overdue:
          iconColor = Colors.red.shade700;
          break;
        case TaskFilter.all:
          iconColor = colorScheme.primary;
          break;
      }
    } else {
      iconColor = accentColor;
    }

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              if (_selectedFilter == filter && filter != TaskFilter.all) {
                _selectedFilter = TaskFilter.all;
              } else {
                _selectedFilter = filter;
              }
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.18),
                width: isSelected ? 1.5 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, size: 14, color: iconColor),
                    const SizedBox(width: 4),
                    Text(
                      value,
                      style: TextStyle(
                        color: isSelected ? colorScheme.primary : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? colorScheme.primary : Colors.white70,
                    fontSize: 10.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onChanged: (val) => setState(() => _searchQuery = val.trim()),
        decoration: InputDecoration(
          hintText: 'Search tasks by title, store, or details...',
          hintStyle: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
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
    );
  }



  Widget _buildTaskCard({required String taskID, required Tasks task}) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDone = task.isTaskDone;
    final isOverdue = !isDone && task.taskDeadline.toDate().isBefore(DateTime.now());
    final deadlineFormatted = DateFormat('EEE, d MMM • h:mm a').format(task.taskDeadline.toDate());

    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (isDone) {
      statusColor = Colors.green;
      statusText = 'Completed';
      statusIcon = Icons.check_circle_rounded;
    } else if (isOverdue) {
      statusColor = Colors.red;
      statusText = 'Overdue';
      statusIcon = Icons.error_outline_rounded;
    } else {
      statusColor = Colors.orange;
      statusText = 'Pending';
      statusIcon = Icons.schedule_rounded;
    }

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDone
              ? Colors.green.withValues(alpha: 0.3)
              : (isOverdue ? Colors.red.withValues(alpha: 0.3) : colorScheme.outlineVariant.withValues(alpha: 0.6)),
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _navigateToEditTask(taskID, task),
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Checkbox / Toggle Status Button
              IconButton(
                icon: Icon(
                  isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: isDone ? Colors.green : (isOverdue ? Colors.red.shade400 : colorScheme.outline),
                  size: 26,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: isDone ? 'Mark as Pending' : 'Mark as Completed',
                onPressed: () => _toggleTaskStatus(taskID, task),
              ),
              const SizedBox(width: 10),

              // Task Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title and status badge
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            task.taskTitle,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              decoration: isDone ? TextDecoration.lineThrough : null,
                              color: isDone ? colorScheme.onSurfaceVariant : colorScheme.onSurface,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(statusIcon, size: 12, color: statusColor),
                              const SizedBox(width: 4),
                              Text(
                                statusText,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Description snippet if available
                    if (task.taskDescription.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        task.taskDescription,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],

                    const SizedBox(height: 8),

                    // Meta: Store & Deadline
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        if (task.storeName.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.storefront_outlined, size: 14, color: colorScheme.primary),
                              const SizedBox(width: 4),
                              Text(
                                task.storeName,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.calendar_month_outlined,
                              size: 14,
                              color: isOverdue ? Colors.red : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              deadlineFormatted,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isOverdue ? FontWeight.w600 : FontWeight.normal,
                                color: isOverdue ? Colors.red.shade800 : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Icon(Icons.chevron_right, size: 20, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String headerKey) {
    final colorScheme = Theme.of(context).colorScheme;

    final String label;
    final IconData icon;
    final Color color;

    switch (headerKey) {
      case '_header_overdue':
        label = 'Overdue';
        icon = Icons.warning_amber_rounded;
        color = Colors.red;
        break;
      case '_header_pending':
        label = 'Pending';
        icon = Icons.hourglass_top_rounded;
        color = Colors.orange;
        break;
      case '_header_completed':
        label = 'Completed';
        icon = Icons.check_circle_outline_rounded;
        color = Colors.green;
        break;
      default:
        label = headerKey;
        icon = Icons.label_outline;
        color = colorScheme.primary;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Divider(
              color: color.withValues(alpha: 0.25),
              thickness: 1,
            ),
          ),
        ],
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
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.assignment_outlined, color: Colors.blue, size: 50),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Tasks Created',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Keep track of assignments and store duties by adding your first task.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _navigateToAddTask,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add First Task'),
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
            const Icon(Icons.search_off_rounded, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No tasks matching "$_searchQuery"'
                  : 'No tasks found with the selected filter',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navigateToAddTask,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Add Task',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
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

          if (_selectedFilter == TaskFilter.overdue || isShowingAll) {
            final filtered = overdueDocs.where(matchesSearch).toList();
            if (filtered.isNotEmpty) {
              if (isShowingAll) displayItems.add('_header_overdue');
              displayItems.addAll(filtered);
            }
          }

          if (_selectedFilter == TaskFilter.pending || isShowingAll) {
            final filtered = pendingDocs.where(matchesSearch).toList();
            if (filtered.isNotEmpty) {
              if (isShowingAll) displayItems.add('_header_pending');
              displayItems.addAll(filtered);
            }
          }

          if (_selectedFilter == TaskFilter.completed || isShowingAll) {
            final filtered = completedDocs.where(matchesSearch).toList();
            if (filtered.isNotEmpty) {
              if (isShowingAll) displayItems.add('_header_completed');
              displayItems.addAll(filtered);
            }
          }

          return Column(
            children: [
              // 1. KPI Summary Card
              _buildSummaryCard(
                totalCount: allDocs.length,
                pendingCount: pendingCount,
                completedCount: completedCount,
                overdueCount: overdueCount,
              ),

              // 2. Search Field
              _buildSearchBar(),

              const SizedBox(height: 4),

              // 3. Tasks List View
              Expanded(
                child: displayItems.isEmpty
                    ? _buildNoSearchResultsState()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 88),
                        itemCount: displayItems.length,
                        itemBuilder: (context, index) {
                          final item = displayItems[index];

                          if (item is String) {
                            // Section header
                            return _buildSectionHeader(item);
                          }

                          final doc = item as QueryDocumentSnapshot;
                          final task = doc.data() as Tasks;
                          final taskID = task.taskID.isNotEmpty ? task.taskID : doc.id;

                          // Add spacing between items (not after headers)
                          final isLastItem = index == displayItems.length - 1;
                          return Padding(
                            padding: EdgeInsets.only(bottom: isLastItem ? 0 : 10),
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
