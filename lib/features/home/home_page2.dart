import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:share_plus/share_plus.dart';

import '../../theme/app_theme.dart';

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

  // Uzun mesafeli talimatlarda 3 aşamalı (uzak / yakın / şimdi) anons takibi.
  // Kısa mesafeli talimatlarda sadece "spokenNow" kullanılır (tek anons).
  bool spokenFar = false;
  bool spokenNear = false;
  bool spokenNow = false;

  _NavigationInstruction({
    required this.text,
    required this.distance,
    required this.duration,
    this.location,
  });

  // Bu talimat "uzun mesafe" sayılır mı? (3 km'lik erken uyarı mantıklı mı)
  bool get isLongLeg => distance >= 1000;
}

class _HomePageState extends State<HomePage> {
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

  // Harita üzerindeki ikincil (sık kullanılmayan) kontrollerin
  // açık/kapalı olma durumu — menüyü sadeleştirip daha anlaşılır kılar.
  bool _showMoreControls = false;

  // ============================================================
  // ADRES ARAMA
  // ============================================================

  final TextEditingController addressController = TextEditingController();

  List<dynamic> searchSuggestions = <dynamic>[];

  bool isLoadingSuggestions = false;

  Timer? _debounce;

  // ============================================================
  // ROTA BAŞLANGIÇ NOKTASI
  // ============================================================

  // null ise: rota her zaman güncel GPS konumundan hesaplanır.
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

  double _truckWeight = 40.0;

  double _truckHeight = 4.0;

  double _truckWidth = 2.55;

  double _truckLength = 16.5;

  double _truckAxleLoad = 11.5;

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
  // FAVORİLERİ YÜKLE
  // ============================================================

  Future<void> _loadFavorites() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      final String? saved = prefs.getString(
        _favoritesStorageKey,
      );

      if (saved == null || saved.isEmpty) {
        if (!mounted) {
          return;
        }

        setState(() {
          _favorites = <_FavoritePlace>[];
          _favoritesLoaded = true;
        });

        return;
      }

      final dynamic decoded = jsonDecode(saved);

      if (decoded is! List) {
        return;
      }

      final List<_FavoritePlace> loaded = <_FavoritePlace>[];

      for (final dynamic item in decoded) {
        if (item is Map) {
          try {
            loaded.add(
              _FavoritePlace.fromJson(
                Map<String, dynamic>.from(item),
              ),
            );
          } catch (e) {
            debugPrint(
              'FAVORITE LOAD ITEM ERROR: $e',
            );
          }
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _favorites = loaded;
        _favoritesLoaded = true;
      });
    } catch (e) {
      debugPrint(
        'FAVORITES LOAD ERROR: $e',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _favoritesLoaded = true;
      });
    }
  }

  // ============================================================
  // FAVORİLERİ KAYDET
  // ============================================================

  Future<void> _saveFavorites() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      final String encoded = jsonEncode(
        _favorites
            .map(
              (_FavoritePlace place) => place.toJson(),
            )
            .toList(),
      );

      await prefs.setString(
        _favoritesStorageKey,
        encoded,
      );
    } catch (e) {
      debugPrint(
        'FAVORITES SAVE ERROR: $e',
      );
    }
  }

  // ============================================================
  // KONUMU FAVORİ OLARAK KAYDET
  // ============================================================

  Future<void> _saveCurrentLocationAsFavorite() async {
    if (userLocation == null) {
      await loadLocation();

      if (userLocation == null) {
        _showRouteError(
          'Mevcut konum alınamadı.',
        );

        return;
      }
    }

    final LatLng location = userLocation!;

    final TextEditingController nameController = TextEditingController();

    final TextEditingController addressControllerForFavorite =
        TextEditingController();

    String detectedAddress = '';

    try {
      final String url = 'https://nominatim.openstreetmap.org/reverse'
          '?lat=${location.latitude}'
          '&lon=${location.longitude}'
          '&format=json'
          '&zoom=18';

      final http.Response response = await http.get(
        Uri.parse(url),
        headers: const {
          'User-Agent': 'lkw_almanya_navigation_app',
        },
      );

      if (response.statusCode == 200) {
        final dynamic data = jsonDecode(
          response.body,
        );

        if (data is Map) {
          detectedAddress = data['display_name']?.toString() ?? '';
        }
      }
    } catch (e) {
      debugPrint(
        'REVERSE GEOCODING ERROR: $e',
      );
    }

    addressControllerForFavorite.text = detectedAddress;

    if (!mounted) {
      nameController.dispose();
      addressControllerForFavorite.dispose();
      return;
    }

    bool dialogClosed = false;

    final bool? save = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(
                Icons.location_on,
                color: AppTheme.primaryBlue,
              ),
              SizedBox(
                width: 8,
              ),
              Text(
                'Konumu Kaydet',
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Yer adı',
                    hintText: 'Örneğin: Ev, Depo, Müşteri 1',
                    prefixIcon: Icon(
                      Icons.bookmark,
                    ),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(
                  height: 14,
                ),
                TextField(
                  controller: addressControllerForFavorite,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Adres',
                    prefixIcon: Icon(
                      Icons.home,
                    ),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(
                  height: 12,
                ),
                Text(
                  'GPS: ${location.latitude.toStringAsFixed(6)}, '
                  '${location.longitude.toStringAsFixed(6)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (dialogClosed) {
                  return;
                }

                dialogClosed = true;

                FocusScope.of(dialogContext).unfocus();

                Navigator.of(dialogContext).pop(false);
              },
              child: const Text(
                'İptal',
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                if (dialogClosed) {
                  return;
                }

                final String enteredName = nameController.text.trim();

                if (enteredName.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Lütfen bir yer adı girin.',
                      ),
                    ),
                  );

                  return;
                }

                dialogClosed = true;

                FocusScope.of(dialogContext).unfocus();

                Navigator.of(dialogContext).pop(true);
              },
              icon: const Icon(
                Icons.save,
              ),
              label: const Text(
                'Kaydet',
              ),
            ),
          ],
        );
      },
    );

    /*
   * Dialog kapandıktan sonra Flutter'ın Focus/TextField
   * temizleme işlemlerinin tamamlanmasını bekliyoruz.
   */
    await Future<void>.delayed(
      const Duration(
        milliseconds: 100,
      ),
    );

    final String name = nameController.text.trim();

    final String address = addressControllerForFavorite.text.trim();

    nameController.dispose();
    addressControllerForFavorite.dispose();

    if (!mounted) {
      return;
    }

    if (save != true || name.isEmpty) {
      return;
    }

    final _FavoritePlace favorite = _FavoritePlace(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      latitude: location.latitude,
      longitude: location.longitude,
      address: address,
    );

    setState(() {
      _favorites.insert(
        0,
        favorite,
      );
    });

    await _saveFavorites();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$name favorilere kaydedildi.',
        ),
        action: SnackBarAction(
          label: 'Yerler',
          onPressed: _showFavorites,
        ),
      ),
    );

    await _speak(
      _voiceLanguage == 'tr-TR'
          ? '$name favorilere kaydedildi.'
          : _voiceLanguage == 'en-US'
              ? '$name has been saved to your places.'
              : '$name wurde in Ihren Favoriten gespeichert.',
    );
  }

  // ============================================================
  // FAVORİ SİL
  // ============================================================

  Future<void> _deleteFavorite(
    _FavoritePlace favorite,
  ) async {
    setState(() {
      _favorites.removeWhere(
        (_FavoritePlace item) => item.id == favorite.id,
      );
    });

    await _saveFavorites();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${favorite.name} silindi.',
        ),
      ),
    );
  }

  // ============================================================
  // FAVORİLER PENCERESİ
  // ============================================================

  void _showFavorites() {
    if (!_favoritesLoaded) {
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.72,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.bookmarks,
                        color: AppTheme.primaryBlue,
                      ),
                      SizedBox(
                        width: 10,
                      ),
                      Text(
                        'Yerler / Favoriler',
                        style: TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: _favorites.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(30),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.bookmark_border,
                                  size: 70,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(
                                  height: 15,
                                ),
                                const Text(
                                  'Henüz kayıtlı yer yok.',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(
                                  height: 8,
                                ),
                                const Text(
                                  'Bulunduğunuz konumu kaydetmek için '
                                  'haritadaki Konum Al düğmesini kullanın.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          itemCount: _favorites.length,
                          separatorBuilder: (
                            BuildContext context,
                            int index,
                          ) {
                            return const Divider(
                              height: 1,
                            );
                          },
                          itemBuilder: (
                            BuildContext context,
                            int index,
                          ) {
                            final _FavoritePlace favorite = _favorites[index];

                            return ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: AppTheme.primaryBlue,
                                child: Icon(
                                  Icons.bookmark,
                                  color: Colors.white,
                                ),
                              ),
                              title: Text(
                                favorite.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (favorite.address.isNotEmpty)
                                    Text(
                                      favorite.address,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  const SizedBox(
                                    height: 3,
                                  ),
                                  Text(
                                    '${favorite.latitude.toStringAsFixed(5)}, '
                                    '${favorite.longitude.toStringAsFixed(5)}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                              trailing: PopupMenuButton<String>(
                                onSelected: (
                                  String value,
                                ) {
                                  if (value == 'delete') {
                                    _deleteFavorite(
                                      favorite,
                                    );
                                  }
                                },
                                itemBuilder: (
                                  BuildContext context,
                                ) {
                                  return const [
                                    PopupMenuItem<String>(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.delete,
                                            color: Colors.red,
                                          ),
                                          SizedBox(
                                            width: 8,
                                          ),
                                          Text(
                                            'Sil',
                                          ),
                                        ],
                                      ),
                                    ),
                                  ];
                                },
                              ),
                              onTap: () {
                                Navigator.pop(
                                  sheetContext,
                                );

                                _selectFavorite(
                                  favorite,
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // FAVORİ SEÇ
  // ============================================================

  void _selectFavorite(
    _FavoritePlace favorite,
  ) {
    final LatLng point = LatLng(
      favorite.latitude,
      favorite.longitude,
    );

    FocusScope.of(context).unfocus();

    setState(() {
      destination = point;

      addressController.text =
          favorite.address.isNotEmpty ? favorite.address : favorite.name;

      searchSuggestions = <dynamic>[];

      routePoints = <LatLng>[];

      alternativeRoutePoints = <List<LatLng>>[];

      _navigationStarted = false;
    });

    mapController.rotate(
      0,
    );

    mapController.move(
      point,
      14.0,
    );

    showVehicleSelector(
      point,
    );
  }

  // ============================================================
  // SES SİSTEMİ
  // ============================================================

  Future<void> _initializeVoice() async {
    try {
      final bool available = await _speech.initialize(
        onStatus: (String status) {
          if (!mounted) {
            return;
          }

          if (status == 'done' || status == 'notListening') {
            setState(() {
              _isListening = false;
            });
          }
        },
        onError: (dynamic error) {
          if (!mounted) {
            return;
          }

          setState(() {
            _isListening = false;
          });

          debugPrint(
            'SPEECH ERROR: ${error.errorMsg}',
          );
        },
      );

      await _tts.setLanguage(
        _voiceLanguage,
      );

      await _tts.setSpeechRate(
        0.48,
      );

      await _tts.setPitch(
        1.0,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _speechAvailable = available;
      });
    } catch (e) {
      debugPrint(
        'VOICE INITIALIZATION ERROR: $e',
      );
    }
  }

  // ============================================================
  // SES DİLİ
  // ============================================================

  Future<void> _changeVoiceLanguage(
    String language,
    String name,
  ) async {
    try {
      await _speech.stop();

      await _tts.stop();

      await _tts.isLanguageAvailable(
        language,
      );

      await _tts.setLanguage(
        language,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _voiceLanguage = language;
        _voiceLanguageName = name;
        _isListening = false;
      });

      String message;

      if (language == 'tr-TR') {
        message = 'Ses dili Türkçe olarak ayarlandı.';
      } else if (language == 'en-US') {
        message = 'Voice language changed to English.';
      } else {
        message = 'Die Sprache wurde auf Deutsch eingestellt.';
      }

      await _speak(
        message,
      );
    } catch (e) {
      debugPrint(
        'VOICE LANGUAGE ERROR: $e',
      );

      _showRouteError(
        'Ses dili değiştirilemedi.',
      );
    }
  }

  void _showVoiceLanguageSelector() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Sesli Navigasyon Dili',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 12,
                ),
                ListTile(
                  leading: const Text(
                    '🇹🇷',
                    style: TextStyle(
                      fontSize: 28,
                    ),
                  ),
                  title: const Text(
                    'Türkçe',
                  ),
                  trailing: _voiceLanguage == 'tr-TR'
                      ? const Icon(
                          Icons.check,
                          color: Colors.green,
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(
                      sheetContext,
                    );

                    _changeVoiceLanguage(
                      'tr-TR',
                      'Türkçe',
                    );
                  },
                ),
                ListTile(
                  leading: const Text(
                    '🇩🇪',
                    style: TextStyle(
                      fontSize: 28,
                    ),
                  ),
                  title: const Text(
                    'Deutsch',
                  ),
                  trailing: _voiceLanguage == 'de-DE'
                      ? const Icon(
                          Icons.check,
                          color: Colors.green,
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(
                      sheetContext,
                    );

                    _changeVoiceLanguage(
                      'de-DE',
                      'Deutsch',
                    );
                  },
                ),
                ListTile(
                  leading: const Text(
                    '🇬🇧',
                    style: TextStyle(
                      fontSize: 28,
                    ),
                  ),
                  title: const Text(
                    'English',
                  ),
                  trailing: _voiceLanguage == 'en-US'
                      ? const Icon(
                          Icons.check,
                          color: Colors.green,
                        )
                      : null,
                  onTap: () {
                    Navigator.pop(
                      sheetContext,
                    );

                    _changeVoiceLanguage(
                      'en-US',
                      'English',
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // SESLİ KOMUT
  // ============================================================

  Future<void> _startListening() async {
    if (!_speechAvailable) {
      await _initializeVoice();
    }

    if (!_speechAvailable) {
      if (!mounted) {
        return;
      }

      _showRouteError(
        'Sesli komut kullanılamıyor. Mikrofon iznini kontrol edin.',
      );

      return;
    }

    if (_isListening) {
      await _stopListening();
      return;
    }

    setState(() {
      _isListening = true;
      _voiceText = '';
    });

    await _speech.listen(
      onResult: (result) {
        if (!mounted) {
          return;
        }

        setState(() {
          _voiceText = result.recognizedWords;
        });

        if (result.finalResult && result.recognizedWords.trim().isNotEmpty) {
          _processVoiceCommand(
            result.recognizedWords,
          );
        }
      },
      listenOptions: stt.SpeechListenOptions(
        localeId: _voiceLanguage,
        listenMode: stt.ListenMode.confirmation,
      ),
    );
  }

  Future<void> _stopListening() async {
    await _speech.stop();

    if (!mounted) {
      return;
    }

    setState(() {
      _isListening = false;
    });
  }

  Future<void> _processVoiceCommand(
    String command,
  ) async {
    await _stopListening();

    final String text = command.trim();

    if (text.isEmpty) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _voiceText = text;
      addressController.text = text;
    });

    String searchText = text;

    searchText = searchText
        .replaceAll(
          RegExp(
            r'\b(navigasyon|navigation|rota|route|'
            r'git|g[oö]tür|götür|oluştur|olustur|'
            r'başlat|baslat)\b',
            caseSensitive: false,
          ),
          '',
        )
        .trim();

    searchText = searchText
        .replaceAll(
          RegExp(
            r'\b(kamyon|lkw|truck|otomobil|araba|'
            r'auto|car)\b',
            caseSensitive: false,
          ),
          '',
        )
        .trim();

    if (searchText.isEmpty) {
      searchText = text;
    }

    await searchAddress(
      searchText,
    );
  }

  // ============================================================
  // TTS
  // ============================================================

  Future<void> _speak(
    String text,
  ) async {
    try {
      await _tts.stop();

      await _tts.speak(
        text,
      );
    } catch (e) {
      debugPrint(
        'TTS ERROR: $e',
      );
    }
  }

  // ============================================================
  // KONUM
  // ============================================================

  Future<void> loadLocation() async {
    try {
      final Position position = await getUserLocation();

      if (!mounted) {
        return;
      }

      final LatLng location = LatLng(
        position.latitude,
        position.longitude,
      );

      setState(() {
        userLocation = location;

        if (position.heading >= 0 && position.heading.isFinite) {
          _currentHeading = position.heading;
        }
      });

      // ------------------------------------------------------------
      // DÜZELTME (FIX): mapController.move() çağrısı, setState()
      // sonrası HEMEN çalıştırılıyordu. Ancak setState() sadece bir
      // sonraki frame'de yeniden çizimi PLANLAR; o an FlutterMap
      // widget'ı (ve dolayısıyla mapController'ın dahili "state"
      // alanı) henüz oluşmamış olabiliyordu. Bu da
      // "LateInitializationError: Field 'state@...' has not been
      // initialized" hatasına yol açıyordu.
      //
      // Çözüm: move() çağrısını addPostFrameCallback ile bir sonraki
      // frame'e erteliyoruz, böylece FlutterMap widget'ı build edilip
      // controller'a bağlandıktan SONRA çalışır. Ekstra güvenlik için
      // try/catch de ekledik.
      // ------------------------------------------------------------
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        try {
          mapController.move(
            location,
            13.0,
          );
        } catch (e) {
          debugPrint(
            'MAP MOVE ERROR (loadLocation): $e',
          );
        }
      });

      _startPositionTracking();
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Konum alınamadı: $e',
          ),
        ),
      );
    }
  }

  // ============================================================
  // KONUM TAKİBİ
  // ============================================================

  void _startPositionTracking() {
    _positionSubscription?.cancel();

    const LocationSettings settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 3,
    );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
      (Position position) {
        if (!mounted) {
          return;
        }

        final LatLng location = LatLng(
          position.latitude,
          position.longitude,
        );

        double heading = _currentHeading;

        if (position.heading >= 0 &&
            position.heading.isFinite &&
            position.speed > 1.0) {
          heading = position.heading;
        }

        setState(() {
          userLocation = location;
          _currentHeading = heading;
        });

        if (_isFollowingLocation) {
          _moveMapWithDirection(
            location,
            heading,
          );
        }

        if (_navigationStarted && routePoints.isNotEmpty) {
          _checkNavigationProgress(
            location,
          );

          _updateNavigationInstruction(
            location,
          );

          _checkOffRoute(
            location,
          );

          _checkDestinationReached(
            location,
          );

          _updateCurrentSpeedLimit(
            location,
          );

          _checkFatigue();
        }
      },
    );
  }

  // ============================================================
  // HARİTAYI YÖNE ÇEVİR
  // ============================================================

  void _moveMapWithDirection(
    LatLng location,
    double heading,
  ) {
    try {
      double zoom = mapController.zoom;

      if (_navigationStarted) {
        zoom = 17.0;
      }

      mapController.move(
        location,
        zoom,
      );

      if (_navigationMode) {
        mapController.rotate(
          -heading,
        );
      } else {
        mapController.rotate(
          0,
        );
      }
    } catch (e) {
      debugPrint(
        'MAP MOVE ERROR (_moveMapWithDirection): $e',
      );
    }
  }

  // ============================================================
  // NAVİGASYON MODU
  // ============================================================

  void _toggleNavigationMode() {
    setState(() {
      _navigationMode = !_navigationMode;
    });

    if (_navigationMode) {
      _speak(
        _voiceLanguage == 'tr-TR'
            ? 'Sürüş yönü ekranın ön tarafında.'
            : _voiceLanguage == 'en-US'
                ? 'Driving direction is now at the top.'
                : 'Die Fahrtrichtung befindet sich jetzt oben.',
      );
    } else {
      mapController.rotate(
        0,
      );

      _speak(
        _voiceLanguage == 'tr-TR'
            ? 'Kuzey yukarıda.'
            : _voiceLanguage == 'en-US'
                ? 'North is up.'
                : 'Norden ist oben.',
      );
    }

    if (userLocation != null) {
      _isFollowingLocation = true;

      _moveMapWithDirection(
        userLocation!,
        _currentHeading,
      );
    }
  }

  // ============================================================
  // NAVİGASYONU DURDUR
  // ============================================================

  void _stopNavigation() {
    setState(() {
      _navigationStarted = false;
      _isFollowingLocation = false;
      _navigationInstructions = <_NavigationInstruction>[];
      routePoints = <LatLng>[];
      alternativeRoutePoints = <List<LatLng>>[];
      _routeRestrictions = <_RouteRestriction>[];
      _routeRestrictionWarning = '';
      _speedLimits = <_SpeedLimitSegment>[];
      _currentSpeedLimit = 0;
      _truckParkings = <_TruckParking>[];
      _fuelStations = <_FuelStation>[];
      _truckWeight = 40.0;
      _truckHeight = 4.0;
      _truckWidth = 2.55;
      _truckLength = 16.5;
      _truckAxleLoad = 11.5;
      _truckWeight = 40.0;
      _truckHeight = 4.0;
      _truckWidth = 2.55;
      _truckLength = 16.5;
      _truckAxleLoad = 11.5;
      destination = null;
      addressController.clear();
      _remainingDistance = 0;
      _remainingDuration = 0;
      _currentInstructionText = 'Rotanız hazırlanıyor...';
      _currentInstructionDistance = 0;
      _drivingStartTime = null;
      _fatigueWarningShown = false;
    });

    mapController.rotate(0);

    WakelockPlus.disable();
  }

  // ============================================================
  // NAVİGASYON İLERLEMESİ
  // ============================================================

  void _checkNavigationProgress(
    LatLng currentLocation,
  ) {
    if (routePoints.isEmpty) {
      return;
    }

    double nearestDistance = double.infinity;

    int nearestIndex = 0;

    for (int i = 0; i < routePoints.length; i++) {
      final double distance = Geolocator.distanceBetween(
        currentLocation.latitude,
        currentLocation.longitude,
        routePoints[i].latitude,
        routePoints[i].longitude,
      );

      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = i;
      }
    }

    if (nearestIndex <= _lastSpokenRouteIndex) {
      return;
    }

    if (nearestDistance > 80) {
      return;
    }

    final DateTime now = DateTime.now();

    if (_lastNavigationSpeech != null &&
        now.difference(
              _lastNavigationSpeech!,
            ) <
            const Duration(
              seconds: 8,
            )) {
      return;
    }

    _lastSpokenRouteIndex = nearestIndex;

    _lastNavigationSpeech = now;
  }

  // ============================================================
  // NAVİGASYON TALİMATLARINI GÜNCELLE
  // ============================================================

  void _updateNavigationInstruction(
    LatLng currentLocation,
  ) {
    if (_navigationInstructions.isEmpty) {
      return;
    }

    int bestIndex = _currentInstructionIndex;

    double bestDistance = double.infinity;

    for (int i = _currentInstructionIndex;
        i < _navigationInstructions.length;
        i++) {
      final _NavigationInstruction instruction = _navigationInstructions[i];

      if (instruction.location == null) {
        continue;
      }

      final double distance = Geolocator.distanceBetween(
        currentLocation.latitude,
        currentLocation.longitude,
        instruction.location!.latitude,
        instruction.location!.longitude,
      );

      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }

    if (bestIndex > _currentInstructionIndex) {
      _currentInstructionIndex = bestIndex;
    }

    if (_currentInstructionIndex >= _navigationInstructions.length) {
      return;
    }

    final _NavigationInstruction instruction =
        _navigationInstructions[_currentInstructionIndex];

    if (instruction.location != null) {
      final double distance = Geolocator.distanceBetween(
        currentLocation.latitude,
        currentLocation.longitude,
        instruction.location!.latitude,
        instruction.location!.longitude,
      );

      _currentInstructionDistance = distance;

      double remaining = 0;

      for (int i = _currentInstructionIndex;
          i < _navigationInstructions.length;
          i++) {
        remaining += _navigationInstructions[i].distance;
      }

      _remainingDistance = remaining;

      double duration = 0;

      for (int i = _currentInstructionIndex;
          i < _navigationInstructions.length;
          i++) {
        duration += _navigationInstructions[i].duration;
      }

      _remainingDuration = duration;

      if (mounted) {
        setState(() {});
      }

      _speakNavigationInstructionIfNeeded(
        instruction,
        distance,
      );
    }
  }

  // ============================================================
  // DÖNÜŞ TALİMATINI SESLENDİR
  // ============================================================

  Future<void> _speakNavigationInstructionIfNeeded(
    _NavigationInstruction instruction,
    double distance,
  ) async {
    if (instruction.spokenNow) {
      return;
    }

    final String text = instruction.text;
    String? speakText;

    if (!instruction.isLongLeg) {
      // KISA MESAFE: tek seferlik anons yeterli.
      // Talimat aktif olur olmaz (segment ne kadar kısaysa o kadar erken,
      // en geç 250 m kala) tek seferde söylenir.
      final double announceAt = math.min(instruction.distance, 250);

      if (distance <= announceAt) {
        instruction.spokenNow = true;

        if (distance <= 50) {
          speakText = _localizedInstructionText('now', text);
        } else {
          speakText = _localizedInstructionText(
            'in_distance',
            text,
            distanceText: _formatDistance(distance),
          );
        }
      }

      if (speakText != null) {
        await _speak(speakText);
      }

      return;
    }

    // UZUN MESAFE: 3 aşamalı anons -> ~3 km, ~500 m, şimdi.
    if (distance <= 50) {
      instruction.spokenNow = true;
      instruction.spokenNear = true;
      instruction.spokenFar = true;

      speakText = _localizedInstructionText('now', text);
    } else if (!instruction.spokenNear && distance <= 500) {
      instruction.spokenNear = true;
      instruction.spokenFar = true;

      speakText = _localizedInstructionText(
        'in_distance',
        text,
        distanceText: _formatDistance(distance),
      );
    } else if (!instruction.spokenFar && distance <= 3000) {
      instruction.spokenFar = true;

      speakText = _localizedInstructionText(
        'in_distance',
        text,
        distanceText: _formatDistance(distance),
      );
    }

    if (speakText != null) {
      await _speak(speakText);
    }
  }

  String _localizedInstructionText(
    String kind,
    String text, {
    String? distanceText,
  }) {
    if (kind == 'now') {
      if (_voiceLanguage == 'tr-TR') {
        return 'Şimdi $text';
      } else if (_voiceLanguage == 'en-US') {
        return 'Now $text';
      }
      return 'Jetzt $text';
    }

    // kind == 'in_distance'
    if (_voiceLanguage == 'tr-TR') {
      return '$distanceText sonra $text';
    } else if (_voiceLanguage == 'en-US') {
      return '$text in $distanceText';
    }
    return '$text in $distanceText';
  }

  // ============================================================
  // ROTADAN ÇIKMA
  // ============================================================

  void _checkOffRoute(
    LatLng currentLocation,
  ) {
    if (_isRecalculating || routePoints.isEmpty || destination == null) {
      return;
    }

    double nearestDistance = double.infinity;

    for (final LatLng point in routePoints) {
      final double distance = Geolocator.distanceBetween(
        currentLocation.latitude,
        currentLocation.longitude,
        point.latitude,
        point.longitude,
      );

      if (distance < nearestDistance) {
        nearestDistance = distance;
      }
    }

    if (nearestDistance < 80) {
      return;
    }

    final DateTime now = DateTime.now();

    if (_lastRecalculation != null &&
        now.difference(
              _lastRecalculation!,
            ) <
            const Duration(
              seconds: 20,
            )) {
      return;
    }

    _lastRecalculation = now;

    _recalculateRoute();
  }

  // ============================================================
  // YENİDEN ROTA
  // ============================================================

  Future<void> _recalculateRoute() async {
    if (destination == null ||
        userLocation == null ||
        selectedVehicle == null ||
        _isRecalculating) {
      return;
    }

    _isRecalculating = true;

    if (mounted) {
      setState(() {});
    }

    await _speak(
      _voiceLanguage == 'tr-TR'
          ? 'Rotadan çıktınız. Yeni rota hesaplanıyor.'
          : _voiceLanguage == 'en-US'
              ? 'You left the route. Recalculating.'
              : 'Sie haben die Route verlassen. '
                  'Die Route wird neu berechnet.',
    );

    try {
      await calculateRoute(
        destination!,
        selectedVehicle!,
        showLoading: false,
        announce: false,
      );
    } finally {
      _isRecalculating = false;

      if (mounted) {
        setState(() {});
      }
    }
  }

  // ============================================================
  // HEDEFE VARIŞ
  // ============================================================

  void _checkDestinationReached(
    LatLng currentLocation,
  ) {
    if (destination == null || !_navigationStarted) {
      return;
    }

    final double distance = Geolocator.distanceBetween(
      currentLocation.latitude,
      currentLocation.longitude,
      destination!.latitude,
      destination!.longitude,
    );

    if (distance > 45) {
      return;
    }

    _stopNavigation();

    _speak(
      _voiceLanguage == 'tr-TR'
          ? 'Hedefinize ulaştınız.'
          : _voiceLanguage == 'en-US'
              ? 'You have reached your destination.'
              : 'Sie haben Ihr Ziel erreicht.',
    );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Hedefinize ulaştınız.',
        ),
        duration: Duration(
          seconds: 5,
        ),
      ),
    );
  }

  // ============================================================
  // MESAFE FORMAT
  // ============================================================

  String _formatDistance(
    double meters,
  ) {
    if (meters < 1000) {
      return '${meters.round()} m';
    }

    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  // ============================================================
  // SÜRE FORMAT
  // ============================================================

  String _formatDuration(
    double seconds,
  ) {
    final int totalMinutes = (seconds / 60).round();

    if (totalMinutes < 60) {
      return '$totalMinutes dk';
    }

    final int hours = totalMinutes ~/ 60;

    final int minutes = totalMinutes % 60;

    if (minutes == 0) {
      return '$hours sa';
    }

    return '$hours sa $minutes dk';
  }

  // ============================================================
  // ADRES ARAMA
  // ============================================================

  void onSearchChanged(
    String query,
  ) {
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
    }

    _debounce = Timer(
      const Duration(
        milliseconds: 400,
      ),
      () {
        if (query.trim().length > 2) {
          fetchSuggestions(
            query,
          );
        } else {
          if (!mounted) {
            return;
          }

          setState(() {
            searchSuggestions = <dynamic>[];
          });
        }
      },
    );
  }

  Future<void> fetchSuggestions(
    String query,
  ) async {
    if (!mounted) {
      return;
    }

    setState(() {
      isLoadingSuggestions = true;
    });

    final String url = 'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}'
        '&format=json'
        '&limit=5'
        '&countrycodes=de';

    try {
      final http.Response response = await http.get(
        Uri.parse(url),
        headers: const {
          'User-Agent': 'lkw_almanya_navigation_app',
        },
      );

      if (!mounted) {
        return;
      }

      if (response.statusCode == 200) {
        final dynamic data = jsonDecode(response.body);

        setState(() {
          searchSuggestions = data is List ? data : <dynamic>[];
        });
      }
    } catch (e) {
      debugPrint(
        'SUGGESTION ERROR: $e',
      );
    }

    if (!mounted) {
      return;
    }

    setState(() {
      isLoadingSuggestions = false;
    });
  }

  // ============================================================
  // ADRES SEÇ
  // ============================================================

  void selectSuggestion(
    dynamic item,
  ) {
    try {
      final double lat = double.parse(
        item['lat'].toString(),
      );

      final double lon = double.parse(
        item['lon'].toString(),
      );

      final LatLng selectedLocation = LatLng(
        lat,
        lon,
      );

      FocusScope.of(context).unfocus();

      setState(() {
        destination = selectedLocation;

        searchSuggestions = <dynamic>[];

        addressController.text = item['display_name']?.toString() ?? '';

        routePoints = <LatLng>[];

        alternativeRoutePoints = <List<LatLng>>[];

        _routeRestrictions = <_RouteRestriction>[];

        _navigationStarted = false;

        _navigationInstructions = <_NavigationInstruction>[];

        _currentInstructionIndex = 0;

        _remainingDistance = 0;

        _remainingDuration = 0;
      });

      mapController.rotate(
        0,
      );

      mapController.move(
        selectedLocation,
        14.0,
      );

      showVehicleSelector(
        selectedLocation,
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Adres seçilemedi: $e',
          ),
        ),
      );
    }
  }

  // ============================================================
  // MANUEL ADRES
  // ============================================================

  Future<void> searchAddress(
    String query,
  ) async {
    if (query.trim().isEmpty) {
      return;
    }

    FocusScope.of(context).unfocus();

    final String url = 'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}'
        '&format=json'
        '&limit=1'
        '&countrycodes=de';

    try {
      final http.Response response = await http.get(
        Uri.parse(url),
        headers: const {
          'User-Agent': 'lkw_almanya_navigation_app',
        },
      );

      if (!mounted) {
        return;
      }

      if (response.statusCode != 200) {
        _showRouteError(
          'Adres servisine ulaşılamadı.',
        );

        return;
      }

      final dynamic data = jsonDecode(response.body);

      if (data is! List || data.isEmpty) {
        _showRouteError(
          'Adres bulunamadı.',
        );

        return;
      }

      selectSuggestion(
        data[0],
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      _showRouteError(
        'Arama hatası: $e',
      );
    }
  }

  // ============================================================
  // BAŞLANGIÇ NOKTASI SEÇİCİ
  // ============================================================

  void _showStartPointSelector() {
    final TextEditingController localController = TextEditingController(
      text: _routeStartPoint != null ? _routeStartLabel : '',
    );

    List<dynamic> localSuggestions = <dynamic>[];

    bool localLoading = false;

    Timer? localDebounce;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (
            BuildContext context,
            StateSetter setModalState,
          ) {
            Future<void> runSearch(String query) async {
              if (query.trim().length < 3) {
                setModalState(() {
                  localSuggestions = <dynamic>[];
                });

                return;
              }

              setModalState(() {
                localLoading = true;
              });

              final String url = 'https://nominatim.openstreetmap.org/search'
                  '?q=${Uri.encodeComponent(query)}'
                  '&format=json'
                  '&limit=5'
                  '&countrycodes=de';

              try {
                final http.Response response = await http.get(
                  Uri.parse(url),
                  headers: const {
                    'User-Agent': 'lkw_almanya_navigation_app',
                  },
                );

                if (response.statusCode == 200) {
                  final dynamic data = jsonDecode(response.body);

                  setModalState(() {
                    localSuggestions = data is List ? data : <dynamic>[];
                  });
                }
              } catch (e) {
                debugPrint('BAŞLANGIÇ ARAMA HATASI: $e');
              }

              setModalState(() {
                localLoading = false;
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 8,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Rota Başlangıç Noktası',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        backgroundColor: AppTheme.primaryBlue,
                        child: Icon(
                          Icons.my_location,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      title: const Text(
                        'Güncel Konumum',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      trailing: _routeStartPoint == null
                          ? const Icon(Icons.check_circle,
                              color: AppTheme.primaryBlue)
                          : null,
                      onTap: () {
                        setState(() {
                          _routeStartPoint = null;
                          _routeStartLabel = 'Güncel Konumum';
                        });

                        Navigator.pop(sheetContext);
                      },
                    ),
                    const Divider(),
                    TextField(
                      controller: localController,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Başlangıç adresi yazın',
                        hintStyle: const TextStyle(
                          color: Colors.black45,
                          fontWeight: FontWeight.w400,
                        ),
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: localLoading
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : null,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onChanged: (String value) {
                        if (localDebounce?.isActive ?? false) {
                          localDebounce!.cancel();
                        }

                        localDebounce = Timer(
                          const Duration(milliseconds: 400),
                          () => runSearch(value),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    if (localSuggestions.isNotEmpty)
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: localSuggestions.length,
                          itemBuilder: (
                            BuildContext context,
                            int index,
                          ) {
                            final dynamic item = localSuggestions[index];

                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.place_outlined),
                              title: Text(
                                item['display_name']?.toString() ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.black87,
                                ),
                              ),
                              onTap: () {
                                try {
                                  final double lat = double.parse(
                                    item['lat'].toString(),
                                  );

                                  final double lon = double.parse(
                                    item['lon'].toString(),
                                  );

                                  setState(() {
                                    _routeStartPoint = LatLng(lat, lon);

                                    _routeStartLabel =
                                        item['display_name']?.toString() ??
                                            'Seçilen nokta';
                                  });

                                  Navigator.pop(sheetContext);
                                } catch (e) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Konum seçilemedi: $e'),
                                    ),
                                  );
                                }
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      localDebounce?.cancel();
    });
  }

  Widget _buildStartPointRow() {
    final bool isCustom = _routeStartPoint != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            Icons.trip_origin,
            size: 18,
            color: isCustom ? Colors.orange.shade800 : Colors.green.shade700,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isCustom ? _routeStartLabel : 'Başlangıç: Güncel Konumum',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          TextButton(
            onPressed: _showStartPointSelector,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
            ),
            child: const Text('Değiştir'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HARİTAYA TIKLAMA
  // ============================================================

  void selectMapPoint(
    LatLng point,
  ) {
    FocusScope.of(context).unfocus();

    setState(() {
      destination = point;

      searchSuggestions = <dynamic>[];

      routePoints = <LatLng>[];

      alternativeRoutePoints = <List<LatLng>>[];

      _routeRestrictions = <_RouteRestriction>[];

      _navigationStarted = false;

      _navigationInstructions = <_NavigationInstruction>[];

      _currentInstructionIndex = 0;

      _remainingDistance = 0;

      _remainingDuration = 0;
    });

    showVehicleSelector(
      point,
    );
  }

  // ============================================================
  // ARAÇ SEÇİMİ
  // ============================================================

  void showVehicleSelector(
    LatLng destinationPoint,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (
        BuildContext bottomSheetContext,
      ) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(
              left: 12,
              right: 12,
              bottom: 8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Araç Tipi Seçin',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.black54,
                    ),
                  ),
                ),
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: const CircleAvatar(
                    radius: 16,
                    backgroundColor: AppTheme.truckOrange,
                    child: Icon(
                      Icons.local_shipping,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  title: const Text(
                    'Kamyon (LKW)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: const Text(
                    'Ağır vasıta uyumlu rota',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    size: 20,
                  ),
                  onTap: () {
                    Navigator.pop(
                      bottomSheetContext,
                    );

                    if (!mounted) {
                      return;
                    }

                    setState(() {
                      selectedVehicle = 'truck';
                    });

                    calculateRoute(
                      destinationPoint,
                      'truck',
                    );
                  },
                ),
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: const CircleAvatar(
                    radius: 16,
                    backgroundColor: AppTheme.primaryBlue,
                    child: Icon(
                      Icons.directions_car,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  title: const Text(
                    'Otomobil',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  subtitle: const Text(
                    'Standart araç rotası',
                    style: TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    size: 20,
                  ),
                  onTap: () {
                    Navigator.pop(
                      bottomSheetContext,
                    );

                    if (!mounted) {
                      return;
                    }

                    setState(() {
                      selectedVehicle = 'car';
                    });

                    calculateRoute(
                      destinationPoint,
                      'car',
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // ROTA HESAPLA
  // ============================================================

  Future<void> calculateRoute(
    LatLng destinationPoint,
    String vehicle, {
    bool showLoading = true,
    bool announce = true,
  }) async {
    final LatLng? effectiveStart = _routeStartPoint ?? userLocation;

    if (effectiveStart == null) {
      _showRouteError(
        'Önce mevcut konumunuz alınmalı.',
      );

      return;
    }

    WakelockPlus.enable();

    final LatLng start = effectiveStart;

    // Rota bir kez hesaplandıktan sonra, rotadan sapma durumunda yapılacak
    // yeniden hesaplamalar her zaman güncel GPS konumunu kullanmalı; bu
    // yüzden özel başlangıç noktasını burada sıfırlıyoruz.
    final bool usedCustomStart = _routeStartPoint != null;

    if (!mounted) {
      return;
    }

    if (showLoading) {
      _showRouteLoading();
    }

    try {
      // ========================================================
      // KAMYON - ORS
      // ========================================================

      if (vehicle == 'truck') {
        final String? apiKey = dotenv.env['ORS_API_KEY'];

        if (apiKey == null || apiKey.isEmpty) {
          if (showLoading && mounted) {
            Navigator.of(context).maybePop();
          }

          _showRouteError(
            'ORS API anahtarı bulunamadı.',
          );

          return;
        }

        final http.Response response = await http.post(
          Uri.parse(
            'https://api.openrouteservice.org/'
            'v2/directions/driving-hgv/geojson',
          ),
          headers: {
            'Authorization': apiKey,
            'Content-Type': 'application/json',
          },
          body: jsonEncode(
            {
              'coordinates': [
                [
                  start.longitude,
                  start.latitude,
                ],
                [
                  destinationPoint.longitude,
                  destinationPoint.latitude,
                ],
              ],
              'instructions': true,
              'instructions_format': 'text',
              'language': _orsLanguageCode(),
              'options': {
                'vehicle_type': 'hgv',
                'profile_params': {
                  'restrictions': {
                    'height': math.max(_truckHeight, 3.90),
                    'width': _truckWidth,
                    'length': _truckLength,
                    'weight': _truckWeight,
                    'axleload': _truckAxleLoad,
                    'hazmat': false,
                  },
                },
              },
              'alternative_routes': {
                'target_count': 2,
                'weight_factor': 1.4,
                'share_factor': 0.6,
              },
            },
          ),
        );

        if (!mounted) {
          return;
        }

        if (showLoading) {
          Navigator.of(context).maybePop();
        }

        if (response.statusCode != 200) {
          debugPrint(
            'ORS STATUS: '
            '${response.statusCode}',
          );

          debugPrint(
            'ORS BODY: '
            '${response.body}',
          );

          _showRouteError(
            'Kamyon rota hatası '
            '(${response.statusCode})',
          );

          return;
        }

        final dynamic data = jsonDecode(
          response.body,
        );

        if (data['features'] == null ||
            data['features'] is! List ||
            (data['features'] as List).isEmpty) {
          _showRouteError(
            'Kamyon rotası bulunamadı.',
          );

          return;
        }

        final List orsFeatures = data['features'] as List;

        final dynamic feature = orsFeatures[0];

        final dynamic geometry = feature['geometry'];

        if (geometry == null || geometry['coordinates'] == null) {
          _showRouteError(
            'Kamyon rota geometrisi alınamadı.',
          );

          return;
        }

        final List coordinates = geometry['coordinates'] as List;

        final List<LatLng> points = coordinates.map<LatLng>(
          (dynamic coord) {
            return LatLng(
              (coord[1] as num).toDouble(),
              (coord[0] as num).toDouble(),
            );
          },
        ).toList();

        if (points.isEmpty) {
          _showRouteError(
            'Kamyon rotası boş geldi.',
          );

          return;
        }

        final List<List<LatLng>> truckAlternatives = <List<LatLng>>[];

        for (int i = 1; i < orsFeatures.length; i++) {
          final dynamic altGeometry = orsFeatures[i]['geometry'];

          if (altGeometry == null || altGeometry['coordinates'] == null) {
            continue;
          }

          final List altCoordinates = altGeometry['coordinates'] as List;

          final List<LatLng> altPoints = altCoordinates.map<LatLng>(
            (dynamic coord) {
              return LatLng(
                (coord[1] as num).toDouble(),
                (coord[0] as num).toDouble(),
              );
            },
          ).toList();

          if (altPoints.isNotEmpty) {
            truckAlternatives.add(altPoints);
          }
        }

        final List<_NavigationInstruction> instructions = _parseOrsInstructions(
          feature,
        );

        double totalDistance = 0;

        double totalDuration = 0;

        final dynamic properties = feature['properties'];

        if (properties is Map) {
          final dynamic summary = properties['summary'];

          if (summary is Map) {
            totalDistance = _numberValue(
              summary['distance'],
            );

            totalDuration = _numberValue(
              summary['duration'],
            );
          }
        }

        if (totalDistance <= 0) {
          totalDistance = _calculateRouteDistance(
            points,
          );
        }

        setState(() {
          routeColor = AppTheme.truckOrange;

          routePoints = points;

          alternativeRoutePoints = truckAlternatives;

          if (usedCustomStart) {
            _routeStartPoint = null;
            _routeStartLabel = 'Güncel Konumum';
          }

          _navigationStarted = true;

          _lastSpokenRouteIndex = -1;

          _lastNavigationSpeech = null;

          _isFollowingLocation = true;

          _navigationInstructions = instructions;

          _currentInstructionIndex = 0;

          _remainingDistance = totalDistance;

          _remainingDuration = totalDuration;

          _currentInstructionText = instructions.isNotEmpty
              ? instructions.first.text
              : 'Rotayı takip edin.';

          _currentInstructionDistance =
              instructions.isNotEmpty ? instructions.first.distance : 0;
        });

        _fitRouteOnMap(
          points,
        );

        _fetchRouteRestrictions(points);
        _checkRouteRestrictions();
        _fetchTruckParkings(points);
        _fetchFuelStations(points);
        _fetchSpeedLimits(points);

        _drivingStartTime = DateTime.now();
        _fatigueWarningShown = false;

        _addRouteToHistory(
          destinationPoint,
          'truck',
          addressController.text.isNotEmpty
              ? addressController.text
              : 'Kamyon Rotası',
          totalDistance,
          totalDuration,
        );

        if (announce) {
          await _speak(
            _voiceLanguage == 'tr-TR'
                ? 'Kamyon rotası hazır. Navigasyon başladı.'
                : _voiceLanguage == 'en-US'
                    ? 'Truck route ready. Navigation started.'
                    : 'LKW Route ist bereit. Navigation gestartet.',
          );
        }

        return;
      }

      // ========================================================
      // OTOMOBİL - OSRM
      // ========================================================

      final Uri url = Uri.parse(
        'https://router.project-osrm.org/'
        'route/v1/driving/'
        '${start.longitude},'
        '${start.latitude};'
        '${destinationPoint.longitude},'
        '${destinationPoint.latitude}'
        '?overview=full'
        '&geometries=geojson'
        '&alternatives=2'
        '&steps=true',
      );

      final http.Response response = await http.get(
        url,
      );

      if (!mounted) {
        return;
      }

      if (showLoading) {
        Navigator.of(context).maybePop();
      }

      if (response.statusCode != 200) {
        _showRouteError(
          'Otomobil rota servisi hata verdi: '
          '${response.statusCode}',
        );

        return;
      }

      final dynamic data = jsonDecode(
        response.body,
      );

      final dynamic routes = data['routes'];

      if (routes is List && routes.isNotEmpty) {
        final List<LatLng> mainRoute = _convertCoordinatesToPoints(
          routes[0]['geometry']['coordinates'],
        );

        final List<List<LatLng>> alternatives = <List<LatLng>>[];

        for (int i = 1; i < routes.length; i++) {
          final dynamic route = routes[i];

          if (route['geometry'] != null) {
            final List<LatLng> points = _convertCoordinatesToPoints(
              route['geometry']['coordinates'],
            );

            if (points.isNotEmpty) {
              alternatives.add(
                points,
              );
            }
          }
        }

        if (mainRoute.isEmpty) {
          _showRouteError(
            'Otomobil rotası boş geldi.',
          );

          return;
        }

        final List<_NavigationInstruction> instructions =
            _parseOsrmInstructions(
          routes[0],
        );

        final double totalDistance = _numberValue(
          routes[0]['distance'],
        );

        final double totalDuration = _numberValue(
          routes[0]['duration'],
        );

        setState(() {
          routeColor = AppTheme.primaryBlue;

          routePoints = mainRoute;

          alternativeRoutePoints = alternatives;

          if (usedCustomStart) {
            _routeStartPoint = null;
            _routeStartLabel = 'Güncel Konumum';
          }

          _navigationStarted = true;

          _lastSpokenRouteIndex = -1;

          _lastNavigationSpeech = null;

          _isFollowingLocation = true;

          _navigationInstructions = instructions;

          _currentInstructionIndex = 0;

          _remainingDistance = totalDistance;

          _remainingDuration = totalDuration;

          _currentInstructionText = instructions.isNotEmpty
              ? instructions.first.text
              : 'Rotayı takip edin.';

          _currentInstructionDistance =
              instructions.isNotEmpty ? instructions.first.distance : 0;
        });

        _fitRouteOnMap(
          mainRoute,
        );

        _fetchRouteRestrictions(mainRoute);
        _checkRouteRestrictions();
        _fetchTruckParkings(mainRoute);
        _fetchFuelStations(mainRoute);
        _fetchSpeedLimits(mainRoute);

        _drivingStartTime = DateTime.now();
        _fatigueWarningShown = false;

        _addRouteToHistory(
          destinationPoint,
          'car',
          addressController.text.isNotEmpty
              ? addressController.text
              : 'Otomobil Rotası',
          totalDistance,
          totalDuration,
        );

        if (announce) {
          if (alternatives.isNotEmpty) {
            await _speak(
              _voiceLanguage == 'tr-TR'
                  ? 'Otomobil rotası hazır. '
                      '${alternatives.length} alternatif rota mevcut. '
                      'Haritada renkli çizgilerle gösteriliyor.'
                  : _voiceLanguage == 'en-US'
                      ? 'Car route ready. '
                          '${alternatives.length} alternative routes available. '
                          'Shown as colored lines on the map.'
                      : 'Die Autoroute ist bereit. '
                          '${alternatives.length} alternative Routen verfügbar. '
                          'Als farbige Linien auf der Karte angezeigt.',
            );
          } else {
            await _speak(
              _voiceLanguage == 'tr-TR'
                  ? 'Otomobil rotası hazır. Tek rota mevcut. Navigasyon başladı.'
                  : _voiceLanguage == 'en-US'
                      ? 'Car route ready. Single route available. Navigation started.'
                      : 'Die Autoroute ist bereit. Einzelne Route verfügbar. Navigation gestartet.',
            );
          }
        }
      } else {
        _showRouteError(
          'Otomobil rotası bulunamadı.',
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }

      if (showLoading) {
        Navigator.of(context).maybePop();
      }

      debugPrint(
        'ROTA HATASI: $e',
      );

      _showRouteError(
        'Rota hatası: $e',
      );
    }
  }

  // ============================================================
  // ROTA GEÇMİŞİ
  // ============================================================

  Future<void> _loadRouteHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? saved = prefs.getString(_historyStorageKey);
      if (saved == null || saved.isEmpty) {
        if (mounted) setState(() => _routeHistory = <_RouteHistoryItem>[]);
        return;
      }
      final dynamic decoded = jsonDecode(saved);
      if (decoded is! List) return;
      final List<_RouteHistoryItem> loaded = <_RouteHistoryItem>[];
      for (final dynamic item in decoded) {
        if (item is Map) {
          try {
            loaded.add(
                _RouteHistoryItem.fromJson(Map<String, dynamic>.from(item)));
          } catch (e) {
            debugPrint('HISTORY LOAD ITEM ERROR: $e');
          }
        }
      }
      if (mounted) setState(() => _routeHistory = loaded);
    } catch (e) {
      debugPrint('HISTORY LOAD ERROR: $e');
    }
  }

  Future<void> _saveRouteHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String encoded = jsonEncode(
        _routeHistory.map((item) => item.toJson()).toList(),
      );
      await prefs.setString(_historyStorageKey, encoded);
    } catch (e) {
      debugPrint('HISTORY SAVE ERROR: $e');
    }
  }

  Future<void> _addRouteToHistory(
    LatLng dest,
    String vehicle,
    String name,
    double distance,
    double duration,
  ) async {
    final item = _RouteHistoryItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      destinationName: name,
      destination: dest,
      vehicle: vehicle,
      timestamp: DateTime.now(),
      distance: distance,
      duration: duration,
    );
    setState(() {
      _routeHistory.insert(0, item);
      if (_routeHistory.length > 20) {
        _routeHistory = _routeHistory.sublist(0, 20);
      }
    });
    await _saveRouteHistory();
  }

  void _showRouteHistory() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.72,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.history, color: AppTheme.primaryBlue),
                      SizedBox(width: 10),
                      Text(
                        'Rota Geçmişi',
                        style: TextStyle(
                            fontSize: 21, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: _routeHistory.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(30),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.history,
                                    size: 70, color: Colors.grey),
                                SizedBox(height: 15),
                                Text(
                                  'Henüz rota geçmişi yok.',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          itemCount: _routeHistory.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (BuildContext ctx, int index) {
                            final item = _routeHistory[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: item.vehicle == 'truck'
                                    ? AppTheme.truckOrange
                                    : AppTheme.primaryBlue,
                                child: Icon(
                                  item.vehicle == 'truck'
                                      ? Icons.local_shipping
                                      : Icons.directions_car,
                                  color: Colors.white,
                                ),
                              ),
                              title: Text(
                                item.destinationName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                '${_formatDistance(item.distance)} · ${_formatDuration(item.duration)} · '
                                '${item.timestamp.day}.${item.timestamp.month}.${item.timestamp.year}',
                              ),
                              trailing: IconButton(
                                icon:
                                    const Icon(Icons.delete, color: Colors.red),
                                onPressed: () async {
                                  setState(() => _routeHistory.removeAt(index));
                                  await _saveRouteHistory();
                                  if (!mounted) return;
                                  Navigator.of(context).pop();
                                  _showRouteHistory();
                                },
                              ),
                              onTap: () {
                                final dest = item.destination;
                                final name = item.destinationName;
                                final id = item.id;
                                Navigator.of(context).pop();
                                if (!mounted) return;
                                _selectFavorite(_FavoritePlace(
                                  id: id,
                                  name: name,
                                  latitude: dest.latitude,
                                  longitude: dest.longitude,
                                  address: name,
                                ));
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // DURAKLAR
  // ============================================================

  Future<void> _loadStops() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? saved = prefs.getString(_stopsStorageKey);
      if (saved == null || saved.isEmpty) {
        if (mounted) setState(() => _stops = <_RouteStop>[]);
        return;
      }
      final dynamic decoded = jsonDecode(saved);
      if (decoded is! List) return;
      final List<_RouteStop> loaded = <_RouteStop>[];
      for (final dynamic item in decoded) {
        if (item is Map) {
          try {
            loaded.add(_RouteStop.fromJson(Map<String, dynamic>.from(item)));
          } catch (e) {
            debugPrint('STOPS LOAD ITEM ERROR: $e');
          }
        }
      }
      if (mounted) setState(() => _stops = loaded);
    } catch (e) {
      debugPrint('STOPS LOAD ERROR: $e');
    }
  }

  Future<void> _saveStops() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String encoded = jsonEncode(
        _stops.map((s) => s.toJson()).toList(),
      );
      await prefs.setString(_stopsStorageKey, encoded);
    } catch (e) {
      debugPrint('STOPS SAVE ERROR: $e');
    }
  }

  Future<void> _addStop(LatLng location, String name, String address) async {
    final stop = _RouteStop(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.isNotEmpty ? name : 'Durak ${_stops.length + 1}',
      location: location,
      address: address,
    );
    setState(() => _stops.add(stop));
    await _saveStops();
  }

  Future<void> _removeStop(_RouteStop stop) async {
    setState(() => _stops.removeWhere((s) => s.id == stop.id));
    await _saveStops();
  }

  void _showStopsManager() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.72,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.flag, color: AppTheme.primaryBlue),
                      SizedBox(width: 10),
                      Text(
                        'Duraklar',
                        style: TextStyle(
                            fontSize: 21, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(
                  child: _stops.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(30),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.flag_outlined,
                                    size: 70, color: Colors.grey),
                                SizedBox(height: 15),
                                Text(
                                  'Henüz durak eklenmemiş.',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Haritaya uzun basarak durak ekleyebilirsiniz.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          itemCount: _stops.length,
                          onReorderItem: (oldIndex, newIndex) {
                            setState(() {
                              final item = _stops.removeAt(oldIndex);
                              _stops.insert(newIndex, item);
                            });
                            _saveStops();
                          },
                          itemBuilder: (BuildContext ctx, int index) {
                            final stop = _stops[index];
                            return ListTile(
                              key: ValueKey(stop.id),
                              leading: CircleAvatar(
                                backgroundColor: Colors.green,
                                child: Text('${index + 1}',
                                    style:
                                        const TextStyle(color: Colors.white)),
                              ),
                              title: Text(stop.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                              subtitle: Text(stop.address),
                              trailing: IconButton(
                                icon:
                                    const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _removeStop(stop),
                              ),
                            );
                          },
                        ),
                ),
                if (_stops.length >= 2)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _calculateMultiStopRoute();
                      },
                      icon: const Icon(Icons.route),
                      label: const Text('Çoklu Durak Rotası Hesapla'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _calculateMultiStopRoute() async {
    if (userLocation == null || _stops.isEmpty) return;
    if (_stops.length < 2) {
      _showRouteError('En az 2 durak gerekli.');
      return;
    }

    WakelockPlus.enable();
    _showRouteLoading();

    try {
      final List<LatLng> allPoints = [
        userLocation!,
        ..._stops.map((s) => s.location)
      ];
      final List<LatLng> fullRoute = <LatLng>[];
      double totalDistance = 0;
      double totalDuration = 0;

      for (int i = 0; i < allPoints.length - 1; i++) {
        final LatLng from = allPoints[i];
        final LatLng to = allPoints[i + 1];

        final Uri url = Uri.parse(
          'https://router.project-osrm.org/route/v1/driving/'
          '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
          '?overview=full&geometries=geojson&steps=true',
        );

        final response = await http.get(url);
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final routes = data['routes'];
          if (routes is List && routes.isNotEmpty) {
            final points = _convertCoordinatesToPoints(
              routes[0]['geometry']['coordinates'],
            );
            fullRoute.addAll(points);
            totalDistance += _numberValue(routes[0]['distance']);
            totalDuration += _numberValue(routes[0]['duration']);
          }
        }
      }

      if (!mounted) return;
      Navigator.of(context).maybePop();

      if (fullRoute.isEmpty) {
        _showRouteError('Çoklu durak rotası hesaplanamadı.');
        return;
      }

      setState(() {
        routeColor = AppTheme.primaryBlue;
        routePoints = fullRoute;
        alternativeRoutePoints = <List<LatLng>>[];
        _navigationStarted = true;
        _lastSpokenRouteIndex = -1;
        _lastNavigationSpeech = null;
        _isFollowingLocation = true;
        _navigationInstructions = <_NavigationInstruction>[];
        _currentInstructionIndex = 0;
        _remainingDistance = totalDistance;
        _remainingDuration = totalDuration;
        _currentInstructionText = 'Rotayı takip edin.';
        _currentInstructionDistance = 0;
      });

      _fitRouteOnMap(fullRoute);
      _fetchRouteRestrictions(fullRoute);
      _fetchTruckParkings(fullRoute);
      _fetchFuelStations(fullRoute);
      _fetchSpeedLimits(fullRoute);

      await _speak(
        _voiceLanguage == 'tr-TR'
            ? 'Çoklu durak rotası hazır. ${_stops.length} durak.'
            : _voiceLanguage == 'en-US'
                ? 'Multi-stop route ready. ${_stops.length} stops.'
                : 'Mehrstopp-Route bereit. ${_stops.length} Stopps.',
      );
    } catch (e) {
      if (mounted) Navigator.of(context).maybePop();
      _showRouteError('Çoklu durak hatası: $e');
    }
  }

  // ============================================================
  // TIR PARK / YAKIT / HIZ / YORGUNLUK / GECE / PAYLAŞ
  // ============================================================

  Future<void> _fetchTruckParkings(List<LatLng> points) async {
    if (points.isEmpty) return;
    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    const double pad = 0.05;
    minLat -= pad;
    maxLat += pad;
    minLng -= pad;
    maxLng += pad;

    final String query = '''[out:json][timeout:25];
(
  node["amenity"="truck_parking"]($minLat,$minLng,$maxLat,$maxLng);
  way["amenity"="truck_parking"]($minLat,$minLng,$maxLat,$maxLng);
  node["highway"="services"]($minLat,$minLng,$maxLat,$maxLng);
  way["highway"="services"]($minLat,$minLng,$maxLat,$maxLng);
  node["amenity"="rest_area"]($minLat,$minLng,$maxLat,$maxLng);
  way["amenity"="rest_area"]($minLat,$minLng,$maxLat,$maxLng);
);
out center;''';

    try {
      final response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: query,
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      );
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body);
      final List<dynamic> elements =
          data['elements'] is List ? data['elements'] as List : <dynamic>[];
      final List<_TruckParking> parkings = <_TruckParking>[];
      for (final dynamic element in elements) {
        if (element is! Map) {
          continue;
        }
        if (element['type']?.toString() != 'way' &&
            element['type']?.toString() != 'node') {
          continue;
        }
        final tags = Map<String, dynamic>.from(element['tags'] as Map? ?? {});
        double? lat, lon;
        if (element['type']?.toString() == 'node') {
          lat = (element['lat'] as num?)?.toDouble();
          lon = (element['lon'] as num?)?.toDouble();
        } else {
          final center =
              Map<String, dynamic>.from(element['center'] as Map? ?? {});
          lat = (center['lat'] as num?)?.toDouble();
          lon = (center['lon'] as num?)?.toDouble();
        }
        if (lat == null || lon == null) {
          continue;
        }
        parkings.add(_TruckParking(
          location: LatLng(lat, lon),
          name: tags['name']?.toString() ?? 'TIR Parkı',
          capacity: tags['capacity']?.toString(),
          hasRestaurant: tags['restaurant']?.toString() == 'yes' ||
              tags['food']?.toString() == 'yes',
          hasShower: tags['shower']?.toString() == 'yes',
          hasFuel: tags['fuel']?.toString() == 'yes',
        ));
      }
      if (mounted) setState(() => _truckParkings = parkings);
    } catch (e) {
      debugPrint('TRUCK PARKING ERROR: $e');
    }
  }

  Future<void> _fetchFuelStations(List<LatLng> points) async {
    if (points.isEmpty) return;
    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    const double pad = 0.05;
    minLat -= pad;
    maxLat += pad;
    minLng -= pad;
    maxLng += pad;

    final String query = '''[out:json][timeout:25];
(
  node["amenity"="fuel"]["hgv"="yes"]($minLat,$minLng,$maxLat,$maxLng);
  node["amenity"="fuel"]["truck"="yes"]($minLat,$minLng,$maxLat,$maxLng);
  way["amenity"="fuel"]["hgv"="yes"]($minLat,$minLng,$maxLat,$maxLng);
);
out center;''';

    try {
      final response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: query,
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      );
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body);
      final List<dynamic> elements =
          data['elements'] is List ? data['elements'] as List : <dynamic>[];
      final List<_FuelStation> stations = <_FuelStation>[];
      for (final dynamic element in elements) {
        if (element is! Map) {
          continue;
        }
        final tags = Map<String, dynamic>.from(element['tags'] as Map? ?? {});
        double? lat, lon;
        if (element['type']?.toString() == 'node') {
          lat = (element['lat'] as num?)?.toDouble();
          lon = (element['lon'] as num?)?.toDouble();
        } else {
          final center =
              Map<String, dynamic>.from(element['center'] as Map? ?? {});
          lat = (center['lat'] as num?)?.toDouble();
          lon = (center['lon'] as num?)?.toDouble();
        }
        if (lat == null || lon == null) {
          continue;
        }
        stations.add(_FuelStation(
          location: LatLng(lat, lon),
          name: tags['name']?.toString() ?? 'Yakıt İstasyonu',
          hgvFriendly: tags['hgv']?.toString() == 'yes' ||
              tags['truck']?.toString() == 'yes',
          hasAdBlue: tags['adblue']?.toString() == 'yes' ||
              tags['fuel:adblue']?.toString() == 'yes',
          hasRestaurant: tags['restaurant']?.toString() == 'yes',
        ));
      }
      if (mounted) setState(() => _fuelStations = stations);
    } catch (e) {
      debugPrint('FUEL STATION ERROR: $e');
    }
  }

  Future<void> _fetchSpeedLimits(List<LatLng> points) async {
    if (points.isEmpty) return;
    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    const double pad = 0.02;
    minLat -= pad;
    maxLat += pad;
    minLng -= pad;
    maxLng += pad;

    final String query = '''[out:json][timeout:25];
(
  way["maxspeed"]($minLat,$minLng,$maxLat,$maxLng);
);
out geom;''';

    try {
      final response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: query,
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      );
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body);
      final List<dynamic> elements =
          data['elements'] is List ? data['elements'] as List : <dynamic>[];
      final List<_SpeedLimitSegment> limits = <_SpeedLimitSegment>[];
      for (final dynamic element in elements) {
        if (element is! Map) {
          continue;
        }
        if (element['type']?.toString() != 'way') {
          continue;
        }
        final tags = Map<String, dynamic>.from(element['tags'] as Map? ?? {});
        final maxspeedStr = tags['maxspeed']?.toString() ?? '';
        final int? maxspeed =
            int.tryParse(maxspeedStr.replaceAll(RegExp(r'[^0-9]'), ''));
        if (maxspeed == null || maxspeed <= 0) {
          continue;
        }
        final List<dynamic> geometry = element['geometry'] is List
            ? element['geometry'] as List
            : <dynamic>[];
        if (geometry.length < 2) {
          continue;
        }
        for (int i = 0; i < geometry.length - 1; i++) {
          final start = geometry[i];
          final end = geometry[i + 1];
          if (start is Map && end is Map) {
            final sLat = (start['lat'] as num?)?.toDouble();
            final sLon = (start['lon'] as num?)?.toDouble();
            final eLat = (end['lat'] as num?)?.toDouble();
            final eLon = (end['lon'] as num?)?.toDouble();
            if (sLat != null && sLon != null && eLat != null && eLon != null) {
              limits.add(_SpeedLimitSegment(
                start: LatLng(sLat, sLon),
                end: LatLng(eLat, eLon),
                maxSpeed: maxspeed,
              ));
            }
          }
        }
      }
      if (mounted) setState(() => _speedLimits = limits);
    } catch (e) {
      debugPrint('SPEED LIMIT ERROR: $e');
    }
  }

  void _updateCurrentSpeedLimit(LatLng currentLocation) {
    if (_speedLimits.isEmpty) return;
    double bestDistance = double.infinity;
    int bestSpeed = 0;
    for (final seg in _speedLimits) {
      final midLat = (seg.start.latitude + seg.end.latitude) / 2;
      final midLng = (seg.start.longitude + seg.end.longitude) / 2;
      final dist = Geolocator.distanceBetween(
        currentLocation.latitude,
        currentLocation.longitude,
        midLat,
        midLng,
      );
      if (dist < bestDistance) {
        bestDistance = dist;
        bestSpeed = seg.maxSpeed;
      }
    }
    if (bestDistance < 100 && bestSpeed != _currentSpeedLimit) {
      setState(() => _currentSpeedLimit = bestSpeed);
    }
  }

  void _checkFatigue() {
    if (_drivingStartTime == null || !_navigationStarted) return;
    final elapsed = DateTime.now().difference(_drivingStartTime!);
    if (elapsed.inMinutes >= 270 && !_fatigueWarningShown) {
      _fatigueWarningShown = true;
      _speak(
        _voiceLanguage == 'tr-TR'
            ? 'Dikkat! 4.5 saatlik sürüş süreniz doldu. Mola vermeniz gerekiyor.'
            : _voiceLanguage == 'en-US'
                ? 'Attention! Your 4.5 hour driving time is up. You need to take a break.'
                : 'Achtung! Ihre 4,5 Stunden Fahrzeit ist abgelaufen. Sie müssen eine Pause machen.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ 4.5 saat doldu! Mola zamanı.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 10),
          ),
        );
      }
    }
  }

  void _toggleDarkMode() {
    setState(() => _isDarkMode = !_isDarkMode);
    _speak(
      _voiceLanguage == 'tr-TR'
          ? _isDarkMode
              ? 'Gece modu açıldı.'
              : 'Gündüz modu açıldı.'
          : _voiceLanguage == 'en-US'
              ? _isDarkMode
                  ? 'Dark mode enabled.'
                  : 'Light mode enabled.'
              : _isDarkMode
                  ? 'Dunkelmodus aktiviert.'
                  : 'Hellmodus aktiviert.',
    );
  }

  String get _tileUrlTemplate {
    if (_isDarkMode) {
      return 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
    }
    return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  }

  Future<void> _shareRoute() async {
    if (destination == null) {
      _showRouteError('Paylaşılacak hedef yok.');
      return;
    }
    final String url =
        'https://www.google.com/maps/search/?api=1&query=${destination!.latitude},${destination!.longitude}';
    final String text = _voiceLanguage == 'tr-TR'
        ? 'Navigasyon hedefim: ${addressController.text.isNotEmpty ? addressController.text : "Konum"}\n$url'
        : _voiceLanguage == 'en-US'
            ? 'My navigation destination: ${addressController.text.isNotEmpty ? addressController.text : "Location"}\n$url'
            : 'Mein Navigationsziel: ${addressController.text.isNotEmpty ? addressController.text : "Standort"}\n$url';
    await Share.share(text);
  }

  // ============================================================
  // ALTERNATİF ROTA SEÇ
  // ============================================================

  void _selectAlternativeRoute(int index) {
    if (index < 0 || index >= alternativeRoutePoints.length) return;

    final List<LatLng> selected = alternativeRoutePoints[index];
    final List<LatLng> oldMain = List<LatLng>.from(routePoints);

    setState(() {
      routePoints = selected;
      alternativeRoutePoints[index] = oldMain;
      _lastSpokenRouteIndex = -1;
      _lastNavigationSpeech = null;
      _currentInstructionIndex = 0;
    });

    _fitRouteOnMap(routePoints);

    _speak(
      _voiceLanguage == 'tr-TR'
          ? 'Alternatif rota seçildi.'
          : _voiceLanguage == 'en-US'
              ? 'Alternative route selected.'
              : 'Alternative Route ausgewählt.',
    );
  }

  // ============================================================
  // ROTA KISITLAMALARINI ÇEK (Overpass API)
  // ============================================================

  Future<void> _fetchRouteRestrictions(List<LatLng> points) async {
    if (points.isEmpty) return;

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final LatLng p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final double latPad = (maxLat - minLat) * 0.1 + 0.01;
    final double lngPad = (maxLng - minLng) * 0.1 + 0.01;
    minLat -= latPad;
    maxLat += latPad;
    minLng -= lngPad;
    maxLng += lngPad;

    final String query = '''[out:json][timeout:25];
(
  way["maxheight"]($minLat,$minLng,$maxLat,$maxLng);
  way["maxweight"]($minLat,$minLng,$maxLat,$maxLng);
  way["maxwidth"]($minLat,$minLng,$maxLat,$maxLng);
  way["maxlength"]($minLat,$minLng,$maxLat,$maxLng);
  way["hgv"="no"]($minLat,$minLng,$maxLat,$maxLng);
  way["access"="no"]($minLat,$minLng,$maxLat,$maxLng);
  way["highway"="construction"]($minLat,$minLng,$maxLat,$maxLng);
  way["motor_vehicle"="no"]($minLat,$minLng,$maxLat,$maxLng);
);
out center;''';

    try {
      final http.Response response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        body: query,
        headers: const {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
      );

      if (response.statusCode != 200) return;

      final dynamic data = jsonDecode(response.body);
      final List<dynamic> elements =
          data['elements'] is List ? data['elements'] as List : <dynamic>[];

      final List<_RouteRestriction> restrictions = <_RouteRestriction>[];

      for (final dynamic element in elements) {
        if (element is! Map) {
          continue;
        }
        if (element['type']?.toString() != 'way') {
          continue;
        }

        final Map<String, dynamic> tags =
            Map<String, dynamic>.from(element['tags'] as Map? ?? {});
        final Map<String, dynamic> center =
            Map<String, dynamic>.from(element['center'] as Map? ?? {});
        final double? lat = (center['lat'] as num?)?.toDouble();
        final double? lon = (center['lon'] as num?)?.toDouble();

        if (lat == null || lon == null) {
          continue;
        }

        final LatLng location = LatLng(lat, lon);

        if (tags['maxheight'] != null) {
          restrictions.add(_RouteRestriction(
            location: location,
            type: 'maxheight',
            value: tags['maxheight']?.toString(),
            description: 'Max Yükseklik: ${tags['maxheight']} m',
          ));
        }
        if (tags['maxweight'] != null) {
          restrictions.add(_RouteRestriction(
            location: location,
            type: 'maxweight',
            value: tags['maxweight']?.toString(),
            description: 'Max Ağırlık: ${tags['maxweight']} t',
          ));
        }
        if (tags['maxwidth'] != null) {
          restrictions.add(_RouteRestriction(
            location: location,
            type: 'maxwidth',
            value: tags['maxwidth']?.toString(),
            description: 'Max Genişlik: ${tags['maxwidth']} m',
          ));
        }
        if (tags['maxlength'] != null) {
          restrictions.add(_RouteRestriction(
            location: location,
            type: 'maxlength',
            value: tags['maxlength']?.toString(),
            description: 'Max Uzunluk: ${tags['maxlength']} m',
          ));
        }
        if (tags['hgv']?.toString() == 'no') {
          restrictions.add(_RouteRestriction(
            location: location,
            type: 'hgv_no',
            value: null,
            description: 'Kamyon Giremez',
          ));
        }
        if (tags['access']?.toString() == 'no' ||
            tags['access']?.toString() == 'private') {
          restrictions.add(_RouteRestriction(
            location: location,
            type: 'closed',
            value: null,
            description: 'Kapalı Yol',
          ));
        }
        if (tags['highway']?.toString() == 'construction') {
          restrictions.add(_RouteRestriction(
            location: location,
            type: 'construction',
            value: null,
            description: 'Yapım Aşamasında',
          ));
        }
      }

      if (mounted) {
        setState(() {
          _routeRestrictions = restrictions;
        });
      }
    } catch (e) {
      debugPrint('OVERPASS ERROR: \$e');
    }
  }

  // ============================================================
  // KISITLAMA İKONU
  // ============================================================

  Widget _buildRestrictionMarker(_RouteRestriction r) {
    IconData icon;
    Color color;

    switch (r.type) {
      case 'maxheight':
        icon = Icons.height;
        color = Colors.orange;
        break;
      case 'maxweight':
        icon = Icons.scale;
        color = Colors.deepOrange;
        break;
      case 'maxwidth':
        icon = Icons.straighten;
        color = Colors.purple;
        break;
      case 'maxlength':
        icon = Icons.linear_scale;
        color = Colors.indigo;
        break;
      case 'hgv_no':
        icon = Icons.block;
        color = Colors.red;
        break;
      case 'closed':
        icon = Icons.do_not_disturb_on;
        color = Colors.grey;
        break;
      case 'construction':
        icon = Icons.construction;
        color = Colors.brown;
        break;
      default:
        icon = Icons.warning;
        color = Colors.amber;
    }

    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(r.description),
            duration: const Duration(seconds: 3),
          ),
        );
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 4),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  // ============================================================
  // ROTA ÜZERİNDEKİ KISITLAMALARI KONTROL ET VE UYAR
  // ALTERNATİF ROTA ÖNER
  // ============================================================

  void _checkRouteRestrictions() {
    if (_routeRestrictions.isEmpty) return;

    int closedCount = 0;
    int hgvBanCount = 0;
    int constructionCount = 0;
    int heightCount = 0;
    int weightCount = 0;

    for (final r in _routeRestrictions) {
      switch (r.type) {
        case 'closed':
          {
            closedCount++;
            break;
          }
        case 'hgv_no':
          {
            hgvBanCount++;
            break;
          }
        case 'construction':
          {
            constructionCount++;
            break;
          }
        case 'maxheight':
          {
            heightCount++;
            break;
          }
        case 'maxweight':
          {
            weightCount++;
            break;
          }
      }
    }

    if (closedCount == 0 &&
        hgvBanCount == 0 &&
        constructionCount == 0 &&
        heightCount == 0 &&
        weightCount == 0) {
      return;
    }

    // Düşük köprü kontrolü (3.90m altı)
    int lowBridgeCount = 0;
    for (final r in _routeRestrictions) {
      if (r.type == 'maxheight' && r.value != null) {
        final double? bridgeHeight = double.tryParse(r.value!);
        if (bridgeHeight != null && bridgeHeight < 3.90) {
          lowBridgeCount++;
        }
      }
    }

    String warning = '';
    String speech = '';
    String alertTitle = '';
    String alertContent = '';
    String alertYes = '';
    String alertNo = '';

    if (_voiceLanguage == 'tr-TR') {
      final List<String> parts = <String>[];
      if (closedCount > 0) parts.add('$closedCount kapalı yol');
      if (hgvBanCount > 0) parts.add('$hgvBanCount kamyon yasağı');
      if (constructionCount > 0) parts.add('$constructionCount yol çalışması');
      if (heightCount > 0) parts.add('$heightCount yükseklik sınırı');
      if (weightCount > 0) parts.add('$weightCount ağırlık sınırı');
      warning = '⚠️ Rota üzerinde: ${parts.join(', ')}';
      speech =
          'Dikkat! Rota üzerinde ${parts.join(', ')} var. Lütfen dikkatli sürün.';
      alertTitle = 'Rota Kısıtlaması Tespit Edildi';
      alertContent =
          'Mevcut rotada ${parts.join(', ')} bulundu.\n\nAlternatif rota kullanılsın mı?';
      alertYes = 'Evet, Alternatif Rota';
      alertNo = 'Hayır, Bu Rotayı Takip Et';
    } else if (_voiceLanguage == 'en-US') {
      final List<String> parts = <String>[];
      if (closedCount > 0)
        parts.add('$closedCount closed road${closedCount > 1 ? 's' : ''}');
      if (hgvBanCount > 0)
        parts.add('$hgvBanCount truck ban${hgvBanCount > 1 ? 's' : ''}');
      if (constructionCount > 0)
        parts.add(
            '$constructionCount construction zone${constructionCount > 1 ? 's' : ''}');
      if (heightCount > 0)
        parts.add('$heightCount height limit${heightCount > 1 ? 's' : ''}');
      if (weightCount > 0)
        parts.add('$weightCount weight limit${weightCount > 1 ? 's' : ''}');
      if (lowBridgeCount > 0)
        parts.add(
            '$lowBridgeCount low bridge${lowBridgeCount > 1 ? 's' : ''} (<3.90m)');
      warning = '⚠️ On route: ${parts.join(', ')}';
      speech =
          'Attention! On route: ${parts.join(', ')}. Please drive carefully.';
      alertTitle = 'Route Restriction Detected';
      alertContent =
          'Current route has ${parts.join(', ')}.\n\nUse alternative route?';
      alertYes = 'Yes, Alternative Route';
      alertNo = 'No, Follow This Route';
    } else {
      final List<String> parts = <String>[];
      if (closedCount > 0)
        parts.add('$closedCount gesperrte Straße${closedCount > 1 ? 'n' : ''}');
      if (hgvBanCount > 0)
        parts.add('$hgvBanCount LKW-Verbot${hgvBanCount > 1 ? 'e' : ''}');
      if (constructionCount > 0)
        parts.add(
            '$constructionCount Baustelle${constructionCount > 1 ? 'n' : ''}');
      if (heightCount > 0)
        parts.add('$heightCount Höhenbegrenzung${heightCount > 1 ? 'en' : ''}');
      if (weightCount > 0)
        parts.add(
            '$weightCount Gewichtsbegrenzung${weightCount > 1 ? 'en' : ''}');
      if (lowBridgeCount > 0)
        parts.add(
            '$lowBridgeCount niedrige Brücke${lowBridgeCount > 1 ? 'n' : ''} (<3,90m)');
      warning = '⚠️ Auf der Route: ${parts.join(', ')}';
      speech =
          'Achtung! Auf der Route: ${parts.join(', ')}. Bitte fahren Sie vorsichtig.';
      alertTitle = 'Routenbeschränkung erkannt';
      alertContent =
          'Aktuelle Route hat ${parts.join(', ')}.\n\nAlternative Route verwenden?';
      alertYes = 'Ja, Alternative Route';
      alertNo = 'Nein, dieser Route folgen';
    }

    setState(() {
      _routeRestrictionWarning = warning;
    });

    _speak(speech);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(warning),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Tamam',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    }

    // Ciddi kısıtlama varsa ve alternatif rota mevcutsa kullanıcıya sor
    final bool hasSeriousRestriction = closedCount > 0 ||
        hgvBanCount > 0 ||
        constructionCount > 0 ||
        lowBridgeCount > 0;
    if (hasSeriousRestriction && alternativeRoutePoints.isNotEmpty && mounted) {
      _showAlternativeRouteDialog(alertTitle, alertContent, alertYes, alertNo);
    }
  }

  // ============================================================
  // ALTERNATİF ROTA DİYALOĞU
  // ============================================================

  Future<void> _showAlternativeRouteDialog(
    String title,
    String content,
    String yesLabel,
    String noLabel,
  ) async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final bool? useAlternative = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          icon: const Icon(Icons.alt_route, color: Colors.orange, size: 40),
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(noLabel),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.map),
              label: Text(yesLabel),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );

    if (useAlternative == true &&
        mounted &&
        alternativeRoutePoints.isNotEmpty) {
      _selectAlternativeRoute(0);
      _speak(
        _voiceLanguage == 'tr-TR'
            ? 'Alternatif rota seçildi. Kısıtlama olmayan yoldan gidin.'
            : _voiceLanguage == 'en-US'
                ? 'Alternative route selected. Follow the unrestricted road.'
                : 'Alternative Route ausgewählt. Folgen Sie der unbeschränkten Straße.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Alternatif rota seçildi.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  // ============================================================
  // ORS DİL
  // ============================================================

  String _orsLanguageCode() {
    if (_voiceLanguage == 'tr-TR') {
      return 'tr';
    }

    if (_voiceLanguage == 'en-US') {
      return 'en';
    }

    return 'de';
  }

  // ============================================================
  // ORS TALİMATLARI
  // ============================================================

  List<_NavigationInstruction> _parseOrsInstructions(
    dynamic feature,
  ) {
    final List<_NavigationInstruction> result = <_NavigationInstruction>[];

    if (feature is! Map) {
      return result;
    }

    final dynamic properties = feature['properties'];

    if (properties is! Map) {
      return result;
    }

    final dynamic segments = properties['segments'];

    if (segments is! List) {
      return result;
    }

    for (final dynamic segment in segments) {
      if (segment is! Map) {
        continue;
      }

      final dynamic steps = segment['steps'];

      if (steps is! List) {
        continue;
      }

      for (final dynamic step in steps) {
        if (step is! Map) {
          continue;
        }

        final String instruction = step['instruction']?.toString() ?? '';

        if (instruction.isEmpty) {
          continue;
        }

        final double distance = _numberValue(
          step['distance'],
        );

        final double duration = _numberValue(
          step['duration'],
        );

        LatLng? location;

        final dynamic wayPoints = step['way_points'];

        if (wayPoints is List && wayPoints.isNotEmpty) {
          final int index = (wayPoints.first as num).toInt();

          final dynamic geometry = feature['geometry'];

          if (geometry is Map) {
            final dynamic coords = geometry['coordinates'];

            if (coords is List && index >= 0 && index < coords.length) {
              final dynamic coord = coords[index];

              if (coord is List && coord.length >= 2) {
                location = LatLng(
                  (coord[1] as num).toDouble(),
                  (coord[0] as num).toDouble(),
                );
              }
            }
          }
        }

        result.add(
          _NavigationInstruction(
            text: instruction,
            distance: distance,
            duration: duration,
            location: location,
          ),
        );
      }
    }

    return result;
  }

  // ============================================================
  // OSRM TALİMATLARI
  // ============================================================

  List<_NavigationInstruction> _parseOsrmInstructions(
    dynamic route,
  ) {
    final List<_NavigationInstruction> result = <_NavigationInstruction>[];

    if (route is! Map) {
      return result;
    }

    final dynamic legs = route['legs'];

    if (legs is! List) {
      return result;
    }

    for (final dynamic leg in legs) {
      if (leg is! Map) {
        continue;
      }

      final dynamic steps = leg['steps'];

      if (steps is! List) {
        continue;
      }

      for (final dynamic step in steps) {
        if (step is! Map) {
          continue;
        }

        final dynamic maneuver = step['maneuver'];

        String instruction = _createOsrmInstruction(
          maneuver,
          step['name'],
        );

        if (instruction.isEmpty) {
          instruction = 'Rotayı takip edin';
        }

        final double distance = _numberValue(
          step['distance'],
        );

        final double duration = _numberValue(
          step['duration'],
        );

        LatLng? location;

        if (maneuver is Map) {
          final dynamic locationData = maneuver['location'];

          if (locationData is List && locationData.length >= 2) {
            location = LatLng(
              (locationData[1] as num).toDouble(),
              (locationData[0] as num).toDouble(),
            );
          }
        }

        result.add(
          _NavigationInstruction(
            text: instruction,
            distance: distance,
            duration: duration,
            location: location,
          ),
        );
      }
    }

    return result;
  }

  // ============================================================
  // OSRM TALİMATI OLUŞTUR
  // ============================================================

  String _createOsrmInstruction(
    dynamic maneuver,
    dynamic roadName,
  ) {
    if (maneuver is! Map) {
      return '';
    }

    final String type = maneuver['type']?.toString() ?? '';

    final String modifier = maneuver['modifier']?.toString() ?? '';

    final String road = roadName?.toString() ?? '';

    String action;

    if (type == 'depart') {
      action = _localizedText(
        'Yola çıkın',
        'Start driving',
        'Fahren Sie los',
      );
    } else if (type == 'arrive') {
      action = _localizedText(
        'Hedefinize ulaştınız',
        'You have arrived',
        'Sie haben Ihr Ziel erreicht',
      );
    } else if (type == 'roundabout' || type == 'rotary') {
      action = _localizedText(
        'Döner kavşaktan çıkın',
        'Exit the roundabout',
        'Verlassen Sie den Kreisverkehr',
      );
    } else if (type == 'merge') {
      action = _localizedText(
        'Birleşin',
        'Merge',
        'Einfädeln',
      );
    } else if (type == 'fork') {
      action = _localizedText(
        'Yoldan ayrılın',
        'Take the fork',
        'An der Gabelung abbiegen',
      );
    } else if (type == 'on_ramp') {
      action = _localizedText(
        'Rampaya girin',
        'Take the ramp',
        'Nehmen Sie die Auffahrt',
      );
    } else if (type == 'off_ramp') {
      action = _localizedText(
        'Rampadan çıkın',
        'Take the exit ramp',
        'Nehmen Sie die Ausfahrt',
      );
    } else if (type == 'new name') {
      action = _localizedText(
        'Yola devam edin',
        'Continue',
        'Fahren Sie weiter',
      );
    } else if (modifier.contains('left')) {
      action = _localizedText(
        'Sola dönün',
        'Turn left',
        'Biegen Sie links ab',
      );
    } else if (modifier.contains('right')) {
      action = _localizedText(
        'Sağa dönün',
        'Turn right',
        'Biegen Sie rechts ab',
      );
    } else if (modifier == 'straight') {
      action = _localizedText(
        'Düz devam edin',
        'Continue straight',
        'Fahren Sie geradeaus',
      );
    } else if (modifier.contains('uturn')) {
      action = _localizedText(
        'U dönüşü yapın',
        'Make a U-turn',
        'Machen Sie eine Kehrtwende',
      );
    } else {
      action = _localizedText(
        'Rotayı takip edin',
        'Follow the route',
        'Folgen Sie der Route',
      );
    }

    if (road.isNotEmpty && type != 'arrive') {
      return '$action: $road';
    }

    return action;
  }

  // ============================================================
  // ÇOKLU DİL
  // ============================================================

  String _localizedText(
    String tr,
    String en,
    String de,
  ) {
    if (_voiceLanguage == 'tr-TR') {
      return tr;
    }

    if (_voiceLanguage == 'en-US') {
      return en;
    }

    return de;
  }

  // ============================================================
  // SAYI
  // ============================================================

  double _numberValue(
    dynamic value,
  ) {
    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(
          value?.toString() ?? '',
        ) ??
        0;
  }

  // ============================================================
  // ROTA MESAFESİ
  // ============================================================

  double _calculateRouteDistance(
    List<LatLng> points,
  ) {
    double total = 0;

    for (int i = 1; i < points.length; i++) {
      total += Geolocator.distanceBetween(
        points[i - 1].latitude,
        points[i - 1].longitude,
        points[i].latitude,
        points[i].longitude,
      );
    }

    return total;
  }

  // ============================================================
  // KOORDİNATLAR
  // ============================================================

  List<LatLng> _convertCoordinatesToPoints(
    dynamic coordinates,
  ) {
    if (coordinates is! List) {
      return const <LatLng>[];
    }

    return coordinates.map<LatLng>(
      (dynamic coord) {
        return LatLng(
          (coord[1] as num).toDouble(),
          (coord[0] as num).toDouble(),
        );
      },
    ).toList();
  }

  // ============================================================
  // ROTA YÜKLENİYOR
  // ============================================================

  void _showRouteLoading() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (
        BuildContext dialogContext,
      ) {
        return const AlertDialog(
          content: Row(
            children: [
              SizedBox(
                width: 25,
                height: 25,
                child: CircularProgressIndicator(),
              ),
              SizedBox(
                width: 20,
              ),
              Expanded(
                child: Text(
                  'Rota hesaplanıyor...',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // HATA
  // ============================================================

  void _showRouteError(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
        ),
        duration: const Duration(
          seconds: 5,
        ),
      ),
    );
  }

  // ============================================================
  // ROTAYI EKRANA SIĞDIR
  // ============================================================

  void _fitRouteOnMap(
    List<LatLng> points,
  ) {
    if (points.isEmpty) {
      return;
    }

    double minLat = points.first.latitude;

    double maxLat = points.first.latitude;

    double minLng = points.first.longitude;

    double maxLng = points.first.longitude;

    for (final LatLng point in points) {
      if (point.latitude < minLat) {
        minLat = point.latitude;
      }

      if (point.latitude > maxLat) {
        maxLat = point.latitude;
      }

      if (point.longitude < minLng) {
        minLng = point.longitude;
      }

      if (point.longitude > maxLng) {
        maxLng = point.longitude;
      }
    }

    final LatLng center = LatLng(
      (minLat + maxLat) / 2,
      (minLng + maxLng) / 2,
    );

    try {
      mapController.move(
        center,
        _calculateZoom(
          minLat,
          maxLat,
          minLng,
          maxLng,
        ),
      );
    } catch (e) {
      debugPrint(
        'MAP MOVE ERROR (_fitRouteOnMap): $e',
      );
    }

    if (_navigationStarted && userLocation != null) {
      _isFollowingLocation = true;

      _moveMapWithDirection(
        userLocation!,
        _currentHeading,
      );
    }
  }

  double _calculateZoom(
    double minLat,
    double maxLat,
    double minLng,
    double maxLng,
  ) {
    final double latDifference = (maxLat - minLat).abs();

    final double lngDifference = (maxLng - minLng).abs();

    final double difference =
        latDifference > lngDifference ? latDifference : lngDifference;

    if (difference > 5) {
      return 6;
    }

    if (difference > 2) {
      return 7;
    }

    if (difference > 1) {
      return 8;
    }

    if (difference > 0.5) {
      return 9;
    }

    if (difference > 0.2) {
      return 10;
    }

    if (difference > 0.1) {
      return 11;
    }

    if (difference > 0.05) {
      return 12;
    }

    if (difference > 0.02) {
      return 13;
    }

    return 14;
  }

  // ============================================================
  // ARAMA KUTUSU
  // ============================================================

  Widget _buildSearchBox() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(
          14,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(
              0,
              3,
            ),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 12,
          ),
          const Icon(
            Icons.search,
            color: Colors.grey,
          ),
          const SizedBox(
            width: 8,
          ),
          Expanded(
            child: TextField(
              controller: addressController,
              textInputAction: TextInputAction.search,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              cursorColor: AppTheme.primaryBlue,
              decoration: const InputDecoration(
                hintText: 'Adres yazın veya konuşun',
                hintStyle: TextStyle(
                  color: Colors.black45,
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 14,
                ),
              ),
              onChanged: onSearchChanged,
              onSubmitted: searchAddress,
            ),
          ),
          IconButton(
            tooltip: _isListening ? 'Dinlemeyi durdur' : 'Sesli komut',
            icon: Icon(
              _isListening ? Icons.mic : Icons.mic_none,
              color: _isListening ? Colors.red : AppTheme.primaryBlue,
            ),
            onPressed: _startListening,
          ),
          if (isLoadingSuggestions)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
              ),
            ),
          IconButton(
            tooltip: 'Temizle',
            icon: const Icon(
              Icons.clear,
            ),
            onPressed: () {
              addressController.clear();

              setState(() {
                searchSuggestions = <dynamic>[];

                _voiceText = '';
              });
            },
          ),
          Padding(
            padding: const EdgeInsets.only(
              right: 6,
            ),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    10,
                  ),
                ),
              ),
              onPressed: () {
                searchAddress(
                  addressController.text,
                );
              },
              child: const Text(
                'Git',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SES DURUMU
  // ============================================================

  Widget _buildVoiceStatus() {
    if (!_isListening && _voiceText.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(
        top: 8,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(
          12,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(
              0,
              3,
            ),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            _isListening ? Icons.mic : Icons.record_voice_over,
            color: _isListening ? Colors.red : AppTheme.primaryBlue,
          ),
          const SizedBox(
            width: 10,
          ),
          Expanded(
            child: Text(
              _isListening
                  ? (_voiceText.isEmpty ? 'Dinliyorum...' : _voiceText)
                  : _voiceText,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // ÖNERİLER
  // ============================================================

  Widget _buildSuggestions() {
    if (searchSuggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(
        top: 6,
      ),
      constraints: const BoxConstraints(
        maxHeight: 300,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(
          14,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(
              0,
              3,
            ),
          ),
        ],
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: searchSuggestions.length,
        separatorBuilder: (
          BuildContext context,
          int index,
        ) {
          return const Divider(
            height: 1,
          );
        },
        itemBuilder: (
          BuildContext context,
          int index,
        ) {
          final dynamic item = searchSuggestions[index];

          return ListTile(
            leading: const Icon(
              Icons.location_on,
              color: AppTheme.primaryBlue,
            ),
            title: Text(
              item['display_name']?.toString() ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () {
              selectSuggestion(
                item,
              );
            },
          );
        },
      ),
    );
  }

  // ============================================================
  // NAVİGASYON ÜST BİLGİSİ
  // ============================================================

  Widget _buildNavigationTopPanel() {
    if (!_navigationStarted || routePoints.isEmpty) {
      return const SizedBox.shrink();
    }

    // Navigasyon sırasında AppBar kaldırıldığı için (harita tam ekran),
    // panel durum çubuğunun (saat/sinyal) arkasında kalmasın diye
    // üst güvenli alan boşluğu manuel olarak ekleniyor.
    final double topSafeArea = MediaQuery.of(context).padding.top;

    return Positioned(
      top: 15 + topSafeArea,
      left: 15,
      right: 15,
      child: Container(
        padding: const EdgeInsets.all(
          14,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(
            18,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              offset: Offset(
                0,
                4,
              ),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: routeColor,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.turn_right,
                color: Colors.white,
                size: 32,
              ),
            ),
            const SizedBox(
              width: 12,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentInstructionText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(
                    height: 5,
                  ),
                  Text(
                    _currentInstructionDistance > 0
                        ? _formatDistanceText
                        : 'Rotayı takip edin',
                    style: TextStyle(
                      fontSize: 14,
                      color: routeColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String get _formatDistanceText {
    return '${_formatDistance(_currentInstructionDistance)} sonra';
  }

  // ============================================================
  // NAVİGASYON ALT BİLGİ
  // ============================================================

  Widget _buildNavigationInfo() {
    if (!_navigationStarted || routePoints.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 15,
      right: 15,
      bottom: 20,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(
            16,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              offset: Offset(
                0,
                4,
              ),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 45,
              height: 45,
              decoration: BoxDecoration(
                color: routeColor,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.navigation,
                color: Colors.white,
              ),
            ),
            const SizedBox(
              width: 12,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatDistance(
                      _remainingDistance,
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(
                    height: 3,
                  ),
                  Text(
                    _formatDuration(
                      _remainingDuration,
                    ),
                    style: const TextStyle(
                      color: Colors.grey,
                    ),
                  ),
                  if (_currentSpeedLimit > 0)
                    Row(
                      children: [
                        const Icon(Icons.speed, size: 14, color: Colors.red),
                        const SizedBox(width: 4),
                        Text(
                          '$_currentSpeedLimit km/s',
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  if (_drivingStartTime != null)
                    Row(
                      children: [
                        const Icon(Icons.timer, size: 14, color: Colors.orange),
                        const SizedBox(width: 4),
                        Text(
                          _formatDuration(
                            DateTime.now()
                                .difference(_drivingStartTime!)
                                .inSeconds
                                .toDouble(),
                          ),
                          style: TextStyle(
                            color: DateTime.now()
                                        .difference(_drivingStartTime!)
                                        .inMinutes >=
                                    270
                                ? Colors.red
                                : Colors.orange,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  if (_routeRestrictionWarning.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(
                        _routeRestrictionWarning,
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (selectedVehicle == 'truck')
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.truckOrange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: AppTheme.truckOrange.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        '🚛 ${_truckWeight.toStringAsFixed(1)}t · ${_truckHeight}m×${_truckWidth}m · ${_truckLength}m',
                        style: const TextStyle(
                          color: AppTheme.truckOrange,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Column(
              children: [
                Icon(
                  selectedVehicle == 'truck'
                      ? Icons.local_shipping
                      : Icons.directions_car,
                  color: routeColor,
                ),
                const SizedBox(
                  height: 2,
                ),
                Text(
                  selectedVehicle == 'truck' ? 'LKW' : 'Auto',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            IconButton(
              tooltip: 'Navigasyonu kapat',
              icon: const Icon(
                Icons.close,
              ),
              onPressed: _stopNavigation,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // HARİTA KONTROLLERİ
  // ============================================================

  // Etiketli, belirgin kenarlıklı ikincil menü butonu.
  // Bare ikon yerine ikon + yazı kullanarak menüyü daha anlaşılır yapar.
  Widget _labeledControlButton({
    required String heroTag,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool active = false,
    Color activeColor = AppTheme.primaryBlue,
  }) {
    final Color bg = active ? activeColor : Colors.white;
    final Color fg = active ? Colors.white : Colors.black87;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: bg,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: active ? activeColor : Colors.grey.shade400,
            width: 1.2,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: fg, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Her zaman görünen (sık kullanılan) küçük dairesel kontrol.
  Widget _primaryControlButton({
    required String heroTag,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool active = false,
    double size = 40,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: active ? AppTheme.primaryBlue : Colors.white,
          shape: CircleBorder(
            side: BorderSide(
              color: active ? AppTheme.primaryBlue : Colors.grey.shade400,
              width: 1.2,
            ),
          ),
          elevation: 3,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(
                icon,
                size: 20,
                color: active ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMapControls() {
    return Positioned(
      right: 15,
      bottom: _navigationStarted ? 125 : 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // İKİNCİL MENÜ (açılır/kapanır)

          if (_showMoreControls)
            Container(
              constraints: const BoxConstraints(maxHeight: 340),
              margin: const EdgeInsets.only(bottom: 4),
              child: SingleChildScrollView(
                reverse: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _labeledControlButton(
                      heroTag: 'favorites',
                      icon: Icons.bookmarks,
                      label: 'Favoriler',
                      onPressed: _showFavorites,
                    ),
                    _labeledControlButton(
                      heroTag: 'save_location',
                      icon: Icons.add_location_alt,
                      label: 'Konumu Kaydet',
                      onPressed: _saveCurrentLocationAsFavorite,
                    ),
                    _labeledControlButton(
                      heroTag: 'voice_language',
                      icon: Icons.translate,
                      label: 'Ses: $_voiceLanguageName',
                      onPressed: _showVoiceLanguageSelector,
                    ),
                    _labeledControlButton(
                      heroTag: 'restrictions',
                      icon: _showRestrictions
                          ? Icons.warning_amber
                          : Icons.warning_amber_outlined,
                      label: 'Kısıtlamalar',
                      active: _showRestrictions,
                      activeColor: Colors.orange.shade800,
                      onPressed: () {
                        setState(() {
                          _showRestrictions = !_showRestrictions;
                        });
                      },
                    ),
                    _labeledControlButton(
                      heroTag: 'truck_parkings',
                      icon: _showTruckParkings
                          ? Icons.local_shipping
                          : Icons.local_shipping_outlined,
                      label: 'TIR Parkları',
                      active: _showTruckParkings,
                      activeColor: Colors.green.shade700,
                      onPressed: () {
                        setState(() {
                          _showTruckParkings = !_showTruckParkings;
                        });
                      },
                    ),
                    _labeledControlButton(
                      heroTag: 'fuel_stations',
                      icon: _showFuelStations
                          ? Icons.local_gas_station
                          : Icons.local_gas_station_outlined,
                      label: 'Yakıt İstasyonları',
                      active: _showFuelStations,
                      activeColor: Colors.blue.shade700,
                      onPressed: () {
                        setState(() {
                          _showFuelStations = !_showFuelStations;
                        });
                      },
                    ),
                    _labeledControlButton(
                      heroTag: 'stops',
                      icon: Icons.flag,
                      label: _stops.isEmpty
                          ? 'Duraklar'
                          : 'Duraklar (${_stops.length})',
                      onPressed: _showStopsManager,
                    ),
                    _labeledControlButton(
                      heroTag: 'dark_mode',
                      icon: _isDarkMode ? Icons.wb_sunny : Icons.nights_stay,
                      label: _isDarkMode ? 'Gündüz Modu' : 'Gece Modu',
                      active: _isDarkMode,
                      activeColor: Colors.indigo,
                      onPressed: _toggleDarkMode,
                    ),
                    _labeledControlButton(
                      heroTag: 'share',
                      icon: Icons.share,
                      label: 'Rotayı Paylaş',
                      onPressed: _shareRoute,
                    ),
                    _labeledControlButton(
                      heroTag: 'history',
                      icon: Icons.history,
                      label: 'Rota Geçmişi',
                      onPressed: _showRouteHistory,
                    ),
                  ],
                ),
              ),
            ),

          // DAHA FAZLA / KAPAT

          _primaryControlButton(
            heroTag: 'more_controls',
            icon: _showMoreControls ? Icons.close : Icons.more_horiz,
            tooltip: _showMoreControls ? 'Menüyü kapat' : 'Diğer seçenekler',
            active: _showMoreControls,
            onPressed: () {
              setState(() {
                _showMoreControls = !_showMoreControls;
              });
            },
          ),

          const SizedBox(height: 6),

          // YAKINLAŞTIR / UZAKLAŞTIR / YÖN

          _primaryControlButton(
            heroTag: 'zoom_in',
            icon: Icons.add,
            tooltip: 'Yakınlaştır',
            onPressed: () {
              mapController.move(
                mapController.center,
                mapController.zoom + 1,
              );
            },
          ),
          _primaryControlButton(
            heroTag: 'zoom_out',
            icon: Icons.remove,
            tooltip: 'Uzaklaştır',
            onPressed: () {
              mapController.move(
                mapController.center,
                mapController.zoom - 1,
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Tooltip(
              message: _navigationMode ? 'Kuzey yukarı' : 'Sürüş yönü yukarı',
              child: Material(
                color: _navigationMode ? AppTheme.primaryBlue : Colors.white,
                shape: CircleBorder(
                  side: BorderSide(
                    color: _navigationMode
                        ? AppTheme.primaryBlue
                        : Colors.grey.shade400,
                    width: 1.2,
                  ),
                ),
                elevation: 3,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _toggleNavigationMode,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Transform.rotate(
                      angle:
                          _navigationMode ? 0 : _currentHeading * math.pi / 180,
                      child: Icon(
                        Icons.navigation,
                        size: 20,
                        color: _navigationMode ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 4),

          // KONUMUM (ana / en belirgin buton)

          FloatingActionButton(
            heroTag: 'my_location',
            tooltip: 'Konumum / Navigasyonu takip et',
            backgroundColor: AppTheme.primaryBlue,
            foregroundColor: Colors.white,
            shape: const CircleBorder(
              side: BorderSide(color: Colors.white, width: 2),
            ),
            onPressed: () {
              if (userLocation == null) {
                loadLocation();

                return;
              }

              setState(() {
                _isFollowingLocation = true;
              });

              _moveMapWithDirection(
                userLocation!,
                _currentHeading,
              );
            },
            child: const Icon(
              Icons.my_location,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // HARİTA
  // ============================================================

  Widget _buildMap() {
    if (userLocation == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        center: userLocation!,
        zoom: 13.0,
        interactiveFlags: InteractiveFlag.all,
        onTap: (
          TapPosition tapPosition,
          LatLng point,
        ) {
          setState(() {
            _isFollowingLocation = false;
          });

          selectMapPoint(
            point,
          );
        },
        onLongPress: (
          TapPosition tapPosition,
          LatLng point,
        ) async {
          final TextEditingController stopNameController =
              TextEditingController();
          final bool? add = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Durak Ekle'),
              content: TextField(
                controller: stopNameController,
                decoration: const InputDecoration(
                  labelText: 'Durak adı',
                  hintText: 'Örn: Depo, Müşteri',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Ekle'),
                ),
              ],
            ),
          );
          if (add == true && mounted) {
            await _addStop(
              point,
              stopNameController.text.trim(),
              '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}',
            );
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      '${stopNameController.text.trim()} durak olarak eklendi.')),
            );
          }
          stopNameController.dispose();
        },
        onPositionChanged: (
          MapPosition position,
          bool hasGesture,
        ) {
          if (hasGesture && _isFollowingLocation) {
            setState(() {
              _isFollowingLocation = false;
            });
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: _tileUrlTemplate,
          userAgentPackageName: 'com.example.lkw_almanya',
        ),

        // ALTERNATİF ROTALAR

        if (alternativeRoutePoints.isNotEmpty)
          PolylineLayer(
            polylines: alternativeRoutePoints.asMap().entries.map(
              (
                MapEntry<int, List<LatLng>> entry,
              ) {
                final List<Color> altColors = [
                  Colors.teal,
                  Colors.purple,
                  Colors.orange,
                ];
                return Polyline(
                  points: entry.value,
                  strokeWidth: 4.5,
                  color: altColors[entry.key % altColors.length].withValues(
                    alpha: 0.75,
                  ),
                );
              },
            ).toList(),
          ),

        // ANA ROTA

        if (routePoints.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: routePoints,
                strokeWidth: 5.0,
                color: routeColor,
              ),
            ],
          ),

        // MARKERLAR

        MarkerLayer(
          markers: [
            if (_showTruckParkings)
              ..._truckParkings.map(
                (_TruckParking p) => Marker(
                  point: p.location,
                  width: 40,
                  height: 40,
                  builder: (BuildContext ctx) {
                    return GestureDetector(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${p.name}${p.capacity != null ? ' · Kapasite: ${p.capacity}' : ''}${p.hasRestaurant ? ' · Restoran' : ''}${p.hasShower ? ' · Duş' : ''}${p.hasFuel ? ' · Yakıt' : ''}',
                            ),
                            duration: const Duration(seconds: 4),
                          ),
                        );
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.green.shade700,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [
                            BoxShadow(color: Colors.black38, blurRadius: 4),
                          ],
                        ),
                        child: const Icon(Icons.local_shipping,
                            color: Colors.white, size: 20),
                      ),
                    );
                  },
                ),
              ),
            if (_showFuelStations)
              ..._fuelStations.map(
                (_FuelStation f) => Marker(
                  point: f.location,
                  width: 36,
                  height: 36,
                  builder: (BuildContext ctx) {
                    return GestureDetector(
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${f.name}${f.hgvFriendly ? ' · LKW Uyumlu' : ''}${f.hasAdBlue ? ' · AdBlue' : ''}${f.hasRestaurant ? ' · Restoran' : ''}',
                            ),
                            duration: const Duration(seconds: 4),
                          ),
                        );
                      },
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.blue.shade700,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [
                            BoxShadow(color: Colors.black38, blurRadius: 4),
                          ],
                        ),
                        child: const Icon(Icons.local_gas_station,
                            color: Colors.white, size: 18),
                      ),
                    );
                  },
                ),
              ),
            if (_showRestrictions)
              ..._routeRestrictions.map(
                (_RouteRestriction r) => Marker(
                  point: r.location,
                  width: 36,
                  height: 36,
                  builder: (BuildContext ctx) {
                    return _buildRestrictionMarker(r);
                  },
                ),
              ),
            if (alternativeRoutePoints.isNotEmpty)
              for (int i = 0; i < alternativeRoutePoints.length; i++)
                if (alternativeRoutePoints[i].isNotEmpty)
                  Marker(
                    point: alternativeRoutePoints[i]
                        [alternativeRoutePoints[i].length ~/ 2],
                    width: 44,
                    height: 44,
                    builder: (BuildContext ctx) {
                      final List<Color> altColors = [
                        Colors.teal,
                        Colors.purple,
                        Colors.orange,
                      ];
                      return GestureDetector(
                        onTap: () => _selectAlternativeRoute(i),
                        child: Container(
                          decoration: BoxDecoration(
                            color: altColors[i % altColors.length],
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 2.5,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black38,
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              'A${i + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
            if (userLocation != null)
              Marker(
                point: userLocation!,
                width: 55,
                height: 55,
                builder: (
                  BuildContext context,
                ) {
                  return Transform.rotate(
                    angle:
                        _navigationMode ? 0 : _currentHeading * math.pi / 180,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 5,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.navigation,
                        color: AppTheme.primaryBlue,
                        size: 34,
                      ),
                    ),
                  );
                },
              ),
            if (destination != null)
              Marker(
                point: destination!,
                width: 50,
                height: 50,
                builder: (
                  BuildContext context,
                ) {
                  return const Icon(
                    Icons.location_on,
                    color: Colors.red,
                    size: 45,
                  );
                },
              ),
          ],
        ),
      ],
    );
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

                // NAVİGASYON ÜST PANELİ

                _buildNavigationTopPanel(),

                // ARAMA

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

                // NAVİGASYON ALT BİLGİSİ

                _buildNavigationInfo(),

                // HARİTA KONTROLLERİ

                _buildMapControls(),
              ],
            ),
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
