import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';

Future<void> openMaintenancePlanViewer(
  BuildContext context, {
  required String vehicleName,
  required String fileName,
  required String url,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => MaintenancePlanViewerScreen(
        vehicleName: vehicleName,
        fileName: fileName,
        url: url,
      ),
    ),
  );
}

class MaintenancePlanViewerScreen extends StatelessWidget {
  const MaintenancePlanViewerScreen({
    super.key,
    required this.vehicleName,
    required this.fileName,
    required this.url,
  });

  final String vehicleName;
  final String fileName;
  final String url;

  Future<Uint8List> _loadPdfBytes() async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('Nao foi possivel baixar o plano de manutencao.');
    }
    return Uint8List.fromList(response.bodyBytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Plano — $vehicleName')),
      body: PdfPreview(
        canChangePageFormat: false,
        canChangeOrientation: false,
        allowPrinting: true,
        allowSharing: true,
        pdfFileName: fileName,
        build: (_) => _loadPdfBytes(),
      ),
    );
  }
}
