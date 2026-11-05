import 'dart:convert';
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

    test(
        'isCurrentClass handles invalid time strings gracefully without throwing',
        () {
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

    Future<void> loadClasses(WidgetTester tester) async {
      final now = DateTime.now();
      final items = ['Physics', 'Chemistry', 'Art']
          .map((title) => ScheduleItem(
                title: title,
                time: '09:00 AM - 10:00 AM',
                room: 'Room 1',
                color: Colors.blue,
              ).toJson())
          .toList();
      SharedPreferences.setMockInitialValues({
        'saved_timetable_config': jsonEncode({
          'weeksCount': 1,
          'startDate': now.toIso8601String(),
        }),
        'saved_timetable_data_v2': jsonEncode({
          '0': {
            for (final day in ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
              day: items
          },
        }),
      });
      await tester.pumpWidget(const TimetableApp());
      await tester.pumpAndSettle();
    }

    testWidgets('selects multiple classes, deletes, and restores their order',
        (tester) async {
      await loadClasses(tester);
      expect(find.byType(Dismissible), findsNothing);
      await tester.drag(find.text('Physics'), const Offset(-250, 0));
      await tester.pumpAndSettle();
      expect(find.text('Physics'), findsOneWidget);
      await tester.tap(find.byTooltip('Settings menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select classes'));
      await tester.pumpAndSettle();
      final physics = find.descendant(
        of: find.widgetWithText(ListTile, 'Physics'),
        matching: find.byType(Checkbox),
      );
      final chemistry = find.descendant(
        of: find.widgetWithText(ListTile, 'Chemistry'),
        matching: find.byType(Checkbox),
      );
      await tester.tap(physics);
      await tester.ensureVisible(chemistry);
      await tester.pumpAndSettle();
      await tester.tap(chemistry);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete (2)'));
      await tester.pumpAndSettle();
      expect(find.text('Physics'), findsNothing);
      expect(find.text('Chemistry'), findsNothing);
      expect(find.text('Art'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Physics'), findsOneWidget);
      expect(find.text('Chemistry'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString('saved_timetable_data_v2')!);
      final dayItems = (saved['0'] as Map).values.first as List;
      expect(dayItems.map((item) => item['title']),
          ['Physics', 'Chemistry', 'Art']);
    });

    testWidgets('undo expires after three seconds', (tester) async {
      await loadClasses(tester);
      await tester.longPress(find.text('Physics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete (1)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final snackbar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackbar.duration, const Duration(seconds: 3));
      expect(snackbar.persist, isFalse);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Undo'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsNothing);
      expect(find.text('Physics'), findsNothing);
    });

    testWidgets('renders main timetable app bar, days, and default classes',
        (WidgetTester tester) async {
      await tester.pumpWidget(const TimetableApp());
      await tester.pumpAndSettle();

      // Verify AppBar title in English
      expect(find.text('Class Timetable'), findsNothing);
      expect(find.text('Class timetable'), findsOneWidget);

      // Verify Day segments exist
      expect(find.text('Mon'), findsWidgets);
      expect(find.text('Tue'), findsWidgets);
      expect(find.text('Wed'), findsWidgets);
      expect(find.text('Thu'), findsWidgets);
      expect(find.text('Fri'), findsWidgets);

      // Verify Add Entry button is present
      expect(find.text('Add class'), findsOneWidget);
    });

    testWidgets('opens a simple add-class sheet and cancels without saving',
        (WidgetTester tester) async {
      await tester.pumpWidget(const TimetableApp());
      await tester.pumpAndSettle();

      final addEntryButton = find.text('Add class');
      expect(addEntryButton, findsOneWidget);

      await tester.tap(addEntryButton);
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Class name'), findsOneWidget);
      expect(find.text('Room (optional)'), findsOneWidget);
      expect(find.text('Starts'), findsOneWidget);
      expect(find.text('Ends'), findsOneWidget);
      expect(find.text('Notes / Homework'), findsNothing);

      // Tap Cancel to close dialog
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Class name'), findsNothing);
    });

    testWidgets('validates the name and saves a class on the chosen day',
        (tester) async {
      await loadClasses(tester);
      await tester.tap(find.text('Add class'));
      await tester.pumpAndSettle();
      final add = find.widgetWithText(FilledButton, 'Add class');
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.text('Enter a class name.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, '  Biology  ');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Tue'));
      await tester.tap(add);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Biology'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString('saved_timetable_data_v2')!);
      expect(saved['0']['Tue'].last['title'], 'Biology');
      expect(saved['0']['Tue'].last['room'], 'TBA');
      expect(saved['0']['Tue'].last['time'], '10:00 AM - 11:00 AM');
    });

    testWidgets('expands optional details and handles a visible keyboard',
        (tester) async {
      await loadClasses(tester);
      await tester.tap(find.text('Add class'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Notes & color'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notes & color'));
      await tester.pumpAndSettle();
      expect(find.text('Notes / Homework'), findsOneWidget);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(FilledButton, 'Add class'), findsOneWidget);
    });

    testWidgets('reuses a class on another day without changing the original',
        (tester) async {
      await loadClasses(tester);
      await tester.tap(find.text('Add class'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<ScheduleItem>));
      await tester.pumpAndSettle();
      // Repeated occurrences across days appear only once in the picker.
      expect(find.text('Physics · Room 1'), findsOneWidget);
      await tester.tap(find.text('Physics · Room 1'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<TextFormField>(find.byType(TextFormField).first)
              .controller!
              .text,
          'Physics');
      final day = find.widgetWithText(ChoiceChip, 'Fri');
      await tester.ensureVisible(day);
      await tester.tap(day);
      await tester.tap(find.widgetWithText(FilledButton, 'Add class'));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString('saved_timetable_data_v2')!);
      expect(saved['0']['Fri'].length, 4);
      expect(saved['0']['Fri'].last['title'], 'Physics');
      expect(saved['0']['Fri'].last['room'], 'Room 1');
      expect(saved['0']['Fri'].last['time'], '10:00 AM - 11:00 AM');
      expect(saved['0']['Mon'].length, 3);
      expect(saved['0']['Mon'].first['time'], '09:00 AM - 10:00 AM');
    });

    testWidgets('shows one menu button with all four actions', (tester) async {
      await loadClasses(tester);
      expect(find.text('Class Timetable'), findsNothing);
      expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
      expect(find.byIcon(Icons.autorenew), findsNothing);
      expect(find.byIcon(Icons.sync_alt), findsNothing);
      expect(find.byIcon(Icons.info_outline), findsNothing);
      await tester.tap(find.byTooltip('Settings menu'));
      await tester.pumpAndSettle();
      for (final action in [
        'Select classes',
        'Rotation Settings',
        'Backup & restore',
        'About & Copyright'
      ]) {
        expect(find.text(action), findsOneWidget);
      }
    });

    testWidgets('edits one selected class and persists the replacement',
        (tester) async {
      await loadClasses(tester);
      await tester.longPress(find.text('Physics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Edit class'), findsOneWidget);
      expect(find.text('Reuse a class'), findsNothing);
      final fields = find.byType(TextFormField);
      expect(tester.widget<TextFormField>(fields.first).controller!.text,
          'Physics');
      expect(tester.widget<TextFormField>(fields.at(1)).controller!.text,
          'Room 1');
      expect(find.text('9:00 AM'), findsOneWidget);
      await tester.enterText(fields.first, 'Advanced Physics');
      await tester.enterText(fields.at(1), 'Lab 2');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Advanced Physics'), findsOneWidget);
      expect(find.text('Physics'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString('saved_timetable_data_v2')!);
      final day = [
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun'
      ][DateTime.now().weekday - 1];
      expect(saved['0'][day].length, 3);
      expect(saved['0'][day][0]['title'], 'Advanced Physics');
      expect(saved['0'][day][0]['room'], 'Lab 2');
      expect(saved['0'][day][0]['time'], '9:00 AM - 10:00 AM');
    });

    testWidgets('cancels editing without changing the selected class',
        (tester) async {
      await loadClasses(tester);
      await tester.longPress(find.text('Physics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Unsaved');
      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Physics'), findsOneWidget);
      expect(find.text('Unsaved'), findsNothing);
      expect(find.text('1 selected'), findsOneWidget);
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      expect(find.text('Edit'), findsNothing);
    });

    testWidgets('moves an edited class to another day without duplicating it',
        (tester) async {
      await loadClasses(tester);
      final originalDay = [
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat',
        'Sun'
      ][DateTime.now().weekday - 1];
      final targetDay = originalDay == 'Tue' ? 'Wed' : 'Tue';
      await tester.longPress(find.text('Physics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, targetDay));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      final saved = jsonDecode(prefs.getString('saved_timetable_data_v2')!);
      expect(saved['0'][originalDay].length, 2);
      expect(saved['0'][targetDay].length, 4);
      expect(saved['0'][targetDay].last['title'], 'Physics');
    });

    testWidgets('opens Rotation Schedule Settings dialog when icon is tapped',
        (WidgetTester tester) async {
      await tester.pumpWidget(const TimetableApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Settings menu'));
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

    testWidgets(
        'shows backup actions and hides raw JSON until advanced options opens',
        (WidgetTester tester) async {
      await tester.pumpWidget(const TimetableApp());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Settings menu'));
      await tester.pumpAndSettle();
      final syncIcon = find.byIcon(Icons.sync_alt);
      expect(syncIcon, findsOneWidget);

      await tester.tap(syncIcon);
      await tester.pumpAndSettle();

      // Modal bottom sheet should be visible
      expect(find.text('Backup & restore'), findsOneWidget);
      expect(find.text('Copy'), findsNothing);
      expect(find.text('Paste'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Save to File'), findsOneWidget);
      expect(find.text('Restore from File'), findsOneWidget);
      expect(find.text('Apply JSON'), findsNothing);

      await tester.ensureVisible(find.text('Advanced options'));
      await tester.tap(find.text('Advanced options'));
      await tester.pumpAndSettle();
      expect(find.text('Schedule JSON'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Paste'), findsOneWidget);
      expect(find.text('Apply JSON'), findsOneWidget);

      // Close modal
      await tester.ensureVisible(find.byTooltip('Close backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close backup'));
      await tester.pumpAndSettle();

      expect(find.text('Backup & restore'), findsNothing);
    });

    testWidgets(
        'advanced restore rejects invalid text and applies a valid backup',
        (tester) async {
      await loadClasses(tester);
      final prefs = await SharedPreferences.getInstance();
      final initial = prefs.getString('saved_timetable_data_v2')!;
      await tester.tap(find.byTooltip('Settings menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Backup & restore'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Advanced options'));
      await tester.tap(find.text('Advanced options'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'invalid backup');
      await tester.ensureVisible(find.text('Apply JSON'));
      await tester.tap(find.text('Apply JSON'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(prefs.getString('saved_timetable_data_v2'), initial);
      final backup = jsonEncode({
        'weeksCount': 1,
        'timetable':
            jsonDecode(initial.replaceAll('Physics', 'Restored Physics')),
      });
      await tester.enterText(find.byType(TextField), backup);
      await tester.ensureVisible(find.text('Apply JSON'));
      await tester.tap(find.text('Apply JSON'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Restored Physics'), findsOneWidget);
      expect(prefs.getString('saved_timetable_data_v2'),
          contains('Restored Physics'));
    });
  });
}
