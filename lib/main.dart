import 'package:flutter/material.dart';

import 'data/database.dart';
import 'data/repository.dart';

void main() =>
    runApp(TaskFlowApp(repository: TaskFlowRepository(AppDatabase())));

class TaskFlowApp extends StatelessWidget {
  const TaskFlowApp({super.key, required this.repository});
  final TaskFlowRepository repository;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TaskFlow',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff4c62d8)),
      useMaterial3: true,
    ),
    home: HomePage(repository: repository),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.repository});
  final TaskFlowRepository repository;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardPage(repo: widget.repository),
      ProjectsPage(repo: widget.repository),
      TasksPage(repo: widget.repository),
      PeoplePage(repo: widget.repository),
      TasksPage(repo: widget.repository, trash: true),
    ];
    final titles = ['Обзор', 'Проекты', 'Задачи', 'Участники', 'Корзина'];
    return Scaffold(
      appBar: AppBar(title: Text(titles[index]), centerTitle: false),
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (v) => setState(() => index = v),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Обзор',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Проекты',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_outlined),
            selectedIcon: Icon(Icons.checklist),
            label: 'Задачи',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Люди',
          ),
          NavigationDestination(
            icon: Icon(Icons.delete_outline),
            selectedIcon: Icon(Icons.delete),
            label: 'Корзина',
          ),
        ],
      ),
    );
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.repo});
  final TaskFlowRepository repo;
  @override
  Widget build(BuildContext context) => StreamBuilder<Map<String, int>>(
    stream: repo.watchStatistics(),
    builder: (context, snap) {
      if (!snap.hasData)
        return const Center(child: CircularProgressIndicator());
      final values = snap.data!;
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Рабочее пространство',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          const Text('Сводка по проектам и задачам'),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _StatCard(
                'Проекты',
                values['projects']!,
                Icons.folder,
                Colors.indigo,
              ),
              _StatCard(
                'Все задачи',
                values['tasks']!,
                Icons.checklist,
                Colors.blue,
              ),
              _StatCard(
                'Завершено',
                values['done']!,
                Icons.task_alt,
                Colors.green,
              ),
              _StatCard(
                'В работе',
                values['open']!,
                Icons.pending_actions,
                Colors.orange,
              ),
              _StatCard(
                'Просрочено',
                values['overdue']!,
                Icons.event_busy,
                Colors.red,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await repo.seedPerformanceData();
                    if (context.mounted)
                      _message(
                        context,
                        'Добавлены 1 000 пользователей, 100 проектов и 10 000 задач',
                      );
                  } catch (e) {
                    if (context.mounted) _message(context, e.toString());
                  }
                },
                icon: const Icon(Icons.storage),
                label: const Text('Создать тестовый набор'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    final result = await repo.compareIndexPerformance();
                    if (context.mounted)
                      _message(
                        context,
                        'С индексом: ${result['indexedMicroseconds']} мкс · без индекса: ${result['withoutIndexMicroseconds']} мкс',
                      );
                  } catch (e) {
                    if (context.mounted) _message(context, e.toString());
                  }
                },
                icon: const Icon(Icons.speed),
                label: const Text('Сравнить запросы'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Задачи по приоритету',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          StreamBuilder<List<Map<String, Object>>>(
            stream: repo.watchPriorityCounts(),
            builder: (c, s) => Wrap(
              spacing: 10,
              children: (s.data ?? [])
                  .map((r) => Chip(label: Text('${r['name']}: ${r['count']}')))
                  .toList(),
            ),
          ),
          Text(
            'Задачи по исполнителям',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          StreamBuilder<List<Map<String, Object>>>(
            stream: repo.watchAssigneeCounts(),
            builder: (c, s) => Column(
              children: (s.data ?? [])
                  .take(5)
                  .map(
                    (r) => ListTile(
                      dense: true,
                      title: Text('${r['name']}'),
                      trailing: Text('${r['count']}'),
                    ),
                  )
                  .toList(),
            ),
          ),
          Text(
            'Готовность проектов',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          StreamBuilder<List<Map<String, Object>>>(
            stream: repo.watchProjectProgress(),
            builder: (c, s) => Column(
              children: (s.data ?? [])
                  .map(
                    (r) => ListTile(
                      dense: true,
                      title: Text('${r['name']}'),
                      subtitle: LinearProgressIndicator(
                        value: (r['count'] as int) / 100,
                      ),
                      trailing: Text('${r['count']}%'),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Последние задачи',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          StreamBuilder<List<Task>>(
            stream: repo.watchTasks(),
            builder: (context, ts) => Column(
              children: (ts.data ?? [])
                  .take(5)
                  .map(
                    (t) => ListTile(
                      leading: const Icon(Icons.circle_outlined),
                      title: Text(t.title),
                      subtitle: Text('${t.status} · ${t.priority}'),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      );
    },
  );
}

class _StatCard extends StatelessWidget {
  const _StatCard(this.label, this.count, this.icon, this.color);
  final String label;
  final int count;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 165,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 10),
            Text('$count', style: Theme.of(context).textTheme.headlineMedium),
            Text(label),
          ],
        ),
      ),
    ),
  );
}

class ProjectsPage extends StatelessWidget {
  const ProjectsPage({super.key, required this.repo});
  final TaskFlowRepository repo;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: StreamBuilder<List<Project>>(
      stream: repo.watchProjects(),
      builder: (context, snap) {
        final items = snap.data ?? [];
        if (items.isEmpty) return const _Empty(label: 'Проектов пока нет');
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final p = items[i];
            return Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.folder)),
                title: Text(p.name),
                subtitle: Text(
                  p.description.isEmpty ? p.status : p.description,
                ),
                onTap: () => _editProject(context, repo, p),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) async {
                    if (v == 'member') await _addMember(context, repo, p.id);
                    if (v == 'removeMember')
                      await _removeMember(context, repo, p.id);
                    if (v.startsWith('project:'))
                      await repo.setProjectStatus(p.id, v.substring(8));
                    if (v == 'delete')
                      await _confirm(
                        context,
                        'Удалить проект и его задачи?',
                        () => repo.deleteProject(p.id),
                      );
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'member',
                      child: Text('Добавить участника'),
                    ),
                    PopupMenuItem(
                      value: 'removeMember',
                      child: Text('Удалить участника'),
                    ),
                    PopupMenuItem(
                      value: 'project:active',
                      child: Text('Статус: активный'),
                    ),
                    PopupMenuItem(
                      value: 'project:completed',
                      child: Text('Статус: завершённый'),
                    ),
                    PopupMenuItem(
                      value: 'project:archived',
                      child: Text('Статус: архивный'),
                    ),
                    PopupMenuItem(value: 'delete', child: Text('Удалить')),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _createProject(context, repo),
      icon: const Icon(Icons.add),
      label: const Text('Проект'),
    ),
  );
}

class PeoplePage extends StatelessWidget {
  const PeoplePage({super.key, required this.repo});
  final TaskFlowRepository repo;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: StreamBuilder<List<User>>(
      stream: repo.watchUsers(),
      builder: (context, snap) {
        final items = snap.data ?? [];
        if (items.isEmpty) return const _Empty(label: 'Участников пока нет');
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          itemBuilder: (_, i) {
            final u = items[i];
            return Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(u.name),
                subtitle: Text(u.email),
                onTap: () => _editUser(context, repo, u),
                trailing: IconButton(
                  tooltip: 'Удалить',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirm(
                    context,
                    'Удалить пользователя?',
                    () => repo.deleteUser(u.id),
                  ),
                ),
              ),
            );
          },
        );
      },
    ),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => _createUser(context, repo),
      icon: const Icon(Icons.person_add),
      label: const Text('Участник'),
    ),
  );
}

class TasksPage extends StatefulWidget {
  const TasksPage({super.key, this.trash = false, required this.repo});
  final TaskFlowRepository repo;
  final bool trash;
  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  final search = TextEditingController();
  String? status;
  String? priority;
  int? assigneeId;
  String sortBy = 'created';
  int pageLimit = 30;
  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        if (!widget.trash)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              children: [
                TextField(
                  controller: search,
                  onChanged: (_) => setState(() => pageLimit = 30),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Поиск задач',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  children: [
                    DropdownButton<String?>(
                      value: status,
                      hint: const Text('Статус'),
                      items: [
                        DropdownMenuItem(value: null, child: Text('Все')),
                        ...['todo', 'inProgress', 'done', 'cancelled'].map(
                          (s) => DropdownMenuItem(value: s, child: Text(s)),
                        ),
                      ],
                      onChanged: (v) => setState(() {
                        status = v;
                        pageLimit = 30;
                      }),
                    ),
                    DropdownButton<String?>(
                      value: priority,
                      hint: const Text('Приоритет'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('Все')),
                        ...['low', 'medium', 'high', 'critical'].map(
                          (v) => DropdownMenuItem(value: v, child: Text(v)),
                        ),
                      ],
                      onChanged: (v) => setState(() {
                        priority = v;
                        pageLimit = 30;
                      }),
                    ),
                    DropdownButton<String>(
                      value: sortBy,
                      items: const [
                        DropdownMenuItem(
                          value: 'created',
                          child: Text('Сначала новые'),
                        ),
                        DropdownMenuItem(
                          value: 'deadline',
                          child: Text('По дедлайну'),
                        ),
                      ],
                      onChanged: (v) => setState(() {
                        sortBy = v!;
                        pageLimit = 30;
                      }),
                    ),
                    StreamBuilder<List<User>>(
                      stream: widget.repo.watchUsers(),
                      builder: (context, snapshot) {
                        final users = snapshot.data ?? [];
                        return DropdownButton<int?>(
                          value: assigneeId,
                          hint: const Text('Исполнитель'),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('Все исполнители'),
                            ),
                            ...users.map(
                              (u) => DropdownMenuItem<int?>(
                                value: u.id,
                                child: Text(u.name),
                              ),
                            ),
                          ],
                          onChanged: (v) => setState(() {
                            assigneeId = v;
                            pageLimit = 30;
                          }),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        Expanded(
          child: StreamBuilder<List<Task>>(
            stream: widget.repo.watchTasks(
              search: search.text,
              status: status,
              priority: priority,
              assigneeId: assigneeId,
              trash: widget.trash,
              limit: pageLimit,
              sortBy: sortBy,
            ),
            builder: (context, snap) {
              final items = snap.data ?? [];
              if (items.isEmpty)
                return _Empty(
                  label: widget.trash ? 'Корзина пуста' : 'Задач не найдено',
                );
              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: items.length + (items.length == pageLimit ? 1 : 0),
                itemBuilder: (_, i) {
                  if (i == items.length)
                    return Center(
                      child: TextButton(
                        onPressed: () => setState(() => pageLimit += 30),
                        child: const Text('Показать ещё'),
                      ),
                    );
                  final t = items[i];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(child: Icon(_statusIcon(t.status))),
                      title: Text(t.title),
                      subtitle: Text(
                        '${t.status} · ${t.priority}${t.deadline == null ? '' : ' · ${_date(t.deadline!)}'}',
                      ),
                      onTap: () => _taskDetails(context, widget.repo, t),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          try {
                            if (widget.trash) {
                              if (v == 'restore')
                                await widget.repo.restoreTask(t.id);
                              if (v == 'purge')
                                await _confirm(
                                  context,
                                  'Удалить задачу навсегда?',
                                  () => widget.repo.purgeTask(t.id),
                                );
                            } else {
                              if (v == 'delete')
                                await widget.repo.removeTask(t.id);
                              if (v == 'undo')
                                await widget.repo.undoStatus(t.id);
                              if (v == 'assign')
                                await _assignTask(context, widget.repo, t);
                              if (v.startsWith('status:'))
                                await widget.repo.changeStatus(
                                  t.id,
                                  v.substring(7),
                                );
                            }
                          } catch (e) {
                            if (context.mounted)
                              _message(context, e.toString());
                          }
                        },
                        itemBuilder: (_) => widget.trash
                            ? const [
                                PopupMenuItem(
                                  value: 'restore',
                                  child: Text('Восстановить'),
                                ),
                                PopupMenuItem(
                                  value: 'purge',
                                  child: Text('Удалить навсегда'),
                                ),
                              ]
                            : const [
                                PopupMenuItem(
                                  value: 'status:todo',
                                  child: Text('Статус: todo'),
                                ),
                                PopupMenuItem(
                                  value: 'status:inProgress',
                                  child: Text('Статус: inProgress'),
                                ),
                                PopupMenuItem(
                                  value: 'status:done',
                                  child: Text('Статус: done'),
                                ),
                                PopupMenuItem(
                                  value: 'status:cancelled',
                                  child: Text('Статус: cancelled'),
                                ),
                                PopupMenuItem(
                                  value: 'undo',
                                  child: Text('Отменить статус'),
                                ),
                                PopupMenuItem(
                                  value: 'assign',
                                  child: Text('Назначить исполнителя'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('В корзину'),
                                ),
                              ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    ),
    floatingActionButton: widget.trash
        ? null
        : FloatingActionButton.extended(
            onPressed: () => _createTask(context, widget.repo),
            icon: const Icon(Icons.add),
            label: const Text('Задача'),
          ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.inbox_outlined, size: 54, color: Colors.grey),
        const SizedBox(height: 10),
        Text(label),
      ],
    ),
  );
}

Future<void> _createUser(BuildContext context, TaskFlowRepository repo) async {
  final name = TextEditingController(), email = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Новый участник'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Имя'),
          ),
          TextField(
            controller: email,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
  if (ok == true)
    try {
      await repo.addUser(name.text, email.text);
    } catch (e) {
      if (context.mounted) _message(context, e.toString());
    }
}

Future<void> _createProject(
  BuildContext context,
  TaskFlowRepository repo,
) async {
  final name = TextEditingController(), desc = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Новый проект'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Название'),
          ),
          TextField(
            controller: desc,
            decoration: const InputDecoration(labelText: 'Описание'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
  if (ok == true)
    try {
      await repo.addProject(name.text, desc.text);
    } catch (e) {
      if (context.mounted) _message(context, e.toString());
    }
}

Future<void> _editUser(
  BuildContext context,
  TaskFlowRepository repo,
  User user,
) async {
  final name = TextEditingController(text: user.name);
  final email = TextEditingController(text: user.email);
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Изменить участника'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Имя'),
          ),
          TextField(
            controller: email,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
  if (ok == true)
    try {
      await repo.updateUser(user.id, name.text, email.text);
    } catch (e) {
      if (context.mounted) _message(context, e.toString());
    }
}

Future<void> _editProject(
  BuildContext context,
  TaskFlowRepository repo,
  Project project,
) async {
  final name = TextEditingController(text: project.name);
  final description = TextEditingController(text: project.description);
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Изменить проект'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Название'),
          ),
          TextField(
            controller: description,
            decoration: const InputDecoration(labelText: 'Описание'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Сохранить'),
        ),
      ],
    ),
  );
  if (ok == true)
    try {
      await repo.updateProject(project.id, name.text, description.text);
    } catch (e) {
      if (context.mounted) _message(context, e.toString());
    }
}

Future<void> _removeMember(
  BuildContext context,
  TaskFlowRepository repo,
  int projectId,
) async {
  final members = await repo.projectMembers(projectId);
  if (members.isEmpty) {
    if (context.mounted) _message(context, 'В проекте нет участников');
    return;
  }
  final users = await repo.watchUsers().first;
  int selected = members.first.userId;
  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('Удалить участника из проекта'),
        content: DropdownButton<int>(
          value: selected,
          isExpanded: true,
          items: members
              .map(
                (m) => DropdownMenuItem(
                  value: m.userId,
                  child: Text(
                    users.where((u) => u.id == m.userId).firstOrNull?.name ??
                        'Участник #${m.userId}',
                  ),
                ),
              )
              .toList(),
          onChanged: (v) => set(() => selected = v!),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    ),
  );
  if (ok == true)
    try {
      await repo.removeProjectMember(projectId, selected);
    } catch (e) {
      if (context.mounted) _message(context, e.toString());
    }
}

Future<void> _addMember(
  BuildContext context,
  TaskFlowRepository repo,
  int projectId,
) async {
  final users = await repo.users();
  if (users.isEmpty) {
    _message(context, 'Сначала добавьте участника');
    return;
  }
  int selected = users.first.id;
  String role = 'Member';
  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('Добавить участника'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButton<int>(
              value: selected,
              isExpanded: true,
              items: users
                  .map(
                    (u) => DropdownMenuItem(value: u.id, child: Text(u.name)),
                  )
                  .toList(),
              onChanged: (v) => set(() => selected = v!),
            ),
            DropdownButton<String>(
              value: role,
              isExpanded: true,
              items: const [
                'Owner',
                'Admin',
                'Member',
              ].map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
              onChanged: (v) => set(() => role = v!),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Добавить'),
          ),
        ],
      ),
    ),
  );
  if (ok == true)
    try {
      await repo.addProjectMember(projectId, selected, role);
    } catch (e) {
      if (context.mounted) _message(context, e.toString());
    }
}

Future<void> _createTask(BuildContext context, TaskFlowRepository repo) async {
  final projects = await repo.watchProjects().first;
  if (projects.isEmpty) {
    _message(context, 'Сначала создайте проект');
    return;
  }
  final title = TextEditingController(), desc = TextEditingController();
  int project = projects.first.id;
  int? assignee;
  String priority = 'medium';
  DateTime? deadline;
  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('Новая задача'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Название'),
              ),
              TextField(
                controller: desc,
                decoration: const InputDecoration(labelText: 'Описание'),
              ),
              DropdownButton<int>(
                value: project,
                isExpanded: true,
                items: projects
                    .map(
                      (p) => DropdownMenuItem(value: p.id, child: Text(p.name)),
                    )
                    .toList(),
                onChanged: (v) => set(() {
                  project = v!;
                  assignee = null;
                }),
              ),
              FutureBuilder<List<ProjectMember>>(
                future: repo.projectMembers(project),
                builder: (c, s) {
                  final members = s.data ?? [];
                  return DropdownButton<int?>(
                    value: assignee,
                    hint: const Text('Без исполнителя'),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Без исполнителя'),
                      ),
                      ...members.map(
                        (m) => DropdownMenuItem(
                          value: m.userId,
                          child: Text('Участник #${m.userId}'),
                        ),
                      ),
                    ],
                    onChanged: (v) => set(() => assignee = v),
                  );
                },
              ),
              DropdownButton<String>(
                value: priority,
                isExpanded: true,
                items: const ['low', 'medium', 'high', 'critical']
                    .map(
                      (v) => DropdownMenuItem(
                        value: v,
                        child: Text('Приоритет: $v'),
                      ),
                    )
                    .toList(),
                onChanged: (v) => set(() => priority = v!),
              ),
              TextButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: c,
                    initialDate: deadline ?? DateTime.now(),
                    firstDate: DateTime.now().subtract(
                      const Duration(days: 3650),
                    ),
                    lastDate: DateTime.now().add(const Duration(days: 3650)),
                  );
                  if (picked != null) set(() => deadline = picked);
                },
                icon: const Icon(Icons.calendar_month),
                label: Text(
                  deadline == null
                      ? 'Указать дедлайн'
                      : 'Дедлайн: ${_date(deadline!)}',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Создать'),
          ),
        ],
      ),
    ),
  );
  if (ok == true)
    try {
      await repo.addTask(
        title: title.text,
        description: desc.text,
        projectId: project,
        assigneeId: assignee,
        priority: priority,
        deadline: deadline,
      );
    } catch (e) {
      if (context.mounted) _message(context, e.toString());
    }
}

Future<void> _assignTask(
  BuildContext context,
  TaskFlowRepository repo,
  Task task,
) async {
  final members = await repo.projectMembers(task.projectId);
  if (members.isEmpty) {
    if (context.mounted)
      _message(context, 'Сначала добавьте участника в проект');
    return;
  }
  int selected = task.assigneeId ?? members.first.userId;
  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('Назначить исполнителя'),
        content: DropdownButton<int>(
          value: selected,
          isExpanded: true,
          items: members
              .map(
                (m) => DropdownMenuItem(
                  value: m.userId,
                  child: Text('Участник #${m.userId}'),
                ),
              )
              .toList(),
          onChanged: (v) => set(() => selected = v!),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Назначить'),
          ),
        ],
      ),
    ),
  );
  if (ok == true)
    try {
      await repo.assignTask(task.id, selected);
    } catch (e) {
      if (context.mounted) _message(context, e.toString());
    }
}

Future<void> _taskDetails(
  BuildContext context,
  TaskFlowRepository repo,
  Task task,
) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(task.title),
      content: SizedBox(
        width: 420,
        child: DefaultTabController(
          length: 3,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TabBar(
                tabs: const [
                  Tab(text: 'История'),
                  Tab(text: 'Комментарии'),
                  Tab(text: 'Файлы'),
                ],
              ),
              SizedBox(
                height: 320,
                child: TabBarView(
                  children: [
                    StreamBuilder<List<TaskHistoryData>>(
                      stream: repo.watchHistory(task.id),
                      builder: (c, s) => ListView(
                        children: (s.data ?? [])
                            .map(
                              (h) => ListTile(
                                dense: true,
                                title: Text(
                                  '${h.event}: ${h.previousStatus ?? '—'} → ${h.newStatus}',
                                ),
                                subtitle: Text(
                                  '${_date(h.changedAt)} · пользователь #${h.changedBy ?? '—'}',
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    _CommentsPanel(repo: repo, task: task),
                    _AttachmentsPanel(repo: repo, task: task),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(c);
            _editTask(context, repo, task);
          },
          child: const Text('Изменить задачу'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Закрыть'),
        ),
      ],
    ),
  );
}

Future<void> _editTask(
  BuildContext context,
  TaskFlowRepository repo,
  Task task,
) async {
  final title = TextEditingController(text: task.title);
  final description = TextEditingController(text: task.description);
  String priority = task.priority;
  DateTime? deadline = task.deadline;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => AlertDialog(
        title: const Text('Изменить задачу'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Название'),
            ),
            TextField(
              controller: description,
              decoration: const InputDecoration(labelText: 'Описание'),
            ),
            DropdownButton<String>(
              value: priority,
              isExpanded: true,
              items: const ['low', 'medium', 'high', 'critical']
                  .map(
                    (p) => DropdownMenuItem(
                      value: p,
                      child: Text('Приоритет: $p'),
                    ),
                  )
                  .toList(),
              onChanged: (v) => set(() => priority = v!),
            ),
            TextButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(
                  context: c,
                  initialDate: deadline ?? DateTime.now(),
                  firstDate: DateTime.now().subtract(
                    const Duration(days: 3650),
                  ),
                  lastDate: DateTime.now().add(const Duration(days: 3650)),
                );
                if (picked != null) set(() => deadline = picked);
              },
              icon: const Icon(Icons.calendar_month),
              label: Text(
                deadline == null ? 'Указать дедлайн' : _date(deadline!),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    ),
  );
  if (ok == true)
    try {
      await repo.updateTask(
        id: task.id,
        title: title.text,
        description: description.text,
        priority: priority,
        deadline: deadline,
        assigneeId: task.assigneeId,
      );
    } catch (e) {
      if (context.mounted) _message(context, e.toString());
    }
}

class _AttachmentsPanel extends StatelessWidget {
  const _AttachmentsPanel({required this.repo, required this.task});
  final TaskFlowRepository repo;
  final Task task;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: StreamBuilder<List<Attachment>>(
          stream: repo.watchAttachments(task.id),
          builder: (c, s) => ListView(
            children: (s.data ?? [])
                .map(
                  (a) => ListTile(
                    leading: const Icon(Icons.attach_file),
                    title: Text(a.fileName),
                    subtitle: Text(a.localPath),
                  ),
                )
                .toList(),
          ),
        ),
      ),
      TextButton.icon(
        onPressed: () async {
          final path = TextEditingController();
          final ok = await showDialog<bool>(
            context: context,
            builder: (d) => AlertDialog(
              title: const Text('Добавить вложение'),
              content: TextField(
                controller: path,
                decoration: const InputDecoration(
                  labelText: 'Локальный путь к файлу',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(d),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(d, true),
                  child: const Text('Сохранить'),
                ),
              ],
            ),
          );
          if (ok == true && path.text.trim().isNotEmpty)
            await repo.addAttachment(task.id, path.text.trim());
        },
        icon: const Icon(Icons.attach_file),
        label: const Text('Добавить путь к файлу'),
      ),
    ],
  );
}

class _CommentsPanel extends StatelessWidget {
  const _CommentsPanel({required this.repo, required this.task});
  final TaskFlowRepository repo;
  final Task task;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: StreamBuilder<List<Comment>>(
          stream: repo.watchComments(task.id),
          builder: (c, s) => ListView(
            children: (s.data ?? [])
                .map(
                  (m) => ListTile(
                    dense: true,
                    title: Text(m.body),
                    subtitle: Text(
                      'Автор #${m.authorId} · ${_date(m.createdAt)}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        try {
                          await repo.deleteComment(
                            m.id,
                            (await repo.currentUserId()) ?? -1,
                          );
                        } catch (e) {
                          if (context.mounted) _message(context, e.toString());
                        }
                      },
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
      TextButton.icon(
        onPressed: () async {
          final users = await repo.watchUsers().first;
          if (users.isEmpty) {
            if (context.mounted)
              _message(context, 'Сначала добавьте участника');
            return;
          }
          final body = TextEditingController();
          if (!context.mounted) return;
          final ok = await showDialog<bool>(
            context: context,
            builder: (d) => AlertDialog(
              title: const Text('Комментарий'),
              content: TextField(
                controller: body,
                decoration: const InputDecoration(labelText: 'Текст'),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(d),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(d, true),
                  child: const Text('Добавить'),
                ),
              ],
            ),
          );
          if (ok == true)
            await repo.addComment(task.id, users.first.id, body.text);
        },
        icon: const Icon(Icons.add_comment),
        label: const Text('Добавить комментарий'),
      ),
    ],
  );
}

Future<void> _confirm(
  BuildContext context,
  String title,
  Future<void> Function() action,
) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Подтвердить'),
        ),
      ],
    ),
  );
  if (yes == true)
    try {
      await action();
    } catch (e) {
      if (context.mounted) _message(context, e.toString());
    }
}

void _message(BuildContext c, String text) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(text)));
String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
IconData _statusIcon(String s) => switch (s) {
  'done' => Icons.task_alt,
  'inProgress' => Icons.pending_actions,
  'cancelled' => Icons.cancel_outlined,
  _ => Icons.circle_outlined,
};
