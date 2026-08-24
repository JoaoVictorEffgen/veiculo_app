import '../models/app_models.dart';

abstract class VehicleRepository {
  AppUser? get currentUser;
  Stream<AppUser?> get authStateChanges;

  Future<String?> login(String email, String password);
  Future<String?> sendPasswordResetEmail(String email);
  Future<void> logout();

  Stream<List<Vehicle>> watchVehicles();
  Future<List<Vehicle>> fetchVehicles();
  Stream<List<Movement>> watchMovements();
  Stream<List<AppUser>> watchUsers();
  Stream<List<DriverTrack>> watchDriverTracks();

  Stream<List<FleetAnnouncement>> watchAnnouncementsForUser(AppUser user);
  Future<String?> publishAnnouncement(
    AppUser actor, {
    required String message,
    DateTime? expiresAt,
    String? targetDriverId,
    String? targetDriverName,
  });
  Future<String?> deleteAnnouncement(AppUser actor, String announcementId);
  Future<String?> respondToAnnouncement(
    AppUser driver,
    String announcementId,
    AnnouncementResponseStatus status, {
    String? rejectionReason,
  });
  Stream<List<FleetAdminAlert>> watchAdminAlerts();
  Future<void> markAdminAlertsViewed(AppUser admin);
  Future<void> saveFcmToken(AppUser user, String token);

  Future<String?> startVehicle(String vehicleId, AppUser user);

  Future<VehicleChecklist?> getTodayChecklist(AppUser driver, String vehicleId);
  Future<String?> saveVehicleChecklist(
    AppUser driver,
    Vehicle vehicle, {
    required Map<String, bool> items,
    String? notes,
    required String signatureBase64,
  });
  Stream<List<VehicleChecklist>> watchTodayChecklistsForDriver(AppUser driver);
  Stream<List<VehicleChecklist>> watchVehicleChecklists(AppUser user);
  Future<String?> stopVehicle(String vehicleId, AppUser user, String location, {double? distanceKm});

  Future<String?> addVehicle(AppUser actor, {required String name, required String model, required String plate});
  Future<String?> editVehicle(AppUser actor, {required String vehicleId, required String name, required String model, required String plate});
  Future<String?> deleteVehicle(AppUser actor, String vehicleId);
  Future<String?> uploadMaintenancePlan(AppUser actor, String vehicleId, List<int> bytes, String fileName);
  Future<String?> removeMaintenancePlan(AppUser actor, String vehicleId);
  Future<String?> addDriver(AppUser actor, {required String name, required String email, required String password});
  Future<String?> editDriver(AppUser actor, {required String driverId, required String name, required String email, String? password});
  Future<String?> deleteDriver(AppUser actor, String driverId);

  Future<void> purgeOrphanedTracking(List<String> driverIds);

  Future<void> ensureSeedData();
}
