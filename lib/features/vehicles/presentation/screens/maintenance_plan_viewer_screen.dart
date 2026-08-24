import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/widgets/pdf_bytes_viewer.dart';

Future<void> openMaintenancePlanViewer(
  BuildContext context, {
  required String vehicleName,
  required String fileName,
  required Future<Uint8List> Function() loadBytes,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => MaintenancePlanViewerScreen(
        vehicleName: vehicleName,
        fileName: fileName,
        loadBytes: loadBytes,
      ),
    ),
  );
}

class MaintenancePlanViewerScreen extends StatelessWidget {
  const MaintenancePlanViewerScreen({
    super.key,
    required this.vehicleName,
    required this.fileName,
    required this.loadBytes,
  });

  final String vehicleName;
  final String fileName;
  final Future<Uint8List> Function() loadBytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Plano — $vehicleName')),
      body: PdfBytesViewer(
        fileName: fileName,
        loadBytes: loadBytes,
      ),
    );
  }
}
