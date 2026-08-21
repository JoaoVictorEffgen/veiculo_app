import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'checklist_pdf_file_saver.dart';

Future<String> saveChecklistPdfBytes(Uint8List bytes, String fileName) async {
  final base = await getApplicationDocumentsDirectory();
  final directory = Directory(p.join(base.path, 'checklists'));
  if (!await directory.exists()) {
    await directory.create(recursive: true);
  }
  final file = File(p.join(directory.path, fileName));
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
