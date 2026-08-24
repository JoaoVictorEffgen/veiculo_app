import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

Widget buildPdfBytesViewer({
  required Uint8List bytes,
  required String fileName,
}) {
  return PdfPreview(
    canChangePageFormat: false,
    canChangeOrientation: false,
    allowPrinting: true,
    allowSharing: true,
    pdfFileName: fileName,
    build: (_) async => bytes,
  );
}
