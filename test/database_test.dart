import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/data/database.dart';

void main() {
  late AppDatabase db;
  late int userId;
  late int projectId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    userId = await db
        .into(db.users)
        .insert(UsersCompanion.insert(name: 'Ari', email: 'ari@example.com'));
    projectId = await db
        .into(db.projects)
        .insert(ProjectsCompanion.insert(name: 'Demo'));
    await db.addProjectMember(projectId, userId, 'Owner');
  });
  tearDown(() async => db.close());

  Future<int> task({
    int? assignee,
    String priority = 'medium',
    DateTime? deadline,
  }) => db.createTask(
    title: 'Task',
    projectId: projectId,
    assigneeId: assignee,
    priority: priority,
    deadline: deadline,
  );

  test('creates a user', () async {
    expect((await db.select(db.users).get()).length, 1);
  });
  test('email is unique', () async {
    await expectLater(
      db
          .into(db.users)
          .insert(
            UsersCompanion.insert(name: 'Other', email: 'ari@example.com'),
          ),
      throwsA(anything),
    );
  });
  test('creates a project', () async {
    expect((await db.select(db.projects).getSingle()).name, 'Demo');
  });
  test('adds a project member with role', () async {
    expect((await db.select(db.projectMembers).getSingle()).role, 'Owner');
  });
  test('prevents adding a member twice', () async {
    await expectLater(
      db.addProjectMember(projectId, userId, 'Member'),
      throwsA(anything),
    );
  });
  test('creates a task with medium priority by default', () async {
    final id = await db.createTask(title: 'Task', projectId: projectId);
    expect(
      (await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(id))).getSingle()).priority,
      'medium',
    );
  });
  test('creates initial history in the same transaction', () async {
    final id = await task();
    expect((await db.watchHistory(id).first).single.event, 'created');
  });
  test('rejects an assignee who is not in the project', () async {
    final outsider = await db
        .into(db.users)
        .insert(UsersCompanion.insert(name: 'Bo', email: 'bo@example.com'));
    await expectLater(task(assignee: outsider), throwsA(isA<StateError>()));
    expect(await db.select(db.tasks).get(), isEmpty);
  });
  test('rolls back a task if initial history insert fails', () async {
    await db.customStatement(
      "CREATE TRIGGER fail_history BEFORE INSERT ON task_history BEGIN SELECT RAISE(ABORT, 'history failed'); END",
    );
    await expectLater(task(), throwsA(anything));
    expect(await db.select(db.tasks).get(), isEmpty);
  });
  test('changes status and records previous and new values', () async {
    final id = await task();
    await db.setStatus(id, 'inProgress');
    final h = await db.watchHistory(id).first;
    expect(h.first.previousStatus, 'todo');
    expect(h.first.newStatus, 'inProgress');
  });
  test('undo restores the previous status', () async {
    final id = await task();
    await db.setStatus(id, 'inProgress');
    await db.undoStatus(id);
    expect(
      (await (db.select(
        db.tasks,
      )..where((t) => t.id.equals(id))).getSingle()).status,
      'todo',
    );
  });
  test('soft delete keeps task out of the active list', () async {
    final id = await task();
    await db.softDeleteTask(id);
    expect(await db.watchTasks().first, isEmpty);
    expect((await db.watchTasks(trash: true).first).single.id, id);
  });
  test('restores a task from trash', () async {
    final id = await task();
    await db.softDeleteTask(id);
    await db.restoreTask(id);
    expect((await db.watchTasks().first).single.id, id);
  });
  test('adds and reads comments', () async {
    final id = await task();
    await db.addComment(id, userId, 'Note');
    expect((await db.watchComments(id).first).single.body, 'Note');
  });
  test('only the comment author can delete it', () async {
    final id = await task();
    await db.addComment(id, userId, 'Note');
    final comment = (await db.watchComments(id).first).single;
    await expectLater(
      db.deleteComment(comment.id, userId + 1),
      throwsA(isA<StateError>()),
    );
  });
  test('blocks deleting a user with an unfinished assigned task', () async {
    await task(assignee: userId);
    await expectLater(db.deleteUser(userId), throwsA(isA<StateError>()));
  });
  test('allows deleting a user after their task is done', () async {
    final id = await task(assignee: userId);
    await db.setStatus(id, 'done');
    await db.deleteUser(userId);
    expect(await db.select(db.users).get(), isEmpty);
  });
  test('calculates SQL dashboard totals', () async {
    final id = await task();
    await db.setStatus(id, 'done');
    final stats = await db.statistics();
    expect(stats['projects'], 1);
    expect(stats['tasks'], 1);
    expect(stats['done'], 1);
  });
  test('paginates search results', () async {
    await task();
    await db.createTask(title: 'Second', projectId: projectId);
    expect(await db.searchTasks(limit: 1), hasLength(1));
    expect(await db.searchTasks(limit: 1, offset: 1), hasLength(1));
  });
  test(
    'limits an assignee to three open tasks for the same deadline',
    () async {
      final date = DateTime(2026, 12, 1);
      for (var i = 0; i < 3; i++)
        await db.createTask(
          title: 'Due $i',
          projectId: projectId,
          assigneeId: userId,
          deadline: date,
        );
      await expectLater(
        db.createTask(
          title: 'Too many',
          projectId: projectId,
          assigneeId: userId,
          deadline: date,
        ),
        throwsA(isA<StateError>()),
      );
    },
  );
  test('stores an attachment path without copying file contents', () async {
    final id = await task();
    await db.addAttachment(id, '/tmp/brief.pdf');
    final attachment = (await db.watchAttachments(id).first).single;
    expect(attachment.fileName, 'brief.pdf');
    expect(attachment.localPath, '/tmp/brief.pdf');
  });
  test('prepares the requested performance dataset and index timing', () async {
    await db.seedPerformanceData();
    expect((await db.select(db.users).get()).length, 1001);
    expect((await db.select(db.projects).get()).length, 101);
    expect((await db.select(db.tasks).get()).length, 10000);
    final timings = await db.compareIndexPerformance();
    expect(
      timings.keys,
      containsAll(['indexedMicroseconds', 'withoutIndexMicroseconds']),
    );
  });
  test('migrates an existing v1 task and preserves its data', () async {
    await db.close();
    final migrated = AppDatabase.forTesting(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute(
            'CREATE TABLE users (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, email TEXT NOT NULL, registered_at INTEGER NOT NULL)',
          );
          raw.execute(
            "CREATE TABLE projects (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, description TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL, deadline INTEGER, status TEXT NOT NULL DEFAULT 'active')",
          );
          raw.execute(
            "CREATE TABLE tasks (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '', project_id INTEGER NOT NULL, assignee_id INTEGER, status TEXT NOT NULL DEFAULT 'todo', deadline INTEGER, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, deleted_at INTEGER)",
          );
          raw.execute(
            "INSERT INTO projects (name, created_at) VALUES ('Legacy', 1)",
          );
          raw.execute(
            "INSERT INTO tasks (title, project_id, created_at, updated_at) VALUES ('Old task', 1, 1, 1)",
          );
          raw.execute('PRAGMA user_version = 1');
        },
      ),
    );
    final saved = await migrated.select(migrated.tasks).getSingle();
    expect(saved.title, 'Old task');
    expect(saved.priority, 'medium');
    await migrated.close();
  });
}
