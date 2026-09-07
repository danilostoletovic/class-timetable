import 'file_saver_models.dart';

Future<SaveFileResult> saveJsonFileImpl({
  required String fileName,
  required String content,
}) async {
  throw UnsupportedError('Saving files is not supported on this platform.');
}
