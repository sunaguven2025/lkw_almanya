import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

// ============================================================
// ÖZEL HATA SINIFLARI
// ============================================================
class RouteException implements Exception {
  final String message;
  final int? statusCode;
  RouteException(this.message, {this.statusCode});
  @override
  String toString() => 'RouteException: $message';
}

class RouteParseException extends RouteException {
  RouteParseException(super.message);
}

// ============================================================
// YARDIMCI (SAFE PARSE) FONKSİYONLAR
// ============================================================
double _safeDouble(dynamic value, {double fallback = 0.0}) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}

// ============================================================
// ARAÇ PROFİLİ
// ============================================================
class VehicleProfile {
  final String type; // 'car' veya 'truck'
  final double heightM;
  final double widthM;
  final double lengthM;
  final double weightT;
  final double axleLoadT;
  final bool avoidToll;
  final bool avoidFerry;
  final bool avoidMotorway;

  const VehicleProfile({
    required this.type,
    this.heightM = 2.55,
    this.widthM = 2.55,
    this.lengthM = 5.0,
    this.weightT = 3.5,
    this.axleLoadT = 10.0,
    this.avoidToll = false,
    this.avoidFerry = false,
    this.avoidMotorway = false,
  });

  static const VehicleProfile car = VehicleProfile(
    type: 'car',
    heightM: 2.0,
    widthM: 2.0,
    lengthM: 4.5,
    weightT: 1.5,
    axleLoadT: 10.0,
  );

  static const VehicleProfile truck = VehicleProfile(
    type: 'truck',
    heightM: 4.0,
    widthM: 2.55,
    lengthM: 16.5,
    weightT: 40.0,
    axleLoadT: 11.5,
  );

  static const VehicleProfile heavyTruck = VehicleProfile(
    type: 'truck',
    heightM: 3.8,
    widthM: 2.55,
    lengthM: 13.6,
    weightT: 25.0,
    axleLoadT: 11.5,
  );

  bool get isTruck => type == 'truck';
}

// ============================================================
// ROTA NOKTASI
// ============================================================
class RoutePoint {
  final double latitude;
  final double longitude;

  RoutePoint({required this.latitude, required this.longitude});

  LatLng toLatLng() => LatLng(latitude, longitude);

  factory RoutePoint.fromLatLng(LatLng latLng) => RoutePoint(
        latitude: latLng.latitude,
        longitude: latLng.longitude,
      );
}

// ============================================================
// ROTA ADIMI
// ============================================================
class RouteStep {
  final String instruction;
  final double distanceM;
  final double durationS;
  final String modifier;
  final RoutePoint location;

  RouteStep({
    required this.instruction,
    required this.distanceM,
    required this.durationS,
    required this.modifier,
    required this.location,
  });

  factory RouteStep.fromJson(Map<dynamic, dynamic> json) {
    final step = (json['maneuver'] as Map?) ?? const {};

    // Güvenli koordinat çıkarma
    double lat = 0.0;
    double lon = 0.0;

    final geometry = json['geometry'];
    if (geometry is Map && geometry['coordinates'] is List) {
      final coords = geometry['coordinates'] as List;
      if (coords.isNotEmpty && coords.first is List) {
        final first = coords.first as List;
        if (first.length >= 2) {
          lon = _safeDouble(first[0]);
          lat = _safeDouble(first[1]);
        }
      }
    }

    return RouteStep(
      instruction: json['name']?.toString() ?? 'Devam et',
      distanceM: _safeDouble(json['distance']),
      durationS: _safeDouble(json['duration']),
      modifier: step['modifier']?.toString() ?? '',
      location: RoutePoint(latitude: lat, longitude: lon),
    );
  }
}

// ============================================================
// ROTA SONUCU
// ============================================================
class RouteResult {
  final double distanceM;
  final double durationS;
  final List<LatLng> points;
  final List<RouteStep> steps;
  final String summary;

  RouteResult({
    required this.distanceM,
    required this.durationS,
    required this.points,
    required this.steps,
    this.summary = '',
  });

  String get distanceKm => '${(distanceM / 1000).toStringAsFixed(1)} km';

  String get durationFormatted {
    final hours = (durationS / 3600).floor();
    final minutes = ((durationS % 3600) / 60).floor();
    if (hours > 0) return '$hours sa $minutes dk';
    return '$minutes dk';
  }

  factory RouteResult.fromJson(Map<dynamic, dynamic> json) {
    // routes kontrolü
    final routes = json['routes'];
    if (routes is! List || routes.isEmpty) {
      throw RouteParseException('Rota API cevabında rota bulunamadı');
    }

    final routeData = routes.first;
    if (routeData is! Map) {
      throw RouteParseException('Geçersiz rota veri formatı');
    }

    // geometry kontrolü
    final geometry = routeData['geometry'];
    if (geometry is! Map) {
      throw RouteParseException('Rota geometrisi eksik');
    }

    final coordinates = geometry['coordinates'];
    if (coordinates is! List || coordinates.isEmpty) {
      throw RouteParseException('Rota koordinatları eksik');
    }

    // Koordinatları dönüştür
    final points = <LatLng>[];
    for (final coord in coordinates) {
      if (coord is List && coord.length >= 2) {
        final lon = _safeDouble(coord[0]);
        final lat = _safeDouble(coord[1]);
        // Geçersiz (0,0) noktalarını atla
        if (lat != 0.0 || lon != 0.0) {
          points.add(LatLng(lat, lon));
        }
      }
    }

    if (points.isEmpty) {
      throw RouteParseException('Geçerli rota noktası bulunamadı');
    }

    // legs ve steps
    final steps = <RouteStep>[];
    final legs = routeData['legs'];
    if (legs is List) {
      for (final leg in legs) {
        if (leg is! Map) continue;
        final stepsList = leg['steps'];
        if (stepsList is List) {
          for (final step in stepsList) {
            if (step is! Map) continue;
            try {
              steps.add(RouteStep.fromJson(step));
            } catch (e) {
              debugPrint('Adım ayrıştırma hatası: $e');
            }
          }
        }
      }
    }

    final distanceM = _safeDouble(routeData['distance']);
    final durationS = _safeDouble(routeData['duration']);

    if (distanceM <= 0 || durationS <= 0) {
      debugPrint('⚠️ Uyarı: distance=$distanceM, duration=$durationS');
    }

    return RouteResult(
      distanceM: distanceM,
      durationS: durationS,
      points: points,
      steps: steps,
      summary: routeData['summary']?.toString() ?? '',
    );
  }
}

// ============================================================
// ROTA SERVİSİ
// ============================================================
class RouteService {
  /// NOT: `router.project-osrm.org` public demo sunucusu SADECE
  /// `driving`, `walking`, `cycling` profillerini destekler.
  /// `driving-hgv` (kamyon) İÇİN kendi OSRM sunucunu barındırman gerekir.
  /// Kendi sunucun varsa buraya yaz:
  static const String _osrmBaseUrl = 'https://router.project-osrm.org/route/v1';

  static const Duration _timeout = Duration(seconds: 30);
  static const int _maxCoordinates = 25; // URL uzunluğu güvenliği
  static const String _userAgent = 'LkwAlmanyaApp/1.0 (Flutter)';

  /// Araç profilini OSRM profiline çevir.
  /// Public sunucuda truck için `driving` fallback uygular.
  String _getProfileMode(VehicleProfile profile) {
    if (profile.type == 'truck') {
      // ⚠️ Public sunucu driving-hgv desteklemiyor.
      // Kendi sunucun varsa: return 'driving-hgv';
      return 'driving';
    }
    return 'driving';
  }

  /// URL uzunluğunu güvenli tut
  void _validateCoordinateCount(int count) {
    if (count > _maxCoordinates) {
      throw RouteException(
        'Çok fazla nokta ($count). En fazla $_maxCoordinates nokta destekleniyor.',
      );
    }
  }

  /// Ortak HTTP isteği
  Future<RouteResult> _requestRoute(String url) async {
    debugPrint('🗺️ Route URL: $url');

    final response = await http.get(
      Uri.parse(url),
      headers: {'User-Agent': _userAgent},
    ).timeout(_timeout);

    if (response.statusCode != 200) {
      throw RouteException(
        'Rota API hatası: ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    final dynamic data = jsonDecode(response.body);
    if (data is! Map) {
      throw RouteParseException('API cevabı geçersiz JSON formatı');
    }

    if (data['code']?.toString() != 'Ok') {
      throw RouteException('OSRM Error: ${data['message'] ?? 'bilinmeyen'}');
    }

    return RouteResult.fromJson(data);
  }

  /// İki nokta (veya opsiyonel waypoint'ler) arasında rota hesapla.
  /// ✅ DÜZELTME: Waypoint'ler artık `to` noktasından ÖNCE ekleniyor.
  Future<RouteResult> fetchRoute({
    required LatLng from,
    required LatLng to,
    required VehicleProfile profile,
    List<LatLng>? waypoints,
  }) async {
    try {
      final profileMode = _getProfileMode(profile);

      // Doğru sıra: from → waypoints → to
      final ordered = <LatLng>[
        from,
        ...?waypoints,
        to,
      ];

      _validateCoordinateCount(ordered.length);

      final coordinates =
          ordered.map((p) => '${p.longitude},${p.latitude}').join(';');

      final url = '$_osrmBaseUrl/$profileMode/$coordinates'
          '?overview=full'
          '&geometries=geojson'
          '&steps=true'
          '&continue_straight=default';

      final result = await _requestRoute(url);

      debugPrint(
        '✅ Rota hesaplandı: ${result.distanceKm}, ${result.durationFormatted}',
      );
      return result;
    } catch (e) {
      debugPrint('❌ Rota hesaplama hatası: $e');
      rethrow;
    }
  }

  /// Çoklu durak rotası (tur)
  Future<RouteResult> fetchMultiStopRoute({
    required LatLng start,
    required List<LatLng> stops,
    required VehicleProfile profile,
  }) async {
    try {
      if (stops.isEmpty) {
        throw RouteException('En az bir durak gerekli');
      }

      final profileMode = _getProfileMode(profile);
      final allPoints = <LatLng>[start, ...stops];

      _validateCoordinateCount(allPoints.length);

      final coordinates =
          allPoints.map((p) => '${p.longitude},${p.latitude}').join(';');

      final url = '$_osrmBaseUrl/$profileMode/$coordinates'
          '?overview=full'
          '&geometries=geojson'
          '&steps=true'
          '&continue_straight=default';

      final result = await _requestRoute(url);

      debugPrint(
        '✅ Çoklu rota: ${stops.length} durak, ${result.distanceKm}',
      );
      return result;
    } catch (e) {
      debugPrint('❌ Çoklu rota hatası: $e');
      rethrow;
    }
  }

  /// Alternatif rotalar
  Future<List<RouteResult>> fetchAlternativeRoutes({
    required LatLng from,
    required LatLng to,
    required VehicleProfile profile,
    int alternatives = 2,
  }) async {
    try {
      final profileMode = _getProfileMode(profile);

      final url = '$_osrmBaseUrl/$profileMode/'
          '${from.longitude},${from.latitude};'
          '${to.longitude},${to.latitude}'
          '?overview=full'
          '&geometries=geojson'
          '&steps=true'
          '&alternatives=$alternatives';

      debugPrint('🗺️ Alternative routes URL: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': _userAgent},
      ).timeout(_timeout);

      if (response.statusCode != 200) {
        throw RouteException(
          'Alternatif rota API hatası: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }

      final dynamic data = jsonDecode(response.body);
      if (data is! Map) {
        throw RouteParseException('Geçersiz JSON');
      }

      if (data['code']?.toString() != 'Ok') {
        throw RouteException('OSRM Error: ${data['message']}');
      }

      final routes = data['routes'];
      if (routes is! List || routes.isEmpty) {
        throw RouteException('Alternatif rota bulunamadı');
      }

      final results = <RouteResult>[];
      for (final route in routes) {
        try {
          results.add(RouteResult.fromJson({
            'routes': [route]
          }));
        } catch (e) {
          debugPrint('Alternatif rota ayrıştırma hatası: $e');
        }
      }

      if (results.isEmpty) {
        throw RouteException('Geçerli alternatif rota bulunamadı');
      }

      debugPrint('✅ ${results.length} alternatif rota bulundu');
      return results;
    } catch (e) {
      debugPrint('❌ Alternatif rota hatası: $e');
      rethrow;
    }
  }

  /// İki nokta arası kuş uçuşu mesafe (metre)
  double calculateDistance(LatLng from, LatLng to) {
    const R = 6371000.0;
    final lat1 = _toRad(from.latitude);
    final lat2 = _toRad(to.latitude);
    final dLat = _toRad(to.latitude - from.latitude);
    final dLng = _toRad(to.longitude - from.longitude);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _toRad(double deg) => deg * (math.pi / 180);
}
