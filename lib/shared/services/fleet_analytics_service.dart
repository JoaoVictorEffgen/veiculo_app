import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../models/fleet_analytics.dart';

abstract final class FleetAnalyticsConfig {
  static const idleAlertHours = 24;
  static const lowUtilizationThreshold = 5;
  static const lowUtilizationWindowDays = 30;
}

class FleetAnalyticsService {
  FleetAnalyticsReport compute({
    required List<Movement> movements,
    required List<Vehicle> vehicles,
    required List<AppUser> drivers,
    required FleetPeriodSelection periodSelection,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final period = periodSelection.resolveRange(now: current);
    final inPeriod = movements.where((m) => _inRange(m.createdAt, period)).toList();

    final utilizationByVehicle = _utilizationByVehicle(inPeriod, vehicles);
    final utilizationByDriver = _utilizationByDriver(inPeriod, drivers);
    final timeShareByVehicle = _timeShareByVehicle(movements, vehicles, period, current);
    final movementsOverTime = _movementsOverTime(inPeriod, period);
    final highlights = _highlights(inPeriod, utilizationByVehicle, utilizationByDriver, movements, period, current);
    final summary = _summary(vehicles, drivers, timeShareByVehicle);
    final alerts = _alerts(
      vehicles: vehicles,
      utilizationByVehicle: utilizationByVehicle,
      allMovements: movements,
      period: period,
      now: current,
    );

    return FleetAnalyticsReport(
      period: period,
      summary: summary,
      utilizationByVehicle: utilizationByVehicle,
      utilizationByDriver: utilizationByDriver,
      timeShareByVehicle: timeShareByVehicle,
      movementsOverTime: movementsOverTime,
      highlights: highlights,
      alerts: alerts,
    );
  }

  FleetSummary _summary(List<Vehicle> vehicles, List<AppUser> drivers, List<VehicleTimeShare> timeShares) {
    final moving = vehicles.where((v) => v.status == VehicleStatus.moving).length;
    final stopped = vehicles.length - moving;
    final available = vehicles.where((v) => v.status == VehicleStatus.stopped).length;

    final avgMoving = timeShares.isEmpty
        ? 0.0
        : timeShares.map((e) => e.movingPercent).reduce((a, b) => a + b) / timeShares.length;
    final availabilityRate = vehicles.isEmpty ? 0.0 : (available / vehicles.length) * 100;

    return FleetSummary(
      totalVehicles: vehicles.length,
      movingVehicles: moving,
      stoppedVehicles: stopped,
      availableVehicles: available,
      totalDrivers: drivers.length,
      utilizationRate: avgMoving,
      availabilityRate: availabilityRate,
    );
  }

  List<NamedCount> _utilizationByVehicle(List<Movement> inPeriod, List<Vehicle> vehicles) {
    final counts = <String, int>{for (final v in vehicles) v.id: 0};
    for (final movement in inPeriod) {
      if (movement.action != MovementAction.on) continue;
      counts.update(movement.vehicleId, (value) => value + 1, ifAbsent: () => 1);
    }

    return vehicles
        .map((vehicle) => NamedCount(id: vehicle.id, name: vehicle.name, count: counts[vehicle.id] ?? 0))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
  }

  List<NamedCount> _utilizationByDriver(List<Movement> inPeriod, List<AppUser> drivers) {
    final counts = <String, int>{for (final d in drivers) d.id: 0};
    for (final movement in inPeriod) {
      if (movement.action != MovementAction.on) continue;
      counts.update(movement.driverId, (value) => value + 1, ifAbsent: () => 1);
    }

    return drivers
        .map((driver) => NamedCount(id: driver.id, name: driver.name, count: counts[driver.id] ?? 0))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
  }

  List<VehicleTimeShare> _timeShareByVehicle(
    List<Movement> allMovements,
    List<Vehicle> vehicles,
    DateTimeRange period,
    DateTime now,
  ) {
    final periodDuration = period.end.difference(period.start);
    if (periodDuration.inSeconds <= 0) return [];

    return vehicles.map((vehicle) {
      final movingDuration = _movingDurationForVehicle(
        allMovements.where((m) => m.vehicleId == vehicle.id).toList(),
        period,
        now,
      );
      final clampedMoving = movingDuration > periodDuration ? periodDuration : movingDuration;
      final stoppedDuration = periodDuration - clampedMoving;
      final movingPercent = (clampedMoving.inSeconds / periodDuration.inSeconds) * 100;
      final stoppedPercent = 100 - movingPercent;

      return VehicleTimeShare(
        vehicleId: vehicle.id,
        vehicleName: vehicle.name,
        movingPercent: movingPercent,
        stoppedPercent: stoppedPercent,
        movingDuration: clampedMoving,
        stoppedDuration: stoppedDuration,
      );
    }).toList()
      ..sort((a, b) => b.movingPercent.compareTo(a.movingPercent));
  }

  Duration _movingDurationForVehicle(List<Movement> movements, DateTimeRange period, DateTime now) {
    if (movements.isEmpty) return Duration.zero;

    final sorted = [...movements]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    var total = Duration.zero;

    for (var i = 0; i < sorted.length; i++) {
      final movement = sorted[i];
      if (movement.action != MovementAction.on) continue;

      final start = movement.createdAt.isBefore(period.start) ? period.start : movement.createdAt;
      DateTime end = period.end;

      Movement? off;
      for (var j = i + 1; j < sorted.length; j++) {
        if (sorted[j].action == MovementAction.off) {
          off = sorted[j];
          break;
        }
      }

      if (off != null) {
        end = off.createdAt.isAfter(period.end) ? period.end : off.createdAt;
      } else if (start.isBefore(now) && now.isBefore(period.end)) {
        end = now;
      }

      if (end.isAfter(start)) {
        total += end.difference(start);
      }
    }

    return total;
  }

  List<TimeSeriesPoint> _movementsOverTime(List<Movement> inPeriod, DateTimeRange period) {
    final onMovements = inPeriod.where((m) => m.action == MovementAction.on).toList();
    if (onMovements.isEmpty) return [];

    final spanDays = period.end.difference(period.start).inDays + 1;
    if (spanDays <= 45) {
      final buckets = <DateTime, int>{};
      for (final movement in onMovements) {
        final day = DateTime(movement.createdAt.year, movement.createdAt.month, movement.createdAt.day);
        buckets.update(day, (value) => value + 1, ifAbsent: () => 1);
      }
      final days = buckets.keys.toList()..sort();
      return days
          .map(
            (day) => TimeSeriesPoint(
              label: '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}',
              count: buckets[day]!,
            ),
          )
          .toList();
    }

    if (spanDays <= 120) {
      final buckets = <String, int>{};
      for (final movement in onMovements) {
        final weekStart = movement.createdAt.subtract(Duration(days: movement.createdAt.weekday - 1));
        final key = '${weekStart.day}/${weekStart.month}';
        buckets.update(key, (value) => value + 1, ifAbsent: () => 1);
      }
      return buckets.entries.map((e) => TimeSeriesPoint(label: e.key, count: e.value)).toList();
    }

    final buckets = <String, int>{};
    for (final movement in onMovements) {
      final key = '${movement.createdAt.month.toString().padLeft(2, '0')}/${movement.createdAt.year}';
      buckets.update(key, (value) => value + 1, ifAbsent: () => 1);
    }
    return buckets.entries.map((e) => TimeSeriesPoint(label: e.key, count: e.value)).toList();
  }

  FleetHighlights _highlights(
    List<Movement> inPeriod,
    List<NamedCount> byVehicle,
    List<NamedCount> byDriver,
    List<Movement> allMovements,
    DateTimeRange period,
    DateTime now,
  ) {
    final trips = <Duration>[];
    final sorted = [...allMovements]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    for (var i = 0; i < sorted.length; i++) {
      final on = sorted[i];
      if (on.action != MovementAction.on) continue;
      for (var j = i + 1; j < sorted.length; j++) {
        if (sorted[j].vehicleId == on.vehicleId && sorted[j].action == MovementAction.off) {
          final duration = sorted[j].createdAt.difference(on.createdAt);
          if (_overlapsPeriod(on.createdAt, sorted[j].createdAt, period)) {
            trips.add(duration);
          }
          break;
        }
      }
    }

    final avgTrip = trips.isEmpty
        ? Duration.zero
        : Duration(milliseconds: (trips.map((d) => d.inMilliseconds).reduce((a, b) => a + b) / trips.length).round());

    final stopDurations = <Duration>[];
    for (var i = 0; i < sorted.length; i++) {
      final off = sorted[i];
      if (off.action != MovementAction.off) continue;
      for (var j = i + 1; j < sorted.length; j++) {
        if (sorted[j].vehicleId == off.vehicleId && sorted[j].action == MovementAction.on) {
          stopDurations.add(sorted[j].createdAt.difference(off.createdAt));
          break;
        }
      }
    }

    final avgStop = stopDurations.isEmpty
        ? Duration.zero
        : Duration(
            milliseconds: (stopDurations.map((d) => d.inMilliseconds).reduce((a, b) => a + b) / stopDurations.length).round(),
          );

    NamedCount? mostUsed;
    NamedCount? leastUsed;
    if (byVehicle.isNotEmpty) {
      mostUsed = byVehicle.first;
      leastUsed = byVehicle.last;
      if (byVehicle.every((item) => item.count == 0)) {
        mostUsed = null;
        leastUsed = null;
      }
    }

    return FleetHighlights(
      mostUsedVehicle: mostUsed,
      leastUsedVehicle: leastUsed,
      topDriver: byDriver.isEmpty || byDriver.first.count == 0 ? null : byDriver.first,
      averageTripDuration: avgTrip,
      averageStoppedDuration: avgStop,
    );
  }

  List<FleetAlert> _alerts({
    required List<Vehicle> vehicles,
    required List<NamedCount> utilizationByVehicle,
    required List<Movement> allMovements,
    required DateTimeRange period,
    required DateTime now,
  }) {
    final alerts = <FleetAlert>[];

    for (final vehicle in vehicles) {
      if (vehicle.status != VehicleStatus.stopped || vehicle.stoppedAt == null) continue;
      final idle = now.difference(vehicle.stoppedAt!);
      if (idle.inHours >= FleetAnalyticsConfig.idleAlertHours) {
        alerts.add(
          FleetAlert(
            message: '${vehicle.name} esta parada ha ${idle.inHours} horas',
            level: FleetAlertLevel.warning,
          ),
        );
      }
    }

    final windowStart = now.subtract(const Duration(days: FleetAnalyticsConfig.lowUtilizationWindowDays));
    for (final vehicle in vehicles) {
      final count = allMovements
          .where(
            (m) =>
                m.vehicleId == vehicle.id &&
                m.action == MovementAction.on &&
                !m.createdAt.isBefore(windowStart) &&
                !m.createdAt.isAfter(now),
          )
          .length;
      if (count <= FleetAnalyticsConfig.lowUtilizationThreshold) {
        alerts.add(
          FleetAlert(
            message: '${vehicle.name} apresentou baixa utilizacao nos ultimos ${FleetAnalyticsConfig.lowUtilizationWindowDays} dias ($count)',
            level: FleetAlertLevel.warning,
          ),
        );
      }
    }

    if (utilizationByVehicle.isNotEmpty && utilizationByVehicle.first.count > 0) {
      alerts.add(
        FleetAlert(
          message: '${utilizationByVehicle.first.name} foi o veiculo mais utilizado no periodo (${utilizationByVehicle.first.count})',
          level: FleetAlertLevel.info,
        ),
      );
    }

    return alerts;
  }

  bool _inRange(DateTime value, DateTimeRange range) {
    return !value.isBefore(range.start) && !value.isAfter(range.end);
  }

  bool _overlapsPeriod(DateTime start, DateTime end, DateTimeRange period) {
    return !end.isBefore(period.start) && !start.isAfter(period.end);
  }
}
