import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get email => text().unique()();
  DateTimeColumn get registeredAt =>
      dateTime().withDefault(currentDateAndTime)();
}

@TableIndex(name: 'projects_status_idx', columns: {#status})
class Projects extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 160)();
  TextColumn get description => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deadline => dateTime().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
}

@TableIndex(name: 'members_user_idx', columns: {#userId})
class ProjectMembers extends Table {
  IntColumn get projectId =>
      integer().references(Projects, #id, onDelete: KeyAction.cascade)();
  IntColumn get userId =>
      integer().references(Users, #id, onDelete: KeyAction.cascade)();
  TextColumn get role => text().withDefault(const Constant('Member'))();
  @override
  Set<Column> get primaryKey => {projectId, userId};
}

@TableIndex(name: 'tasks_project_idx', columns: {#projectId})
@TableIndex(name: 'tasks_status_priority_idx', columns: {#status, #priority})
@TableIndex(
  name: 'tasks_assignee_deadline_idx',
  columns: {#assigneeId, #deadline},
)
@TableIndex(name: 'tasks_deleted_idx', columns: {#deletedAt})
class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get description => text().withDefault(const Constant(''))();
  IntColumn get projectId =>
      integer().references(Projects, #id, onDelete: KeyAction.cascade)();
  IntColumn get assigneeId => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get priority => text().withDefault(const Constant('medium'))();
  TextColumn get status => text().withDefault(const Constant('todo'))();
  DateTimeColumn get deadline => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
}

class Comments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get taskId =>
      integer().references(Tasks, #id, onDelete: KeyAction.cascade)();
  IntColumn get authorId =>
      integer().references(Users, #id, onDelete: KeyAction.cascade)();
  TextColumn get body => text().withLength(min: 1, max: 4000)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Attachments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get taskId =>
      integer().references(Tasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get fileName => text()();
  TextColumn get localPath => text()();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();
}

class TaskHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get taskId =>
      integer().references(Tasks, #id, onDelete: KeyAction.cascade)();
  TextColumn get previousStatus => text().nullable()();
  TextColumn get newStatus => text()();
  IntColumn get changedBy => integer().nullable().references(
    Users,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get event => text().withDefault(const Constant('status'))();
  DateTimeColumn get changedAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(
  tables: [
    Users,
    Projects,
    ProjectMembers,
    Tasks,
    Comments,
    Attachments,
    TaskHistory,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(tasks, tasks.priority);
        await customStatement(
          "UPDATE tasks SET priority = 'medium' WHERE priority IS NULL",
        );
      }
    },
    beforeOpen: (details) async => customStatement('PRAGMA foreign_keys = ON'),
  );

  Future<int> createTask({
    required String title,
    String description = '',
    required int projectId,
    int? assigneeId,
    String priority = 'medium',
    DateTime? deadline,
  }) async {
    return transaction(() async {
      if (assigneeId != null) {
        await _requireMembership(projectId, assigneeId);
        await _ensureCapacity(assigneeId, deadline);
      }
      final id = await into(tasks).insert(
        TasksCompanion.insert(
          title: title.trim(),
          description: Value(description),
          projectId: projectId,
          assigneeId: Value(assigneeId),
          priority: Value(priority),
          deadline: Value(deadline),
        ),
      );
      final actorId = await currentUserId();
      await into(taskHistory).insert(
        TaskHistoryCompanion.insert(
          taskId: id,
          newStatus: 'todo',
          changedBy: Value(actorId),
          event: const Value('created'),
        ),
      );
      return id;
    });
  }

  Future<int?> currentUserId() async =>
      (await (select(users)
                ..orderBy([(u) => OrderingTerm.asc(u.id)])
                ..limit(1))
              .getSingleOrNull())
          ?.id;

  Future<void> _requireMembership(int projectId, int userId) async {
    final member =
        await (select(projectMembers)..where(
              (m) => m.projectId.equals(projectId) & m.userId.equals(userId),
            ))
            .getSingleOrNull();
    if (member == null)
      throw StateError('Исполнитель должен быть участником проекта');
  }

  Future<void> _ensureCapacity(
    int userId,
    DateTime? deadline, {
    int? excludeTaskId,
  }) async {
    if (deadline == null) return;
    final openTasks =
        await (select(tasks)..where(
              (t) =>
                  t.assigneeId.equals(userId) &
                  t.deadline.equals(deadline) &
                  t.deletedAt.isNull() &
                  t.status.isNotIn(['done', 'cancelled']) &
                  (excludeTaskId == null
                      ? const Constant(true)
                      : t.id.isNotIn([excludeTaskId])),
            ))
            .get();
    if (openTasks.length >= 3) {
      throw StateError(
        'У исполнителя уже есть три незавершённые задачи с этим дедлайном',
      );
    }
  }

  Future<void> setStatus(int taskId, String status, {int? changedBy}) async {
    const allowed = {'todo', 'inProgress', 'done', 'cancelled'};
    if (!allowed.contains(status)) throw ArgumentError.value(status, 'status');
    await transaction(() async {
      final task = await (select(
        tasks,
      )..where((t) => t.id.equals(taskId) & t.deletedAt.isNull())).getSingle();
      if (task.status == status) return;
      final actorId = changedBy ?? await currentUserId();
      await (update(tasks)..where((t) => t.id.equals(taskId))).write(
        TasksCompanion(status: Value(status), updatedAt: Value(DateTime.now())),
      );
      await into(taskHistory).insert(
        TaskHistoryCompanion.insert(
          taskId: taskId,
          previousStatus: Value(task.status),
          newStatus: status,
          changedBy: Value(actorId),
        ),
      );
    });
  }

  Future<void> undoStatus(int taskId) async {
    await transaction(() async {
      final latest =
          await (select(taskHistory)
                ..where(
                  (h) => h.taskId.equals(taskId) & h.event.equals('status'),
                )
                ..orderBy([
                  (h) => OrderingTerm.desc(h.changedAt),
                  (h) => OrderingTerm.desc(h.id),
                ])
                ..limit(1))
              .getSingleOrNull();
      if (latest?.previousStatus == null) return;
      await (update(tasks)..where((t) => t.id.equals(taskId))).write(
        TasksCompanion(
          status: Value(latest!.previousStatus!),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await into(taskHistory).insert(
        TaskHistoryCompanion.insert(
          taskId: taskId,
          previousStatus: Value(latest.newStatus),
          newStatus: latest.previousStatus!,
          event: const Value('undo'),
        ),
      );
    });
  }

  Future<void> assignTask(int taskId, int? userId) async {
    await transaction(() async {
      final task = await (select(
        tasks,
      )..where((t) => t.id.equals(taskId))).getSingle();
      if (userId != null) {
        await _requireMembership(task.projectId, userId);
        if (task.status != 'done' && task.status != 'cancelled')
          await _ensureCapacity(userId, task.deadline, excludeTaskId: taskId);
      }
      await (update(tasks)..where((t) => t.id.equals(taskId))).write(
        TasksCompanion(
          assigneeId: Value(userId),
          updatedAt: Value(DateTime.now()),
        ),
      );
      await into(taskHistory).insert(
        TaskHistoryCompanion.insert(
          taskId: taskId,
          previousStatus: Value(task.assigneeId?.toString()),
          newStatus: userId?.toString() ?? '',
          event: const Value('assignee'),
        ),
      );
    });
  }

  Future<void> softDeleteTask(int taskId) async =>
      (update(tasks)..where((t) => t.id.equals(taskId))).write(
        TasksCompanion(deletedAt: Value(DateTime.now())),
      );
  Future<void> restoreTask(int taskId) async =>
      (update(tasks)..where((t) => t.id.equals(taskId))).write(
        const TasksCompanion(deletedAt: Value(null)),
      );
  Future<void> purgeTask(int taskId) async =>
      (delete(tasks)..where((t) => t.id.equals(taskId))).go();

  Stream<List<Task>> watchTasks({
    int? projectId,
    String? status,
    String? priority,
    int? assigneeId,
    String search = '',
    bool trash = false,
    int limit = 50,
    int offset = 0,
    String sortBy = 'created',
  }) {
    final q = select(tasks)
      ..where((t) => trash ? t.deletedAt.isNotNull() : t.deletedAt.isNull());
    if (projectId != null) q.where((t) => t.projectId.equals(projectId));
    if (status != null) q.where((t) => t.status.equals(status));
    if (priority != null) q.where((t) => t.priority.equals(priority));
    if (assigneeId != null) q.where((t) => t.assigneeId.equals(assigneeId));
    if (search.trim().isNotEmpty)
      q.where(
        (t) =>
            t.title.contains(search.trim()) |
            t.description.contains(search.trim()),
      );
    if (sortBy == 'deadline') {
      q.orderBy([(t) => OrderingTerm.asc(t.deadline)]);
    } else {
      q.orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    }
    q.limit(limit, offset: offset);
    return q.watch();
  }

  Future<List<Task>> searchTasks({
    String search = '',
    int limit = 50,
    int offset = 0,
  }) =>
      (select(tasks)
            ..where(
              (t) =>
                  t.deletedAt.isNull() &
                  (t.title.contains(search) | t.description.contains(search)),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
            ..limit(limit, offset: offset))
          .get();

  Stream<List<Project>> watchProjects() => select(projects).watch();
  Stream<List<User>> watchUsers() => select(users).watch();
  Stream<List<TaskHistoryData>> watchHistory(int taskId) =>
      (select(taskHistory)
            ..where((h) => h.taskId.equals(taskId))
            ..orderBy([
              (h) => OrderingTerm.desc(h.changedAt),
              (h) => OrderingTerm.desc(h.id),
            ]))
          .watch();
  Stream<List<Comment>> watchComments(int taskId) =>
      (select(comments)
            ..where((c) => c.taskId.equals(taskId))
            ..orderBy([(c) => OrderingTerm.asc(c.createdAt)]))
          .watch();

  Future<void> addComment(int taskId, int authorId, String body) async =>
      into(comments).insert(
        CommentsCompanion.insert(
          taskId: taskId,
          authorId: authorId,
          body: body.trim(),
        ),
      );
  Stream<List<Attachment>> watchAttachments(int taskId) =>
      (select(attachments)..where((a) => a.taskId.equals(taskId))).watch();
  Future<void> addAttachment(int taskId, String path) async {
    final fileName = path.split(RegExp(r'[/\\]')).last;
    await into(attachments).insert(
      AttachmentsCompanion.insert(
        taskId: taskId,
        fileName: fileName,
        localPath: path,
      ),
    );
  }

  Future<void> deleteComment(int commentId, int authorId) async {
    final comment = await (select(
      comments,
    )..where((c) => c.id.equals(commentId))).getSingle();
    if (comment.authorId != authorId)
      throw StateError('Удалить комментарий может только его автор');
    await (delete(comments)..where((c) => c.id.equals(commentId))).go();
  }

  Future<void> addProjectMember(int projectId, int userId, String role) async =>
      into(projectMembers).insert(
        ProjectMembersCompanion.insert(
          projectId: projectId,
          userId: userId,
          role: Value(role),
        ),
      );
  Future<void> removeProjectMember(int projectId, int userId) async {
    final active =
        await (select(tasks)..where(
              (t) =>
                  t.projectId.equals(projectId) &
                  t.assigneeId.equals(userId) &
                  t.deletedAt.isNull() &
                  t.status.isNotIn(['done', 'cancelled']),
            ))
            .get();
    if (active.isNotEmpty)
      throw StateError('Сначала переназначьте незавершённые задачи участника');
    await (delete(projectMembers)..where(
          (m) => m.projectId.equals(projectId) & m.userId.equals(userId),
        ))
        .go();
  }

  Future<void> deleteUser(int userId) async {
    final active =
        await (select(tasks)..where(
              (t) =>
                  t.assigneeId.equals(userId) &
                  t.deletedAt.isNull() &
                  t.status.isNotIn(['done', 'cancelled']),
            ))
            .get();
    if (active.isNotEmpty)
      throw StateError('Нельзя удалить пользователя с незавершёнными задачами');
    await (delete(users)..where((u) => u.id.equals(userId))).go();
  }

  Future<void> updateUser(int id, String name, String email) async =>
      (update(users)..where((u) => u.id.equals(id))).write(
        UsersCompanion(
          name: Value(name.trim()),
          email: Value(email.trim().toLowerCase()),
        ),
      );
  Future<void> updateProject(int id, String name, String description) async =>
      (update(projects)..where((p) => p.id.equals(id))).write(
        ProjectsCompanion(
          name: Value(name.trim()),
          description: Value(description.trim()),
        ),
      );
  Future<void> setProjectStatus(int id, String status) async {
    if (!{'active', 'completed', 'archived'}.contains(status)) {
      throw ArgumentError.value(status, 'status');
    }
    await (update(projects)..where((p) => p.id.equals(id))).write(
      ProjectsCompanion(status: Value(status)),
    );
  }

  Future<void> updateTask({
    required int id,
    required String title,
    required String description,
    required String priority,
    DateTime? deadline,
    int? assigneeId,
  }) async {
    await transaction(() async {
      final task = await (select(
        tasks,
      )..where((t) => t.id.equals(id))).getSingle();
      if (assigneeId != null)
        await _requireMembership(task.projectId, assigneeId);
      if (assigneeId != null &&
          deadline != null &&
          task.status != 'done' &&
          task.status != 'cancelled') {
        await _ensureCapacity(assigneeId, deadline, excludeTaskId: id);
      }
      await (update(tasks)..where((t) => t.id.equals(id))).write(
        TasksCompanion(
          title: Value(title.trim()),
          description: Value(description.trim()),
          priority: Value(priority),
          deadline: Value(deadline),
          assigneeId: Value(assigneeId),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  Future<Map<String, int>> compareIndexPerformance() async {
    final indexed = Stopwatch()..start();
    await customSelect(
      "SELECT COUNT(*) AS total FROM tasks INDEXED BY tasks_status_priority_idx WHERE status = 'todo' AND priority = 'high'",
    ).getSingle();
    indexed.stop();
    final scan = Stopwatch()..start();
    await customSelect(
      "SELECT COUNT(*) AS total FROM tasks NOT INDEXED WHERE status = 'todo' AND priority = 'high'",
    ).getSingle();
    scan.stop();
    return {
      'indexedMicroseconds': indexed.elapsedMicroseconds,
      'withoutIndexMicroseconds': scan.elapsedMicroseconds,
    };
  }

  Future<Map<String, int>> statistics() async {
    final rows = await customSelect(
      '''SELECT
      (SELECT COUNT(*) FROM projects) AS projects,
      (SELECT COUNT(*) FROM tasks WHERE deleted_at IS NULL) AS tasks,
      (SELECT COUNT(*) FROM tasks WHERE deleted_at IS NULL AND status = 'done') AS done,
      (SELECT COUNT(*) FROM tasks WHERE deleted_at IS NULL AND status NOT IN ('done','cancelled')) AS open,
      (SELECT COUNT(*) FROM tasks WHERE deleted_at IS NULL AND deadline < ? AND status NOT IN ('done','cancelled')) AS overdue''',
      variables: [Variable.withDateTime(DateTime.now())],
    ).getSingle();
    return {
      for (final k in ['projects', 'tasks', 'done', 'open', 'overdue'])
        k: rows.read<int>(k),
    };
  }

  Stream<Map<String, int>> watchStatistics() =>
      customSelect(
        '''SELECT
      (SELECT COUNT(*) FROM projects) AS projects,
      (SELECT COUNT(*) FROM tasks WHERE deleted_at IS NULL) AS tasks,
      (SELECT COUNT(*) FROM tasks WHERE deleted_at IS NULL AND status = 'done') AS done,
      (SELECT COUNT(*) FROM tasks WHERE deleted_at IS NULL AND status NOT IN ('done','cancelled')) AS open,
      (SELECT COUNT(*) FROM tasks WHERE deleted_at IS NULL AND deadline < ? AND status NOT IN ('done','cancelled')) AS overdue''',
        variables: [Variable.withDateTime(DateTime.now())],
        readsFrom: {projects, tasks},
      ).watch().map((rows) {
        final row = rows.single;
        return {
          for (final key in ['projects', 'tasks', 'done', 'open', 'overdue'])
            key: row.read<int>(key),
        };
      });

  Stream<List<Map<String, Object>>> watchPriorityCounts() =>
      customSelect(
        "SELECT priority, COUNT(*) AS total FROM tasks WHERE deleted_at IS NULL GROUP BY priority ORDER BY priority",
        readsFrom: {tasks},
      ).watch().map(
        (rows) => rows
            .map(
              (r) => <String, Object>{
                'name': r.read<String>('priority'),
                'count': r.read<int>('total'),
              },
            )
            .toList(),
      );

  Stream<List<Map<String, Object>>> watchAssigneeCounts() =>
      customSelect(
        "SELECT COALESCE(users.name, 'Без исполнителя') AS name, COUNT(*) AS total FROM tasks LEFT JOIN users ON users.id = tasks.assignee_id WHERE tasks.deleted_at IS NULL GROUP BY users.id, users.name ORDER BY total DESC",
        readsFrom: {tasks, users},
      ).watch().map(
        (rows) => rows
            .map(
              (r) => <String, Object>{
                'name': r.read<String>('name'),
                'count': r.read<int>('total'),
              },
            )
            .toList(),
      );

  Stream<List<Map<String, Object>>> watchProjectProgress() =>
      customSelect(
        "SELECT projects.name AS name, CASE WHEN COUNT(tasks.id)=0 THEN 0 ELSE CAST(SUM(CASE WHEN tasks.status='done' THEN 1 ELSE 0 END) * 100.0 / COUNT(tasks.id) AS INTEGER) END AS progress FROM projects LEFT JOIN tasks ON tasks.project_id=projects.id AND tasks.deleted_at IS NULL GROUP BY projects.id, projects.name ORDER BY projects.name",
        readsFrom: {projects, tasks},
      ).watch().map(
        (rows) => rows
            .map(
              (r) => <String, Object>{
                'name': r.read<String>('name'),
                'count': r.read<int>('progress'),
              },
            )
            .toList(),
      );

  Future<void> seedPerformanceData() async => transaction(() async {
    final userIds = <int>[];
    for (var i = 0; i < 1000; i++)
      userIds.add(
        await into(users).insert(
          UsersCompanion.insert(
            name: 'User $i',
            email: 'user$i@taskflow.local',
          ),
        ),
      );
    final projectIds = <int>[];
    for (var i = 0; i < 100; i++)
      projectIds.add(
        await into(projects)
            .insert(ProjectsCompanion.insert(name: 'Project $i')),
      );
    for (var i = 0; i < 10000; i++) {
      await into(tasks).insert(
        TasksCompanion.insert(
          title: 'Task $i',
          projectId: projectIds[i % projectIds.length],
          assigneeId: Value(userIds[i % userIds.length]),
          priority: Value(['low', 'medium', 'high', 'critical'][i % 4]),
        ),
      );
    }
  });
}

LazyDatabase _openConnection() => LazyDatabase(() async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path, 'taskflow.sqlite'));
  return NativeDatabase.createInBackground(file);
});
