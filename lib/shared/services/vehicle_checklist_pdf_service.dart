import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/app_models.dart';
import 'checklist_pdf_file_saver.dart'
    if (dart.library.io) 'checklist_pdf_file_saver_io.dart'
    if (dart.library.html) 'checklist_pdf_file_saver_web.dart';

class VehicleChecklistPdfService {
  Future<void> share(VehicleChecklist checklist) async {
    final bytes = Uint8List.fromList(await buildPdfBytes(checklist));
    final fileName = _fileName(checklist);
    await Share.shareXFiles(
      [XFile.fromData(bytes, mimeType: 'application/pdf', name: fileName)],
      subject: 'Checklist ${checklist.vehicleName} - ${checklist.checklistDate}',
      text: 'Checklist do veiculo ${checklist.vehicleName} (${checklist.vehiclePlate})',
    );
  }

  Future<String> download(VehicleChecklist checklist) async {
    final bytes = Uint8List.fromList(await buildPdfBytes(checklist));
    final fileName = _fileName(checklist);
    return saveChecklistPdfBytes(bytes, fileName);
  }

  Future<List<int>> buildPdfBytes(VehicleChecklist checklist) async {
    final completedLabel = DateFormat('dd/MM/yyyy HH:mm').format(checklist.completedAt);
    final signatureImage = _signatureImage(checklist.signatureBase64);
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text(
            'CHECKLIST DO VEICULO',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          pw.Text('Data: ${checklist.checklistDate}', style: const pw.TextStyle(fontSize: 12)),
          pw.SizedBox(height: 20),
          pw.Text('Motorista: ${checklist.driverName}', style: const pw.TextStyle(fontSize: 12)),
          pw.Text('Veiculo: ${checklist.vehicleName}', style: const pw.TextStyle(fontSize: 12)),
          pw.Text('Modelo: ${checklist.vehicleModel}', style: const pw.TextStyle(fontSize: 12)),
          pw.Text('Placa: ${checklist.vehiclePlate}', style: const pw.TextStyle(fontSize: 12)),
          pw.Text('Concluido em: $completedLabel', style: const pw.TextStyle(fontSize: 12)),
          if (checklist.missingItemsCount > 0)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 8),
              child: pw.Text(
                'Itens sem marca: ${checklist.missingItemsCount} (possivel falta ou problema)',
                style: pw.TextStyle(fontSize: 11, color: PdfColors.red800),
              ),
            ),
          pw.SizedBox(height: 24),
          pw.Text('Itens verificados', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Table.fromTextArray(
            headers: const ['Item', 'Status'],
            data: VehicleChecklistConfig.items
                .map(
                  (item) => [
                    item.label,
                    checklist.items[item.id] == true ? 'OK' : 'FALTA / PROBLEMA',
                  ],
                )
                .toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellAlignment: pw.Alignment.centerLeft,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          ),
          if (checklist.notes != null && checklist.notes!.trim().isNotEmpty) ...[
            pw.SizedBox(height: 20),
            pw.Text('Observacoes', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Text(checklist.notes!, style: const pw.TextStyle(fontSize: 11)),
          ],
          if (signatureImage != null) ...[
            pw.SizedBox(height: 24),
            pw.Text('Assinatura do motorista', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Container(
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey500)),
              padding: const pw.EdgeInsets.all(8),
              child: pw.Image(signatureImage, height: 80),
            ),
          ],
          pw.SizedBox(height: 32),
          pw.Text(
            'Documento gerado pelo Drive Control.',
            style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    );

    return doc.save();
  }

  pw.MemoryImage? _signatureImage(String? signatureBase64) {
    if (signatureBase64 == null || signatureBase64.trim().isEmpty) return null;
    try {
      return pw.MemoryImage(base64Decode(signatureBase64));
    } catch (_) {
      return null;
    }
  }

  String _fileName(VehicleChecklist checklist) {
    final safeVehicle = checklist.vehicleName.replaceAll(RegExp(r'[^\w\-]+'), '_');
    return 'checklist_${checklist.checklistDate}_$safeVehicle.pdf';
  }
}
