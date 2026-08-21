import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

import 'checklist_pdf_file_saver.dart';

Future<String> saveChecklistPdfBytes(Uint8List bytes, String fileName) async {
  await Share.shareXFiles(
    [XFile.fromData(bytes, mimeType: 'application/pdf', name: fileName)],
    subject: fileName,
  );
  return fileName;
}
