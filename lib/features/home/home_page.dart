import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/route_service.dart'; // ⬅️ YENİ — TomTom + modeller
import '../../theme/app_theme.dart';
import '../models/truck_profile.dart';
import '../services/truck_profile_storage.dart';
import '../widgets/truck_profile_sheet.dart';

part 'home_page_logic.dart';
part 'home_page_ui.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _FavoritePlace {
  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String address;

  const _FavoritePlace({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.address,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
    };
  }

  factory _FavoritePlace.fromJson(Map<String, dynamic> json) {
    return _FavoritePlace(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Kayıtlı Yer',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      address: json['address']?.toString() ?? '',
    );
  }
}

class _RouteStop {
  final String id;
  final String name;
  final LatLng location;
  final String address;

  _RouteStop({
    required this.id,
    required this.name,
    required this.location,
    required this.address,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'address': address,
      };

  factory _RouteStop.fromJson(Map<String, dynamic> json) => _RouteStop(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Durak',
        location: LatLng(
          (json['latitude'] as num).toDouble(),
          (json['longitude'] as num).toDouble(),
        ),
        address: json['address']?.toString() ?? '',
      );
}

class _RouteHistoryItem {
  final String id;
  final String destinationName;
  final LatLng destination;
  final String vehicle;
  final DateTime timestamp;
  final double distance;
  final double duration;

  _RouteHistoryItem({
    required this.id,
    required this.destinationName,
    required this.destination,
    required this.vehicle,
    required this.timestamp,
    required this.distance,
    required this.duration,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'destinationName': destinationName,
        'latitude': destination.latitude,
        'longitude': destination.longitude,
        'vehicle': vehicle,
        'timestamp': timestamp.toIso8601String(),
        'distance': distance,
        'duration': duration,
      };

  factory _RouteHistoryItem.fromJson(Map<String, dynamic> json) =>
      _RouteHistoryItem(
        id: json['id']?.toString() ?? '',
        destinationName: json['destinationName']?.toString() ?? '',
        destination: LatLng(
          (json['latitude'] as num).toDouble(),
          (json['longitude'] as num).toDouble(),
        ),
        vehicle: json['vehicle']?.toString() ?? 'car',
        timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
            DateTime.now(),
        distance: (json['distance'] as num?)?.toDouble() ?? 0,
        duration: (json['duration'] as num?)?.toDouble() ?? 0,
      );
}

class _TruckParking {
  final LatLng location;
  final String name;
  final String? capacity;
  final bool hasRestaurant;
  final bool hasShower;
  final bool hasFuel;

  _TruckParking({
    required this.location,
    required this.name,
    this.capacity,
    this.hasRestaurant = false,
    this.hasShower = false,
    this.hasFuel = false,
  });
}

class _FuelStation {
  final LatLng location;
  final String name;
  final bool hgvFriendly;
  final bool hasAdBlue;
  final bool hasRestaurant;

  _FuelStation({
    required this.location,
    required this.name,
    this.hgvFriendly = false,
    this.hasAdBlue = false,
    this.hasRestaurant = false,
  });
}

class _SpeedLimitSegment {
  final LatLng start;
  final LatLng end;
  final int maxSpeed;

  _SpeedLimitSegment({
    required this.start,
    required this.end,
    required this.maxSpeed,
  });
}

class _RouteRestriction {
  final LatLng location;
  final String type;
  final String? value;
  final String description;

  _RouteRestriction({
    required this.location,
    required this.type,
    this.value,
    required this.description,
  });
}

class _NavigationInstruction {
  final String text;
  final double distance;
  final double duration;
  final LatLng? location;
  // DÜZELTME (FIX): Manevra ikonu için modifier string'i
  // saklıyoruz ("left", "right", "straight" ...). Bunu
  // üst ve alt kartta kullanıyoruz.
  final String modifier;

  bool spokenFar = false;
  bool spokenNear = false;
  bool spokenNow = false;

  _NavigationInstruction({
    required this.text,
    required this.distance,
    required this.duration,
    this.location,
    this.modifier = '',
  });

  bool get isLongLeg => distance >= 1000;
}

class _HomePageState extends State<HomePage> {
  // ============================================================
  // ROUTE SERVICE
  // ============================================================

  //late RouteService _routeService;

  // ============================================================
  // TRUCK PROFILE
  // ============================================================

  final TruckProfileStorage _truckProfileStorage = TruckProfileStorage();

  TruckProfile _truckProfile = TruckProfile.defaultProfile;

  // ============================================================
  // HARİTA
  // ============================================================

  final MapController mapController = MapController();

  LatLng? userLocation;
  LatLng? destination;

  List<LatLng> routePoints = <LatLng>[];

  List<List<LatLng>> alternativeRoutePoints = <List<LatLng>>[];

  Color routeColor = AppTheme.primaryBlue;

  bool _navigationMode = true;

  double _currentHeading = 0.0;

  bool _showMoreControls = false;

  // ============================================================
  // ADRES ARAMA
  // ============================================================

  final TextEditingController addressController = TextEditingController();

  List<dynamic> searchSuggestions = <dynamic>[];

  bool isLoadingSuggestions = false;

  int _suggestionRequestId = 0;

  Timer? _debounce;

  // ============================================================
  // ROTA BAŞLANGIÇ NOKTASI
  // ============================================================

  LatLng? _routeStartPoint;

  String _routeStartLabel = 'Güncel Konumum';

  // ============================================================
  // ARAÇ
  // ============================================================

  String? selectedVehicle;

  // ============================================================
  // SES
  // ============================================================

  final stt.SpeechToText _speech = stt.SpeechToText();

  final FlutterTts _tts = FlutterTts();

  bool _speechAvailable = false;

  bool _isListening = false;

  String _voiceText = '';

  // ============================================================
  // SES DİLİ
  // ============================================================

  String _voiceLanguage = 'de-DE';

  String _voiceLanguageName = 'Deutsch';

  // ============================================================
  // KONUM
  // ============================================================

  StreamSubscription<Position>? _positionSubscription;

  bool _isFollowingLocation = false;

  // ============================================================
  // NAVİGASYON
  // ============================================================

  bool _navigationStarted = false;

  int _lastSpokenRouteIndex = -1;

  DateTime? _lastNavigationSpeech;

  List<_NavigationInstruction> _navigationInstructions =
      <_NavigationInstruction>[];

  int _currentInstructionIndex = 0;

  List<_RouteRestriction> _routeRestrictions = <_RouteRestriction>[];

  bool _showRestrictions = true;

  String _routeRestrictionWarning = '';

  // ============================================================
  // KAMYON TONAJ SINIFI
  // ============================================================

  List<_RouteStop> _stops = <_RouteStop>[];

  static const String _historyStorageKey = 'lkw_route_history';

  static const String _stopsStorageKey = 'lkw_route_stops';

  List<_RouteHistoryItem> _routeHistory = <_RouteHistoryItem>[];

  List<_TruckParking> _truckParkings = <_TruckParking>[];

  List<_FuelStation> _fuelStations = <_FuelStation>[];

  bool _showTruckParkings = false;

  bool _showFuelStations = false;

  List<_SpeedLimitSegment> _speedLimits = <_SpeedLimitSegment>[];

  int _currentSpeedLimit = 0;

  bool _isDarkMode = false;

  DateTime? _drivingStartTime;

  bool _fatigueWarningShown = false;

  double _remainingDistance = 0.0;

  double _remainingDuration = 0.0;

  String _currentInstructionText = 'Rotanız hazırlanıyor...';

  double _currentInstructionDistance = 0.0;

  bool _isRecalculating = false;

  DateTime? _lastRecalculation;

  // ============================================================
  // FAVORİLER
  // ============================================================

  static const String _favoritesStorageKey = 'lkw_favorite_places';

  List<_FavoritePlace> _favorites = <_FavoritePlace>[];

  bool _favoritesLoaded = false;

  // ============================================================
  // YAŞAM DÖNGÜSÜ
  // ============================================================

  @override
  void initState() {
    super.initState();

    //_routeService = RouteService();

    selectedVehicle = 'truck';

    _loadTruckProfile();

    loadLocation();

    _initializeVoice();

    _loadFavorites();

    _loadRouteHistory();

    _loadStops();
  }

  @override
  void dispose() {
    WakelockPlus.disable();

    _debounce?.cancel();

    _positionSubscription?.cancel();

    _speech.stop();

    _tts.stop();

    addressController.dispose();

    super.dispose();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      appBar: _navigationStarted
          ? null
          : AppBar(
              backgroundColor: _isDarkMode ? Colors.black87 : null,
              title: const Text(
                'LKW Almanya Navigasyon',
              ),
              actions: [
                IconButton(
                  tooltip: 'Kamyon profili',
                  icon: const Icon(
                    Icons.local_shipping,
                  ),
                  onPressed: _openTruckProfileSheet,
                ),
                IconButton(
                  tooltip: 'Yerler / Favoriler',
                  icon: const Icon(
                    Icons.bookmarks,
                  ),
                  onPressed: _showFavorites,
                ),
                IconButton(
                  tooltip: 'Ses dili: $_voiceLanguageName',
                  icon: const Icon(
                    Icons.record_voice_over,
                  ),
                  onPressed: _showVoiceLanguageSelector,
                ),
                IconButton(
                  tooltip: _navigationMode ? 'Sürüş yönü' : 'Kuzey',
                  icon: Icon(
                    _navigationMode ? Icons.navigation : Icons.explore,
                  ),
                  onPressed: _toggleNavigationMode,
                ),
                if (selectedVehicle != null)
                  Padding(
                    padding: const EdgeInsets.only(
                      right: 12,
                    ),
                    child: Center(
                      child: Icon(
                        selectedVehicle == 'truck'
                            ? Icons.local_shipping
                            : Icons.directions_car,
                      ),
                    ),
                  ),
              ],
            ),
      body: userLocation == null
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : Stack(
              children: [
                _buildMap(),
                _buildNavigationTopPanel(),
                if (!_navigationStarted)
                  Positioned(
                    top: 15,
                    left: 15,
                    right: 15,
                    child: Column(
                      children: [
                        _buildStartPointRow(),
                        _buildSearchBox(),
                        _buildVoiceStatus(),
                        _buildSuggestions(),
                      ],
                    ),
                  ),
                _buildNavigationInfo(),
                _buildMapControls(),
              ],
            ),
    );
  }

  // ============================================================
  // TRUCK PROFILE METHODS
  // ============================================================

  Future<void> _loadTruckProfile() async {
    try {
      final profile = await _truckProfileStorage.load();

      if (!mounted) {
        return;
      }

      setState(() {
        _truckProfile = profile;
      });
    } catch (e) {
      debugPrint('TRUCK PROFILE LOAD ERROR: $e');
    }
  }

  Future<void> _openTruckProfileSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext modalContext) {
        return TruckProfileSheet(
          profile: _truckProfile,
          onSaved: (profile) async {
            _truckProfile = profile;

            await _truckProfileStorage.save(profile);

            if (!mounted) {
              return;
            }

            setState(() {});

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Kamyon profili kaydedildi.'),
                duration: Duration(seconds: 2),
              ),
            );
          },
        );
      },
    );
  }
}

// ================================================================
// KONUM İZNİ VE KONUM ALMA
// ================================================================

Future<Position> getUserLocation() async {
  final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

  if (!serviceEnabled) {
    throw Exception('Konum servisi kapalı.');
  }

  LocationPermission permission = await Geolocator.checkPermission();

  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();

    if (permission == LocationPermission.denied) {
      throw Exception('Konum izni reddedildi.');
    }
  }

  if (permission == LocationPermission.deniedForever) {
    throw Exception(
      'Konum izni kalıcı olarak reddedildi. Telefon ayarlarından konum iznini açın.',
    );
  }

  return Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.high,
    timeLimit: const Duration(seconds: 20),
  );
}
