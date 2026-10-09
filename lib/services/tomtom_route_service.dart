import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/env.dart';
import 'route_service.dart'
    show VehicleProfile, RouteResult, RouteStep, RoutePoint;

/// TomTom Routing API v1 istemcisi.
///
/// OSRM public sunucusunun kamyon (HGV) profili eksikliğini giderir.
/// Kamyon yükseklik, ağırlık, aks yükü gibi kısıtları destekler.
///
/// Kullanım:
///   final service = TomTomRouteService();
///   final route = await service.fetchRoute(
///     from: LatLng(52.52, 13.40),
///     to: LatLng(48.13, 11.58),
///     profile: VehicleProfile.truck,
///   );
class TomTomRouteService {
  // ============================================================
  // SABİTLER
  // ============================================================
  static const String _baseUrl =
      'https://api.tomtom.com/routing/1/calculateRoute';

  static const Duration _timeout = Duration(seconds: 30);

  /// TomTom v1 pratik nokta limiti
  static const int _maxLocations = 50;

  /// Öğretici dil (Almanya için Almanca)
  static const String _instructionLanguage = 'de-DE';

  // ============================================================
  // STATE
  // ============================================================
  final String _apiKey;

  TomTomRouteService({String? apiKey}) : _apiKey = apiKey ?? Env.tomtomApiKey {
    if (_apiKey.isEmpty) {
      throw StateError(
        'TOMTOM_API_KEY bulunamadı. '
        '.env dosyasına ekleyin veya --dart-define ile geçirin.',
      );
    }
  }

  // ============================================================
  // PUBLIC API
  // ============================================================

  /// İki nokta arasında rota (opsiyonel waypoint'lerle).
  Future<RouteResult> fetchRoute({
    required LatLng from,
    required LatLng to,
    required VehicleProfile profile,
    List<LatLng>? waypoints,
  }) async {
    final all = <LatLng>[from, ...?waypoints, to];
    final results = await _calculateRoute(all, profile);
    return results.first;
  }

  /// Çoklu durak (tur) rotası.
  Future<RouteResult> fetchMultiStopRoute({
    required LatLng start,
    required List<LatLng> stops,
    required VehicleProfile profile,
  }) async {
    if (stops.isEmpty) {
      throw Exception('En az bir durak gerekli');
    }
    final all = <LatLng>[start, ...stops];
    final results = await _calculateRoute(all, profile);
    return results.first;
  }

  /// Alternatif rotalar.
  Future<List<RouteResult>> fetchAlternativeRoutes({
    required LatLng from,
    required LatLng to,
    required VehicleProfile profile,
    int alternatives = 2,
  }) async {
    final all = <LatLng>[from, to];
    return _calculateRoute(all, profile, maxAlternatives: alternatives);
  }

  // ============================================================
  // CORE
  // ============================================================

  Future<List<RouteResult>> _calculateRoute(
    List<LatLng> locations,
    VehicleProfile profile, {
    int maxAlternatives = 0,
  }) async {
    if (locations.length < 2) {
      throw Exception('En az iki nokta gerekli');
    }
    if (locations.length > _maxLocations) {
      throw Exception(
        'Çok fazla nokta (${locations.length}). Maks: $_maxLocations',
      );
    }

    final url = _buildUrl(
      locations,
      profile,
      maxAlternatives: maxAlternatives,
    );

    debugPrint('🚚 TomTom isteği: ${locations.length} nokta, '
        'profil=${profile.type}');

    final http.Response response;
    try {
      response = await http.get(Uri.parse(url)).timeout(_timeout);
    } catch (e) {
      throw Exception('TomTom bağlantı hatası: $e');
    }

    // HTTP durum kodlarına göre anlamlı hata mesajları
    switch (response.statusCode) {
      case 200:
        break;
      case 400:
        throw Exception(
          'TomTom: Geçersiz istek. Parametreleri kontrol edin. '
          '(${response.body})',
        );
      case 401:
      case 403:
        throw Exception(
          'TomTom: API anahtarı geçersiz veya yetkisiz '
          '(${response.statusCode}). my.tomtom.com/keys adresinden '
          'kontrol edin.',
        );
      case 429:
        throw Exception(
          'TomTom: Günlük istek limiti aşıldı. Yarın tekrar deneyin.',
        );
      default:
        throw Exception(
          'TomTom API hatası: ${response.statusCode} - ${response.body}',
        );
    }

    final dynamic data = jsonDecode(response.body);
    if (data is! Map) {
      throw Exception('TomTom cevabı geçersiz JSON formatı');
    }

    // TomTom bazen 200 ile birlikte detailedError döner
    if (data['detailedError'] != null) {
      final err = data['detailedError'];
      final msg = err is Map ? err['message']?.toString() : err.toString();
      throw Exception('TomTom Error: ${msg ?? "bilinmeyen hata"}');
    }

    final results = _parseResponse(data);

    if (results.isEmpty) {
      throw Exception('TomTom geçerli rota döndürmedi');
    }

    debugPrint(
      '✅ TomTom: ${results.length} rota, '
      'ilki ${results.first.distanceKm} / ${results.first.durationFormatted}',
    );

    return results;
  }

  // ============================================================
  // URL OLUŞTURMA
  // ============================================================

  String _buildUrl(
    List<LatLng> locations,
    VehicleProfile profile, {
    required int maxAlternatives,
  }) {
    // TomTom formatı: "lat,lon:lat,lon:lat,lon"
    final locStr =
        locations.map((p) => '${p.latitude},${p.longitude}').join(':');

    final params = <String, String>{
      'key': _apiKey,
      'travelMode': profile.isTruck ? 'truck' : 'car',
      'routeType': 'fastest',
      'traffic': 'true',
      'instructionsType': 'text',
      'language': _instructionLanguage,
    };

    // Kamyon parametreleri
    if (profile.isTruck) {
      params['vehicleWeight'] = (profile.weightT * 1000).round().toString();
      params['vehicleAxleWeight'] =
          (profile.axleLoadT * 1000).round().toString();
      params['vehicleLength'] = profile.lengthM.toStringAsFixed(2);
      params['vehicleWidth'] = profile.widthM.toStringAsFixed(2);
      params['vehicleHeight'] = profile.heightM.toStringAsFixed(2);
      params['vehicleCommercial'] = 'true';
    }

    // Kaçınılacak yollar
    final avoid = <String>[];
    if (profile.avoidToll) avoid.add('tollRoads');
    if (profile.avoidMotorway) avoid.add('motorways');
    if (profile.avoidFerry) avoid.add('ferries');
    if (avoid.isNotEmpty) {
      params['avoid'] = avoid.join(',');
    }

    if (maxAlternatives > 0) {
      params['maxAlternatives'] = maxAlternatives.toString();
    }

    final query = params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');

    return '$_baseUrl/$locStr/json?$query';
  }

  // ============================================================
  // RESPONSE PARSE
  // ============================================================

  List<RouteResult> _parseResponse(Map<dynamic, dynamic> data) {
    final routes = data['routes'];
    if (routes is! List || routes.isEmpty) {
      return const [];
    }

    final results = <RouteResult>[];
    for (final route in routes) {
      if (route is! Map) continue;
      try {
        results.add(_parseSingleRoute(route));
      } catch (e) {
        debugPrint('TomTom rota ayrıştırma hatası: $e');
      }
    }
    return results;
  }

  RouteResult _parseSingleRoute(Map<dynamic, dynamic> route) {
    final summary = route['summary'];
    if (summary is! Map) {
      throw Exception('Rota özeti eksik');
    }

    final distanceM = _toDouble(summary['lengthInMeters']);
    final durationS = _toDouble(summary['travelTimeInSeconds']);

    // Tüm noktaları legs[*].points üzerinden topla
    final points = <LatLng>[];
    final legs = route['legs'];
    if (legs is List) {
      for (final leg in legs) {
        if (leg is! Map) continue;
        final pts = leg['points'];
        if (pts is List) {
          for (final p in pts) {
            if (p is Map) {
              final lat = _toDouble(p['latitude']);
              final lon = _toDouble(p['longitude']);
              // (0,0) hatalı noktaları atla
              if (lat != 0 || lon != 0) {
                points.add(LatLng(lat, lon));
              }
            }
          }
        }
      }
    }

    if (points.isEmpty) {
      throw Exception('TomTom rota geometrisi boş');
    }

    // Turn-by-turn talimatlar
    final steps = <RouteStep>[];
    final guidance = route['guidance'];
    if (guidance is Map) {
      final instructions = guidance['instructions'];
      if (instructions is List && instructions.isNotEmpty) {
        for (int i = 0; i < instructions.length; i++) {
          final inst = instructions[i];
          if (inst is! Map) continue;

          // Mesafe: sonraki adımın offseti - bu adımın offseti
          final currentOffset = _toDouble(inst['routeOffsetInMeters']);
          double nextOffset = distanceM;
          if (i + 1 < instructions.length) {
            final next = instructions[i + 1];
            if (next is Map) {
              nextOffset = _toDouble(next['routeOffsetInMeters']);
            }
          }
          final stepDist =
              (nextOffset - currentOffset).clamp(0.0, double.infinity);

          // Süreyi mesafeye oranla dağıt
          final stepDuration =
              distanceM > 0 ? (stepDist / distanceM) * durationS : 0.0;

          // Konum
          double lat = 0, lon = 0;
          final pt = inst['point'];
          if (pt is Map) {
            lat = _toDouble(pt['latitude']);
            lon = _toDouble(pt['longitude']);
          }

          steps.add(RouteStep(
            instruction: inst['message']?.toString() ?? 'Devam et',
            distanceM: stepDist,
            durationS: stepDuration,
            modifier: inst['instructionType']?.toString() ?? '',
            location: RoutePoint(latitude: lat, longitude: lon),
          ));
        }
      }
    }

    return RouteResult(
      distanceM: distanceM,
      durationS: durationS,
      points: points,
      steps: steps,
      summary: summary['departureTime']?.toString() ?? '',
    );
  }

  double _toDouble(dynamic v, {double fallback = 0.0}) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }
}
