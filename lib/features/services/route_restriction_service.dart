import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/route_restriction.dart';
import '../models/truck_profile.dart';

class RouteRestrictionService {
  /// Rota üzerindeki kısıtlamaları kamyon profilene göre kontrol et
  static List<RouteRestriction> checkRouteRestrictions(
    List<LatLng> routePoints,
    TruckProfile truckProfile,
  ) {
    final List<RouteRestriction> restrictions = <RouteRestriction>[];

    if (routePoints.isEmpty) {
      return restrictions;
    }

    // Örnek olarak rota başlangıcında mock kısıtlamalar ekleyelim
    // Gerçek verilerde bu, OSM Overpass API veya başka kaynaklardan gelir

    // Örnek 1: Rota başından 2 km sonra düşük köprü
    if (routePoints.length >= 20) {
      restrictions.add(
        RouteRestriction(
          id: 'low_bridge_1',
          latitude: routePoints[10].latitude,
          longitude: routePoints[10].longitude,
          type: 'height',
          value: 3.5,
          description: 'Düşük köprü - 3.5 m',
          isCritical: truckProfile.height > 3.5,
        ),
      );
    }

    // Örnek 2: Dar geçit
    if (routePoints.length >= 30) {
      restrictions.add(
        RouteRestriction(
          id: 'narrow_passage_1',
          latitude: routePoints[20].latitude,
          longitude: routePoints[20].longitude,
          type: 'width',
          value: 2.8,
          description: 'Dar geçit - 2.8 m',
          isCritical: truckProfile.width > 2.8,
        ),
      );
    }

    // Örnek 3: Ağırlık limiti
    if (routePoints.length >= 40) {
      restrictions.add(
        RouteRestriction(
          id: 'weight_limit_1',
          latitude: routePoints[30].latitude,
          longitude: routePoints[30].longitude,
          type: 'weight',
          value: 35.0,
          description: 'Ağırlık limiti - 35 ton',
          isCritical: truckProfile.weight > 35.0,
        ),
      );
    }

    return restrictions;
  }

  /// Kamyon profiline göre kritik uyarıları döndür
  static String getCriticalWarning(
    TruckProfile profile,
    List<RouteRestriction> restrictions,
  ) {
    final List<String> warnings = <String>[];

    for (final restriction in restrictions) {
      if (!restriction.isCritical) continue;

      if (restriction.type == 'height' && restriction.value != null) {
        warnings.add(
          'Yükseklik: ${profile.height}m > ${restriction.value}m engeli var',
        );
      } else if (restriction.type == 'width' && restriction.value != null) {
        warnings.add(
          'Genişlik: ${profile.width}m > ${restriction.value}m engeli var',
        );
      } else if (restriction.type == 'weight' && restriction.value != null) {
        warnings.add(
          'Ağırlık: ${profile.weight}t > ${restriction.value}t limiti var',
        );
      }
    }

    if (warnings.isEmpty) {
      return '';
    }

    return warnings.join('\n');
  }

  /// Rota üzerinde en yakın kısıtlamayı bul
  static RouteRestriction? getNearestRestriction(
    LatLng currentLocation,
    List<RouteRestriction> restrictions,
  ) {
    if (restrictions.isEmpty) {
      return null;
    }

    RouteRestriction? nearest;
    double nearestDistance = double.infinity;

    for (final restriction in restrictions) {
      final double distance = Geolocator.distanceBetween(
        currentLocation.latitude,
        currentLocation.longitude,
        restriction.latitude,
        restriction.longitude,
      );

      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = restriction;
      }
    }

    return nearestDistance < 500 ? nearest : null;
  }
}
