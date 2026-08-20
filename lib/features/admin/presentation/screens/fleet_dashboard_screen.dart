import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/widgets/corporate_ui.dart';
import '../../../../core/widgets/fleet_announcement_banner.dart';
import '../../../../core/widgets/admin_only_gate.dart';
import '../../../../core/widgets/main_app_shell.dart';
import '../../../../shared/models/fleet_analytics.dart';
import '../../../../shared/services/app_providers.dart';

class FleetDashboardScreen extends ConsumerWidget {
  const FleetDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AdminOnlyGate(
      child: Scaffold(
        appBar: const CorporateAppBar(title: 'Dashboard da frota'),
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
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          const CorporatePageHeader(
            title: 'Metricas da frota',
            subtitle: 'Veja quem mais anda e quais veiculos sao mais usados.',
          ),
          const SizedBox(height: 16),
          const FleetAnnouncementBanner(),
          const SizedBox(height: 8),
          _PeriodFilter(),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: CorporateMetricTile(
                  label: 'Motorista que mais andou',
                  value: report.topDriver == null ? '--' : report.topDriver!.name.split(' ').first,
                  icon: Icons.person_pin_circle_outlined,
                  color: AppColors.statusMoving,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CorporateMetricTile(
                  label: 'Veiculo mais usado',
                  value: report.topVehicle?.name ?? '--',
                  icon: Icons.local_shipping_outlined,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          if (report.topDriver != null) ...[
            const SizedBox(height: 8),
            CorporateSurface(
              child: Text(
                '${report.topDriver!.name} • ${_formatDuration(report.topDriver!.duration)} em movimento',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
          if (report.topVehicle != null) ...[
            const SizedBox(height: 8),
            CorporateSurface(
              child: Text(
                '${report.topVehicle!.name} • ${report.topVehicle!.count} utilizacoes no periodo',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
          const SizedBox(height: 24),
          _ChartCard(
            title: 'Tempo em movimento por motorista',
            subtitle: 'Quem mais tempo ficou dirigindo no periodo',
            child: _DriverMovingTimeChart(data: report.movingTimeByDriver),
          ),
          _ChartCard(
            title: 'Utilizacoes por veiculo',
            subtitle: 'Quantas vezes cada veiculo foi utilizado',
            child: _VehicleUtilizationChart(data: report.utilizationByVehicle),
          ),
        ],
      ),
    );
  }
}

class _PeriodFilter extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(fleetPeriodProvider);

    return CorporateSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Filtro de periodo', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          DropdownButtonFormField<FleetPeriodPreset>(
            initialValue: period.preset,
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
    return CorporateSurface(
      margin: const EdgeInsets.only(bottom: 16),
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

class _DriverMovingTimeChart extends StatelessWidget {
  const _DriverMovingTimeChart({required this.data});

  final List<NamedDuration> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty || data.every((item) => item.duration <= Duration.zero)) {
      return const _EmptyChart(message: 'Nenhum tempo em movimento no periodo.');
    }

    final hours = data.map((e) => e.duration.inMinutes / 60.0).toList();
    final maxY = hours.reduce((a, b) => a > b ? a : b);
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
                  return Text(data[index].name.split(' ').first, style: const TextStyle(fontSize: 11));
                },
              ),
            ),
            bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= data.length) return const SizedBox.shrink();
                  return Text(_formatDuration(data[index].duration), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600));
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
                    toY: hours[i],
                    width: 16,
                    color: AppColors.statusMoving,
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
  if (duration.inMinutes <= 0) return '0 min';
  if (duration.inHours >= 1) return '${duration.inHours}h ${duration.inMinutes.remainder(60)}min';
  return '${duration.inMinutes} min';
}
