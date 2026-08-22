import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
            subtitle: 'Distancia percorrida, tempo em movimento e uso dos veiculos.',
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
                  label: 'Mais km no periodo',
                  value: report.topDriverByKm == null ? '--' : report.topDriverByKm!.name.split(' ').first,
                  icon: Icons.route_outlined,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CorporateMetricTile(
                  label: 'Total da frota',
                  value: '${report.totalKm.toStringAsFixed(1)} km',
                  icon: Icons.speed_outlined,
                  color: AppColors.statusMoving,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: CorporateMetricTile(
                  label: 'Mais tempo dirigindo',
                  value: report.topDriver == null ? '--' : report.topDriver!.name.split(' ').first,
                  icon: Icons.timer_outlined,
                  color: AppColors.statusMovingDark,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CorporateMetricTile(
                  label: 'Veiculo mais usado',
                  value: report.topVehicle?.name ?? '--',
                  icon: Icons.local_shipping_outlined,
                  color: AppColors.primaryDark,
                ),
              ),
            ],
          ),
          if (report.topDriverByKm != null) ...[
            const SizedBox(height: 8),
            CorporateSurface(
              child: Text(
                '${report.topDriverByKm!.name} • ${report.topDriverByKm!.km.toStringAsFixed(1)} km rodados',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
          const SizedBox(height: 24),
          _ChartCard(
            title: 'Km rodados por motorista',
            subtitle: 'Grafico de barras horizontais — ideal para ranking de distancia',
            child: _KmBarChart(
              data: report.kmByDriver,
              emptyMessage: 'Nenhum km registrado ainda. Os dados aparecem ao parar a corrida com GPS ativo.',
              barColor: AppColors.primary,
              formatValue: (km) => '${km.toStringAsFixed(1)} km',
            ),
          ),
          _ChartCard(
            title: 'Km por dia',
            subtitle: 'Grafico de linha — mostra a evolucao diaria da frota',
            child: _DailyKmLineChart(data: report.dailyKmTrend),
          ),
          _ChartCard(
            title: 'Tempo em movimento por motorista',
            subtitle: 'Barras horizontais — compara horas/minutos de uso',
            child: _DurationBarChart(data: report.movingTimeByDriver),
          ),
          _ChartCard(
            title: 'Participacao de uso por veiculo',
            subtitle: 'Grafico de rosca — mostra a fatia de cada veiculo no total de saidas',
            child: _VehicleUsageDonutChart(data: report.utilizationByVehicle),
          ),
          _ChartCard(
            title: 'Utilizacoes por veiculo',
            subtitle: 'Barras horizontais — quantidade exata de vezes que saiu',
            child: _CountBarChart(
              data: report.utilizationByVehicle,
              barColor: AppColors.primaryDark,
            ),
          ),
          const _ChartGuideCard(),
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

class _KmBarChart extends StatelessWidget {
  const _KmBarChart({
    required this.data,
    required this.emptyMessage,
    required this.barColor,
    required this.formatValue,
  });

  final List<NamedKm> data;
  final String emptyMessage;
  final Color barColor;
  final String Function(double km) formatValue;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty || data.every((item) => item.km <= 0)) {
      return _EmptyChart(message: emptyMessage);
    }

    final maxY = data.map((e) => e.km).reduce((a, b) => a > b ? a : b);
    final height = (data.length * 44.0).clamp(200.0, 360.0);

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: maxY <= 0 ? 1 : maxY * 1.15,
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
                reservedSize: 52,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= data.length) return const SizedBox.shrink();
                  return Text(formatValue(data[index].km), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600));
                },
              ),
            ),
          ),
          gridData: FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          barGroups: [
            for (var i = 0; i < data.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: data[i].km,
                    width: 16,
                    color: barColor,
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

class _DurationBarChart extends StatelessWidget {
  const _DurationBarChart({required this.data});

  final List<NamedDuration> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty || data.every((item) => item.duration <= Duration.zero)) {
      return const _EmptyChart(message: 'Nenhum tempo em movimento no periodo.');
    }

    final hours = data.map((e) => e.duration.inMinutes / 60.0).toList();
    final maxY = hours.reduce((a, b) => a > b ? a : b);
    final height = (data.length * 44.0).clamp(200.0, 360.0);

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: maxY <= 0 ? 1 : maxY * 1.15,
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
                reservedSize: 52,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= data.length) return const SizedBox.shrink();
                  return Text(_formatDuration(data[index].duration), style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600));
                },
              ),
            ),
          ),
          gridData: FlGridData(show: true, drawVerticalLine: false),
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

class _CountBarChart extends StatelessWidget {
  const _CountBarChart({required this.data, required this.barColor});

  final List<NamedCount> data;
  final Color barColor;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty || data.every((item) => item.count == 0)) {
      return const _EmptyChart(message: 'Nenhuma utilizacao registrada no periodo.');
    }

    final maxY = data.map((e) => e.count).reduce((a, b) => a > b ? a : b).toDouble();
    final height = (data.length * 44.0).clamp(200.0, 360.0);

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: maxY <= 0 ? 1 : maxY * 1.15,
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
          gridData: FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          barGroups: [
            for (var i = 0; i < data.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: data[i].count.toDouble(),
                    width: 16,
                    color: barColor,
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

class _DailyKmLineChart extends StatelessWidget {
  const _DailyKmLineChart({required this.data});

  final List<DailyKmPoint> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty || data.every((item) => item.km <= 0)) {
      return const _EmptyChart(message: 'Sem km registrados por dia neste periodo.');
    }

    final spots = [
      for (var i = 0; i < data.length; i++) FlSpot(i.toDouble(), data[i].km),
    ];
    final maxY = data.map((e) => e.km).reduce((a, b) => a > b ? a : b);

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY <= 0 ? 1 : maxY * 1.2,
          gridData: FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                getTitlesWidget: (value, meta) => Text('${value.toInt()}', style: const TextStyle(fontSize: 10)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: data.length > 7 ? (data.length / 4).ceilToDouble() : 1,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= data.length) return const SizedBox.shrink();
                  return Text(DateFormat('dd/MM').format(data[index].date), style: const TextStyle(fontSize: 10));
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: AppColors.statusMoving,
              barWidth: 3,
              dotData: FlDotData(show: data.length <= 14),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.statusMovingBg.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VehicleUsageDonutChart extends StatelessWidget {
  const _VehicleUsageDonutChart({required this.data});

  final List<NamedCount> data;

  static const _palette = [
    AppColors.primary,
    AppColors.statusMoving,
    Color(0xFF4B6FA8),
    Color(0xFF2F9E8F),
    Color(0xFF8B6BB1),
    Color(0xFFB08968),
    Color(0xFF6B7280),
  ];

  @override
  Widget build(BuildContext context) {
    final active = data.where((item) => item.count > 0).toList();
    if (active.isEmpty) {
      return const _EmptyChart(message: 'Sem utilizacoes para calcular participacao.');
    }

    final total = active.fold<int>(0, (sum, item) => sum + item.count);

    return Column(
      children: [
        SizedBox(
          height: 220,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 42,
              sections: [
                for (var i = 0; i < active.length; i++)
                  PieChartSectionData(
                    value: active[i].count.toDouble(),
                    color: _palette[i % _palette.length],
                    title: '${((active[i].count / total) * 100).round()}%',
                    radius: 58,
                    titleStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (var i = 0; i < active.length; i++)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: _palette[i % _palette.length], shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('${active[i].name} (${active[i].count})', style: const TextStyle(fontSize: 12)),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _ChartGuideCard extends StatelessWidget {
  const _ChartGuideCard();

  @override
  Widget build(BuildContext context) {
    return CorporateSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          CorporateSectionTitle(title: 'Qual grafico usar?'),
          SizedBox(height: 8),
          _GuideRow(icon: Icons.bar_chart, label: 'Barras horizontais', detail: 'Ranking — km, tempo ou quantidade por pessoa/veiculo'),
          _GuideRow(icon: Icons.show_chart, label: 'Linha', detail: 'Evolucao diaria de km ao longo do tempo'),
          _GuideRow(icon: Icons.donut_large, label: 'Rosca (donut)', detail: 'Participacao percentual de cada veiculo no total'),
        ],
      ),
    );
  }
}

class _GuideRow extends StatelessWidget {
  const _GuideRow({required this.icon, required this.label, required this.detail});

  final IconData icon;
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, height: 1.35),
                children: [
                  TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: detail, style: const TextStyle(color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        ],
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
      child: Center(child: Text(message, style: const TextStyle(color: AppColors.textSecondary), textAlign: TextAlign.center)),
    );
  }
}

String _formatDuration(Duration duration) {
  if (duration.inMinutes <= 0) return '0 min';
  if (duration.inHours >= 1) return '${duration.inHours}h ${duration.inMinutes.remainder(60)}min';
  return '${duration.inMinutes} min';
}
