import 'file_saver_models.dart';
import 'file_saver_stub.dart'
    if (dart.library.js_interop) 'file_saver_web.dart'
    if (dart.library.io) 'file_saver_io.dart';

export 'file_saver_models.dart';

Future<SaveFileResult> saveJsonFile({
  required String fileName,
  required String content,
}) =>
    saveJsonFileImpl(fileName: fileName, content: content);
