import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:selecta_ops/models/tasks.dart';

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

  Stream<QuerySnapshot> getListTasks({int limit = 100}) {
    return _tasksRef.orderBy('taskDeadline', descending: true).limit(limit).snapshots();
  }

  Future<List<Tasks>> getTasksByStoreName(String storeName, {int limit = 50}) async {
    final snapshot = await _tasksRef.where('storeName', isEqualTo: storeName).limit(limit).get();
    return snapshot.docs.map((doc) => doc.data() as Tasks).toList();
  }

  /// Cost Optimization: Server-side aggregation count without downloading documents.
  Future<int> getPendingAndOverdueCount() async {
    final agg = await _tasksRef.where('isTaskDone', isEqualTo: false).count().get();
    return agg.count ?? 0;
  }

  Stream<int> getPendingAndOverdueCountStream({int limit = 100}) {
    return _tasksRef
        .where('isTaskDone', isEqualTo: false)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
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
