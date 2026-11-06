import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskflow/data/database.dart';
import 'package:taskflow/data/repository.dart';
import 'package:taskflow/main.dart';

void main() {
  testWidgets('opens the TaskFlow overview', (tester) async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    await tester.pumpWidget(
      TaskFlowApp(repository: TaskFlowRepository(database)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(HomePage), findsOneWidget);
    await database.close();
  });
}
