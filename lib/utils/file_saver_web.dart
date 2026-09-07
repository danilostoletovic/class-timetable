import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;
import 'file_saver_models.dart';

Future<SaveFileResult> saveJsonFileImpl({
  required String fileName,
  required String content,
}) async {
  try {
    final bytes = Uint8List.fromList(utf8.encode(content));
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'application/json;charset=utf-8'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = url;
    anchor.download = fileName;
    anchor.style.display = 'none';

    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();

    Future.delayed(const Duration(seconds: 5), () {
      web.URL.revokeObjectURL(url);
    });

    return SaveFileResult(
      success: true,
      message: 'Downloaded $fileName',
    );
  } catch (e) {
    return SaveFileResult(
      success: false,
      message: 'Failed to save file: $e',
    );
  }
}
