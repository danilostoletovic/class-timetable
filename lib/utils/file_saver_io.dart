import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'file_saver_models.dart';

Future<SaveFileResult> saveJsonFileImpl({
  required String fileName,
  required String content,
}) async {
  try {
    final bytes = utf8.encode(content);
    final String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Schedule JSON',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: Uint8List.fromList(bytes),
    );

    if (outputFile == null) {
      return const SaveFileResult(
        success: false,
        message: 'Save cancelled.',
        cancelled: true,
      );
    }

    final file = File(outputFile);
    if (!await file.exists() || (await file.length()) == 0) {
      await file.writeAsBytes(bytes);
    }

    return SaveFileResult(
      success: true,
      message: 'File saved: $outputFile',
    );
  } catch (e) {
    try {
      final String? selectedDir = await FilePicker.platform.getDirectoryPath();
      if (selectedDir != null) {
        final file = File('$selectedDir/$fileName');
        await file.writeAsString(content);
        return SaveFileResult(
          success: true,
          message: 'Saved to ${file.path}',
        );
      }
    } catch (_) {}

    return SaveFileResult(
      success: false,
      message: 'Failed to save file: $e',
    );
  }
}
