import 'dart:convert';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'utils/file_saver.dart';

final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('ic_launcher');
  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);

  try {
    await notificationsPlugin.initialize(initializationSettings);
  } catch (e) {
    debugPrint('Notification plugin initialization error: $e');
  }
  runApp(const TimetableApp());
}

class ScheduleItem {
  final String title;
  final String time;
  final String room;
  final Color color;
  final String note;

  ScheduleItem({
    required this.title,
    required this.time,
    required this.room,
    required this.color,
    this.note = '',
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'time': time,
        'room': room,
        'color': color.toARGB32(),
        'note': note,
      };

  factory ScheduleItem.fromJson(Map<String, dynamic> json) => ScheduleItem(
        title: json['title'] as String,
        time: json['time'] as String,
        room: json['room'] as String,
        color: Color(json['color'] as int),
        note: (json['note'] as String?) ?? '',
      );

  bool isCurrentClass(DateTime targetDate) {
    final now = DateTime.now();
    if (now.year != targetDate.year ||
        now.month != targetDate.month ||
        now.day != targetDate.day) {
      return false;
    }

    try {
      final parts = time.split(' - ');
      if (parts.length != 2) return false;

      final currentMinutes = now.hour * 60 + now.minute;

      final start = _parseTimeOfDay(parts[0]);
      final end = _parseTimeOfDay(parts[1]);

      final startMinutes = start.hour * 60 + start.minute;
      final endMinutes = end.hour * 60 + end.minute;

      return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
    } catch (_) {
      return false;
    }
  }

  static TimeOfDay _parseTimeOfDay(String timeStr) {
    final cleanStr = timeStr.trim().toUpperCase();
    final isPM = cleanStr.contains('PM');
    final isAM = cleanStr.contains('AM');
    final formatted = cleanStr.replaceAll(RegExp(r'[^\d:]'), '');
    final parts = formatted.split(':');

    int hour = int.parse(parts[0]);
    int minute = int.parse(parts[1]);

    if (isPM && hour < 12) hour += 12;
    if (isAM && hour == 12) hour = 0;

    return TimeOfDay(hour: hour, minute: minute);
  }
}

class TimetableApp extends StatelessWidget {
  const TimetableApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Class Timetable',
      debugShowCheckedModeBanner: false,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.dark.copyWith(
          statusBarColor: Colors.transparent,
        ),
        child: ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: SafeArea(
            bottom: false,
            child: child!,
          ),
        ),
      ),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3568D4),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF2F4FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: SystemUiOverlayStyle.dark,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF2F4FA),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
      home: const TimetablePage(),
    );
  }
}

class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key});

  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

class _TimetablePageState extends State<TimetablePage> {
  static const String _storageKey = 'saved_timetable_data_v2';
  static const String _configKey = 'saved_timetable_config';

  DateTime _selectedDate = DateTime.now();
  int _rotationWeeksCount = 2; // Default to 2-week rotation (e.g., Week A/B)
  int _activeWeekIndex = 0; // Current viewed rotation week index (0 to N-1)
  DateTime _startDate = DateTime.now(); // Reference start date
  bool _isLoading = true;
  bool _selecting = false;
  final Set<ScheduleItem> _selectedItems = {};
  final ScrollController _scheduleScroll = ScrollController();
  ScheduleItem? _newlyAdded;

  @override
  void dispose() {
    _scheduleScroll.dispose();
    super.dispose();
  }

  // Multi-week schedule storage: Map<WeekIndex, Map<DayAbbreviation, List<ScheduleItem>>>
  Map<int, Map<String, List<ScheduleItem>>> _multiWeekTimetable = {};

  final List<String> _daysOfWeek = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'];

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  String _getDayAbbreviation(DateTime date) {
    switch (date.weekday) {
      case DateTime.monday:
        return 'Mon';
      case DateTime.tuesday:
        return 'Tue';
      case DateTime.wednesday:
        return 'Wed';
      case DateTime.thursday:
        return 'Thu';
      case DateTime.friday:
        return 'Fri';
      case DateTime.saturday:
        return 'Sat';
      case DateTime.sunday:
        return 'Sun';
      default:
        return 'Mon';
    }
  }

  int _calculateWeekIndexForDate(DateTime date) {
    final difference = date.difference(_startDate).inDays;
    final weekDifference = (difference / 7).floor();
    final calculatedIndex = weekDifference % _rotationWeeksCount;
    return calculatedIndex < 0
        ? (calculatedIndex + _rotationWeeksCount)
        : calculatedIndex;
  }

  Future<void> _loadAllData() async {
    final prefs = await SharedPreferences.getInstance();

    final configString = prefs.getString(_configKey);
    if (configString != null) {
      final Map<String, dynamic> config = jsonDecode(configString);
      _rotationWeeksCount = (config['weeksCount'] as int?) ?? 2;
      final savedStart = config['startDate'] as String?;
      if (savedStart != null) {
        _startDate = DateTime.parse(savedStart);
      }
    } else {
      // Normalize start date to beginning of current week
      final now = DateTime.now();
      _startDate = now.subtract(Duration(days: now.weekday - 1));
    }

    final String? rawData = prefs.getString(_storageKey);

    if (rawData != null) {
      final Map<String, dynamic> decodedMap = jsonDecode(rawData);
      final Map<int, Map<String, List<ScheduleItem>>> loadedData = {};

      decodedMap.forEach((weekKey, daysMap) {
        final int wIndex = int.parse(weekKey);
        loadedData[wIndex] = {};
        (daysMap as Map<String, dynamic>).forEach((dayKey, itemsJson) {
          final List<dynamic> list = itemsJson as List<dynamic>;
          loadedData[wIndex]![dayKey] = list
              .map(
                  (item) => ScheduleItem.fromJson(item as Map<String, dynamic>))
              .toList();
        });
      });

      setState(() {
        _multiWeekTimetable = loadedData;
        _activeWeekIndex = _calculateWeekIndexForDate(_selectedDate);
        _isLoading = false;
      });
    } else {
      _initializeEmptyTimetable();
      setState(() {
        _activeWeekIndex = _calculateWeekIndexForDate(_selectedDate);
        _isLoading = false;
      });
      _saveAllData();
    }
  }

  void _initializeEmptyTimetable() {
    _multiWeekTimetable.clear();
    for (int w = 0; w < _rotationWeeksCount; w++) {
      _multiWeekTimetable[w] = {};
      for (var day in _daysOfWeek) {
        _multiWeekTimetable[w]![day] = [];
      }
    }
    // Add default sample class to Week 1 Monday
    _multiWeekTimetable[0]!['Mon']!.add(
      ScheduleItem(
        title: 'Mathematics',
        time: '09:00 AM - 10:30 AM',
        room: 'Room 101',
        color: Colors.blue.shade200,
        note: 'Bring calculator',
      ),
    );
  }

  Future<void> _saveAllData() async {
    final prefs = await SharedPreferences.getInstance();

    final config = {
      'weeksCount': _rotationWeeksCount,
      'startDate': _startDate.toIso8601String(),
    };
    await prefs.setString(_configKey, jsonEncode(config));

    final Map<String, dynamic> serializableMap = {};
    _multiWeekTimetable.forEach((weekIndex, daysMap) {
      final Map<String, dynamic> daysSerializable = {};
      daysMap.forEach((day, items) {
        daysSerializable[day] = items.map((item) => item.toJson()).toList();
      });
      serializableMap[weekIndex.toString()] = daysSerializable;
    });

    await prefs.setString(_storageKey, jsonEncode(serializableMap));
  }

  void _addScheduleItem(int weekIndex, String day, ScheduleItem item) {
    setState(() {
      _multiWeekTimetable[weekIndex] ??= {};
      _multiWeekTimetable[weekIndex]![day] ??= [];
      _multiWeekTimetable[weekIndex]![day]!.add(item);
    });
    _saveAllData();
  }

  void _deleteSelectedItems() {
    final weekIndex = _activeWeekIndex;
    final day = _getDayAbbreviation(_selectedDate);
    final items = _multiWeekTimetable[weekIndex]?[day];
    if (items == null || _selectedItems.isEmpty) return;
    final removed = <int, ScheduleItem>{};
    for (var i = 0; i < items.length; i++) {
      if (_selectedItems.contains(items[i])) removed[i] = items[i];
    }
    setState(() {
      items.removeWhere(_selectedItems.contains);
      _selectedItems.clear();
      _selecting = false;
    });
    _saveAllData();
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '${removed.length} class${removed.length == 1 ? '' : 'es'} deleted'),
        duration: const Duration(seconds: 3),
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            if (!mounted) return;
            setState(() {
              final target =
                  (_multiWeekTimetable[weekIndex] ??= {})[day] ??= [];
              for (final entry in removed.entries) {
                target.insert(entry.key.clamp(0, target.length), entry.value);
              }
            });
            _saveAllData();
          },
        ),
      ),
    );
  }

  Future<void> _showAddClassSheet({ScheduleItem? editing}) async {
    final reusable = <String, ScheduleItem>{};
    for (final week in _multiWeekTimetable.values) {
      for (final items in week.values) {
        for (final item in items) {
          final details = item.toJson()..remove('time');
          reusable.putIfAbsent(jsonEncode(details), () => item);
        }
      }
    }
    final savedClasses = reusable.values.toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final weekIndex = _activeWeekIndex;
    final date = _selectedDate;
    final day = _getDayAbbreviation(date);
    final targetDay =
        editing != null || _daysOfWeek.contains(day) ? day : 'Mon';
    final existing = _multiWeekTimetable[weekIndex]?[targetDay] ?? [];
    var start = const TimeOfDay(hour: 9, minute: 0);
    if (existing.isNotEmpty) {
      try {
        final end =
            ScheduleItem._parseTimeOfDay(existing.last.time.split(' - ').last);
        if (end.hour < 23) start = end;
      } catch (_) {
        // Keep the default for imported, unrecognised time formats.
      }
    }
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final result = await showModalBottomSheet<_ClassDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      sheetAnimationStyle: reducedMotion
          ? AnimationStyle.noAnimation
          : const AnimationStyle(
              duration: Duration(milliseconds: 380),
              reverseDuration: Duration(milliseconds: 260),
            ),
      builder: (_) => _AddClassSheet(
          day: targetDay,
          week: weekIndex + 1,
          start: start,
          editing: editing,
          savedClasses: savedClasses),
    );
    if (result == null || !mounted) return;
    setState(() {
      _selectedDate = date.add(Duration(
          days: const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                  .indexOf(result.day) +
              1 -
              date.weekday));
      _activeWeekIndex = weekIndex;
      _selecting = false;
      _selectedItems.clear();
      _newlyAdded = result.item;
      if (editing != null) {
        final source = _multiWeekTimetable[weekIndex]?[day];
        final index = source?.indexOf(editing) ?? -1;
        if (index >= 0) {
          if (result.day == day) {
            source![index] = result.item;
          } else {
            source!.removeAt(index);
            ((_multiWeekTimetable[weekIndex] ??= {})[result.day] ??= [])
                .add(result.item);
          }
        }
      }
    });
    if (editing == null) {
      _addScheduleItem(weekIndex, result.day, result.item);
    } else {
      _saveAllData();
    }
    HapticFeedback.lightImpact();
    if (editing == null || result.day != day) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealNewClass());
    }
  }

  Future<void> _revealNewClass() async {
    // Lazy lists can refine their extent while scrolling to the final card.
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!mounted || !_scheduleScroll.hasClients) return;
      final target = _scheduleScroll.position.maxScrollExtent;
      if (MediaQuery.disableAnimationsOf(context)) {
        _scheduleScroll.jumpTo(target);
        return;
      }
      await _scheduleScroll.animateTo(target,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic);
      if (!mounted ||
          !_scheduleScroll.hasClients ||
          (_scheduleScroll.position.maxScrollExtent - _scheduleScroll.offset)
                  .abs() <
              2) {
        return;
      }
    }
  }

  void _showRotationSettingsDialog() {
    int tempWeeks = _rotationWeeksCount;
    DateTime tempDate = _startDate;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final colors = Theme.of(context).colorScheme;
            Widget settingsPanel({required Widget child}) => Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      colors.primaryContainer.withValues(alpha: 0.38),
                      Colors.white.withValues(alpha: 0.8),
                    ]),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white),
                  ),
                  child: child,
                );
            return AlertDialog(
              scrollable: true,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(32),
              ),
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              actionsPadding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(Icons.autorenew_rounded,
                        color: colors.onPrimaryContainer, size: 28),
                  ),
                  const SizedBox(height: 16),
                  const Text('Rotation Schedule Settings',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text('Set the rhythm of your timetable.',
                      style: TextStyle(
                          fontSize: 14, color: colors.onSurfaceVariant)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  settingsPanel(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Number of rotating weeks (N):',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: tempWeeks,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.repeat_rounded),
                        ),
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(20),
                        items: List.generate(8, (i) => i + 1)
                            .map((w) => DropdownMenuItem(
                                  value: w,
                                  child:
                                      Text('$w Week${w > 1 ? "s" : ""} Cycle'),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => tempWeeks = val);
                          }
                        },
                      ),
                    ],
                  )),
                  const SizedBox(height: 16),
                  settingsPanel(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Reference Start Date (Week 1):',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          backgroundColor:
                              colors.surface.withValues(alpha: 0.7),
                          side: BorderSide(color: colors.outlineVariant),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18)),
                        ),
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: Text(
                            '${tempDate.year}-${tempDate.month.toString().padLeft(2, '0')}-${tempDate.day.toString().padLeft(2, '0')}'),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: tempDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                          );
                          if (picked != null) {
                            setDialogState(() => tempDate = picked);
                          }
                        },
                      ),
                    ],
                  )),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(104, 48),
                  ),
                  onPressed: () {
                    setState(() {
                      _selectedItems.clear();
                      _selecting = false;
                      _rotationWeeksCount = tempWeeks;
                      _startDate = tempDate;
                      _activeWeekIndex =
                          _calculateWeekIndexForDate(_selectedDate);
                      for (int w = 0; w < _rotationWeeksCount; w++) {
                        _multiWeekTimetable[w] ??= {};
                        for (var day in _daysOfWeek) {
                          _multiWeekTimetable[w]![day] ??= [];
                        }
                      }
                    });
                    _saveAllData();
                    Navigator.pop(context);
                  },
                  child: const Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'Class Timetable',
      applicationVersion: '2.0.0',
      applicationIcon: const Icon(Icons.calendar_month, size: 48),
      applicationLegalese:
          '© 2026 Danilo Stoletovic. All rights reserved.\nLicensed under MIT License.',
      children: [
        const SizedBox(height: 16),
        const Text(
          'A modern class timetable application with multi-week rotation support, JSON backup and restore, and daily schedule notifications.',
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          icon: const Icon(Icons.collections_bookmark),
          label: const Text('View Open Source Libraries'),
          onPressed: () {
            showLicensePage(
              context: context,
              applicationName: 'Class Timetable',
              applicationVersion: '2.0.0',
            );
          },
        ),
      ],
    );
  }

  String _exportScheduleJson() {
    final Map<String, dynamic> daysSerializable = {};
    _multiWeekTimetable.forEach((weekIndex, daysMap) {
      final Map<String, dynamic> daysMapSerializable = {};
      daysMap.forEach((day, items) {
        daysMapSerializable[day] = items.map((item) => item.toJson()).toList();
      });
      daysSerializable[weekIndex.toString()] = daysMapSerializable;
    });

    final Map<String, dynamic> fullBackup = {
      'app': 'Class Timetable',
      'version': 2,
      'weeksCount': _rotationWeeksCount,
      'startDate': _startDate.toIso8601String(),
      'timetable': daysSerializable,
    };

    return const JsonEncoder.withIndent('  ').convert(fullBackup);
  }

  bool _applyJsonString(String rawJson, BuildContext messengerContext) {
    try {
      final dynamic decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected a JSON object.');
      }

      int? newWeeksCount;
      DateTime? newStartDate;
      Map<String, dynamic> timetableMap;

      if (decoded.containsKey('timetable') &&
          decoded['timetable'] is Map<String, dynamic>) {
        timetableMap = decoded['timetable'] as Map<String, dynamic>;
        if (decoded['weeksCount'] is int) {
          newWeeksCount = decoded['weeksCount'] as int;
        }
        if (decoded['startDate'] is String) {
          newStartDate = DateTime.tryParse(decoded['startDate'] as String);
        }
      } else {
        timetableMap = decoded;
      }

      final Map<int, Map<String, List<ScheduleItem>>> loadedData = {};
      timetableMap.forEach((weekKey, daysMap) {
        final int wIndex = int.tryParse(weekKey) ?? 0;
        loadedData[wIndex] = {};
        if (daysMap is Map<String, dynamic>) {
          daysMap.forEach((dayKey, itemsJson) {
            if (itemsJson is List) {
              loadedData[wIndex]![dayKey] = itemsJson
                  .map((item) =>
                      ScheduleItem.fromJson(item as Map<String, dynamic>))
                  .toList();
            }
          });
        }
      });

      if (loadedData.isEmpty) {
        throw const FormatException('No valid schedule items found in JSON.');
      }

      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      setState(() {
        _selectedItems.clear();
        _selecting = false;
        _multiWeekTimetable = loadedData;
        if (newWeeksCount != null && newWeeksCount > 0) {
          _rotationWeeksCount = newWeeksCount;
        } else if (loadedData.keys.isNotEmpty) {
          final maxWeek = loadedData.keys.reduce((a, b) => a > b ? a : b);
          if (maxWeek + 1 > _rotationWeeksCount) {
            _rotationWeeksCount = maxWeek + 1;
          }
        }
        if (newStartDate != null) {
          _startDate = newStartDate;
        }
        _activeWeekIndex = _calculateWeekIndexForDate(_selectedDate);
      });
      _saveAllData();

      ScaffoldMessenger.of(messengerContext).showSnackBar(
        const SnackBar(
          content: Text('Schedule updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      return true;
    } catch (e) {
      ScaffoldMessenger.of(messengerContext).showSnackBar(
        SnackBar(
          content: Text('Invalid schedule JSON: $e'),
          backgroundColor: Theme.of(messengerContext).colorScheme.error,
        ),
      );
      return false;
    }
  }

  void _showBackupModal() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : const AnimationStyle(
              duration: Duration(milliseconds: 380),
              reverseDuration: Duration(milliseconds: 260)),
      builder: (_) => _BackupSheet(
        backup: _exportScheduleJson(),
        onRestore: (value) => _applyJsonString(value, context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final dayAbbreviation = _getDayAbbreviation(_selectedDate);
    final schedule =
        _multiWeekTimetable[_activeWeekIndex]?[dayAbbreviation] ?? [];

    return Scaffold(
      resizeToAvoidBottomInset: false,
      bottomNavigationBar: _selecting
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed:
                      _selectedItems.isEmpty ? null : _deleteSelectedItems,
                  icon: const Icon(Icons.delete_outline),
                  label: Text('Delete (${_selectedItems.length})'),
                ),
              ),
            )
          : null,
      appBar: AppBar(
        title: _selecting ? Text('${_selectedItems.length} selected') : null,
        leading: _selecting
            ? IconButton(
                tooltip: 'Cancel selection',
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _selecting = false;
                  _selectedItems.clear();
                }),
              )
            : PopupMenuButton<String>(
                tooltip: 'Settings menu',
                icon: const Icon(Icons.menu_rounded),
                position: PopupMenuPosition.under,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24)),
                onSelected: (action) {
                  switch (action) {
                    case 'select':
                      setState(() => _selecting = true);
                    case 'rotation':
                      _showRotationSettingsDialog();
                    case 'backup':
                      _showBackupModal();
                    case 'about':
                      _showAboutDialog();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'select',
                      child: ListTile(
                          leading: Icon(Icons.checklist_rounded),
                          title: Text('Select classes'))),
                  PopupMenuItem(
                      value: 'rotation',
                      child: ListTile(
                          leading: Icon(Icons.autorenew),
                          title: Text('Rotation Settings'))),
                  PopupMenuItem(
                      value: 'backup',
                      child: ListTile(
                          leading: Icon(Icons.sync_alt),
                          title: Text('Backup & restore'))),
                  PopupMenuItem(
                      value: 'about',
                      child: ListTile(
                          leading: Icon(Icons.info_outline),
                          title: Text('About & Copyright'))),
                ],
              ),
        actions: [
          if (_selecting && _selectedItems.length == 1)
            TextButton.icon(
              onPressed: () =>
                  _showAddClassSheet(editing: _selectedItems.single),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit'),
            ),
          if (_selecting)
            TextButton(
              onPressed: () => setState(() {
                if (_selectedItems.length == schedule.length) {
                  _selectedItems.clear();
                } else {
                  _selectedItems.addAll(schedule);
                }
              }),
              child: Text(_selectedItems.length == schedule.length
                  ? 'Deselect all'
                  : 'Select all'),
            ),
        ],
      ),
      floatingActionButton: _selecting
          ? null
          : Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom > 0 ? 20.0 : 8.0,
              ),
              child: FloatingActionButton.extended(
                onPressed: _showAddClassSheet,
                icon: const Icon(Icons.add),
                label: const Text('Add class'),
              ),
            ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFDCE7FC), Color(0xFFF3F4FA), Color(0xFFE9E2F8)],
          ),
        ),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                  24,
                  MediaQuery.sizeOf(context).height < 600 ? 8 : 32,
                  24,
                  MediaQuery.sizeOf(context).height < 600 ? 12 : 28),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('YOUR DAY, AT A GLANCE',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 11,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w700,
                        )),
                    const SizedBox(height: 12),
                    const Text('Class timetable',
                        style: TextStyle(
                          fontSize: 38,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1.2,
                        )),
                    const SizedBox(height: 10),
                    Text(
                        '${schedule.length} classes · Week ${_activeWeekIndex + 1}',
                        style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant)),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white.withValues(alpha: 0.85)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_month),
                      label: Text(
                        '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')} ($dayAbbreviation)',
                      ),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2035),
                        );
                        if (picked != null) {
                          setState(() {
                            _selectedItems.clear();
                            _selecting = false;
                            _selectedDate = picked;
                            _activeWeekIndex =
                                _calculateWeekIndexForDate(picked);
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Chip(
                    avatar: const Icon(Icons.repeat, size: 16),
                    label: Text(
                        'Week ${_activeWeekIndex + 1}/$_rotationWeeksCount'),
                    backgroundColor:
                        Theme.of(context).colorScheme.secondaryContainer,
                  ),
                ],
              ),
            ),
            Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
              child: Row(
                children: _daysOfWeek.map((d) {
                  final isSelected = dayAbbreviation == d;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3.0),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: () {
                          final currentWeekdayIndex = _selectedDate.weekday;
                          final targetWeekdayIndex = _daysOfWeek.indexOf(d) + 1;
                          final difference =
                              targetWeekdayIndex - currentWeekdayIndex;

                          setState(() {
                            _selectedItems.clear();
                            _selecting = false;
                            _selectedDate =
                                _selectedDate.add(Duration(days: difference));
                            _activeWeekIndex =
                                _calculateWeekIndexForDate(_selectedDate);
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                      .colorScheme
                                      .outlineVariant
                                      .withValues(alpha: 0.4),
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            d,
                            style: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              fontSize: 14,
                              color: isSelected
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            Expanded(
              child: schedule.isEmpty
                  ? Center(
                      child: Text(
                        'No classes for $dayAbbreviation (Week ${_activeWeekIndex + 1})',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    )
                  : ListView.builder(
                      controller: _scheduleScroll,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                      itemCount: schedule.length,
                      itemBuilder: (context, index) {
                        final item = schedule[index];
                        final isCurrent = item.isCurrentClass(_selectedDate);

                        return _ClassEntrance(
                          key: ObjectKey(item),
                          animate: identical(item, _newlyAdded),
                          onEnd: () {
                            if (identical(item, _newlyAdded)) {
                              _newlyAdded = null;
                            }
                          },
                          child: GestureDetector(
                            onLongPress: () => setState(() {
                              _selecting = true;
                              _selectedItems.add(item);
                            }),
                            onTap: _selecting
                                ? () => setState(() {
                                      if (!_selectedItems.add(item)) {
                                        _selectedItems.remove(item);
                                      }
                                    })
                                : null,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: BackdropFilter(
                                filter:
                                    ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                                child: Card(
                                  elevation: isCurrent ? 4 : 0,
                                  shape: RoundedRectangleBorder(
                                    side: isCurrent
                                        ? BorderSide(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            width: 2,
                                          )
                                        : BorderSide(
                                            color: Colors.white
                                                .withValues(alpha: 0.9)),
                                    borderRadius: BorderRadius.circular(28),
                                  ),
                                  color: isCurrent
                                      ? Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                      : Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withValues(alpha: 0.65),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14.0),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: item.color,
                                        child: Icon(
                                          Icons.book,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                        ),
                                      ),
                                      title: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              item.title,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          if (isCurrent)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: const Text(
                                                'NOW',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('${item.room} • ${item.time}'),
                                          if (item.note.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              'Note: ${item.note}',
                                              style: TextStyle(
                                                fontStyle: FontStyle.italic,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      trailing: _selecting
                                          ? Checkbox(
                                              value:
                                                  _selectedItems.contains(item),
                                              onChanged: (_) => setState(() {
                                                if (!_selectedItems.add(item)) {
                                                  _selectedItems.remove(item);
                                                }
                                              }),
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClassDraft {
  const _ClassDraft(this.day, this.item);
  final String day;
  final ScheduleItem item;
}

class _AddClassSheet extends StatefulWidget {
  const _AddClassSheet(
      {required this.day,
      required this.week,
      required this.start,
      this.editing,
      required this.savedClasses});
  final String day;
  final int week;
  final TimeOfDay start;
  final ScheduleItem? editing;
  final List<ScheduleItem> savedClasses;

  @override
  State<_AddClassSheet> createState() => _AddClassSheetState();
}

class _AddClassSheetState extends State<_AddClassSheet> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _room = TextEditingController();
  final _note = TextEditingController();
  late String _day = widget.day;
  late TimeOfDay _start = widget.start;
  late TimeOfDay _end =
      TimeOfDay(hour: widget.start.hour + 1, minute: widget.start.minute);
  bool _details = false;
  bool _submitted = false;
  String? _timeError;
  Color _color = const Color(0xFFB8D3FF);
  static const _palette = [
    Color(0xFFB8D3FF),
    Color(0xFFCFC1F4),
    Color(0xFFB8DFCA),
    Color(0xFFFFD5AB),
    Color(0xFFF3BDD2)
  ];

  int _minutes(TimeOfDay time) => time.hour * 60 + time.minute;

  @override
  void initState() {
    super.initState();
    final item = widget.editing;
    if (item == null) return;
    _title.text = item.title;
    _room.text = item.room == 'TBA' ? '' : item.room;
    _note.text = item.note;
    _color = item.color;
    _details = item.note.isNotEmpty;
    try {
      final times = item.time.split(' - ');
      _start = ScheduleItem._parseTimeOfDay(times[0]);
      _end = ScheduleItem._parseTimeOfDay(times[1]);
    } catch (_) {
      _timeError = 'Check the start and end times before saving.';
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _room.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickTime(bool start) async {
    final picked = await showTimePicker(
        context: context, initialTime: start ? _start : _end);
    if (picked == null || !mounted) return;
    setState(() {
      if (start) {
        final duration = _minutes(_end) - _minutes(_start);
        _start = picked;
        final proposed = _minutes(picked) + (duration > 0 ? duration : 60);
        if (proposed < 1440) {
          _end = TimeOfDay(hour: proposed ~/ 60, minute: proposed % 60);
        }
      } else {
        _end = picked;
      }
      _timeError = _minutes(_end) <= _minutes(_start)
          ? 'End time must be after start time.'
          : null;
    });
  }

  void _save() {
    if (_submitted) return;
    final valid = _form.currentState!.validate();
    setState(() => _timeError = _minutes(_end) <= _minutes(_start)
        ? 'End time must be after start time.'
        : null);
    if (!valid || _timeError != null) return;
    _submitted = true;
    FocusScope.of(context).unfocus();
    Navigator.pop(
        context,
        _ClassDraft(
            _day,
            ScheduleItem(
              title: _title.text.trim(),
              time: '${_start.format(context)} - ${_end.format(context)}',
              room: _room.text.trim().isEmpty ? 'TBA' : _room.text.trim(),
              color: _color,
              note: _note.text.trim(),
            )));
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final duration =
        reducedMotion ? Duration.zero : const Duration(milliseconds: 260);
    return AnimatedPadding(
      duration: duration,
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Form(
              key: _form,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(
                                widget.editing == null
                                    ? 'Add class'
                                    : 'Edit class',
                                style: const TextStyle(
                                    fontSize: 28, fontWeight: FontWeight.w700)),
                            Text('Week ${widget.week} · $_day',
                                style:
                                    TextStyle(color: colors.onSurfaceVariant)),
                          ])),
                      IconButton(
                          tooltip: 'Cancel',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close)),
                    ]),
                    const SizedBox(height: 20),
                    Flexible(
                        child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (widget.editing == null &&
                                widget.savedClasses.isNotEmpty) ...[
                              DropdownButtonFormField<ScheduleItem>(
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Reuse a class',
                                  prefixIcon: Icon(Icons.history_rounded),
                                  helperText:
                                      'Copies details. Choose the day and time below.',
                                  helperMaxLines: 2,
                                ),
                                items: widget.savedClasses
                                    .map((item) => DropdownMenuItem(
                                          value: item,
                                          child: Text(
                                              '${item.title} · ${item.room}',
                                              overflow: TextOverflow.ellipsis),
                                        ))
                                    .toList(),
                                onChanged: (item) {
                                  if (item == null) return;
                                  setState(() {
                                    _title.text = item.title;
                                    _room.text =
                                        item.room == 'TBA' ? '' : item.room;
                                    _note.text = item.note;
                                    _color = item.color;
                                    _details = item.note.isNotEmpty;
                                  });
                                  _form.currentState!.validate();
                                  FocusScope.of(context).unfocus();
                                },
                              ),
                              const SizedBox(height: 20),
                            ],
                            TextFormField(
                              controller: _title,
                              autofocus: true,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                  labelText: 'Class name',
                                  hintText: 'e.g. Mathematics',
                                  prefixIcon: Icon(Icons.menu_book_rounded)),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                      ? 'Enter a class name.'
                                      : null,
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  'Mon',
                                  'Tue',
                                  'Wed',
                                  'Thu',
                                  'Fri',
                                  if (widget.day == 'Sat' ||
                                      widget.day == 'Sun') ...['Sat', 'Sun']
                                ]
                                    .map((day) => ChoiceChip(
                                          label: Text(day),
                                          selected: day == _day,
                                          onSelected: (_) =>
                                              setState(() => _day = day),
                                        ))
                                    .toList()),
                            const SizedBox(height: 16),
                            Row(children: [
                              Expanded(
                                  child: _timeButton(
                                      'Starts', _start, () => _pickTime(true))),
                              const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 10),
                                  child: Icon(Icons.arrow_forward_rounded,
                                      size: 18)),
                              Expanded(
                                  child: _timeButton(
                                      'Ends', _end, () => _pickTime(false))),
                            ]),
                            AnimatedSize(
                              duration: duration,
                              curve: Curves.easeOutCubic,
                              child: _timeError == null
                                  ? const SizedBox.shrink()
                                  : Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(_timeError!,
                                          style:
                                              TextStyle(color: colors.error)),
                                    ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _room,
                              textCapitalization: TextCapitalization.sentences,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _save(),
                              decoration: const InputDecoration(
                                  labelText: 'Room (optional)',
                                  hintText: 'e.g. Room 101',
                                  prefixIcon: Icon(Icons.location_on_outlined)),
                            ),
                            const SizedBox(height: 8),
                            Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () =>
                                      setState(() => _details = !_details),
                                  icon: AnimatedRotation(
                                      turns: _details ? 0.5 : 0,
                                      duration: duration,
                                      child: const Icon(Icons.expand_more)),
                                  label: const Text('Notes & color'),
                                )),
                            AnimatedSize(
                              duration: duration,
                              curve: Curves.easeOutCubic,
                              alignment: Alignment.topCenter,
                              child: !_details
                                  ? const SizedBox(width: double.infinity)
                                  : Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            TextFormField(
                                                controller: _note,
                                                minLines: 2,
                                                maxLines: 4,
                                                textCapitalization:
                                                    TextCapitalization
                                                        .sentences,
                                                decoration:
                                                    const InputDecoration(
                                                        labelText:
                                                            'Notes / Homework',
                                                        alignLabelWithHint:
                                                            true)),
                                            const SizedBox(height: 16),
                                            const Text('Class color'),
                                            const SizedBox(height: 8),
                                            Wrap(
                                                spacing: 8,
                                                children: List.generate(
                                                    _palette.length, (index) {
                                                  final color = _palette[index];
                                                  final selected =
                                                      color == _color;
                                                  return Semantics(
                                                    label: [
                                                      'Blue',
                                                      'Purple',
                                                      'Green',
                                                      'Orange',
                                                      'Pink'
                                                    ][index],
                                                    selected: selected,
                                                    button: true,
                                                    child: InkWell(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              24),
                                                      onTap: () => setState(
                                                          () => _color = color),
                                                      child: AnimatedContainer(
                                                        duration: duration,
                                                        width: 48,
                                                        height: 48,
                                                        decoration: BoxDecoration(
                                                            color: color,
                                                            shape:
                                                                BoxShape.circle,
                                                            border: Border.all(
                                                                color: selected
                                                                    ? colors
                                                                        .primary
                                                                    : Colors
                                                                        .transparent,
                                                                width: 2)),
                                                        child: selected
                                                            ? const Icon(
                                                                Icons
                                                                    .check_rounded,
                                                                color: Color(
                                                                    0xFF24334E))
                                                            : null,
                                                      ),
                                                    ),
                                                  );
                                                })),
                                          ]),
                                    ),
                            ),
                          ]),
                    )),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56)),
                      onPressed: _save,
                      icon: Icon(widget.editing == null
                          ? Icons.add_rounded
                          : Icons.check_rounded),
                      label: Text(widget.editing == null
                          ? 'Add class'
                          : 'Save changes'),
                    ),
                  ]),
            ),
          )),
    );
  }

  Widget _timeButton(String label, TimeOfDay time, VoidCallback onPressed) =>
      OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20))),
        child: Column(children: [
          Text(label,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12)),
          const SizedBox(height: 4),
          Text(time.format(context),
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        ]),
      );
}

class _ClassEntrance extends StatefulWidget {
  const _ClassEntrance(
      {super.key,
      required this.animate,
      required this.onEnd,
      required this.child});
  final bool animate;
  final VoidCallback onEnd;
  final Widget child;

  @override
  State<_ClassEntrance> createState() => _ClassEntranceState();
}

class _ClassEntranceState extends State<_ClassEntrance> {
  late final bool _animate = widget.animate;

  @override
  Widget build(BuildContext context) {
    if (!_animate || MediaQuery.disableAnimationsOf(context)) {
      return widget.child;
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeOutCubic,
      onEnd: widget.onEnd,
      child: widget.child,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
            offset: Offset(0, 24 * (1 - value)),
            child: Transform.scale(scale: 0.97 + 0.03 * value, child: child)),
      ),
    );
  }
}

class _BackupSheet extends StatefulWidget {
  const _BackupSheet({required this.backup, required this.onRestore});
  final String backup;
  final bool Function(String) onRestore;

  @override
  State<_BackupSheet> createState() => _BackupSheetState();
}

class _BackupSheetState extends State<_BackupSheet> {
  late final _json = TextEditingController(text: widget.backup);
  bool _advanced = false;
  bool _busy = false;
  String? _fileName;
  String? _pending;
  String? _status;

  @override
  void dispose() {
    _json.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final result =
          await saveJsonFile(fileName: 'schedule.json', content: widget.backup);
      if (mounted && !result.cancelled) {
        setState(() => _status = result.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _status = 'Could not save the backup. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseFile() async {
    setState(() => _busy = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (!mounted || result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final contents = file.bytes == null
          ? await file.xFile.readAsString()
          : utf8.decode(file.bytes!);
      if (!mounted) return;
      if (contents.trim().isEmpty) {
        setState(() => _status = 'This backup is empty. Choose another file.');
        return;
      }
      setState(() {
        _fileName = file.name;
        _pending = contents.trim();
        _status = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
            () => _status = 'Could not open that backup. Try another file.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _restore(String value) {
    if (widget.onRestore(value)) {
      Navigator.pop(context);
    } else {
      setState(() => _status =
          'This backup could not be restored. Check the file or text and try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 260);
    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      duration: motion,
      curve: Curves.easeOutCubic,
      child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Expanded(
                        child: Text('Backup & restore',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700))),
                    IconButton(
                        tooltip: 'Close backup',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close)),
                  ]),
                  const SizedBox(height: 4),
                  Text('Keep a copy of your timetable, or bring one back.',
                      style: TextStyle(color: colors.onSurfaceVariant)),
                  const SizedBox(height: 24),
                  _actionCard(
                      icon: Icons.cloud_download_outlined,
                      title: 'Save a backup',
                      subtitle:
                          'Your classes, notes and rotation settings in one file.',
                      label: 'Save to File',
                      onPressed: _export),
                  const SizedBox(height: 12),
                  _actionCard(
                      icon: Icons.restore_rounded,
                      title: 'Restore your timetable',
                      subtitle:
                          'Choose a saved backup to replace your current timetable.',
                      label: 'Restore from File',
                      onPressed: _chooseFile),
                  AnimatedSize(
                      duration: motion,
                      curve: Curves.easeOutCubic,
                      child: _pending == null
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text('Ready to restore: $_fileName',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 8),
                                    FilledButton.icon(
                                        onPressed: _busy
                                            ? null
                                            : () => _restore(_pending!),
                                        icon: const Icon(Icons.check_rounded),
                                        label: const Text('Restore timetable')),
                                  ]),
                            )),
                  if (_busy)
                    const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: LinearProgressIndicator()),
                  if (_status != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child:
                            Semantics(liveRegion: true, child: Text(_status!))),
                  const SizedBox(height: 12),
                  Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => setState(() => _advanced = !_advanced),
                        icon: AnimatedRotation(
                            turns: _advanced ? 0.5 : 0,
                            duration: motion,
                            child: const Icon(Icons.expand_more)),
                        label: const Text('Advanced options'),
                      )),
                  AnimatedSize(
                      duration: motion,
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topCenter,
                      child: !_advanced
                          ? const SizedBox(width: double.infinity)
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextField(
                                    controller: _json,
                                    minLines: 4,
                                    maxLines: 7,
                                    style: const TextStyle(
                                        fontFamily: 'monospace', fontSize: 12),
                                    decoration: const InputDecoration(
                                        labelText: 'Schedule JSON',
                                        alignLabelWithHint: true)),
                                const SizedBox(height: 12),
                                Wrap(spacing: 8, runSpacing: 8, children: [
                                  OutlinedButton.icon(
                                      icon: const Icon(Icons.copy_rounded),
                                      label: const Text('Copy'),
                                      onPressed: () async {
                                        await Clipboard.setData(
                                            ClipboardData(text: _json.text));
                                        if (mounted) {
                                          setState(() =>
                                              _status = 'Copied to clipboard.');
                                        }
                                      }),
                                  OutlinedButton.icon(
                                      icon: const Icon(Icons.paste_rounded),
                                      label: const Text('Paste'),
                                      onPressed: () async {
                                        final data = await Clipboard.getData(
                                            Clipboard.kTextPlain);
                                        if (!mounted) return;
                                        setState(() {
                                          if (data?.text?.trim().isNotEmpty ??
                                              false) {
                                            _json.text = data!.text!.trim();
                                            _status =
                                                'Pasted. Apply when you are ready to replace your timetable.';
                                          } else {
                                            _status = 'Clipboard is empty.';
                                          }
                                        });
                                      }),
                                  FilledButton.icon(
                                      onPressed: _busy
                                          ? null
                                          : () => _restore(_json.text),
                                      icon: const Icon(Icons.check_rounded),
                                      label: const Text('Apply JSON')),
                                ]),
                              ],
                            )),
                ]),
          )),
    );
  }

  Widget _actionCard(
      {required IconData icon,
      required String title,
      required String subtitle,
      required String label,
      required VoidCallback onPressed}) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          colors.primaryContainer.withValues(alpha: 0.42),
          Colors.white.withValues(alpha: 0.8)
        ]),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 30, color: colors.primary),
        const SizedBox(height: 12),
        Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(subtitle, style: TextStyle(color: colors.onSurfaceVariant)),
        const SizedBox(height: 16),
        FilledButton.tonal(
            onPressed: _busy ? null : onPressed, child: Text(label)),
      ]),
    );
  }
}
