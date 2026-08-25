import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/fleet_analytics.dart';
import '../utils/date_formatter.dart';
import 'corporate_ui.dart';

class FleetPeriodFilter extends ConsumerWidget {
  const FleetPeriodFilter({
    super.key,
    required this.period,
    required this.onChanged,
    this.title = 'Filtro de periodo',
  });

  final FleetPeriodSelection period;
  final ValueChanged<FleetPeriodSelection> onChanged;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CorporateSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          DropdownButtonFormField<FleetPeriodPreset>(
            initialValue: period.preset,
            decoration: const InputDecoration(labelText: 'Periodo', prefixIcon: Icon(Icons.date_range)),
            items: FleetPeriodPreset.values
                .map((preset) => DropdownMenuItem(value: preset, child: Text(preset.label)))
                .toList(),
            onChanged: (preset) {
              if (preset == null) return;
              onChanged(period.copyWith(preset: preset));
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
                onChanged(
                  period.copyWith(
                    preset: FleetPeriodPreset.custom,
                    customStart: range.start,
                    customEnd: range.end,
                  ),
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

bool isDateInFleetPeriod(DateTime date, FleetPeriodSelection period, {DateTime? now}) {
  final range = period.resolveRange(now: now);
  return !date.isBefore(range.start) && !date.isAfter(range.end);
}
