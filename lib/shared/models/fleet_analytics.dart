import 'package:flutter/material.dart';

enum FleetPeriodPreset {
  today('Hoje'),
  last7Days('Ultimos 7 dias'),
  last30Days('Ultimos 30 dias'),
  thisMonth('Este mes'),
  lastMonth('Mes anterior'),
  last3Months('Ultimos 3 meses'),
  custom('Periodo personalizado');

  const FleetPeriodPreset(this.label);
  final String label;
}

class FleetPeriodSelection {
  const FleetPeriodSelection({
    required this.preset,
    this.customStart,
    this.customEnd,
  });

  final FleetPeriodPreset preset;
  final DateTime? customStart;
  final DateTime? customEnd;

  FleetPeriodSelection copyWith({
    FleetPeriodPreset? preset,
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    return FleetPeriodSelection(
      preset: preset ?? this.preset,
      customStart: customStart ?? this.customStart,
      customEnd: customEnd ?? this.customEnd,
    );
  }

  DateTimeRange resolveRange({DateTime? now}) {
    final current = now ?? DateTime.now();
    final startOfDay = DateTime(current.year, current.month, current.day);

    switch (preset) {
      case FleetPeriodPreset.today:
        return DateTimeRange(start: startOfDay, end: current);
      case FleetPeriodPreset.last7Days:
        return DateTimeRange(start: startOfDay.subtract(const Duration(days: 6)), end: current);
      case FleetPeriodPreset.last30Days:
        return DateTimeRange(start: startOfDay.subtract(const Duration(days: 29)), end: current);
      case FleetPeriodPreset.thisMonth:
        return DateTimeRange(start: DateTime(current.year, current.month, 1), end: current);
      case FleetPeriodPreset.lastMonth:
        final firstThisMonth = DateTime(current.year, current.month, 1);
        final lastMonthEnd = firstThisMonth.subtract(const Duration(days: 1));
        return DateTimeRange(
          start: DateTime(lastMonthEnd.year, lastMonthEnd.month, 1),
          end: DateTime(lastMonthEnd.year, lastMonthEnd.month, lastMonthEnd.day, 23, 59, 59),
        );
      case FleetPeriodPreset.last3Months:
        return DateTimeRange(start: DateTime(current.year, current.month - 2, 1), end: current);
      case FleetPeriodPreset.custom:
        final start = customStart ?? startOfDay.subtract(const Duration(days: 29));
        final end = customEnd ?? current;
        return DateTimeRange(start: start, end: end.isBefore(start) ? start : end);
    }
  }
}

class FleetSummary {
  const FleetSummary({
    required this.totalVehicles,
    required this.movingVehicles,
    required this.stoppedVehicles,
    required this.availableVehicles,
    required this.totalDrivers,
    required this.utilizationRate,
    required this.availabilityRate,
  });

  final int totalVehicles;
  final int movingVehicles;
  final int stoppedVehicles;
  final int availableVehicles;
  final int totalDrivers;
  final double utilizationRate;
  final double availabilityRate;
}

class NamedCount {
  const NamedCount({required this.id, required this.name, required this.count});
  final String id;
  final String name;
  final int count;
}

class VehicleTimeShare {
  const VehicleTimeShare({
    required this.vehicleId,
    required this.vehicleName,
    required this.movingPercent,
    required this.stoppedPercent,
    required this.movingDuration,
    required this.stoppedDuration,
  });

  final String vehicleId;
  final String vehicleName;
  final double movingPercent;
  final double stoppedPercent;
  final Duration movingDuration;
  final Duration stoppedDuration;
}

class TimeSeriesPoint {
  const TimeSeriesPoint({required this.label, required this.count});
  final String label;
  final int count;
}

class FleetHighlights {
  const FleetHighlights({
    this.mostUsedVehicle,
    this.leastUsedVehicle,
    this.topDriver,
    required this.averageTripDuration,
    required this.averageStoppedDuration,
  });

  final NamedCount? mostUsedVehicle;
  final NamedCount? leastUsedVehicle;
  final NamedCount? topDriver;
  final Duration averageTripDuration;
  final Duration averageStoppedDuration;
}

class FleetAlert {
  const FleetAlert({required this.message, required this.level});
  final String message;
  final FleetAlertLevel level;
}

enum FleetAlertLevel { info, warning }

class FleetAnalyticsReport {
  const FleetAnalyticsReport({
    required this.period,
    required this.summary,
    required this.utilizationByVehicle,
    required this.utilizationByDriver,
    required this.timeShareByVehicle,
    required this.movementsOverTime,
    required this.highlights,
    required this.alerts,
  });

  final DateTimeRange period;
  final FleetSummary summary;
  final List<NamedCount> utilizationByVehicle;
  final List<NamedCount> utilizationByDriver;
  final List<VehicleTimeShare> timeShareByVehicle;
  final List<TimeSeriesPoint> movementsOverTime;
  final FleetHighlights highlights;
  final List<FleetAlert> alerts;
}
