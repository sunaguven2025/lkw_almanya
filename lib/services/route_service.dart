// ============================================================
// ROTA MODELLERİ + TOMTOM TABANLI SERVİS
// ============================================================
// NOT: Modeller (VehicleProfile, RouteResult, RouteStep, RoutePoint)
// burada kalıyor çünkü proje genelinde bu tipler kullanılıyor.
//
// Servis implementasyonu artık TomTom Routing API kullanıyor.
// Eski OSRM tabanlı kod için: route_service_osrm_backup.dart
// ============================================================

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'tomtom_route_service.dart';

// ============================================================
// ARAÇ PROFİLİ
// ============================================================
class VehicleProfile {
  final String type; // 'car' veya 'truck'
  final double heightM; // Yükseklik (metre)
  final double widthM; // Genişlik (metre)
  final double lengthM; // Uzunluk (metre)
  final double weightT; // Ağırlık (ton)
  final double axleLoadT; // Aks yükü (ton)
  final bool avoidToll; // Ücretli yolları avoid et
  final bool avoidFerry; // Feribot avoid et
  final bool avoidMotorway; // Otoyol avoid et

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
// ROTA ADIMI (turn-by-turn talimat)
// ============================================================
class RouteStep {
  final String instruction;
  final double distanceM;
  final double durationS;
  final String modifier; // "left", "right", "straight", "turn" vb.
  final RoutePoint location;

  RouteStep({
    required this.instruction,
    required this.distanceM,
    required this.durationS,
    required this.modifier,
    required this.location,
  });

  /// NOT: Bu metod sadece geriye dönük uyumluluk için duruyor.
  /// TomTom servisi kendi parse işlemini kendi içinde yapar.
  factory RouteStep.fromJson(Map<String, dynamic> json) {
    final step = json['maneuver'] ?? {};
    final geometry = json['geometry'];
    double lat = 0.0;
    double lon = 0.0;

    if (geometry is Map && geometry['coordinates'] is List) {
      final coords = geometry['coordinates'] as List;
      if (coords.isNotEmpty && coords.first is List) {
        final first = coords.first as List;
        if (first.length >= 2) {
          lon = (first[0] as num?)?.toDouble() ?? 0.0;
          lat = (first[1] as num?)?.toDouble() ?? 0.0;
        }
      }
    }

    return RouteStep(
      instruction: json['name']?.toString() ?? 'Devam et',
      distanceM: ((json['distance'] as num?) ?? 0).toDouble(),
      durationS: ((json['duration'] as num?) ?? 0).toDouble(),
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

  /// NOT: Geriye dönük uyumluluk. TomTom servisi kendi parse eder.
  factory RouteResult.fromJson(Map<String, dynamic> json) {
    final routes = json['routes'];
    if (routes is! List || routes.isEmpty) {
      throw Exception('Rota API cevabında rota bulunamadı');
    }

    final routeData = routes.first;
    if (routeData is! Map<String, dynamic>) {
      throw Exception('Geçersiz rota veri formatı');
    }

    final geometry = routeData['geometry'];
    if (geometry is! Map<String, dynamic>) {
      throw Exception('Rota geometrisi eksik');
    }

    final coordinates = geometry['coordinates'];
    if (coordinates is! List || coordinates.isEmpty) {
      throw Exception('Rota koordinatları eksik');
    }

    final points = <LatLng>[];
    for (final coord in coordinates) {
      if (coord is List && coord.length >= 2) {
        points.add(LatLng(
          (coord[1] as num).toDouble(),
          (coord[0] as num).toDouble(),
        ));
      }
    }

    if (points.isEmpty) {
      throw Exception('Geçerli rota noktası bulunamadı');
    }

    final steps = <RouteStep>[];
    final legs = routeData['legs'];
    if (legs is List) {
      for (final leg in legs) {
        if (leg is! Map<String, dynamic>) continue;
        final stepsList = leg['steps'];
        if (stepsList is List) {
          for (final step in stepsList) {
            if (step is! Map<String, dynamic>) continue;
            try {
              steps.add(RouteStep.fromJson(step));
            } catch (e) {
              debugPrint('Adım ayrıştırma hatası: $e');
            }
          }
        }
      }
    }

    final distanceM = ((routeData['distance'] as num?) ?? 0).toDouble();
    final durationS = ((routeData['duration'] as num?) ?? 0).toDouble();

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
// ROTA SERVİSİ — TOMTOM BACKEND
// ============================================================
/// Yüksek seviye rota servisi.
///
/// Şu an **TomTom Routing API v1** kullanır.
/// Araç profili (kamyon ağırlık/yükseklik/uzunluk) TomTom'a otomatik geçirilir.
///
/// Eski OSRM implementasyonu için:
///   → lib/services/route_service_osrm_backup.dart
class RouteService {
  final TomTomRouteService _tomtom;

  RouteService({TomTomRouteService? tomtom})
      : _tomtom = tomtom ?? TomTomRouteService();

  /// İki nokta arası rota (opsiyonel waypoint'lerle).
  Future<RouteResult> fetchRoute({
    required LatLng from,
    required LatLng to,
    required VehicleProfile profile,
    List<LatLng>? waypoints,
  }) =>
      _tomtom.fetchRoute(
        from: from,
        to: to,
        profile: profile,
        waypoints: waypoints,
      );

  /// Çoklu durak (tur) rotası.
  Future<RouteResult> fetchMultiStopRoute({
    required LatLng start,
    required List<LatLng> stops,
    required VehicleProfile profile,
  }) =>
      _tomtom.fetchMultiStopRoute(
        start: start,
        stops: stops,
        profile: profile,
      );

  /// Alternatif rotalar.
  /// Alternatif rotalar.
  Future<List<RouteResult>> fetchAlternativeRoutes({
    required LatLng from,
    required LatLng to,
    required VehicleProfile profile,
    int alternatives = 2,
  }) =>
      _tomtom.fetchAlternativeRoutes(
        from: from,
        to: to,
        profile: profile,
        alternatives: alternatives,
      );

  /// İki nokta arası kuş uçuşu mesafe (metre).
  /// Araç rotasından bağımsızdır, yerel hesaplama yapar.
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
