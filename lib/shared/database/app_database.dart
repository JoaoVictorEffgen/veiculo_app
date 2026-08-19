import 'package:drift/drift.dart';

import 'connection/connection.dart';

part 'app_database.g.dart';

@DataClassName('UserRow')
class Users extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get email => text()();
  TextColumn get password => text()();
  TextColumn get role => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('VehicleRow')
class Vehicles extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get model => text()();
  TextColumn get plate => text()();
  TextColumn get status => text()();
  TextColumn get currentDriverId => text().nullable()();
  TextColumn get currentDriverName => text().nullable()();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get stoppedAt => dateTime().nullable()();
  TextColumn get stoppedLocation => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('MovementRow')
class Movements extends Table {
  TextColumn get id => text()();
  TextColumn get vehicleId => text()();
  TextColumn get vehicleName => text()();
  TextColumn get driverId => text()();
  TextColumn get driverName => text()();
  TextColumn get action => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get location => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(tables: [Users, Vehicles, Movements, AppSettings])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;
}
