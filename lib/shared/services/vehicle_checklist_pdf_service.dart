import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/app_models.dart';

class VehicleChecklistPdfService {
  Future<File> generateAndSave(VehicleChecklist checklist) async {
    final bytes = await buildPdfBytes(checklist);
    final directory = await _checklistDirectory();
    final fileName = _fileName(checklist);
    final file = File(p.join(directory.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> share(VehicleChecklist checklist) async {
    final file = await generateAndSave(checklist);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: p.basename(file.path))],
      subject: 'Checklist ${checklist.vehicleName} - ${checklist.checklistDate}',
      text: 'Checklist do veiculo ${checklist.vehicleName} (${checklist.vehiclePlate})',
    );
  }

  Future<File> download(VehicleChecklist checklist) => generateAndSave(checklist);

  Future<List<int>> buildPdfBytes(VehicleChecklist checklist) async {
    final completedLabel = DateFormat('dd/MM/yyyy HH:mm').format(checklist.completedAt);
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
          pw.SizedBox(height: 24),
          pw.Text('Itens verificados', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Table.fromTextArray(
            headers: const ['Item', 'Status'],
            data: VehicleChecklistConfig.items
                .map(
                  (item) => [
                    item.label,
                    checklist.items[item.id] == true ? 'OK' : 'Pendente',
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
          pw.SizedBox(height: 32),
          pw.Text(
            'Documento gerado pelo Controle de Veiculos.',
            style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    );

    return doc.save();
  }

  Future<Directory> _checklistDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(base.path, 'checklists'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  String _fileName(VehicleChecklist checklist) {
    final safeVehicle = checklist.vehicleName.replaceAll(RegExp(r'[^\w\-]+'), '_');
    return 'checklist_${checklist.checklistDate}_$safeVehicle.pdf';
  }
}
