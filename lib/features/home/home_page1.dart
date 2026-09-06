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

class _NavigationInstruction {
  final String text;
  final double distance;
  final double duration;
  final LatLng? location;
  bool spoken = false;

  _NavigationInstruction({
    required this.text,
    required this.distance,
    required this.duration,
    this.location,
  });
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

  // ============================================================
  // ADRES ARAMA
  // ============================================================

  final TextEditingController addressController = TextEditingController();

  List<dynamic> searchSuggestions = <dynamic>[];

  bool isLoadingSuggestions = false;

  Timer? _debounce;

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
      destination = null;
      addressController.clear();
      _remainingDistance = 0;
      _remainingDuration = 0;
      _currentInstructionText = 'Rotanız hazırlanıyor...';
      _currentInstructionDistance = 0;
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
    if (instruction.spoken) {
      return;
    }

    if (distance > 700) {
      return;
    }

    String text = instruction.text;

    if (distance > 250) {
      return;
    }

    instruction.spoken = true;

    final String distanceText = _formatDistance(distance);

    if (_voiceLanguage == 'tr-TR') {
      text = '$distanceText sonra $text.';
    } else if (_voiceLanguage == 'en-US') {
      text = '$text in $distanceText.';
    } else {
      text = '$text in $distanceText.';
    }

    await _speak(
      text,
    );
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
              left: 16,
              right: 16,
              bottom: 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Araç Tipi Seçin',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 12,
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppTheme.truckOrange,
                    child: Icon(
                      Icons.local_shipping,
                      color: Colors.white,
                    ),
                  ),
                  title: const Text(
                    'Kamyon (LKW)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: const Text(
                    'Ağır vasıta uyumlu rota',
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
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
                  leading: const CircleAvatar(
                    backgroundColor: AppTheme.primaryBlue,
                    child: Icon(
                      Icons.directions_car,
                      color: Colors.white,
                    ),
                  ),
                  title: const Text(
                    'Otomobil',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: const Text(
                    'Standart araç rotası',
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
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
    if (userLocation == null) {
      _showRouteError(
        'Önce mevcut konumunuz alınmalı.',
      );

      return;
    }

    WakelockPlus.enable();

    final LatLng start = userLocation!;

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
                    'height': 4.0,
                    'width': 2.55,
                    'length': 16.5,
                    'weight': 40.0,
                    'axleload': 11.5,
                    'hazmat': false,
                  },
                },
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

        final dynamic feature = (data['features'] as List)[0];

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

          alternativeRoutePoints = <List<LatLng>>[];

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
        '&alternatives=true'
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

        if (announce) {
          if (alternatives.isNotEmpty) {
            await _speak(
              _voiceLanguage == 'tr-TR'
                  ? 'Otomobil rotası hazır. '
                      '${alternatives.length} alternatif rota bulundu.'
                  : _voiceLanguage == 'en-US'
                      ? 'Car route ready. '
                          '${alternatives.length} alternative routes found.'
                      : 'Die Autoroute ist bereit. '
                          '${alternatives.length} alternative Routen gefunden.',
            );
          } else {
            await _speak(
              _voiceLanguage == 'tr-TR'
                  ? 'Otomobil rotası hazır. Navigasyon başladı.'
                  : _voiceLanguage == 'en-US'
                      ? 'Car route ready. Navigation started.'
                      : 'Die Autoroute ist bereit. Navigation gestartet.',
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
      return <LatLng>[];
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
              decoration: const InputDecoration(
                hintText: 'Adres yazın veya konuşun',
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

    return Positioned(
      top: 15,
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

  Widget _buildMapControls() {
    return Positioned(
      right: 15,
      bottom: _navigationStarted ? 125 : 20,
      child: Column(
        children: [
          // YERLER

          FloatingActionButton.small(
            heroTag: 'favorites',
            tooltip: 'Yerler / Favoriler',
            backgroundColor: Colors.white,
            foregroundColor: AppTheme.primaryBlue,
            onPressed: _showFavorites,
            child: const Icon(
              Icons.bookmarks,
            ),
          ),

          const SizedBox(
            height: 8,
          ),

          // KONUM AL

          FloatingActionButton.small(
            heroTag: 'save_location',
            tooltip: 'Bulunduğum konumu kaydet',
            backgroundColor: Colors.white,
            foregroundColor: AppTheme.primaryBlue,
            onPressed: _saveCurrentLocationAsFavorite,
            child: const Icon(
              Icons.add_location_alt,
            ),
          ),

          const SizedBox(
            height: 8,
          ),

          // SES DİLİ

          FloatingActionButton.small(
            heroTag: 'voice_language',
            tooltip: 'Ses dili: $_voiceLanguageName',
            backgroundColor: Colors.white,
            foregroundColor: AppTheme.primaryBlue,
            onPressed: _showVoiceLanguageSelector,
            child: const Icon(
              Icons.translate,
            ),
          ),

          const SizedBox(
            height: 8,
          ),

          // YÖN

          FloatingActionButton.small(
            heroTag: 'navigation_mode',
            tooltip: _navigationMode ? 'Kuzey yukarı' : 'Sürüş yönü yukarı',
            backgroundColor:
                _navigationMode ? AppTheme.primaryBlue : Colors.white,
            foregroundColor:
                _navigationMode ? Colors.white : AppTheme.primaryBlue,
            onPressed: _toggleNavigationMode,
            child: Transform.rotate(
              angle: _navigationMode ? 0 : _currentHeading * math.pi / 180,
              child: const Icon(
                Icons.navigation,
              ),
            ),
          ),

          const SizedBox(
            height: 8,
          ),

          // YAKINLAŞTIR

          FloatingActionButton.small(
            heroTag: 'zoom_in',
            tooltip: 'Yakınlaştır',
            onPressed: () {
              mapController.move(
                mapController.center,
                mapController.zoom + 1,
              );
            },
            child: const Icon(
              Icons.add,
            ),
          ),

          const SizedBox(
            height: 8,
          ),

          // UZAKLAŞTIR

          FloatingActionButton.small(
            heroTag: 'zoom_out',
            tooltip: 'Uzaklaştır',
            onPressed: () {
              mapController.move(
                mapController.center,
                mapController.zoom - 1,
              );
            },
            child: const Icon(
              Icons.remove,
            ),
          ),

          const SizedBox(
            height: 8,
          ),

          // KONUMUM

          FloatingActionButton(
            heroTag: 'my_location',
            tooltip: 'Konumum / Navigasyonu takip et',
            backgroundColor: AppTheme.primaryBlue,
            foregroundColor: Colors.white,
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
          urlTemplate: 'https://tile.openstreetmap.org/'
              '{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.lkw_almanya',
        ),

        // ALTERNATİF ROTALAR

        if (alternativeRoutePoints.isNotEmpty)
          PolylineLayer(
            polylines: alternativeRoutePoints.map(
              (
                List<LatLng> points,
              ) {
                return Polyline(
                  points: points,
                  strokeWidth: 3.5,
                  color: Colors.grey.withValues(
                    alpha: 0.65,
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
      appBar: AppBar(
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
