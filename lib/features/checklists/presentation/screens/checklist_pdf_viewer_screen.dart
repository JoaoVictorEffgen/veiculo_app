import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../core/widgets/pdf_bytes_viewer.dart';
import '../../../../shared/models/app_models.dart';
import '../../../../shared/services/vehicle_checklist_pdf_service.dart';

Future<void> openChecklistPdfViewer(BuildContext context, VehicleChecklist checklist) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => ChecklistPdfViewerScreen(checklist: checklist),
    ),
  );
}

class ChecklistPdfViewerScreen extends StatelessWidget {
  const ChecklistPdfViewerScreen({super.key, required this.checklist});

  final VehicleChecklist checklist;

  @override
  Widget build(BuildContext context) {
    final pdfService = VehicleChecklistPdfService();
    final fileName = 'checklist_${checklist.checklistDate}_${checklist.vehicleName}.pdf';

    return Scaffold(
      appBar: AppBar(
        title: Text('Checklist ${checklist.vehicleName}'),
      ),
      body: PdfBytesViewer(
        fileName: fileName,
        loadBytes: () async {
          final bytes = await pdfService.buildPdfBytes(checklist);
          return Uint8List.fromList(bytes);
        },
      ),
    );
  }
}
