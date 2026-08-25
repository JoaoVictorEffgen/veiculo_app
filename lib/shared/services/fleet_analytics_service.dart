import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../models/fleet_analytics.dart';

class FleetAnalyticsService {
  FleetAnalyticsReport compute({
    required List<Movement> movements,
    required List<Vehicle> vehicles,
    required List<AppUser> drivers,
    required List<FleetAdminAlert> taskAlerts,
    required List<DriverIssueReport> driverReports,
    required FleetPeriodSelection periodSelection,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final period = periodSelection.resolveRange(now: current);
    final inPeriod = movements.where((m) => _inRange(m.createdAt, period)).toList();
    final alertsInPeriod = taskAlerts.where((alert) {
      if (alert.responseStatus != AnnouncementResponseStatus.completed) return false;
      return _inRange(alert.createdAt, period);
    }).toList();
    final reportsInPeriod = driverReports.where((report) => _inRange(report.createdAt, period)).toList();

    final utilizationByVehicle = _utilizationByVehicle(inPeriod, vehicles);
    final movingTimeByDriver = _movingTimeByDriver(movements, drivers, period, current);
    final kmByDriver = _kmByDriver(inPeriod, drivers);
    final kmByVehicle = _kmByVehicle(inPeriod, vehicles);
    final dailyKmTrend = _dailyKmTrend(inPeriod, period);
    final tasksCompletedByDriver = _tasksCompletedByDriver(alertsInPeriod, drivers);
    final totalKm = kmByDriver.fold<double>(0, (sum, item) => sum + item.km);

    final tripSpeedRecords = _tripSpeedRecords(movements, period);
    final avgSpeedByDriver = _avgSpeedByDriver(tripSpeedRecords, drivers);
    final hourlySpeedByDriver = _hourlySpeedByDriver(tripSpeedRecords);

    NamedCount? topVehicle;
    if (utilizationByVehicle.isNotEmpty && utilizationByVehicle.first.count > 0) {
      topVehicle = utilizationByVehicle.first;
    }

    NamedDuration? topDriver;
    if (movingTimeByDriver.isNotEmpty && movingTimeByDriver.first.duration > Duration.zero) {
      topDriver = movingTimeByDriver.first;
    }

    NamedKm? topDriverByKm;
    if (kmByDriver.isNotEmpty && kmByDriver.first.km > 0) {
      topDriverByKm = kmByDriver.first;
    }

    NamedCount? topTaskDriver;
    if (tasksCompletedByDriver.isNotEmpty && tasksCompletedByDriver.first.count > 0) {
      topTaskDriver = tasksCompletedByDriver.first;
    }

    NamedSpeed? topDriverBySpeed;
    final activeSpeeds = avgSpeedByDriver.where((item) => item.avgSpeedKmh > 0).toList();
    if (activeSpeeds.isNotEmpty) {
      topDriverBySpeed = activeSpeeds.first;
    }

    return FleetAnalyticsReport(
      period: period,
      utilizationByVehicle: utilizationByVehicle,
      movingTimeByDriver: movingTimeByDriver,
      kmByDriver: kmByDriver,
      kmByVehicle: kmByVehicle,
      dailyKmTrend: dailyKmTrend,
      totalKm: totalKm,
      tasksCompletedByDriver: tasksCompletedByDriver,
      avgSpeedByDriver: avgSpeedByDriver,
      tripSpeedRecords: tripSpeedRecords,
      hourlySpeedByDriver: hourlySpeedByDriver,
      driverReportsInPeriod: reportsInPeriod,
      topVehicle: topVehicle,
      topDriver: topDriver,
      topDriverByKm: topDriverByKm,
      topTaskDriver: topTaskDriver,
      topDriverBySpeed: topDriverBySpeed,
    );
  }

  List<NamedCount> _tasksCompletedByDriver(List<FleetAdminAlert> alerts, List<AppUser> drivers) {
    final totals = <String, int>{for (final driver in drivers) driver.id: 0};
    for (final alert in alerts) {
      totals.update(alert.driverId, (value) => value + 1, ifAbsent: () => 1);
    }

    return drivers
        .map((driver) => NamedCount(id: driver.id, name: driver.name, count: totals[driver.id] ?? 0))
        .toList()
      ..sort((a, b) => b.count.compareTo(a.count));
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

  List<NamedKm> _kmByDriver(List<Movement> inPeriod, List<AppUser> drivers) {
    final totals = <String, double>{for (final driver in drivers) driver.id: 0};
    for (final movement in inPeriod) {
      if (movement.action != MovementAction.off) continue;
      final km = movement.distanceKm ?? 0;
      if (km <= 0) continue;
      totals.update(movement.driverId, (value) => value + km, ifAbsent: () => km);
    }

    return drivers
        .map((driver) => NamedKm(id: driver.id, name: driver.name, km: totals[driver.id] ?? 0))
        .toList()
      ..sort((a, b) => b.km.compareTo(a.km));
  }

  List<NamedKm> _kmByVehicle(List<Movement> inPeriod, List<Vehicle> vehicles) {
    final totals = <String, double>{for (final vehicle in vehicles) vehicle.id: 0};
    for (final movement in inPeriod) {
      if (movement.action != MovementAction.off) continue;
      final km = movement.distanceKm ?? 0;
      if (km <= 0) continue;
      totals.update(movement.vehicleId, (value) => value + km, ifAbsent: () => km);
    }

    return vehicles
        .map((vehicle) => NamedKm(id: vehicle.id, name: vehicle.name, km: totals[vehicle.id] ?? 0))
        .toList()
      ..sort((a, b) => b.km.compareTo(a.km));
  }

  List<DailyKmPoint> _dailyKmTrend(List<Movement> inPeriod, DateTimeRange period) {
    final buckets = <DateTime, double>{};
    var day = DateTime(period.start.year, period.start.month, period.start.day);
    final endDay = DateTime(period.end.year, period.end.month, period.end.day);
    while (!day.isAfter(endDay)) {
      buckets[day] = 0;
      day = day.add(const Duration(days: 1));
    }

    for (final movement in inPeriod) {
      if (movement.action != MovementAction.off) continue;
      final km = movement.distanceKm ?? 0;
      if (km <= 0) continue;
      final key = DateTime(movement.createdAt.year, movement.createdAt.month, movement.createdAt.day);
      if (buckets.containsKey(key)) {
        buckets[key] = (buckets[key] ?? 0) + km;
      }
    }

    return buckets.entries
        .map((entry) => DailyKmPoint(date: entry.key, km: entry.value))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  List<NamedDuration> _movingTimeByDriver(
    List<Movement> allMovements,
    List<AppUser> drivers,
    DateTimeRange period,
    DateTime now,
  ) {
    final totals = <String, Duration>{for (final driver in drivers) driver.id: Duration.zero};

    for (final driver in drivers) {
      final driverMovements = allMovements.where((m) => m.driverId == driver.id).toList();
      totals[driver.id] = _movingDurationForDriver(driverMovements, period, now);
    }

    return drivers
        .map((driver) => NamedDuration(id: driver.id, name: driver.name, duration: totals[driver.id] ?? Duration.zero))
        .toList()
      ..sort((a, b) => b.duration.compareTo(a.duration));
  }

  Duration _movingDurationForDriver(List<Movement> movements, DateTimeRange period, DateTime now) {
    if (movements.isEmpty) return Duration.zero;

    final sorted = [...movements]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    var total = Duration.zero;

    for (var i = 0; i < sorted.length; i++) {
      final on = sorted[i];
      if (on.action != MovementAction.on) continue;

      final start = on.createdAt.isBefore(period.start) ? period.start : on.createdAt;
      DateTime end = period.end;

      Movement? off;
      for (var j = i + 1; j < sorted.length; j++) {
        if (sorted[j].vehicleId == on.vehicleId && sorted[j].action == MovementAction.off) {
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

  List<TripSpeedRecord> _tripSpeedRecords(List<Movement> allMovements, DateTimeRange period) {
    final records = <TripSpeedRecord>[];
    final sorted = [...allMovements]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    for (var i = 0; i < sorted.length; i++) {
      final on = sorted[i];
      if (on.action != MovementAction.on) continue;

      Movement? off;
      for (var j = i + 1; j < sorted.length; j++) {
        if (sorted[j].vehicleId == on.vehicleId && sorted[j].action == MovementAction.off) {
          off = sorted[j];
          break;
        }
      }
      if (off == null) continue;

      final km = off.distanceKm ?? 0;
      if (km <= 0) continue;

      final startedAt = on.createdAt;
      final endedAt = off.createdAt;
      if (!endedAt.isAfter(startedAt)) continue;
      if (endedAt.isBefore(period.start) || startedAt.isAfter(period.end)) continue;

      final hours = endedAt.difference(startedAt).inSeconds / 3600.0;
      if (hours <= 0) continue;

      records.add(
        TripSpeedRecord(
          driverId: on.driverId,
          driverName: on.driverName,
          vehicleName: on.vehicleName,
          startedAt: startedAt,
          endedAt: endedAt,
          distanceKm: km,
          avgSpeedKmh: km / hours,
        ),
      );
    }

    records.sort((a, b) => b.endedAt.compareTo(a.endedAt));
    return records;
  }

  List<NamedSpeed> _avgSpeedByDriver(List<TripSpeedRecord> trips, List<AppUser> drivers) {
    final kmTotals = <String, double>{for (final driver in drivers) driver.id: 0};
    final hourTotals = <String, double>{for (final driver in drivers) driver.id: 0};

    for (final trip in trips) {
      final hours = trip.endedAt.difference(trip.startedAt).inSeconds / 3600.0;
      if (hours <= 0) continue;
      kmTotals.update(trip.driverId, (value) => value + trip.distanceKm, ifAbsent: () => trip.distanceKm);
      hourTotals.update(trip.driverId, (value) => value + hours, ifAbsent: () => hours);
    }

    return drivers
        .map((driver) {
          final km = kmTotals[driver.id] ?? 0;
          final hours = hourTotals[driver.id] ?? 0;
          final avg = hours > 0 ? km / hours : 0.0;
          return NamedSpeed(
            id: driver.id,
            name: driver.name,
            avgSpeedKmh: avg,
            totalKm: km,
            movingTime: Duration(seconds: (hours * 3600).round()),
          );
        })
        .toList()
      ..sort((a, b) => b.avgSpeedKmh.compareTo(a.avgSpeedKmh));
  }

  List<DriverHourlySpeed> _hourlySpeedByDriver(List<TripSpeedRecord> trips) {
    final kmBuckets = <String, double>{};
    final hourBuckets = <String, double>{};
    final meta = <String, ({String driverId, String driverName, DateTime hourStart})>{};

    for (final trip in trips) {
      final totalMs = trip.endedAt.difference(trip.startedAt).inMilliseconds;
      if (totalMs <= 0) continue;

      var cursor = trip.startedAt;
      final end = trip.endedAt;

      while (cursor.isBefore(end)) {
        final hourStart = DateTime(cursor.year, cursor.month, cursor.day, cursor.hour);
        final hourEnd = hourStart.add(const Duration(hours: 1));
        final segmentEnd = end.isBefore(hourEnd) ? end : hourEnd;
        final segmentMs = segmentEnd.difference(cursor).inMilliseconds;
        if (segmentMs <= 0) break;

        final fraction = segmentMs / totalMs;
        final segmentKm = trip.distanceKm * fraction;
        final segmentHours = segmentMs / 3600000.0;
        final key = '${trip.driverId}_${hourStart.millisecondsSinceEpoch}';

        kmBuckets[key] = (kmBuckets[key] ?? 0) + segmentKm;
        hourBuckets[key] = (hourBuckets[key] ?? 0) + segmentHours;
        meta[key] = (driverId: trip.driverId, driverName: trip.driverName, hourStart: hourStart);

        cursor = segmentEnd;
      }
    }

    final results = <DriverHourlySpeed>[];
    for (final entry in kmBuckets.entries) {
      final info = meta[entry.key];
      if (info == null) continue;
      final hours = hourBuckets[entry.key] ?? 0;
      if (hours <= 0 || entry.value <= 0) continue;
      results.add(
        DriverHourlySpeed(
          driverId: info.driverId,
          driverName: info.driverName,
          hourStart: info.hourStart,
          km: entry.value,
          avgSpeedKmh: entry.value / hours,
        ),
      );
    }

    results.sort((a, b) => b.hourStart.compareTo(a.hourStart));
    return results;
  }

  bool _inRange(DateTime value, DateTimeRange range) {
    return !value.isBefore(range.start) && !value.isAfter(range.end);
  }
}
