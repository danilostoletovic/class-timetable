import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:class_timetable/main.dart';
import 'package:class_timetable/utils/file_saver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ScheduleItem Model Tests', () {
    test('toJson and fromJson serialize and deserialize correctly', () {
      final item = ScheduleItem(
        title: 'Physics',
        time: '10:00 AM - 11:30 AM',
        room: 'Lab 3',
        color: const Color(0xFF4CAF50),
        note: 'Lab experiment',
      );

      final jsonMap = item.toJson();
      expect(jsonMap['title'], 'Physics');
      expect(jsonMap['time'], '10:00 AM - 11:30 AM');
      expect(jsonMap['room'], 'Lab 3');
      expect(jsonMap['note'], 'Lab experiment');

      final reconstructed = ScheduleItem.fromJson(jsonMap);
      expect(reconstructed.title, item.title);
      expect(reconstructed.time, item.time);
      expect(reconstructed.room, item.room);
      expect(reconstructed.color.toARGB32(), item.color.toARGB32());
      expect(reconstructed.note, item.note);
    });

    test('isCurrentClass returns false for different day', () {
      final item = ScheduleItem(
        title: 'Chemistry',
        time: '08:00 AM - 09:30 AM',
        room: 'Room 202',
        color: Colors.red,
      );

      final differentDate = DateTime(2020, 1, 1);
      expect(item.isCurrentClass(differentDate), isFalse);
    });

    test('isCurrentClass handles invalid time strings gracefully without throwing', () {
      final item = ScheduleItem(
        title: 'Art',
        time: 'invalid-time-format',
        room: 'Studio A',
        color: Colors.orange,
      );

      expect(item.isCurrentClass(DateTime.now()), isFalse);
    });
  });

  group('File Saver Model Tests', () {
    test('SaveFileResult properties and defaults', () {
      const successResult = SaveFileResult(
        success: true,
        message: 'Downloaded schedule.json',
      );
      expect(successResult.success, isTrue);
      expect(successResult.message, 'Downloaded schedule.json');
      expect(successResult.cancelled, isFalse);

      const cancelledResult = SaveFileResult(
        success: false,
        message: 'Save cancelled.',
        cancelled: true,
      );
      expect(cancelledResult.success, isFalse);
      expect(cancelledResult.cancelled, isTrue);
    });
  });

  group('TimetableApp Widget Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('renders main timetable app bar, days, and default classes',
        (WidgetTester tester) async {
      await tester.pumpWidget(const TimetableApp());
      await tester.pumpAndSettle();

      // Verify AppBar title in English
      expect(find.text('Class Timetable'), findsOneWidget);

      // Verify Day segments exist
      expect(find.text('Mon'), findsWidgets);
      expect(find.text('Tue'), findsWidgets);
      expect(find.text('Wed'), findsWidgets);
      expect(find.text('Thu'), findsWidgets);
      expect(find.text('Fri'), findsWidgets);

      // Verify Add Entry button is present
      expect(find.text('Add Entry'), findsOneWidget);
    });

    testWidgets('opens Add Entry dialog when floating action button is tapped',
        (WidgetTester tester) async {
      await tester.pumpWidget(const TimetableApp());
      await tester.pumpAndSettle();

      final addEntryButton = find.text('Add Entry');
      expect(addEntryButton, findsOneWidget);

      await tester.tap(addEntryButton);
      await tester.pumpAndSettle();

      // Dialog should be visible
      expect(find.textContaining('Add Entry'), findsWidgets);
      expect(find.text('Subject / Title'), findsOneWidget);
      expect(find.text('Room / Location'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Tap Cancel to close dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Subject / Title'), findsNothing);
    });

    testWidgets('opens Rotation Schedule Settings dialog when icon is tapped',
        (WidgetTester tester) async {
      await tester.pumpWidget(const TimetableApp());
      await tester.pumpAndSettle();

      final rotationIcon = find.byIcon(Icons.autorenew);
      expect(rotationIcon, findsOneWidget);

      await tester.tap(rotationIcon);
      await tester.pumpAndSettle();

      expect(find.text('Rotation Schedule Settings'), findsOneWidget);
      expect(find.text('Number of rotating weeks (N):'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Rotation Schedule Settings'), findsNothing);
    });

    testWidgets('opens Backup & Restore modal and displays Copy, Paste, Save, Restore, and Apply',
        (WidgetTester tester) async {
      await tester.pumpWidget(const TimetableApp());
      await tester.pumpAndSettle();

      final syncIcon = find.byIcon(Icons.sync_alt);
      expect(syncIcon, findsOneWidget);

      await tester.tap(syncIcon);
      await tester.pumpAndSettle();

      // Modal bottom sheet should be visible
      expect(find.text('Backup & Restore Schedule'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Paste'), findsOneWidget);
      expect(find.text('Save to File'), findsOneWidget);
      expect(find.text('Restore from File'), findsOneWidget);
      expect(find.text('Apply JSON'), findsOneWidget);

      // Close modal
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('Backup & Restore Schedule'), findsNothing);
    });
  });
}
