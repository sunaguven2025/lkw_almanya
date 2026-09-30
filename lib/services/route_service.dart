import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Araç profili - kamyon veya otomobil
class VehicleProfile {
  final String type; // 'car' veya 'truck'
  final double heightM; // Yükseklik (metre)
  final double widthM; // Genişlik (metre)
  final double lengthM; // Uzunluk (metre)
  final double weightT; // Ağırlık (ton)
  final double axleLoadT; // Aksı yükü (ton)
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

  // Standart araç profilleri
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
}

/// Rota noktası
class RoutePoint {
  final double latitude;
  final double longitude;

  RoutePoint({required this.latitude, required this.longitude});

  LatLng toLatLng() => LatLng(latitude, longitude);

  factory RoutePoint.fromLatLng(LatLng latLng) {
    return RoutePoint(
      latitude: latLng.latitude,
      longitude: latLng.longitude,
    );
  }
}

/// Rota adımı (dönüş yönleri, talimatlar)
class RouteStep {
  final String instruction;
  final double distanceM;
  final double durationS;
  final String modifier; // "left", "right", "straight", vb.
  final RoutePoint location;

  RouteStep({
    required this.instruction,
    required this.distanceM,
    required this.durationS,
    required this.modifier,
    required this.location,
  });

  factory RouteStep.fromJson(Map<String, dynamic> json) {
    final step = json['maneuver'] ?? {};
    final geometry = json['geometry'];
    late List<dynamic> coordinate;

    if (geometry is Map && geometry['coordinates'] is List) {
      final coords = geometry['coordinates'] as List;
      coordinate = coords.isNotEmpty ? coords[0] : [0, 0];
    } else {
      coordinate = [0, 0];
    }

    return RouteStep(
      instruction: json['name']?.toString() ?? 'Devam et',
      distanceM: ((json['distance'] as num?) ?? 0).toDouble(),
      durationS: ((json['duration'] as num?) ?? 0).toDouble(),
      modifier: step['modifier']?.toString() ?? '',
      location: RoutePoint(
        latitude: (coordinate[1] as num).toDouble(),
        longitude: (coordinate[0] as num).toDouble(),
      ),
    );
  }
}

/// Tam rota sonucu
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

  // Kullanıcı dostu formatlar
  String get distanceKm => '${(distanceM / 1000).toStringAsFixed(1)} km';
  String get durationFormatted {
    final hours = (durationS / 3600).floor();
    final minutes = ((durationS % 3600) / 60).floor();
    if (hours > 0) {
      return '$hours sa $minutes dk';
    }
    return '$minutes dk';
  }

  factory RouteResult.fromJson(Map<String, dynamic> json) {
    final route = json['routes'][0] as Map<String, dynamic>;

    // Koordinatlar
    final geometry = route['geometry'] as Map<String, dynamic>;
    final coordinates = geometry['coordinates'] as List;

    final List<LatLng> points = coordinates
        .map((coord) => LatLng(
              (coord[1] as num).toDouble(),
              (coord[0] as num).toDouble(),
            ))
        .toList();

    // Adımlar
    final List<RouteStep> steps = [];
    final legsList = route['legs'] as List;
    for (final leg in legsList) {
      final stepsList = leg['steps'] as List? ?? [];
      for (final step in stepsList) {
        try {
          steps.add(RouteStep.fromJson(step as Map<String, dynamic>));
        } catch (e) {
          print('Step parsing error: $e');
        }
      }
    }

    return RouteResult(
      distanceM: ((route['distance'] as num?) ?? 0).toDouble(),
      durationS: ((route['duration'] as num?) ?? 0).toDouble(),
      points: points,
      steps: steps,
      summary: route['summary']?.toString() ?? '',
    );
  }
}

/// Rota servisi - OSRM API ile iletişim
class RouteService {
  static const String _osrmBaseUrl = 'https://router.project-osrm.org/route/v1';
  static const Duration _timeout = Duration(seconds: 30);

  /// Başlangıç ve bitiş noktaları arasında rota hesapla
  Future<RouteResult> fetchRoute({
    required LatLng from,
    required LatLng to,
    required VehicleProfile profile,
    List<LatLng>? waypoints,
  }) async {
    try {
      // Rota modu (araç türüne göre)
      final profileMode = profile.type == 'truck' ? 'driving' : 'driving';

      // Koordinatlar
      String coordinates =
          '${from.longitude},${from.latitude};${to.longitude},${to.latitude}';

      // Waypoints varsa ekle
      if (waypoints != null && waypoints.isNotEmpty) {
        for (final wp in waypoints) {
          coordinates += ';${wp.longitude},${wp.latitude}';
        }
      }

      // URL oluştur
      final url = Uri.parse(
        '$_osrmBaseUrl/$profileMode/$coordinates'
        '?overview=full'
        '&geometries=geojson'
        '&steps=true'
        '&continue_straight=default',
      );

      print('🗺️ Route URL: $url');

      // İstek gönder
      final response = await http.get(url).timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception(
          'Rota API hatası: ${response.statusCode} - ${response.body}',
        );
      }

      final data = jsonDecode(response.body);

      // Hata kontrolü
      if (data['code']?.toString() != 'Ok') {
        throw Exception('OSRM Error: ${data['message']}');
      }

      final routeResult = RouteResult.fromJson(data);

      print(
        '✅ Rota hesaplandı: ${routeResult.distanceKm}, ${routeResult.durationFormatted}',
      );

      return routeResult;
    } catch (e) {
      print('❌ Rota hesaplama hatası: $e');
      rethrow;
    }
  }

  /// Çoklu durak rotası hesapla (tur rotası)
  Future<RouteResult> fetchMultiStopRoute({
    required LatLng start,
    required List<LatLng> stops,
    required VehicleProfile profile,
  }) async {
    try {
      if (stops.isEmpty) {
        throw Exception('En az bir durak gerekli');
      }

      // Tüm noktaları birleştir
      final allPoints = [start, ...stops];
      String coordinates = '';

      for (int i = 0; i < allPoints.length; i++) {
        if (i > 0) coordinates += ';';
        coordinates += '${allPoints[i].longitude},${allPoints[i].latitude}';
      }

      final url = Uri.parse(
        '${_osrmBaseUrl}/driving/$coordinates'
        '?overview=full'
        '&geometries=geojson'
        '&steps=true'
        '&continue_straight=default',
      );

      print('🗺️ Multi-stop URL: $url');

      final response = await http.get(url).timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception(
          'Çoklu durak API hatası: ${response.statusCode}',
        );
      }

      final data = jsonDecode(response.body);

      if (data['code']?.toString() != 'Ok') {
        throw Exception('OSRM Error: ${data['message']}');
      }

      final routeResult = RouteResult.fromJson(data);

      print(
        '✅ Çoklu rota hesaplandı: ${stops.length} durak, ${routeResult.distanceKm}',
      );

      return routeResult;
    } catch (e) {
      print('❌ Çoklu rota hatası: $e');
      rethrow;
    }
  }

  /// Alternatif rotalar hesapla
  Future<List<RouteResult>> fetchAlternativeRoutes({
    required LatLng from,
    required LatLng to,
    required VehicleProfile profile,
  }) async {
    try {
      final url = Uri.parse(
        '${_osrmBaseUrl}/driving/'
        '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
        '?overview=full'
        '&geometries=geojson'
        '&steps=true'
        '&alternatives=2',
      );

      print('🗺️ Alternative routes URL: $url');

      final response = await http.get(url).timeout(_timeout);

      if (response.statusCode != 200) {
        throw Exception('Alternatif rota API hatası: ${response.statusCode}');
      }

      final data = jsonDecode(response.body);

      if (data['code']?.toString() != 'Ok') {
        throw Exception('OSRM Error: ${data['message']}');
      }

      final routes = data['routes'] as List;
      final results = routes
          .map((r) => RouteResult.fromJson({
                'routes': [r]
              }))
          .toList();

      print('✅ ${results.length} alternatif rota bulundu');

      return results;
    } catch (e) {
      print('❌ Alternatif rota hatası: $e');
      rethrow;
    }
  }

  /// İki nokta arasındaki mesafeyi hesapla (kuş uçuşu)
  double calculateDistance(LatLng from, LatLng to) {
    const R = 6371000.0; // Dünya yarıçapı (metre)

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

  /// Kamyon için rota uygunluğunu kontrol et (basit check)
  bool isRouteSuitableForTruck({
    required RouteResult route,
    required VehicleProfile truck,
    required double maxHeightM,
    required double maxWeightT,
  }) {
    // Bu metod ileride Overpass API verileriyle genişletilecek
    // Şimdilik sadece temel kontrol yapılıyor
    return truck.heightM <= maxHeightM && truck.weightT <= maxWeightT;
  }
}
