import 'database.dart';

import 'package:drift/drift.dart';

/// The presentation layer uses this class instead of issuing SQL directly.
class TaskFlowRepository {
  TaskFlowRepository(this.db);
  final AppDatabase db;

  Stream<List<User>> watchUsers() => db.watchUsers();
  Stream<List<Project>> watchProjects() => db.watchProjects();
  Stream<List<Task>> watchTasks({
    String search = '',
    String? status,
    String? priority,
    int? assigneeId,
    bool trash = false,
    int limit = 50,
    String sortBy = 'created',
  }) => db.watchTasks(
    search: search,
    status: status,
    priority: priority,
    assigneeId: assigneeId,
    trash: trash,
    limit: limit,
    sortBy: sortBy,
  );
  Future<int> addUser(String name, String email) => db
      .into(db.users)
      .insert(
        UsersCompanion.insert(
          name: name.trim(),
          email: email.trim().toLowerCase(),
        ),
      );
  Future<int> addProject(String name, String description) => db
      .into(db.projects)
      .insert(
        ProjectsCompanion.insert(
          name: name.trim(),
          description: Value(description.trim()),
        ),
      );
  Future<void> deleteProject(int id) =>
      (db.delete(db.projects)..where((p) => p.id.equals(id))).go();
  Future<void> updateProject(int id, String name, String description) =>
      db.updateProject(id, name, description);
  Future<void> deleteUser(int id) => db.deleteUser(id);
  Future<void> updateUser(int id, String name, String email) =>
      db.updateUser(id, name, email);
  Future<int> addTask({
    required String title,
    required String description,
    required int projectId,
    int? assigneeId,
    required String priority,
    DateTime? deadline,
  }) => db.createTask(
    title: title,
    description: description,
    projectId: projectId,
    assigneeId: assigneeId,
    priority: priority,
    deadline: deadline,
  );
  Future<void> changeStatus(int id, String status) => db.setStatus(id, status);
  Future<void> undoStatus(int id) => db.undoStatus(id);
  Future<void> updateTask({
    required int id,
    required String title,
    required String description,
    required String priority,
    DateTime? deadline,
    int? assigneeId,
  }) => db.updateTask(
    id: id,
    title: title,
    description: description,
    priority: priority,
    deadline: deadline,
    assigneeId: assigneeId,
  );
  Future<void> removeTask(int id) => db.softDeleteTask(id);
  Future<void> restoreTask(int id) => db.restoreTask(id);
  Future<void> purgeTask(int id) => db.purgeTask(id);
  Future<Map<String, int>> statistics() => db.statistics();
  Stream<Map<String, int>> watchStatistics() => db.watchStatistics();
  Stream<List<Map<String, Object>>> watchPriorityCounts() =>
      db.watchPriorityCounts();
  Stream<List<Map<String, Object>>> watchAssigneeCounts() =>
      db.watchAssigneeCounts();
  Stream<List<Map<String, Object>>> watchProjectProgress() =>
      db.watchProjectProgress();
  Future<List<User>> users() => db.select(db.users).get();
  Future<List<ProjectMember>> projectMembers(int projectId) => (db.select(
    db.projectMembers,
  )..where((m) => m.projectId.equals(projectId))).get();
  Future<void> addProjectMember(int projectId, int userId, String role) =>
      db.addProjectMember(projectId, userId, role);
  Future<void> removeProjectMember(int projectId, int userId) =>
      db.removeProjectMember(projectId, userId);
  Future<void> setProjectStatus(int id, String status) =>
      db.setProjectStatus(id, status);
  Future<void> assignTask(int id, int? userId) => db.assignTask(id, userId);
  Stream<List<TaskHistoryData>> watchHistory(int taskId) =>
      db.watchHistory(taskId);
  Stream<List<Comment>> watchComments(int taskId) => db.watchComments(taskId);
  Stream<List<Attachment>> watchAttachments(int taskId) =>
      db.watchAttachments(taskId);
  Future<void> addAttachment(int taskId, String path) =>
      db.addAttachment(taskId, path);
  Future<int?> currentUserId() => db.currentUserId();
  Future<void> addComment(int taskId, int authorId, String body) =>
      db.addComment(taskId, authorId, body);
  Future<void> deleteComment(int id, int authorId) =>
      db.deleteComment(id, authorId);
  Future<void> seedPerformanceData() => db.seedPerformanceData();
  Future<Map<String, int>> compareIndexPerformance() =>
      db.compareIndexPerformance();
}
