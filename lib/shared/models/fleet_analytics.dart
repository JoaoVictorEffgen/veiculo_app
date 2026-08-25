import 'package:flutter/material.dart';

import 'app_models.dart';

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

class NamedCount {
  const NamedCount({required this.id, required this.name, required this.count});
  final String id;
  final String name;
  final int count;
}

class NamedDuration {
  const NamedDuration({required this.id, required this.name, required this.duration});
  final String id;
  final String name;
  final Duration duration;
}

class NamedKm {
  const NamedKm({required this.id, required this.name, required this.km});
  final String id;
  final String name;
  final double km;
}

class NamedSpeed {
  const NamedSpeed({
    required this.id,
    required this.name,
    required this.avgSpeedKmh,
    required this.totalKm,
    required this.movingTime,
  });

  final String id;
  final String name;
  final double avgSpeedKmh;
  final double totalKm;
  final Duration movingTime;
}

class TripSpeedRecord {
  const TripSpeedRecord({
    required this.driverId,
    required this.driverName,
    required this.vehicleName,
    required this.startedAt,
    required this.endedAt,
    required this.distanceKm,
    required this.avgSpeedKmh,
  });

  final String driverId;
  final String driverName;
  final String vehicleName;
  final DateTime startedAt;
  final DateTime endedAt;
  final double distanceKm;
  final double avgSpeedKmh;
}

class DriverHourlySpeed {
  const DriverHourlySpeed({
    required this.driverId,
    required this.driverName,
    required this.hourStart,
    required this.km,
    required this.avgSpeedKmh,
  });

  final String driverId;
  final String driverName;
  final DateTime hourStart;
  final double km;
  final double avgSpeedKmh;
}

class DailyKmPoint {
  const DailyKmPoint({required this.date, required this.km});
  final DateTime date;
  final double km;
}

class FleetAnalyticsReport {
  const FleetAnalyticsReport({
    required this.period,
    required this.utilizationByVehicle,
    required this.movingTimeByDriver,
    required this.kmByDriver,
    required this.kmByVehicle,
    required this.dailyKmTrend,
    required this.totalKm,
    required this.tasksCompletedByDriver,
    required this.avgSpeedByDriver,
    required this.tripSpeedRecords,
    required this.hourlySpeedByDriver,
    required this.driverReportsInPeriod,
    required this.topVehicle,
    required this.topDriver,
    required this.topDriverByKm,
    required this.topTaskDriver,
    required this.topDriverBySpeed,
  });

  final DateTimeRange period;
  final List<NamedCount> utilizationByVehicle;
  final List<NamedDuration> movingTimeByDriver;
  final List<NamedKm> kmByDriver;
  final List<NamedKm> kmByVehicle;
  final List<DailyKmPoint> dailyKmTrend;
  final double totalKm;
  final List<NamedCount> tasksCompletedByDriver;
  final List<NamedSpeed> avgSpeedByDriver;
  final List<TripSpeedRecord> tripSpeedRecords;
  final List<DriverHourlySpeed> hourlySpeedByDriver;
  final List<DriverIssueReport> driverReportsInPeriod;
  final NamedCount? topVehicle;
  final NamedDuration? topDriver;
  final NamedKm? topDriverByKm;
  final NamedCount? topTaskDriver;
  final NamedSpeed? topDriverBySpeed;
}
