import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_app/models/tasks.dart';

// ignore: constant_identifier_names
const String TASKS_COLLECTION_REF = 'tasks';

class TasksService {
  final _firestore = FirebaseFirestore.instance;
  late final CollectionReference _tasksRef;

  TasksService() {
    _tasksRef = _firestore
        .collection(TASKS_COLLECTION_REF)
        .withConverter<Tasks>(
          fromFirestore: (snapshots, _) {
            final data = snapshots.data();
            if (data == null) return Tasks.empty();
            final task = Tasks.fromJson(data);
            if (task.taskID.isEmpty) {
              task.taskID = snapshots.id;
            }
            return task;
          },
          toFirestore: (tasks, _) => tasks.toJson(),
        );
  }

  Stream<QuerySnapshot> getListTasks() {
    return _tasksRef.orderBy('taskDeadline', descending: true).snapshots();
  }

  Future<DocumentReference> addTasks(Tasks tasks) async {
    return await _tasksRef.add(tasks);
  }

  Future<void> updateTasks(String taskID, Tasks tasks) async {
    await _tasksRef.doc(taskID).update(tasks.toJson());
  }

  Future<void> deleteTasks(String taskID) async {
    await _tasksRef.doc(taskID).delete();
  }
}
