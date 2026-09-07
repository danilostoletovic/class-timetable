import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
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
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
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
              .map((item) =>
                  ScheduleItem.fromJson(item as Map<String, dynamic>))
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

  void _deleteScheduleItem(int weekIndex, String day, int index) {
    setState(() {
      _multiWeekTimetable[weekIndex]?[day]?.removeAt(index);
    });
    _saveAllData();
  }

  void _showAddEntryDialog() {
    final titleController = TextEditingController();
    final roomController = TextEditingController();
    final noteController = TextEditingController();

    TimeOfDay startTime = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay endTime = const TimeOfDay(hour: 10, minute: 0);
    Color pickerColor = Colors.deepPurple.shade100;
    String targetDay = _getDayAbbreviation(_selectedDate);
    if (!_daysOfWeek.contains(targetDay)) targetDay = 'Mon';

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Add Entry (Week ${_activeWeekIndex + 1})'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: targetDay,
                      decoration: const InputDecoration(
                        labelText: 'Day of Week',
                        border: OutlineInputBorder(),
                      ),
                      items: _daysOfWeek
                          .map((day) => DropdownMenuItem(
                                value: day,
                                child: Text(day),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => targetDay = val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Subject / Title',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: roomController,
                      decoration: const InputDecoration(
                        labelText: 'Room / Location',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteController,
                      decoration: const InputDecoration(
                        labelText: 'Notes / Homework',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      title: Text(
                        'Time: ${startTime.format(context)} - ${endTime.format(context)}',
                      ),
                      trailing: const Icon(Icons.access_time),
                      onTap: () async {
                        final pickedStart = await showTimePicker(
                          context: context,
                          initialTime: startTime,
                        );

                        if (!context.mounted) return;

                        if (pickedStart != null) {
                          final pickedEnd = await showTimePicker(
                            context: context,
                            initialTime: pickedStart,
                          );

                          if (!context.mounted) return;

                          if (pickedEnd != null) {
                            setDialogState(() {
                              startTime = pickedStart;
                              endTime = pickedEnd;
                            });
                          }
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Badge Color: '),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: const Text('Pick Color'),
                                  content: SingleChildScrollView(
                                    child: BlockPicker(
                                      pickerColor: pickerColor,
                                      onColorChanged: (color) {
                                        setDialogState(() {
                                          pickerColor = color;
                                        });
                                        Navigator.of(context).pop();
                                      },
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                          child: CircleAvatar(
                            backgroundColor: pickerColor,
                            radius: 16,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    if (titleController.text.isNotEmpty) {
                      final timeString =
                          '${startTime.format(context)} - ${endTime.format(context)}';
                      _addScheduleItem(
                        _activeWeekIndex,
                        targetDay,
                        ScheduleItem(
                          title: titleController.text,
                          time: timeString,
                          room: roomController.text.isEmpty
                              ? 'TBA'
                              : roomController.text,
                          color: pickerColor,
                          note: noteController.text,
                        ),
                      );
                      Navigator.pop(dialogContext);
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showRotationSettingsDialog() {
    int tempWeeks = _rotationWeeksCount;
    DateTime tempDate = _startDate;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Rotation Schedule Settings'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Number of rotating weeks (N):'),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: tempWeeks,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                    items: List.generate(8, (i) => i + 1)
                        .map((w) => DropdownMenuItem(
                              value: w,
                              child: Text('$w Week${w > 1 ? "s" : ""} Cycle'),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => tempWeeks = val);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text('Reference Start Date (Week 1):'),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today),
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
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    setState(() {
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

      setState(() {
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
    final textController = TextEditingController(text: _exportScheduleJson());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom +
                      MediaQuery.of(context).padding.bottom +
                      28,
                  top: 20,
                  left: 16,
                  right: 16,
                ),
                child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.sync_alt, size: 24),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Backup & Restore Schedule',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(bottomSheetContext),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Export your timetable to JSON or restore from text / file.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: textController,
                    maxLines: 6,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Paste Schedule JSON here...',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy'),
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: textController.text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('JSON copied to clipboard!'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.paste, size: 18),
                        label: const Text('Paste'),
                        onPressed: () async {
                          final data =
                              await Clipboard.getData(Clipboard.kTextPlain);
                          if (data?.text != null &&
                              data!.text!.trim().isNotEmpty) {
                            setModalState(() {
                              textController.text = data.text!.trim();
                            });
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Pasted from clipboard!'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          } else {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Clipboard is empty.'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.save_alt, size: 18),
                        label: const Text('Save to File'),
                        onPressed: () async {
                          final result = await saveJsonFile(
                            fileName: 'schedule.json',
                            content: textController.text,
                          );

                          if (!context.mounted) return;
                          if (result.cancelled) return;

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(result.message),
                              backgroundColor:
                                  result.success ? Colors.green : null,
                            ),
                          );
                        },
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: const Text('Restore from File'),
                        onPressed: () async {
                          try {
                            final result =
                                await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['json'],
                              withData: true,
                            );

                            if (result != null && result.files.isNotEmpty) {
                              final pickedFile = result.files.first;
                              final String fileContents;
                              if (pickedFile.bytes != null) {
                                fileContents = utf8.decode(pickedFile.bytes!);
                              } else {
                                fileContents =
                                    await pickedFile.xFile.readAsString();
                              }

                              if (fileContents.trim().isNotEmpty) {
                                final trimmed = fileContents.trim();
                                setModalState(() {
                                  textController.text = trimmed;
                                });

                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'Loaded ${pickedFile.name} into editor.'),
                                    action: SnackBarAction(
                                      label: 'Apply',
                                      onPressed: () {
                                        final success = _applyJsonString(
                                            textController.text, context);
                                        if (success &&
                                            bottomSheetContext.mounted) {
                                          Navigator.pop(bottomSheetContext);
                                        }
                                      },
                                    ),
                                  ),
                                );
                              }
                            }
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text('Failed to open file: $e')),
                            );
                          }
                        },
                      ),
                      FilledButton.icon(
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text('Apply JSON'),
                        onPressed: () {
                          final success =
                              _applyJsonString(textController.text, context);
                          if (success && bottomSheetContext.mounted) {
                            Navigator.pop(bottomSheetContext);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
      },
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
      appBar: AppBar(
        title: const Text('Class Timetable'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.autorenew),
            tooltip: 'Rotation Settings',
            onPressed: _showRotationSettingsDialog,
          ),
          IconButton(
            icon: const Icon(Icons.sync_alt),
            tooltip: 'Export/Import JSON',
            onPressed: _showBackupModal,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About & Copyright',
            onPressed: _showAboutDialog,
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom > 0 ? 20.0 : 8.0,
        ),
        child: FloatingActionButton.extended(
          onPressed: _showAddEntryDialog,
          icon: const Icon(Icons.add),
          label: const Text('Add Entry'),
        ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceContainerLow,
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
                  label: Text('Week ${_activeWeekIndex + 1}/$_rotationWeeksCount'),
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
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        final currentWeekdayIndex = _selectedDate.weekday;
                        final targetWeekdayIndex =
                            _daysOfWeek.indexOf(d) + 1;
                        final difference =
                            targetWeekdayIndex - currentWeekdayIndex;

                        setState(() {
                          _selectedDate =
                              _selectedDate.add(Duration(days: difference));
                          _activeWeekIndex =
                              _calculateWeekIndexForDate(_selectedDate);
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
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
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                    itemCount: schedule.length,
                    itemBuilder: (context, index) {
                      final item = schedule[index];
                      final isCurrent = item.isCurrentClass(_selectedDate);

                      return Dismissible(
                        key: ValueKey(
                            '${_activeWeekIndex}_${item.title}_${item.time}_$index'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.delete,
                            color:
                                Theme.of(context).colorScheme.onErrorContainer,
                          ),
                        ),
                        onDismissed: (direction) {
                          _deleteScheduleItem(
                              _activeWeekIndex, dayAbbreviation, index);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${item.title} deleted'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        child: Card(
                          elevation: isCurrent ? 4 : 0,
                          shape: RoundedRectangleBorder(
                            side: isCurrent
                                ? BorderSide(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    width: 2,
                                  )
                                : BorderSide.none,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          color: isCurrent
                              ? Theme.of(context)
                                  .colorScheme
                                  .primaryContainer
                              : Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: item.color,
                                child: Icon(
                                  Icons.book,
                                  color: Theme.of(context).colorScheme.primary,
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
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        borderRadius: BorderRadius.circular(8),
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
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                              trailing: IconButton(
                                icon: Icon(
                                  Icons.delete_outline,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                                onPressed: () {
                                  _deleteScheduleItem(
                                      _activeWeekIndex, dayAbbreviation, index);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('${item.title} deleted'),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                },
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
    );
  }
}