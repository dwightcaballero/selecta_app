import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/data/constants.dart';
import 'package:flutter_app/data/helperfunctions.dart';
import 'package:flutter_app/models/tasks.dart';
import 'package:flutter_app/services/auth_service.dart';
import 'package:flutter_app/services/tasks_services.dart';
import 'package:flutter_app/views/widgets/alert_widget.dart';
import 'package:flutter_app/views/widgets/appbar_widget.dart';
import 'package:flutter_app/views/widgets/hapistore_dropdown.dart';
import 'package:intl/intl.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key, required this.taskID, required this.task});

  final String taskID;
  final Tasks task;

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  final TasksService db = TasksService();

  final _formKey = GlobalKey<FormState>();
  final TextEditingController txtTitle = TextEditingController();
  final TextEditingController txtStoreName = TextEditingController();
  final TextEditingController txtDescription = TextEditingController();

  DateTime _selectedDeadline = DateTime.now().add(const Duration(hours: 4));
  bool _isTaskDone = false;
  bool _isLoading = false;

  bool get isEditMode => widget.taskID.isNotEmpty;

  bool get _hasUnsavedChanges {
    if (isEditMode) {
      return txtTitle.text.trim() != widget.task.taskTitle ||
          txtDescription.text.trim() != widget.task.taskDescription ||
          txtStoreName.text.trim() != widget.task.storeName ||
          _isTaskDone != widget.task.isTaskDone ||
          _selectedDeadline != widget.task.taskDeadline.toDate();
    }
    return txtTitle.text.trim().isNotEmpty ||
        txtDescription.text.trim().isNotEmpty ||
        (txtStoreName.text.trim().isNotEmpty && txtStoreName.text.trim() != widget.task.storeName);
  }

  @override
  void initState() {
    super.initState();
    _prefetchData();
  }

  @override
  void dispose() {
    txtTitle.dispose();
    txtStoreName.dispose();
    txtDescription.dispose();
    super.dispose();
  }

  void _prefetchData() {
    if (isEditMode) {
      txtTitle.text = widget.task.taskTitle;
      txtStoreName.text = widget.task.storeName;
      txtDescription.text = widget.task.taskDescription;
      _selectedDeadline = widget.task.taskDeadline.toDate();
      _isTaskDone = widget.task.isTaskDone;
    } else if (widget.task.storeName.isNotEmpty) {
      txtStoreName.text = widget.task.storeName;
    }
  }

  String get _userName {
    return authService.value.currentUser?.displayName ?? 'User';
  }

  Future<void> _pickDeadline() async {
    final pickedDate = await showDatePicker(context: context, initialDate: _selectedDeadline, firstDate: DateTime(2020), lastDate: DateTime(2050));

    if (pickedDate != null && mounted) {
      final pickedTime = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_selectedDeadline));

      if (pickedTime != null && mounted) {
        setState(() {
          _selectedDeadline = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, pickedTime.hour, pickedTime.minute);
        });
      } else if (mounted) {
        setState(() {
          _selectedDeadline = DateTime(pickedDate.year, pickedDate.month, pickedDate.day, _selectedDeadline.hour, _selectedDeadline.minute);
        });
      }
    }
  }

  Future<void> onSave() async {
    if (!_formKey.currentState!.validate()) {
      ShowMessage.error(context, 'Please complete all required fields');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final newTask = Tasks(
        taskID: '',
        taskTitle: txtTitle.text.trim(),
        taskDescription: txtDescription.text.trim(),
        taskDeadline: Timestamp.fromDate(_selectedDeadline),
        storeName: txtStoreName.text.trim(),
        isTaskDone: _isTaskDone,
        createdBy: _userName,
        lastUpdatedBy: _userName,
        createdDate: Timestamp.now(),
        lastupdatedDate: Timestamp.now(),
      );

      final docRef = await db.addTasks(newTask);
      newTask.taskID = docRef.id;

      await Helperfunctions.logCreate(txtTitle.text.trim(), newTask.toJson());

      if (mounted) {
        ShowMessage.success(context, 'Successfully created task [${txtTitle.text.trim()}]!');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Error creating task: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> onUpdate() async {
    if (!_formKey.currentState!.validate()) {
      ShowMessage.error(context, 'Please complete all required fields');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final updatedTask = widget.task.copyWith(
        taskTitle: txtTitle.text.trim(),
        taskDescription: txtDescription.text.trim(),
        taskDeadline: Timestamp.fromDate(_selectedDeadline),
        storeName: txtStoreName.text.trim(),
        isTaskDone: _isTaskDone,
        lastUpdatedBy: _userName,
        lastupdatedDate: Timestamp.now(),
      );

      await db.updateTasks(widget.taskID, updatedTask);
      await Helperfunctions.logUpdate(updatedTask.taskTitle, widget.task.toJson(), updatedTask.toJson());

      if (mounted) {
        ShowMessage.success(context, 'Successfully updated task [${updatedTask.taskTitle}]!');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Error updating task: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> onDelete() async {
    setState(() => _isLoading = true);

    try {
      await db.deleteTasks(widget.taskID);
      await Helperfunctions.logDelete(widget.task.taskTitle, widget.task.toJson());

      if (mounted) {
        ShowMessage.success(context, 'Successfully deleted task [${widget.task.taskTitle}]!');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ShowMessage.error(context, 'Error deleting task: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildSectionCard({required String title, required IconData icon, required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, size: 18, color: colorScheme.primary),
                ),
                const SizedBox(width: 10),
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 24),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildStoreDropdown() {
    return HapistorePickerField(
      controller: txtStoreName,
      label: 'Hapi Store *',
      validator: (value) => value == null || value.trim().isEmpty ? 'Please select a Target Store' : null,
      onChanged: () {
        setState(() {});
      },
    );
  }

  Widget _buildDeadlinePresets() {
    final now = DateTime.now();

    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ActionChip(
              avatar: const Icon(Icons.flash_on_rounded, size: 16),
              label: const Text('+2 Hours', style: TextStyle(fontSize: 12)),
              onPressed: () {
                setState(() => _selectedDeadline = DateTime.now().add(const Duration(hours: 2)));
              },
            ),
            const SizedBox(width: 8),
            ActionChip(
              avatar: const Icon(Icons.wb_twilight_rounded, size: 16),
              label: const Text('End of Day (5 PM)', style: TextStyle(fontSize: 12)),
              onPressed: () {
                final today = DateTime.now();
                setState(() => _selectedDeadline = DateTime(today.year, today.month, today.day, 17, 0));
              },
            ),
            const SizedBox(width: 8),
            ActionChip(
              avatar: const Icon(Icons.wb_sunny_outlined, size: 16),
              label: const Text('Tomorrow (9 AM)', style: TextStyle(fontSize: 12)),
              onPressed: () {
                final tomorrow = now.add(const Duration(days: 1));
                setState(() => _selectedDeadline = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9, 0));
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeadlineField() {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final formattedDate = DateFormat('EEE, d MMM yyyy • h:mm a').format(_selectedDeadline);
    final isOverdue = !_isTaskDone && _selectedDeadline.isBefore(DateTime.now());
    final overdueColor = isDark ? Colors.red.shade300 : Colors.red.shade700;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDeadlinePresets(),
        InkWell(
          onTap: _pickDeadline,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(
                color: isOverdue ? (isDark ? Colors.red.shade400 : Colors.red.shade300) : colorScheme.outlineVariant,
                width: isOverdue ? 1.5 : 1.0,
              ),
              borderRadius: BorderRadius.circular(10),
              color: isOverdue ? (isDark ? Colors.red.withValues(alpha: 0.12) : Colors.red.withValues(alpha: 0.04)) : null,
            ),
            child: Row(
              children: [
                Icon(Icons.event_outlined, size: 20, color: isOverdue ? overdueColor : colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Deadline / Target Date', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Text(
                        formattedDate,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: isOverdue ? overdueColor : null),
                      ),
                    ],
                  ),
                ),
                if (isOverdue)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.red.withValues(alpha: 0.25) : Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Overdue',
                      style: TextStyle(color: overdueColor, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                Icon(Icons.edit_calendar_outlined, size: 18, color: colorScheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusToggle() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;
    final activeColor = _isTaskDone
        ? (isDark ? Colors.green.shade400 : Colors.green.shade700)
        : (isDark ? Colors.orange.shade400 : Colors.orange.shade800);

    return Container(
      decoration: BoxDecoration(
        color: _isTaskDone
            ? (isDark ? Colors.green.withValues(alpha: 0.15) : Colors.green.withValues(alpha: 0.08))
            : (isDark ? Colors.orange.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.08)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isTaskDone
              ? (isDark ? Colors.green.shade600 : Colors.green.withValues(alpha: 0.3))
              : (isDark ? Colors.orange.shade600 : Colors.orange.withValues(alpha: 0.3)),
        ),
      ),
      child: SwitchListTile(
        value: _isTaskDone,
        onChanged: (val) => setState(() => _isTaskDone = val),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          _isTaskDone ? 'Task Completed' : 'Task Pending',
          style: TextStyle(fontWeight: FontWeight.bold, color: activeColor),
        ),
        subtitle: Text(
          _isTaskDone ? 'Marked as completed and accomplished.' : 'Task is currently awaiting completion.',
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        secondary: Icon(_isTaskDone ? Icons.check_circle : Icons.pending_actions, color: activeColor),
      ),
    );
  }

  Widget _buildAuditInfo() {
    if (!isEditMode) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.task.createdBy.isNotEmpty)
            Text(
              'Created by: ${widget.task.createdBy} on ${Helperfunctions.formatTimestampForDisplay(widget.task.createdDate)}',
              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
            ),
          if (widget.task.lastUpdatedBy.isNotEmpty)
            Text(
              'Last updated by: ${widget.task.lastUpdatedBy} on ${Helperfunctions.formatTimestampForDisplay(widget.task.lastupdatedDate)}',
              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: !_hasUnsavedChanges || _isLoading,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await ShowMessage.confirm(
          context,
          title: 'Discard Changes?',
          message: 'You have unsaved changes. Are you sure you want to discard them?',
          isDestructive: true,
          confirmText: 'Discard',
          cancelText: 'Keep Editing',
          icon: Icons.warning_amber_rounded,
        );
        if (shouldPop && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: CustomAppbar(
          title: isEditMode ? 'Task Details' : 'Add Task',
          subtitle: isEditMode
              ? (widget.task.storeName.isNotEmpty
                    ? widget.task.storeName
                    : 'Task ID: ${widget.taskID.substring(0, widget.taskID.length > 8 ? 8 : widget.taskID.length)}')
              : (txtStoreName.text.isNotEmpty ? txtStoreName.text : 'New Task Assignment'),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Task Information Section
                      _buildSectionCard(
                        title: 'Task Information',
                        icon: Icons.assignment_outlined,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextFormField(
                              controller: txtTitle,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: 'Task Title *',
                                hintText: 'e.g. Stock inventory, Inspect cooler...',
                                prefixIcon: Icon(Icons.title_rounded, size: 20, color: colorScheme.primary),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              ),
                              autovalidateMode: AutovalidateMode.onUserInteraction,
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Task title cannot be blank';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                            _buildStoreDropdown(),
                            const SizedBox(height: 16),
                            _buildDeadlineField(),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: txtDescription,
                              maxLines: 4,
                              minLines: 3,
                              decoration: InputDecoration(
                                labelText: 'Task Description / Notes',
                                hintText: 'Provide details, instructions, or steps to fulfill this task...',
                                prefixIcon: Padding(
                                  padding: const EdgeInsets.only(bottom: 40),
                                  child: Icon(Icons.notes_rounded, size: 20, color: colorScheme.primary),
                                ),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Status Section
                      _buildSectionCard(title: 'Task Status', icon: Icons.checklist_rounded, child: _buildStatusToggle()),

                      const SizedBox(height: 8),
                      _buildAuditInfo(),
                      const SizedBox(height: 24),

                      // Action Buttons
                      if (isEditMode)
                        Row(
                          children: [
                            Expanded(
                              flex: 1,
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final confirmed = await ShowMessage.confirm(
                                    context,
                                    title: ConfirmTitle.delete,
                                    message: 'Are you sure you want to delete task [${widget.task.taskTitle}]?',
                                    isDestructive: true,
                                    icon: Icons.delete_outline,
                                    confirmText: 'Delete',
                                  );
                                  if (confirmed) onDelete();
                                },
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 50.0),
                                  foregroundColor: isDark ? Colors.red.shade400 : Colors.red.shade700,
                                  side: BorderSide(color: isDark ? Colors.red.shade400.withValues(alpha: 0.6) : Colors.red.shade300, width: 1.2),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.delete_outline, size: 20),
                                label: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: FilledButton.icon(
                                onPressed: () async {
                                  final confirmed = await ShowMessage.confirm(
                                    context,
                                    title: ConfirmTitle.update,
                                    message: 'Save changes to task [${txtTitle.text.trim()}]?',
                                    icon: Icons.check_circle_outline,
                                    confirmText: 'Update',
                                  );
                                  if (confirmed) onUpdate();
                                },
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(0, 50.0),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                icon: const Icon(Icons.check, size: 20),
                                label: const Text('Update Task', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        )
                      else
                        FilledButton.icon(
                          onPressed: onSave,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(double.infinity, 50.0),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          icon: const Icon(Icons.add_task_rounded, size: 20),
                          label: const Text('Create Task', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
