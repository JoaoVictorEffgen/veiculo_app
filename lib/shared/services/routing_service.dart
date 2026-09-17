import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/navigation_route.dart';

class RoutingService {
  RoutingService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<NavigationRoutePlan> buildDrivingRoute({
    required LatLng origin,
    required ResolvedAddress destination,
  }) async {
    final coordinates = '${origin.longitude},${origin.latitude};'
        '${destination.longitude},${destination.latitude}';
    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/$coordinates'
      '?overview=full&geometries=geojson&steps=false',
    );

    try {
      final response = await _client.get(uri);
      if (response.statusCode != 200) {
        throw RoutingException('Servico de rotas indisponivel (${response.statusCode}).');
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (payload['code'] != 'Ok') {
        throw RoutingException('Nao foi possivel calcular a rota para esse destino.');
      }

      final routes = payload['routes'] as List<dynamic>;
      if (routes.isEmpty) {
        throw RoutingException('Nenhuma rota encontrada para esse destino.');
      }

      final route = routes.first as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>;
      final rawPoints = geometry['coordinates'] as List<dynamic>;
      final points = rawPoints
          .map((entry) {
            final pair = entry as List<dynamic>;
            return LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble());
          })
          .toList(growable: false);

      final distance = (route['distance'] as num?)?.toDouble() ?? 0;
      if (points.length < 2) {
        throw RoutingException('Rota invalida retornada pelo servico.');
      }

      return NavigationRoutePlan(
        destinationLabel: destination.label,
        points: points,
        totalDistanceMeters: distance,
      );
    } catch (error) {
      if (error is RoutingException) rethrow;
      debugPrint('RoutingService: $error');
      if (kIsWeb) {
        throw RoutingException(
          'Nao foi possivel calcular a rota no navegador. '
          'Teste com flutter run -d windows ou no celular.',
        );
      }
      throw RoutingException('Nao foi possivel calcular a rota. Verifique sua conexao.');
    }
  }

  void dispose() => _client.close();
}

class RoutingException implements Exception {
  RoutingException(this.message);

  final String message;

  @override
  String toString() => message;
}
