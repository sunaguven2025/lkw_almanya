import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class OfflineMapService {
  static const String cacheStoreName = 'lkw_offline_map';

  static LatLngBounds get germanyBounds => LatLngBounds(
        const LatLng(47.27, 5.86),
        const LatLng(55.06, 15.04),
      );

  static TileLayer tileLayer() {
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.example.lkw_almanya',
      maxZoom: 18,
      minZoom: 5,
    );
  }

  static Future<void> init() async {
    // Placeholder: daha sonra offline cache başlatılır
  }

  static Future<void> downloadGermanyTiles() async {
    // Placeholder: daha sonra tile indirme eklenir
  }

  static Future<int> getCacheTileCount() async {
    return 0;
  }

  static Future<void> clearCache() async {
    // Placeholder
  }
}
