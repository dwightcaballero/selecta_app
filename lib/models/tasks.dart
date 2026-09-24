import 'package:cloud_firestore/cloud_firestore.dart';

class Tasks {
  String taskID;
  String taskTitle;
  String taskDescription;
  Timestamp taskDeadline;
  String storeName;
  bool isTaskDone;
  String createdBy;
  String lastUpdatedBy;
  Timestamp createdDate;
  Timestamp lastupdatedDate;

  Tasks({
    required this.taskID,
    required this.taskTitle,
    required this.taskDescription,
    required this.taskDeadline,
    required this.storeName,
    required this.isTaskDone,
    required this.createdBy,
    required this.lastUpdatedBy,
    required this.createdDate,
    required this.lastupdatedDate,
  });

  static Tasks empty() => Tasks(
    taskID: '',
    taskTitle: '',
    taskDescription: '',
    taskDeadline: Timestamp.now(),
    storeName: '',
    isTaskDone: false,
    createdBy: '',
    lastUpdatedBy: '',
    createdDate: Timestamp.now(),
    lastupdatedDate: Timestamp.now(),
  );

  Tasks.fromJson(Map<String, Object?> json)
    : this(
        taskID: json['taskID'] as String? ?? '',
        taskTitle: json['taskTitle'] as String? ?? '',
        taskDescription: json['taskDescription'] as String? ?? '',
        taskDeadline: (json['taskDeadline'] is Timestamp)
            ? json['taskDeadline'] as Timestamp
            : Timestamp.now(),
        storeName: json['storeName'] as String? ?? '',
        isTaskDone: json['isTaskDone'] as bool? ?? false,
        createdBy: json['createdBy'] as String? ?? '',
        lastUpdatedBy: json['lastUpdatedBy'] as String? ?? '',
        createdDate: (json['createdDate'] is Timestamp)
            ? json['createdDate'] as Timestamp
            : Timestamp.now(),
        lastupdatedDate: (json['lastupdatedDate'] is Timestamp)
            ? json['lastupdatedDate'] as Timestamp
            : Timestamp.now(),
      );

  factory Tasks.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> document) {
    if (document.data() != null) {
      final data = document.data();
      return Tasks(
        taskID: data?['taskID'] as String? ?? document.id,
        taskTitle: data?['taskTitle'] as String? ?? '',
        taskDescription: data?['taskDescription'] as String? ?? '',
        taskDeadline: (data?['taskDeadline'] is Timestamp)
            ? data!['taskDeadline'] as Timestamp
            : Timestamp.now(),
        storeName: data?['storeName'] as String? ?? '',
        isTaskDone: data?['isTaskDone'] as bool? ?? false,
        createdBy: data?['createdBy'] as String? ?? '',
        lastUpdatedBy: data?['lastUpdatedBy'] as String? ?? '',
        createdDate: (data?['createdDate'] is Timestamp)
            ? data!['createdDate'] as Timestamp
            : Timestamp.now(),
        lastupdatedDate: (data?['lastupdatedDate'] is Timestamp)
            ? data!['lastupdatedDate'] as Timestamp
            : Timestamp.now(),
      );
    } else {
      return Tasks.empty();
    }
  }

  Tasks copyWith({
    String? taskID,
    String? taskTitle,
    String? taskDescription,
    Timestamp? taskDeadline,
    String? storeName,
    bool? isTaskDone,
    String? createdBy,
    String? lastUpdatedBy,
    Timestamp? createdDate,
    Timestamp? lastupdatedDate,
  }) {
    return Tasks(
      taskID: taskID ?? this.taskID,
      taskTitle: taskTitle ?? this.taskTitle,
      taskDescription: taskDescription ?? this.taskDescription,
      taskDeadline: taskDeadline ?? this.taskDeadline,
      storeName: storeName ?? this.storeName,
      isTaskDone: isTaskDone ?? this.isTaskDone,
      createdBy: createdBy ?? this.createdBy,
      lastUpdatedBy: lastUpdatedBy ?? this.lastUpdatedBy,
      createdDate: createdDate ?? this.createdDate,
      lastupdatedDate: lastupdatedDate ?? this.lastupdatedDate,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'taskID': taskID,
      'taskTitle': taskTitle,
      'taskDescription': taskDescription,
      'taskDeadline': taskDeadline,
      'storeName': storeName,
      'isTaskDone': isTaskDone,
      'createdBy': createdBy,
      'lastUpdatedBy': lastUpdatedBy,
      'createdDate': createdDate,
      'lastupdatedDate': lastupdatedDate,
    };
  }
}
