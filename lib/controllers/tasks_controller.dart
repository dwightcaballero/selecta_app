import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/data/constants.dart';
import 'package:selecta_ops/data/helperfunctions.dart';
import 'package:selecta_ops/data/variables.dart';
import 'package:selecta_ops/models/tasks.dart';
import 'package:selecta_ops/services/auth_service.dart';
import 'package:selecta_ops/services/tasks_services.dart';

enum TaskFilter { all, pending, completed, overdue }

/// Holds summary count data for Tasks
class TaskCounts {
  final int total;
  final int pending;
  final int completed;
  final int overdue;

  const TaskCounts({
    required this.total,
    required this.pending,
    required this.completed,
    required this.overdue,
  });
}

/// Result of grouping and filtering tasks for presentation
class TaskGroupResult {
  final TaskCounts counts;
  final List<dynamic> displayItems;
  final Map<String, int> headerCounts;

  const TaskGroupResult({
    required this.counts,
    required this.displayItems,
    required this.headerCounts,
  });
}

/// Controller responsible for task data operations, filtering,
/// categorizing, status toggling, and role validation.
class TasksController {
  final TasksService _service = TasksService();

  /// Real-time stream of all tasks
  Stream<QuerySnapshot> getTasksStream() {
    return _service.getListTasks();
  }

  /// Checks if the current user has dealer privileges
  Future<bool> checkIsDealer() async {
    return await KVariables.getIsDealer();
  }

  /// Current user display name
  String get currentUserName {
    return authService.value.currentUser?.displayName ?? 'User';
  }

  /// Toggles task status between pending and completed
  Future<Tasks> toggleTaskStatus({
    required String taskID,
    required Tasks task,
    required bool isDealer,
  }) async {
    final newStatus = !task.isTaskDone;
    if (task.isTaskDone && !isDealer) {
      throw Exception('Completed tasks can only be reopened by dealers.');
    }

    final updatedTask = task.copyWith(
      isTaskDone: newStatus,
      lastUpdatedBy: currentUserName,
      lastupdatedDate: Timestamp.now(),
      lastUpdatedPage: AppPages.tasks,
    );

    await _service.updateTasks(taskID, updatedTask);
    await Helperfunctions.logUpdate(
      updatedTask.taskTitle,
      task.toJson(),
      updatedTask.toJson(),
      page: AppPages.tasks,
    );

    return updatedTask;
  }

  /// Processes and filters task documents into categorized display groups
  TaskGroupResult processTasks({
    required List<QueryDocumentSnapshot> allDocs,
    required TaskFilter selectedFilter,
    required String searchQuery,
  }) {
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

    // Sort pending: nearest deadline first
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

    // Search filter function
    bool matchesSearch(QueryDocumentSnapshot doc) {
      if (searchQuery.isEmpty) return true;
      final task = doc.data() as Tasks;
      final query = searchQuery.toLowerCase();
      return task.taskTitle.toLowerCase().contains(query) ||
          task.storeName.toLowerCase().contains(query) ||
          task.taskDescription.toLowerCase().contains(query);
    }

    final bool isShowingAll = selectedFilter == TaskFilter.all;
    final List<dynamic> displayItems = [];
    final Map<String, int> headerCounts = {};

    if (selectedFilter == TaskFilter.overdue || isShowingAll) {
      final filtered = overdueDocs.where(matchesSearch).toList();
      if (filtered.isNotEmpty) {
        if (isShowingAll) {
          displayItems.add('_header_overdue');
          headerCounts['_header_overdue'] = filtered.length;
        }
        displayItems.addAll(filtered);
      }
    }

    if (selectedFilter == TaskFilter.pending || isShowingAll) {
      final filtered = pendingDocs.where(matchesSearch).toList();
      if (filtered.isNotEmpty) {
        if (isShowingAll) {
          displayItems.add('_header_pending');
          headerCounts['_header_pending'] = filtered.length;
        }
        displayItems.addAll(filtered);
      }
    }

    if (selectedFilter == TaskFilter.completed || isShowingAll) {
      final filtered = completedDocs.where(matchesSearch).toList();
      if (filtered.isNotEmpty) {
        if (isShowingAll) {
          displayItems.add('_header_completed');
          headerCounts['_header_completed'] = filtered.length;
        }
        displayItems.addAll(filtered);
      }
    }

    return TaskGroupResult(
      counts: TaskCounts(
        total: allDocs.length,
        pending: pendingCount,
        completed: completedCount,
        overdue: overdueCount,
      ),
      displayItems: displayItems,
      headerCounts: headerCounts,
    );
  }

  /// Adds a new task with dealer check and audit logging
  Future<void> createTask({
    required String title,
    required String description,
    required DateTime deadline,
    required String storeName,
    required bool isTaskDone,
    required bool isDealer,
  }) async {
    if (!isDealer) {
      throw Exception('Only dealers are authorized to create tasks');
    }

    final newTask = Tasks(
      taskID: '',
      taskTitle: title.trim(),
      taskDescription: description.trim(),
      taskDeadline: Timestamp.fromDate(deadline),
      storeName: storeName.trim(),
      isTaskDone: isTaskDone,
      createdBy: currentUserName,
      lastUpdatedBy: currentUserName,
      createdDate: Timestamp.now(),
      lastupdatedDate: Timestamp.now(),
      createdPage: AppPages.tasks,
      lastUpdatedPage: AppPages.tasks,
    );

    final docRef = await _service.addTasks(newTask);
    newTask.taskID = docRef.id;

    await Helperfunctions.logCreate(
      title.trim(),
      newTask.toJson(),
      page: AppPages.tasks,
    );
  }

  /// Updates an existing task with dealer permission enforcement and audit logging
  Future<void> updateTask({
    required String taskID,
    required Tasks originalTask,
    required String title,
    required String description,
    required DateTime deadline,
    required String storeName,
    required bool isTaskDone,
    required bool isDealer,
  }) async {
    final bool isReadOnly = originalTask.isTaskDone && !isDealer;
    if (isReadOnly) {
      throw Exception('Completed tasks cannot be modified by non-dealers');
    }

    final updatedTask = originalTask.copyWith(
      taskTitle: isDealer ? title.trim() : originalTask.taskTitle,
      taskDescription: isDealer ? description.trim() : originalTask.taskDescription,
      taskDeadline: isDealer ? Timestamp.fromDate(deadline) : originalTask.taskDeadline,
      storeName: isDealer ? storeName.trim() : originalTask.storeName,
      isTaskDone: isTaskDone,
      lastUpdatedBy: currentUserName,
      lastupdatedDate: Timestamp.now(),
      lastUpdatedPage: AppPages.tasks,
    );

    await _service.updateTasks(taskID, updatedTask);
    await Helperfunctions.logUpdate(
      updatedTask.taskTitle,
      originalTask.toJson(),
      updatedTask.toJson(),
      page: AppPages.tasks,
    );
  }

  /// Deletes a task with dealer permission enforcement and audit logging
  Future<void> deleteTask({
    required String taskID,
    required Tasks task,
    required bool isDealer,
  }) async {
    if (!isDealer) {
      throw Exception('Only dealers are authorized to delete tasks');
    }

    await _service.deleteTasks(taskID);
    await Helperfunctions.logDelete(
      task.taskTitle,
      task.toJson(),
      page: AppPages.tasks,
    );
  }
}
