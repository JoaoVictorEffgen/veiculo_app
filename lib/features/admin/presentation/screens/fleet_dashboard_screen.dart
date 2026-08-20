import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/theme.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/admin_only_gate.dart';
import '../../../../shared/models/fleet_analytics.dart';
import '../../../../shared/services/app_providers.dart';

class FleetDashboardScreen extends ConsumerWidget {
  const FleetDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AdminOnlyGate(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Dashboard da Frota'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.canPop() ? context.pop() : context.go(AppRoutes.admin),
          ),
          actions: [
            IconButton(
              onPressed: () async {
                await ref.read(authControllerProvider.notifier).logout();
                if (context.mounted) context.go(AppRoutes.login);
              },
              icon: const Icon(Icons.logout),
              tooltip: 'Sair',
            ),
          ],
        ),
        body: ref.watch(fleetAnalyticsProvider).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Erro ao carregar dashboard: $error')),
              data: (report) => _DashboardBody(report: report),
            ),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.report});

  final FleetAnalyticsReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(movementsProvider);
        ref.invalidate(usersProvider);
        await ref.read(vehicleControllerProvider.notifier).refresh();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 32),
        children: [
          Text('Indicadores', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          _SummaryGrid(summary: report.summary),
          const SizedBox(height: 20),
          _PeriodFilter(),
          const SizedBox(height: 20),
          _HighlightsSection(highlights: report.highlights, summary: report.summary),
          const SizedBox(height: 24),
          _ChartCard(
            title: 'Utilizacao por veiculo',
            subtitle: 'Quantidade de vezes que cada veiculo foi utilizado no periodo',
            child: _VehicleUtilizationChart(data: report.utilizationByVehicle),
          ),
          _ChartCard(
            title: 'Tempo em movimento x parado',
            subtitle: 'Percentual de tempo em movimento e parado por veiculo',
            child: _VehicleTimeShareChart(data: report.timeShareByVehicle),
          ),
          _ChartCard(
            title: 'Utilizacao por motorista',
            subtitle: 'Distribuicao de utilizacoes entre motoristas (dado administrativo)',
            child: _DriverUtilizationChart(data: report.utilizationByDriver),
          ),
          _ChartCard(
            title: 'Movimentacao ao longo do tempo',
            subtitle: 'Tendencia de utilizacoes registradas no periodo',
            child: _MovementsTimelineChart(data: report.movementsOverTime),
          ),
          const SizedBox(height: 8),
          Text('Alertas', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (report.alerts.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.check_circle_outline, color: AppColors.statusMoving),
                title: Text('Nenhum alerta relevante no momento'),
              ),
            )
          else
            ...report.alerts.map((alert) => _AlertTile(alert: alert)),
        ],
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.summary});

  final FleetSummary summary;

  @override
  Widget build(BuildContext context) {
    final items = [
      _Metric(label: 'Veiculos', value: '${summary.totalVehicles}', icon: Icons.local_shipping_outlined),
      _Metric(label: 'Em movimento', value: '${summary.movingVehicles}', icon: Icons.directions_car, color: AppColors.statusMoving),
      _Metric(label: 'Parados', value: '${summary.stoppedVehicles}', icon: Icons.pause_circle_outline, color: AppColors.statusStopped),
      _Metric(label: 'Disponiveis', value: '${summary.availableVehicles}', icon: Icons.check_circle_outline),
      _Metric(label: 'Motoristas', value: '${summary.totalDrivers}', icon: Icons.people_outline),
      _Metric(label: 'Utilizacao', value: '${summary.utilizationRate.toStringAsFixed(0)}%', icon: Icons.speed),
      _Metric(label: 'Disponibilidade', value: '${summary.availabilityRate.toStringAsFixed(0)}%', icon: Icons.event_available),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((item) => SizedBox(width: 110, child: item)).toList(),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.icon, this.color});

  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color ?? AppColors.primary, size: 20),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _PeriodFilter extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(fleetPeriodProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Filtro de periodo', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            DropdownButtonFormField<FleetPeriodPreset>(
              value: period.preset,
              decoration: const InputDecoration(labelText: 'Periodo', prefixIcon: Icon(Icons.date_range)),
              items: FleetPeriodPreset.values
                  .map((preset) => DropdownMenuItem(value: preset, child: Text(preset.label)))
                  .toList(),
              onChanged: (preset) {
                if (preset == null) return;
                ref.read(fleetPeriodProvider.notifier).state = period.copyWith(preset: preset);
              },
            ),
            if (period.preset == FleetPeriodPreset.custom) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final range = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                    initialDateRange: DateTimeRange(
                      start: period.customStart ?? DateTime.now().subtract(const Duration(days: 29)),
                      end: period.customEnd ?? DateTime.now(),
                    ),
                  );
                  if (range == null) return;
                  ref.read(fleetPeriodProvider.notifier).state = period.copyWith(
                        preset: FleetPeriodPreset.custom,
                        customStart: range.start,
                        customEnd: range.end,
                      );
                },
                icon: const Icon(Icons.edit_calendar),
                label: Text(
                  '${formatDateTime(period.customStart ?? period.resolveRange().start)} - ${formatDateTime(period.customEnd ?? period.resolveRange().end)}',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HighlightsSection extends StatelessWidget {
  const _HighlightsSection({required this.highlights, required this.summary});

  final FleetHighlights highlights;
  final FleetSummary summary;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Destaques do periodo', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _HighlightRow(
              label: 'Veiculo mais utilizado',
              value: highlights.mostUsedVehicle == null
                  ? 'Sem dados'
                  : '${highlights.mostUsedVehicle!.name} (${highlights.mostUsedVehicle!.count})',
            ),
            _HighlightRow(
              label: 'Veiculo menos utilizado',
              value: highlights.leastUsedVehicle == null
                  ? 'Sem dados'
                  : '${highlights.leastUsedVehicle!.name} (${highlights.leastUsedVehicle!.count})',
            ),
            _HighlightRow(
              label: 'Motorista com maior utilizacao',
              value: highlights.topDriver == null ? 'Sem dados' : '${highlights.topDriver!.name} (${highlights.topDriver!.count})',
            ),
            _HighlightRow(label: 'Tempo medio de utilizacao', value: _formatDuration(highlights.averageTripDuration)),
            _HighlightRow(label: 'Tempo medio parado', value: _formatDuration(highlights.averageStoppedDuration)),
            _HighlightRow(label: 'Taxa de utilizacao da frota', value: '${summary.utilizationRate.toStringAsFixed(1)}%'),
            _HighlightRow(label: 'Taxa de disponibilidade', value: '${summary.availabilityRate.toStringAsFixed(1)}%'),
          ],
        ),
      ),
    );
  }
}

class _HighlightRow extends StatelessWidget {
  const _HighlightRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.textSecondary))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.subtitle, required this.child});

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _VehicleUtilizationChart extends StatelessWidget {
  const _VehicleUtilizationChart({required this.data});

  final List<NamedCount> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty || data.every((item) => item.count == 0)) {
      return const _EmptyChart(message: 'Nenhuma utilizacao registrada no periodo.');
    }

    final maxY = data.map((e) => e.count).reduce((a, b) => a > b ? a : b).toDouble();
    final height = (data.length * 42.0).clamp(200.0, 360.0);

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: maxY <= 0 ? 1 : maxY * 1.2,
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 84,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= data.length) return const SizedBox.shrink();
                  return Text(data[index].name, style: const TextStyle(fontSize: 11));
                },
              ),
            ),
            bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= data.length) return const SizedBox.shrink();
                  return Text('${data[index].count}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600));
                },
              ),
            ),
          ),
          gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: maxY > 4 ? (maxY / 4).ceilToDouble() : 1),
          borderData: FlBorderData(show: false),
          barGroups: [
            for (var i = 0; i < data.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: data[i].count.toDouble(),
                    width: 16,
                    color: AppColors.primary,
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _VehicleTimeShareChart extends StatelessWidget {
  const _VehicleTimeShareChart({required this.data});

  final List<VehicleTimeShare> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const _EmptyChart(message: 'Sem dados de tempo no periodo selecionado.');
    }

    return Column(
      children: data.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(item.vehicleName, style: const TextStyle(fontWeight: FontWeight.w600))),
                  Text('${item.movingPercent.toStringAsFixed(0)}% mov.'),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 14,
                  child: Row(
                    children: [
                      Expanded(
                        flex: item.movingPercent.round().clamp(0, 100),
                        child: Container(color: AppColors.statusMoving),
                      ),
                      Expanded(
                        flex: item.stoppedPercent.round().clamp(0, 100),
                        child: Container(color: AppColors.statusStopped.withOpacity(0.35)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${item.movingPercent.toStringAsFixed(0)}% em movimento • ${item.stoppedPercent.toStringAsFixed(0)}% parado',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _DriverUtilizationChart extends StatelessWidget {
  const _DriverUtilizationChart({required this.data});

  final List<NamedCount> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty || data.every((item) => item.count == 0)) {
      return const _EmptyChart(message: 'Nenhuma utilizacao por motorista no periodo.');
    }

    final maxY = data.map((e) => e.count).reduce((a, b) => a > b ? a : b).toDouble();
    final height = 220.0;

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: maxY <= 0 ? 1 : maxY * 1.2,
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 72,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= data.length) return const SizedBox.shrink();
                  return Text(data[index].name.split(' ').first, style: const TextStyle(fontSize: 11));
                },
              ),
            ),
            bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: maxY > 4 ? (maxY / 4).ceilToDouble() : 1),
          borderData: FlBorderData(show: false),
          barGroups: [
            for (var i = 0; i < data.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: data[i].count.toDouble(),
                    width: 16,
                    color: AppColors.primary.withOpacity(0.85),
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _MovementsTimelineChart extends StatelessWidget {
  const _MovementsTimelineChart({required this.data});

  final List<TimeSeriesPoint> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const _EmptyChart(message: 'Sem movimentacoes no periodo selecionado.');
    }

    final maxY = data.map((e) => e.count).reduce((a, b) => a > b ? a : b).toDouble();

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY <= 0 ? 1 : maxY * 1.2,
          gridData: FlGridData(show: true, drawVerticalLine: false),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= data.length) return const SizedBox.shrink();
                  if (data.length > 8 && index.isOdd) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(data[index].label, style: const TextStyle(fontSize: 10)),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(showTitles: true, reservedSize: 32, interval: maxY > 4 ? (maxY / 4).ceilToDouble() : 1),
            ),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: [for (var i = 0; i < data.length; i++) FlSpot(i.toDouble(), data[i].count.toDouble())],
              isCurved: true,
              color: AppColors.primary,
              barWidth: 3,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(show: true, color: AppColors.primary.withOpacity(0.08)),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert});

  final FleetAlert alert;

  @override
  Widget build(BuildContext context) {
    final icon = alert.level == FleetAlertLevel.warning ? Icons.warning_amber_rounded : Icons.info_outline;
    final color = alert.level == FleetAlertLevel.warning ? AppColors.statusStopped : AppColors.primary;

    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(alert.message),
      ),
    );
  }
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: Center(child: Text(message, style: const TextStyle(color: AppColors.textSecondary))),
    );
  }
}

String _formatDuration(Duration duration) {
  if (duration.inMinutes <= 0) return '--';
  if (duration.inHours >= 1) return '${duration.inHours}h ${duration.inMinutes.remainder(60)}min';
  return '${duration.inMinutes} min';
}
