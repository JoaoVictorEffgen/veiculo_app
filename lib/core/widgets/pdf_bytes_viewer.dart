import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'pdf_bytes_viewer_stub.dart'
    if (dart.library.html) 'pdf_bytes_viewer_web.dart'
    if (dart.library.io) 'pdf_bytes_viewer_io.dart';

class PdfBytesViewer extends StatelessWidget {
  const PdfBytesViewer({
    super.key,
    required this.loadBytes,
    required this.fileName,
  });

  final Future<Uint8List> Function() loadBytes;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: loadBytes(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                snapshot.hasError
                    ? 'Nao foi possivel abrir o PDF.\n${snapshot.error}'
                    : 'PDF vazio ou indisponivel.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        return buildPdfBytesViewer(
          bytes: snapshot.data!,
          fileName: fileName,
        );
      },
    );
  }
}

bool get supportsInlinePdfPreview => !kIsWeb;
