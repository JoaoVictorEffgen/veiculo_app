import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;

import '../models/navigation_route.dart';

class GeocodingService {
  Future<ResolvedAddress?> resolveAddress(String query) async {
    final text = query.trim();
    if (text.isEmpty) return null;

    final fromPlugin = await _resolveWithGeocodingPlugin(text);
    if (fromPlugin != null) return fromPlugin;

    return _resolveWithNominatim(text);
  }

  Future<ResolvedAddress?> _resolveWithGeocodingPlugin(String query) async {
    try {
      final locations = await locationFromAddress(query);
      if (locations.isEmpty) return null;
      final location = locations.first;
      return ResolvedAddress(
        label: query,
        latitude: location.latitude,
        longitude: location.longitude,
      );
    } catch (error) {
      debugPrint('Geocoding plugin: $error');
      return null;
    }
  }

  Future<ResolvedAddress?> _resolveWithNominatim(String query) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'json',
        'limit': '1',
        'addressdetails': '0',
      });
      final response = await http.get(
        uri,
        headers: const {'User-Agent': 'DriveControlApp/1.0 (vehicle-control-app)'},
      );
      if (response.statusCode != 200) return null;

      final results = jsonDecode(response.body) as List<dynamic>;
      if (results.isEmpty) return null;

      final first = results.first as Map<String, dynamic>;
      final lat = double.tryParse(first['lat'] as String? ?? '');
      final lon = double.tryParse(first['lon'] as String? ?? '');
      if (lat == null || lon == null) return null;

      final displayName = first['display_name'] as String? ?? query;
      return ResolvedAddress(label: displayName, latitude: lat, longitude: lon);
    } catch (error) {
      debugPrint('Nominatim geocoding: $error');
      return null;
    }
  }
}
