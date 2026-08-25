import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/fleet_analytics.dart';
import '../../core/utils/date_formatter.dart';

class FleetReportExportService {
  Future<void> sharePdf(FleetAnalyticsReport report) async {
    final bytes = Uint8List.fromList(await buildPdfBytes(report));
    final fileName = _fileName(report, 'pdf');
    await Share.shareXFiles(
      [XFile.fromData(bytes, mimeType: 'application/pdf', name: fileName)],
      subject: 'Relatorio Drive Control',
      text: 'Relatorio da frota - Drive Control',
    );
  }

  Future<void> shareCsv(FleetAnalyticsReport report) async {
    final csv = buildCsv(report);
    final bytes = Uint8List.fromList(utf8.encode(csv));
    final fileName = _fileName(report, 'csv');
    await Share.shareXFiles(
      [XFile.fromData(bytes, mimeType: 'text/csv', name: fileName)],
      subject: 'Relatorio Drive Control CSV',
      text: 'Relatorio da frota em CSV',
    );
  }

  String _fileName(FleetAnalyticsReport report, String extension) {
    final start = DateFormat('yyyyMMdd').format(report.period.start);
    final end = DateFormat('yyyyMMdd').format(report.period.end);
    return 'drive_control_relatorio_${start}_$end.$extension';
  }

  String buildCsv(FleetAnalyticsReport report) {
    final buffer = StringBuffer();
    void row(List<String> cells) => buffer.writeln(cells.map(_escapeCsv).join(';'));

    row(['Relatorio Drive Control']);
    row(['Periodo', '${formatDateTime(report.period.start)} ate ${formatDateTime(report.period.end)}']);
    row(['Km total da frota', report.totalKm.toStringAsFixed(1)]);
    buffer.writeln();

    row(['Km por motorista']);
    row(['Motorista', 'Km']);
    for (final item in report.kmByDriver.where((item) => item.km > 0)) {
      row([item.name, item.km.toStringAsFixed(1)]);
    }
    buffer.writeln();

    row(['Velocidade media por motorista (km/h)']);
    row(['Motorista', 'Km', 'Tempo (h)', 'Velocidade media (km/h)']);
    for (final item in report.avgSpeedByDriver.where((item) => item.avgSpeedKmh > 0)) {
      final hours = item.movingTime.inMinutes / 60.0;
      row([item.name, item.totalKm.toStringAsFixed(1), hours.toStringAsFixed(2), item.avgSpeedKmh.toStringAsFixed(1)]);
    }
    buffer.writeln();

    row(['Corridas detalhadas']);
    row(['Motorista', 'Veiculo', 'Inicio', 'Fim', 'Km', 'Velocidade media (km/h)']);
    for (final trip in report.tripSpeedRecords) {
      row([
        trip.driverName,
        trip.vehicleName,
        formatDateTime(trip.startedAt),
        formatDateTime(trip.endedAt),
        trip.distanceKm.toStringAsFixed(1),
        trip.avgSpeedKmh.toStringAsFixed(1),
      ]);
    }
    buffer.writeln();

    row(['Velocidade media por hora']);
    row(['Motorista', 'Hora', 'Km na hora', 'Velocidade media (km/h)']);
    for (final item in report.hourlySpeedByDriver) {
      row([
        item.driverName,
        DateFormat('dd/MM/yyyy HH:mm').format(item.hourStart),
        item.km.toStringAsFixed(1),
        item.avgSpeedKmh.toStringAsFixed(1),
      ]);
    }
    buffer.writeln();

    row(['Km por veiculo']);
    row(['Veiculo', 'Km']);
    for (final item in report.kmByVehicle.where((item) => item.km > 0)) {
      row([item.name, item.km.toStringAsFixed(1)]);
    }
    buffer.writeln();

    row(['Relatos de motoristas no periodo']);
    row(['Motorista', 'Veiculo', 'Data', 'Relato', 'Resposta admin']);
    for (final item in report.driverReportsInPeriod) {
      row([
        item.driverName,
        item.vehicleName ?? '-',
        formatDateTime(item.createdAt),
        item.message,
        item.adminReply ?? '-',
      ]);
    }

    return buffer.toString();
  }

  Future<List<int>> buildPdfBytes(FleetAnalyticsReport report) async {
    final periodLabel = '${DateFormat('dd/MM/yyyy').format(report.period.start)} - ${DateFormat('dd/MM/yyyy').format(report.period.end)}';
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Text('RELATORIO DA FROTA', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text('Drive Control', style: const pw.TextStyle(fontSize: 12)),
          pw.Text('Periodo: $periodLabel', style: const pw.TextStyle(fontSize: 11)),
          pw.Text('Km total: ${report.totalKm.toStringAsFixed(1)} km', style: const pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: 18),
          _pdfSectionTitle('Km por motorista'),
          _pdfTable(
            headers: const ['Motorista', 'Km'],
            rows: report.kmByDriver.where((item) => item.km > 0).map((item) => [item.name, item.km.toStringAsFixed(1)]).toList(),
          ),
          pw.SizedBox(height: 16),
          _pdfSectionTitle('Velocidade media por motorista'),
          _pdfTable(
            headers: const ['Motorista', 'Km', 'Vel. media (km/h)'],
            rows: report.avgSpeedByDriver
                .where((item) => item.avgSpeedKmh > 0)
                .map((item) => [item.name, item.totalKm.toStringAsFixed(1), item.avgSpeedKmh.toStringAsFixed(1)])
                .toList(),
          ),
          pw.SizedBox(height: 16),
          _pdfSectionTitle('Corridas no periodo'),
          _pdfTable(
            headers: const ['Motorista', 'Veiculo', 'Inicio', 'Fim', 'Km', 'km/h'],
            rows: report.tripSpeedRecords
                .take(40)
                .map(
                  (trip) => [
                    trip.driverName,
                    trip.vehicleName,
                    DateFormat('dd/MM HH:mm').format(trip.startedAt),
                    DateFormat('dd/MM HH:mm').format(trip.endedAt),
                    trip.distanceKm.toStringAsFixed(1),
                    trip.avgSpeedKmh.toStringAsFixed(1),
                  ],
                )
                .toList(),
          ),
          if (report.tripSpeedRecords.length > 40)
            pw.Text('... ${report.tripSpeedRecords.length - 40} corridas adicionais no CSV.', style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 16),
          _pdfSectionTitle('Velocidade media por hora'),
          _pdfTable(
            headers: const ['Motorista', 'Hora', 'Km', 'km/h'],
            rows: report.hourlySpeedByDriver
                .take(30)
                .map(
                  (item) => [
                    item.driverName,
                    DateFormat('dd/MM HH:mm').format(item.hourStart),
                    item.km.toStringAsFixed(1),
                    item.avgSpeedKmh.toStringAsFixed(1),
                  ],
                )
                .toList(),
          ),
          pw.SizedBox(height: 16),
          _pdfSectionTitle('Relatos de motoristas'),
          _pdfTable(
            headers: const ['Motorista', 'Veiculo', 'Data', 'Relato', 'Resposta'],
            rows: report.driverReportsInPeriod
                .take(25)
                .map(
                  (item) => [
                    item.driverName,
                    item.vehicleName ?? '-',
                    DateFormat('dd/MM/yyyy HH:mm').format(item.createdAt),
                    item.message,
                    item.adminReply ?? '-',
                  ],
                )
                .toList(),
          ),
          pw.SizedBox(height: 16),
          _pdfSectionTitle('Km por veiculo'),
          _pdfTable(
            headers: const ['Veiculo', 'Km'],
            rows: report.kmByVehicle.where((item) => item.km > 0).map((item) => [item.name, item.km.toStringAsFixed(1)]).toList(),
          ),
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _pdfSectionTitle(String title) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: pw.Text(title, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
    );
  }

  pw.Widget _pdfTable({required List<String> headers, required List<List<String>> rows}) {
    if (rows.isEmpty) {
      return pw.Text('Sem dados neste periodo.', style: const pw.TextStyle(fontSize: 10));
    }

    return pw.Table.fromTextArray(
      headers: headers,
      data: rows,
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignment: pw.Alignment.centerLeft,
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
    );
  }

  String _escapeCsv(String value) {
    if (value.contains(';') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
