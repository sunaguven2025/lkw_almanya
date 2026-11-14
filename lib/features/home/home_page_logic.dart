part of 'home_page.dart';

// setState burada bir extension üzerinden çağrılıyor. Extension'lar Dart'ın
// miras zincirinin parçası sayılmadığı için analyzer bunu "protected üyeye
// dışarıdan erişim" olarak işaretliyor; ancak bu extension SADECE
// _HomePageState (bir State<HomePage> alt sınıfı) üzerinde tanımlı olduğundan
// çağrı güvenli ve doğrudur. Bu dosyaya özel olarak susturuyoruz.
// ignore_for_file: invalid_use_of_protected_member

// ================================================================
// İŞ MANTIĞI (konum, rota hesaplama, favoriler, ses, arama, duraklar,
// kısıtlamalar, yakıt/TIR parkı verileri vb.)
// Bu dosya home_page.dart'ın parçasıdır (part of), bu yüzden
// _HomePageState'in private alan/metodlarına doğrudan erişebilir.
// ================================================================
//
// ----------------------------------------------------------------
// BU SÜRÜMDEKİ DÜZELTMELER
// ----------------------------------------------------------------
// 1. Rota takibi: talimat noktaları rota üzerinde BİR KEZ indekslenir
//    (_ensureRouteIndexed). Eski kodda talimat aramaları _lastRouteIndex'i
//    ileri kaydırıyor, _checkOffRoute araç yanında olduğu hâlde "rotadan
//    çıktın" sanıyordu (sahte yeniden hesaplama = boşa TomTom isteği).
// 2. Rotaya uzaklık artık köşe noktasına değil, ÇİZGİ PARÇASINA göre
//    ölçülür (seyrek noktalı düz yollarda sahte sapma uyarısı vermez).
// 3. Kalan mesafe / talimata mesafe rota boyunca ölçülür (kuş uçuşu değil).
// 4. Sesli uyarı eşikleri hıza bağlı; Almanca cümle düzeltildi
//    ("In 500 Metern, ..."). Dönüş talimatları acil (urgent) sayılır ve
//    mola/uyarı anonsları onları kesmez.
// 5. Yorgunluk sayacı yeniden rota hesaplamada SIFIRLANMAZ; sadece 45 dk
//    durunca sıfırlanır ve telefonda saklanır. (Takograf yerine geçmez!)
// 6. GPS: ilk konum zaman aşımına uğrasa da takip başlar; çok hatalı
//    (>150 m) okumalar atılır; ok, rotaya yaklaşık 30 m içindeyken rota
//    üzerine oturtulur (map matching).
// 7. Yön: hareket hâlinde GPS/rota yönü kullanılır, ham manyetometre
//    DEĞİL. Yavaşken son yön korunur.
// 8. Tüm http çağrılarına zaman aşımı eklendi; Nominatim çağrıları tek
//    yardımcıda toplandı.
// 9. TomTom trafik olayları: sadece rotaya <=150 m olanlar gösterilir,
//    sahte çapraz çizgi kaldırıldı, kategori eşlemesi düzeltildi.
// 10. Rota geçmişine artık yeniden hesaplamalar eklenmez.
// 11. Varış: rota sonuna <=35 m kalınca da algılanır (bina merkezi yola
//    uzaksa navigasyon bitmiyordu).
// 12. Yeniden hesaplama: en az 15 sn ara, yavaşken (<2 m/s) tetiklenmez.
// ----------------------------------------------------------------

// ================================================================
// ÜST DÜZEY SABİTLER VE YARDIMCILAR
// ================================================================

const double _kMetersPerDegLat = 110540.0;
const double _kMetersPerDegLonEq = 111320.0;

/// En yakın rota parçası aranırken son indeksin etrafındaki pencere.
const int _kMatchWindow = 60;

/// Bu mesafeden uzaktaysak rotadan çıkmış sayılırız (GPS hatasına göre artar).
const double _kOffRouteThresholdMeters = 60.0;

/// Bu mesafeden uzaktaysak rota üzerinde olduğumuza güvenmeyiz.
const double _kLostTrackMeters = 150.0;

const Duration _kRecalculationCooldown = Duration(seconds: 15);

/// Nominatim arama ülkeleri. Başka ülkeler için: 'de,pl,nl,at,cz,dk,fr'
const String _kSearchCountryCodes = 'de';

const String _kDrivingBlockStartKey = 'lkw_driving_block_start';
const String _kDrivingLastSeenKey = 'lkw_driving_last_seen';

/// Bu kadar durulursa sürüş bloğu sıfırlanır (AB 561/2006: 45 dk mola).
const Duration _kRequiredBreak = Duration(minutes: 45);
const double _kMovingSpeedMps = 0.5;

/// Dönüş talimatı anonsundan sonra düşük öncelikli anonslar bu süre bekler.
const Duration _kUrgentSpeechWindow = Duration(seconds: 8);

// ----------------------------------------------------------------
// Rota indeksleme durumu.
// NOT: Bunlar tek bir HomePage için üst düzey (global) durumdur.
// Sonraki refactor'da bir RouteTracker sınıfına taşınmalı.
// ----------------------------------------------------------------
List<LatLng>? _indexedRoute;
List<_NavigationInstruction>? _indexedInstructions;
List<double> _routeCumulative = <double>[];
double _routeTotalDuration = 0.0;
bool _routeMatchPrimed = false;
final Expando<int> _instructionRouteIndex = Expando<int>();

DateTime? _lastRecalculationAt;
DateTime? _lastUrgentSpeechAt;
DateTime? _stationarySince;
DateTime? _lastDrivingPersist;
bool _drivingBlockRestored = false;

class _RouteMatch {
  final int index; // rota parçasının başlangıç noktası indeksi
  final double distance; // rota çizgisine uzaklık (m)
  final double alongMeters; // rota başından itibaren ilerleme (m)
  final LatLng snapped; // rota çizgisi üzerindeki izdüşüm

  const _RouteMatch({
    required this.index,
    required this.distance,
    required this.alongMeters,
    required this.snapped,
  });
}

class _SegmentHit {
  final int index;
  final double t;
  final double distance;
  final double offsetX;
  final double offsetY;

  const _SegmentHit({
    required this.index,
    required this.t,
    required this.distance,
    required this.offsetX,
    required this.offsetY,
  });
}

/// [p] noktasına en yakın rota parçasını [from]..[to] (parça indeksleri,
/// dahil) aralığında bulur. [to] en fazla r.length - 2 olmalıdır.
_SegmentHit _nearestSegment(
  List<LatLng> r,
  LatLng p,
  int from,
  int to, {
  double earlyStopMeters = 0.0,
}) {
  final double kx = _kMetersPerDegLonEq * math.cos(p.latitude * math.pi / 180);
  final double earlyStop2 = earlyStopMeters * earlyStopMeters;

  double bestD2 = double.infinity;
  int bestI = from;
  double bestT = 0.0;
  double bestX = 0.0;
  double bestY = 0.0;

  double ax = (r[from].longitude - p.longitude) * kx;
  double ay = (r[from].latitude - p.latitude) * _kMetersPerDegLat;

  for (int i = from; i <= to; i++) {
    final double bx = (r[i + 1].longitude - p.longitude) * kx;
    final double by = (r[i + 1].latitude - p.latitude) * _kMetersPerDegLat;
    final double dx = bx - ax;
    final double dy = by - ay;
    final double len2 = dx * dx + dy * dy;

    double t = 0.0;
    if (len2 > 0.0) {
      t = -(ax * dx + ay * dy) / len2;
      if (t < 0.0) {
        t = 0.0;
      } else if (t > 1.0) {
        t = 1.0;
      }
    }

    final double cx = ax + t * dx;
    final double cy = ay + t * dy;
    final double d2 = cx * cx + cy * cy;

    if (d2 < bestD2) {
      bestD2 = d2;
      bestI = i;
      bestT = t;
      bestX = cx;
      bestY = cy;

      if (earlyStop2 > 0.0 && d2 < earlyStop2) {
        break;
      }
    }

    ax = bx;
    ay = by;
  }

  return _SegmentHit(
    index: bestI,
    t: bestT,
    distance: math.sqrt(bestD2),
    offsetX: bestX,
    offsetY: bestY,
  );
}

/// Bir noktanın verilen rota çizgisine uzaklığı (metre).
double _distanceToRouteMeters(
  LatLng p,
  List<LatLng> route, {
  double stopBelow = 0.0,
}) {
  if (route.length < 2) {
    return double.infinity;
  }

  return _nearestSegment(
    route,
    p,
    0,
    route.length - 2,
    earlyStopMeters: stopBelow,
  ).distance;
}

double _bearingBetween(LatLng from, LatLng to) {
  final double lat1 = from.latitude * math.pi / 180;
  final double lat2 = to.latitude * math.pi / 180;
  final double deltaLongitude = (to.longitude - from.longitude) * math.pi / 180;

  final double y = math.sin(deltaLongitude) * math.cos(lat2);
  final double x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(deltaLongitude);

  final double bearing = math.atan2(y, x) * 180 / math.pi;
  return (bearing + 360) % 360;
}

/// TomTom Traffic olayı için okunur açıklama.
String _incidentReason(Map<String, dynamic> properties, int category) {
  final dynamic events = properties['events'];

  if (events is List && events.isNotEmpty) {
    final dynamic first = events.first;

    if (first is Map) {
      final String description = first['description']?.toString() ?? '';

      if (description.isNotEmpty) {
        return description;
      }
    }
  }

  switch (category) {
    case 8:
      return 'Yol kapalı';
    case 9:
      return 'Yol çalışması';
    case 1:
      return 'Kaza';
    default:
      return 'Trafik olayı';
  }
}

extension _HomePageLogicX on _HomePageState {
  // ============================================================
  // FAVORİLERİ YÜKLE
  // ============================================================

  Future<void> _loadFavorites() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      final String? saved = prefs.getString(
        _HomePageState._favoritesStorageKey,
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
        if (mounted) {
          setState(() {
            _favoritesLoaded = true;
          });
        }
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
        _HomePageState._favoritesStorageKey,
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
      ).timeout(const Duration(seconds: 8));

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

      // DÜZELTME (FIX): 0.48 çok yavaştı, anonslar geç geliyordu.
      // 0.55 normal hız; hâlâ yavaş gelirse 0.6-0.7 yapılabilir.
      await _tts.setSpeechRate(
        0.55,
      );

      // 🎙️ SES TONU (PITCH) AYARI:
      // Samsung cihazlar setVoice'ı yoksaydığı için sesi zorla kalınlaştırıyoruz.
      // NOT: Düşük pitch kabin gürültüsünde anlaşılırlığı düşürebilir; sahada test et.
      await _tts.setPitch(
        0.6,
      );

      // ============================================================
      // 🎙️ ERKEK SESİ SEÇİMİ
      // ============================================================
      try {
        final List<dynamic> voices = await _tts.getVoices;

        dynamic germanMaleNetworkVoice;
        dynamic germanMaleVoice;

        for (var voice in voices) {
          final String name = voice['name'].toString().toLowerCase();
          final String locale = voice['locale'].toString().toLowerCase();
          if (locale.contains('de-de') ||
              locale.contains('de_de') ||
              locale.contains('de')) {
            if (name.contains('deb')) {
              if (name.contains('network')) {
                germanMaleNetworkVoice = voice;
              } else {
                germanMaleVoice ??= voice;
              }
            }
          }
        }

        final selectedVoice = germanMaleNetworkVoice ?? germanMaleVoice;

        if (selectedVoice != null) {
          final Map<String, String> voiceMap = Map<String, String>.from(
            selectedVoice as Map,
          );
          await _tts.setVoice(voiceMap);
          debugPrint('✅ ERKEK SESİ SEÇİLDİ: ${voiceMap['name']}');
        } else {
          debugPrint(
              '⚠️ Uygun bir Almanca erkek sesi bulunamadı. Varsayılan ses kullanılıyor.');
        }
      } catch (e) {
        debugPrint('SES LİSTESİ ALINAMADI: $e');
      }
      // ============================================================

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

      if (language == 'de-DE') {
        message = 'Die Sprache wurde auf Deutsch eingestellt.';
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

// ============================================================
// SES DİLİ SEÇİCİ (Bottom Sheet)
// ============================================================

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
            ],
          ),
        ));
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
        localeId: 'de-DE',
        // DÜZELTME (FIX): confirmation modu her kelimede
        // duraksıyordu; sesli arama çok geç cevap veriyordu.
        // dictation modu konuşma bitene kadar kesintisiz dinler.
        listenMode: stt.ListenMode.dictation,
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
            r'fahrt|fahren|weiterfahrt|ziel|'
            r'başlat|baslat|start|los)\b',
            caseSensitive: false,
          ),
          '',
        )
        .trim();

    searchText = searchText
        .replaceAll(
          RegExp(
            r'\b(kamyon|lkw|truck|otomobil|araba|'
            r'auto|car|lastkraftwagen|lastwagen)\b',
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

  /// [urgent] = true: dönüş talimatı, yeniden rota, varış. Çalan anonsu
  /// keser ve konuşur.
  /// [urgent] = false: mola uyarısı, kısıtlama, arayüz bildirimi. Yakın
  /// zamanda acil bir anons verildiyse onu KESMEZ, bekler (çok yoğunsa düşer).
  Future<void> _speak(
    String text, {
    bool urgent = false,
  }) async {
    try {
      if (urgent) {
        _lastUrgentSpeechAt = DateTime.now();
      } else {
        for (int attempt = 0;; attempt++) {
          final DateTime? last = _lastUrgentSpeechAt;

          if (last == null) {
            break;
          }

          final Duration since = DateTime.now().difference(last);

          if (since >= _kUrgentSpeechWindow) {
            break;
          }

          if (attempt >= 3) {
            return;
          }

          await Future<void>.delayed(_kUrgentSpeechWindow - since);
        }
      }

      await _tts.stop();

      // ⚠️ DÜZELTME: TTS motoru bazen dil ayarını unutuyor
      // (özellikle web'de). Her konuşmada dili zorla.
      // Her zaman Almanca konuş
      await _tts.setLanguage('de-DE');

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
        _isFollowingLocation = true; // ⬅️ Başlangıçta takibi aç

        if (position.heading >= 0 && position.heading.isFinite) {
          _currentHeading = position.heading;
        }
      });

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
    } on TimeoutException {
      // İlk konum 20 sn içinde alınamadı (garaj, kapalı alan).
      // Takibi yine de başlat: ilk sinyal gelince harita kendiliğinden açılır.
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'GPS sinyali henüz yok. Açık alana çıkın; sinyal gelince '
            'harita otomatik açılır.',
          ),
          duration: Duration(seconds: 6),
        ),
      );

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
  // SÜRÜŞ BLOĞU (mola takibi)
  // ============================================================
  // AB 561/2006: 4,5 saat sürüşten sonra 45 dk mola. Burada sadece bir
  // UYARI sayacı var; yasal kayıt TAKOGRAFTIR, bu uygulama değil.

  Future<void> _restoreDrivingBlock() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      final DateTime? start = DateTime.tryParse(
        prefs.getString(_kDrivingBlockStartKey) ?? '',
      );

      final DateTime? seen = DateTime.tryParse(
        prefs.getString(_kDrivingLastSeenKey) ?? '',
      );

      if (start == null || seen == null) {
        return;
      }

      if (DateTime.now().difference(seen) >= _kRequiredBreak) {
        await prefs.remove(_kDrivingBlockStartKey);
        await prefs.remove(_kDrivingLastSeenKey);
        return;
      }

      _drivingStartTime ??= start;
    } catch (e) {
      debugPrint('DRIVING BLOCK RESTORE ERROR: $e');
    }
  }

  Future<void> _persistDrivingBlock({
    bool force = false,
  }) async {
    final DateTime now = DateTime.now();

    if (!force &&
        _lastDrivingPersist != null &&
        now.difference(_lastDrivingPersist!) < const Duration(seconds: 60)) {
      return;
    }

    _lastDrivingPersist = now;

    final DateTime? start = _drivingStartTime;

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      if (start == null) {
        await prefs.remove(_kDrivingBlockStartKey);
        await prefs.remove(_kDrivingLastSeenKey);
        return;
      }

      await prefs.setString(_kDrivingBlockStartKey, start.toIso8601String());
      await prefs.setString(_kDrivingLastSeenKey, now.toIso8601String());
    } catch (e) {
      debugPrint('DRIVING BLOCK SAVE ERROR: $e');
    }
  }

  void _trackDrivingBlock(double speedMps) {
    final DateTime now = DateTime.now();

    if (speedMps >= _kMovingSpeedMps) {
      _stationarySince = null;

      if (_drivingStartTime == null) {
        _drivingStartTime = now;
        _fatigueWarningShown = false;
        unawaited(_persistDrivingBlock(force: true));
      } else {
        unawaited(_persistDrivingBlock());
      }

      return;
    }

    _stationarySince ??= now;

    if (_drivingStartTime != null &&
        now.difference(_stationarySince!) >= _kRequiredBreak) {
      // 45 dk durduk: yeni sürüş bloğu.
      _drivingStartTime = null;
      _fatigueWarningShown = false;
      unawaited(_persistDrivingBlock(force: true));
    } else {
      unawaited(_persistDrivingBlock());
    }
  }

  // ============================================================
  // KONUM TAKİBİ
  // ============================================================

  void _startPositionTracking() {
    _positionSubscription?.cancel();

    if (!_drivingBlockRestored) {
      _drivingBlockRestored = true;
      unawaited(_restoreDrivingBlock());
    }

    const LocationSettings settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
    );

    LatLng? lastValidLocation;
    DateTime? lastValidTime;

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
      (Position position) {
        if (!mounted) return;

        // Çok hatalı okumaları at (ilk konum hariç).
        if (userLocation != null &&
            position.accuracy.isFinite &&
            position.accuracy > 150) {
          return;
        }

        final LatLng rawLocation = LatLng(
          position.latitude,
          position.longitude,
        );

        if (lastValidLocation != null && lastValidTime != null) {
          final double distMoved = Geolocator.distanceBetween(
            lastValidLocation!.latitude,
            lastValidLocation!.longitude,
            rawLocation.latitude,
            rawLocation.longitude,
          );

          final double timeDiffSec =
              DateTime.now().difference(lastValidTime!).inMilliseconds / 1000.0;

          if (timeDiffSec > 0 && distMoved / timeDiffSec > 50) {
            return;
          }
        }

        lastValidLocation = rawLocation;
        lastValidTime = DateTime.now();

        double speedMps = position.speed.isFinite && position.speed >= 0
            ? position.speed
            : 0.0;

        if (speedMps < 0.5) {
          speedMps = 0.0;
        }

        _trackDrivingBlock(speedMps);

        final bool firstFix = userLocation == null;

        final bool navigating = _navigationStarted && routePoints.length >= 2;

        // Rota eşleştirmesi (tek sefer, tüm navigasyon adımları paylaşır).
        final _RouteMatch? match =
            navigating ? _matchOnRoute(rawLocation) : null;

        // ---- YÖN ----
        // Hareket hâlinde: rotadaysak rota yönü, değilsek GPS yönü.
        // Yavaşken: son yönü koru (ham manyetometre güvenilmez).
        double newHeading = _currentHeading;

        if (speedMps >= 1.5) {
          if (match != null && match.distance <= _kOffRouteThresholdMeters) {
            newHeading = _routeBearing(match);
          } else if (position.heading.isFinite && position.heading >= 0) {
            newHeading = position.heading;
          }
        }

        // ---- GÖRÜNTÜLENEN KONUM (map matching) ----
        // Hareket hâlinde ve rotaya <=30 m ise oku rota üzerine oturt.
        LatLng displayLocation = rawLocation;

        if (match != null && speedMps >= 1.5 && match.distance <= 30.0) {
          displayLocation = match.snapped;
        }

        userLocation = displayLocation;

        if (firstFix) {
          _isFollowingLocation = true;
        }

        _currentHeading = _smoothHeading(newHeading);
        _currentSpeed = speedMps;

        // Hız sınırını ve sürüş süresini GPS akışına bağla.
        // UI metotları ayrı bir extension'da olduğu için açıkça çağrılır.
        _HomePageUIX(this)._updateCurrentSpeedLimit(displayLocation);
        _HomePageUIX(this)._checkFatigue();

        // Her GPS güncellemesinde talimatları ve kalan mesafeyi yenile.
        if (_navigationStarted) {
          _updateNavigationInstruction(rawLocation, match: match);
          _checkDestinationReached(rawLocation, match: match);

          if (_navigationStarted) {
            _checkOffRoute(
              rawLocation,
              accuracy: position.accuracy,
              speedMps: speedMps,
              match: match,
            );
          }
        }

        // Tek yeniden çizim (eskiden GPS başına 2-3 setState vardı).
        setState(() {});

        if (firstFix) {
          final LatLng firstLocation = displayLocation;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }

            try {
              mapController.move(
                firstLocation,
                13.0,
              );
            } catch (e) {
              debugPrint(
                'MAP MOVE ERROR (ilk konum): $e',
              );
            }
          });
        }

        if (_isFollowingLocation) {
          _moveMapWithDirection(displayLocation, _currentHeading);
        }
      },
      onError: (Object error) {
        debugPrint('POSITION STREAM ERROR: $error');
      },
    );
  }

  // ============================================================
  // HARİTAYI YÖNE ÇEVİR
  // ============================================================

  void _moveMapWithDirection(LatLng location, double heading) {
    try {
      final double zoom = _navigationStarted ? 17.0 : mapController.camera.zoom;

      mapController.move(location, zoom);

      if (_navigationMode && heading.isFinite) {
        mapController.rotate(-heading);
      } else {
        mapController.rotate(0);
      }
    } catch (e) {
      debugPrint('MAP MOVE ERROR: $e');
    }
  }

  void _scheduleNavigationCamera(
    LatLng location,
    double heading,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isFollowingLocation) {
        return;
      }

      _moveMapWithDirection(
        location,
        heading,
      );
    });
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
      _currentInstructionIndex = 0;
      routePoints = <LatLng>[];
      alternativeRoutePoints = <List<LatLng>>[];
      _routeRestrictions = <_RouteRestriction>[];
      _routeRestrictionWarning = '';
      _closedRoadSections = <ClosedRoadSection>[];
      _speedLimits = <_SpeedLimitSegment>[];
      _currentSpeedLimit = 0;
      _truckParkings = <_TruckParking>[];
      destination = null;
      addressController.clear();
      _remainingDistance = 0;
      _remainingDuration = 0;
      _currentInstructionText = 'Rotanız hazırlanıyor...';
      _currentInstructionDistance = 0;
      _lastRouteIndex = 0;
      _offRouteReadings = 0;
      // NOT: _drivingStartTime burada SIFIRLANMAZ. Varış bir mola değildir;
      // sürüş bloğu ancak 45 dk durulunca biter (_trackDrivingBlock).
    });

    mapController.rotate(0);

    WakelockPlus.disable();
  }

  // ============================================================
  // ROTA İNDEKSLEME (talimat noktaları + kümülatif mesafe)
  // ============================================================
  // Rota veya talimat listesi her değiştiğinde (yeni rota, yeniden hesaplama,
  // alternatif rota seçimi) BİR KEZ çalışır. Böylece GPS başına yapılan
  // aramalar _lastRouteIndex'i bozmaz.

  void _ensureRouteIndexed() {
    if (identical(_indexedRoute, routePoints) &&
        identical(_indexedInstructions, _navigationInstructions)) {
      return;
    }

    _indexedRoute = routePoints;
    _indexedInstructions = _navigationInstructions;

    _lastRouteIndex = 0;
    _offRouteReadings = 0;
    _currentInstructionIndex = 0;
    _routeMatchPrimed = false;

    final List<LatLng> r = routePoints;

    if (r.length < 2) {
      _routeCumulative = <double>[];
      _routeTotalDuration = 0.0;
      return;
    }

    // Kümülatif mesafe (rota başından itibaren, metre)
    final List<double> cum = List<double>.filled(r.length, 0.0);

    for (int i = 1; i < r.length; i++) {
      cum[i] = cum[i - 1] +
          Geolocator.distanceBetween(
            r[i - 1].latitude,
            r[i - 1].longitude,
            r[i].latitude,
            r[i].longitude,
          );
    }

    _routeCumulative = cum;

    // Her talimatın rota üzerindeki nokta indeksi (ileri yönde, monoton)
    int from = 0;
    double durationSum = 0.0;

    for (final _NavigationInstruction ins in _navigationInstructions) {
      durationSum += ins.duration;

      final LatLng? loc = ins.location;

      if (loc == null) {
        _instructionRouteIndex[ins] = -1;
        continue;
      }

      final double kx =
          _kMetersPerDegLonEq * math.cos(loc.latitude * math.pi / 180);

      double best = double.infinity;
      int bestIdx = from;

      for (int i = from; i < r.length; i++) {
        final double dx = (r[i].longitude - loc.longitude) * kx;
        final double dy = (r[i].latitude - loc.latitude) * _kMetersPerDegLat;
        final double d2 = dx * dx + dy * dy;

        if (d2 < best) {
          best = d2;
          bestIdx = i;

          if (best < 1.0) {
            break;
          }
        }
      }

      // Rotadan 300 m'den uzak talimat noktası (ör. (0,0) gibi bozuk veri)
      // güvenilmezdir: atla ve ilerleme noktasını bozma.
      if (best > 300.0 * 300.0) {
        _instructionRouteIndex[ins] = -1;
        continue;
      }

      _instructionRouteIndex[ins] = bestIdx;
      from = bestIdx;
    }

    _routeTotalDuration = durationSum > 0
        ? durationSum
        : (_remainingDuration > 0 ? _remainingDuration : 0.0);
  }

  // ============================================================
  // ROTAYA OTURT (en yakın çizgi parçası)
  // ============================================================

  _RouteMatch _matchOnRoute(
    LatLng p, {
    bool updateIndex = true,
  }) {
    _ensureRouteIndexed();

    final List<LatLng> r = routePoints;
    final int lastSeg = r.length - 2;

    _SegmentHit hit;

    if (_routeMatchPrimed && lastSeg > 2 * _kMatchWindow) {
      final int from = math.max(0, _lastRouteIndex - 10);
      final int to = math.min(lastSeg, _lastRouteIndex + _kMatchWindow);

      hit = _nearestSegment(r, p, from, to);

      // Pencerede bulamadıysak (tünel, GPS boşluğu) tüm rotaya bak.
      if (hit.distance > _kLostTrackMeters) {
        final _SegmentHit full = _nearestSegment(r, p, 0, lastSeg);

        if (full.distance < hit.distance) {
          hit = full;
        }
      }
    } else {
      hit = _nearestSegment(r, p, 0, lastSeg);
    }

    if (updateIndex && hit.distance <= _kLostTrackMeters) {
      _lastRouteIndex = hit.index;
      _routeMatchPrimed = true;
    }

    final double kx =
        _kMetersPerDegLonEq * math.cos(p.latitude * math.pi / 180);

    final double segLen =
        _routeCumulative[hit.index + 1] - _routeCumulative[hit.index];

    return _RouteMatch(
      index: hit.index,
      distance: hit.distance,
      alongMeters: _routeCumulative[hit.index] + hit.t * segLen,
      snapped: LatLng(
        p.latitude + hit.offsetY / _kMetersPerDegLat,
        p.longitude + hit.offsetX / kx,
      ),
    );
  }

  // ============================================================
  // NAVİGASYON TALİMATLARINI GÜNCELLE
  // ============================================================

  void _updateNavigationInstruction(
    LatLng currentLocation, {
    _RouteMatch? match,
  }) {
    if (routePoints.length < 2) {
      return;
    }

    final _RouteMatch m = match ?? _matchOnRoute(currentLocation);

    if (_routeCumulative.isEmpty) {
      return;
    }

    // Rotada olduğumuzdan emin değilsek talimat/anons üretme.
    if (m.distance > _kLostTrackMeters) {
      return;
    }

    final List<double> cum = _routeCumulative;

    // Kalan mesafe ve süre (rota boyunca)
    final double remaining = math.max(0.0, cum.last - m.alongMeters);

    _remainingDistance = remaining;

    if (cum.last > 0 && _routeTotalDuration > 0) {
      _remainingDuration =
          _routeTotalDuration * math.min(1.0, remaining / cum.last);
    }

    if (_navigationInstructions.isEmpty) {
      return;
    }

    if (_currentInstructionIndex >= _navigationInstructions.length) {
      _currentInstructionIndex = _navigationInstructions.length - 1;
    }

    // Geçilen talimatları atla (talimat noktasını 20 m geçtiysek).
    while (_currentInstructionIndex < _navigationInstructions.length - 1) {
      final _NavigationInstruction passed =
          _navigationInstructions[_currentInstructionIndex];

      final int? idx = _instructionRouteIndex[passed];

      if (idx == null) {
        break;
      }

      if (idx < 0 || m.alongMeters > cum[idx] + 20.0) {
        _currentInstructionIndex++;
      } else {
        break;
      }
    }

    final _NavigationInstruction instruction =
        _navigationInstructions[_currentInstructionIndex];

    final int? instructionIdx = _instructionRouteIndex[instruction];

    if (instructionIdx != null && instructionIdx >= 0) {
      final double distance =
          math.max(0.0, cum[instructionIdx] - m.alongMeters);

      _currentInstructionText = instruction.text;
      _currentInstructionDistance = distance;

      unawaited(_speakNavigationInstructionIfNeeded(instruction, distance));
    }
  }

  // ============================================================
  // ROTA YÖNÜ (rota üzerinde ~25 m ileri bakış)
  // ============================================================

  double _routeBearing(_RouteMatch match) {
    final List<LatLng> r = routePoints;

    if (r.length < 2 || match.index + 1 >= r.length) {
      return _currentHeading;
    }

    double covered = 0.0;
    LatLng prev = match.snapped;
    int next = match.index + 1;
    LatLng target = r[next];

    while (true) {
      target = r[next];

      covered += Geolocator.distanceBetween(
        prev.latitude,
        prev.longitude,
        target.latitude,
        target.longitude,
      );

      prev = target;

      if (covered >= 25.0 || next >= r.length - 1) {
        break;
      }

      next++;
    }

    if (covered < 1.0) {
      return _currentHeading;
    }

    return _bearingBetween(match.snapped, target);
  }

  // ============================================================
  // NAVİGASYON ANONSUNU TEKRAR ETME KONTROLÜ
  // ============================================================

  Future<void> _speakNavigationText(String text) async {
    final int instructionIndex = _currentInstructionIndex;
    final DateTime now = DateTime.now();
    final DateTime? lastSpeech = _lastNavigationSpeech;

    // Aynı talimat 3 saniye içinde tekrar seslendirilmesin.
    if (_lastSpokenRouteIndex == instructionIndex &&
        lastSpeech != null &&
        now.difference(lastSpeech).inSeconds < 3) {
      return;
    }

    _lastSpokenRouteIndex = instructionIndex;
    _lastNavigationSpeech = now;

    // Dönüş talimatı ACİL: mola/uyarı anonsları bunu kesmez.
    await _speak(text, urgent: true);
  }

  // ============================================================
  // DÖNÜŞ TALİMATINI SESLENDİR (hıza bağlı eşikler)
  // ============================================================

  Future<void> _speakNavigationInstructionIfNeeded(
    _NavigationInstruction instruction,
    double distance,
  ) async {
    if (!_isVoiceRelevantInstruction(instruction)) {
      instruction.spokenFar = true;
      instruction.spokenNear = true;
      instruction.spokenNow = true;
      return;
    }

    if (instruction.spokenNow) {
      return;
    }

    // Anons mesafeleri ~zamana göre: hız ne kadar yüksekse o kadar erken.
    final double speed = math.max(_currentSpeed, 5.0); // m/s, alt sınır 18 km/h
    final double nowAt = math.min(120.0, math.max(40.0, speed * 5));
    final double nearAt = math.min(600.0, math.max(250.0, speed * 20));
    final double farAt = math.min(2500.0, math.max(800.0, speed * 60));

    final String text = instruction.text;
    String? speakText;

    if (distance <= nowAt) {
      instruction.spokenNow = true;
      instruction.spokenNear = true;
      instruction.spokenFar = true;

      speakText = _localizedInstructionText('now', text);
    } else if (!instruction.spokenNear && distance <= nearAt) {
      instruction.spokenNear = true;
      instruction.spokenFar = true;

      speakText = _localizedInstructionText(
        'in_distance',
        text,
        meters: distance,
      );
    } else if (!instruction.spokenFar && distance <= farAt) {
      instruction.spokenFar = true;

      speakText = _localizedInstructionText(
        'in_distance',
        text,
        meters: distance,
      );
    }

    if (speakText != null) {
      await _speakNavigationText(speakText);
    }
  }

  bool _isVoiceRelevantInstruction(_NavigationInstruction instruction) {
    final String modifier = instruction.modifier.toLowerCase().trim();
    final String text = instruction.text.toLowerCase().trim();

    if (modifier == 'straight' || modifier == 'continue') {
      return false;
    }

    if (modifier.isEmpty &&
        RegExp(
          r'\b(weiter|geradeaus|folgen|nördlich|südlich|östlich|westlich|'
          r'continue|follow|straight|northbound|southbound|eastbound|'
          r'westbound)\b',
          caseSensitive: false,
        ).hasMatch(text) &&
        !RegExp(
          r'\b(rechts|links|abbieg|halten|ausfahrt|auffahrt|rampe|'
          r'kreisel|kreisverkehr|wenden|ziel|ankunft|right|left|exit|'
          r'ramp|roundabout|uturn|destination)\b',
          caseSensitive: false,
        ).hasMatch(text)) {
      return false;
    }

    return true;
  }

  /// Konuşma için mesafe ("500 Metern", "1,5 Kilometern").
  String _spokenDistance(double meters) {
    final bool tr = _voiceLanguage == 'tr-TR';
    final bool en = _voiceLanguage == 'en-US';

    if (meters >= 950) {
      final double km = (meters / 100).round() / 10;
      final bool whole = km == km.roundToDouble();

      final String number = whole
          ? km.round().toString()
          : (en
              ? km.toStringAsFixed(1)
              : km.toStringAsFixed(1).replaceAll('.', ','));

      if (tr) {
        return '$number kilometre';
      }

      if (en) {
        return km == 1.0 ? '1 kilometer' : '$number kilometers';
      }

      return km == 1.0 ? 'einem Kilometer' : '$number Kilometern';
    }

    final int m = meters < 100
        ? math.max(10, (meters / 10).round() * 10)
        : (meters / 50).round() * 50;

    if (tr) {
      return '$m metre';
    }

    if (en) {
      return '$m meters';
    }

    return '$m Metern';
  }

  String _localizedInstructionText(
    String kind,
    String text, {
    double? meters,
  }) {
    if (kind == 'now') {
      if (_voiceLanguage == 'tr-TR') {
        return 'Şimdi $text';
      } else if (_voiceLanguage == 'en-US') {
        return 'Now $text';
      }
      return 'Jetzt $text';
    }

    final String spoken = _spokenDistance(meters ?? 0);

    if (_voiceLanguage == 'tr-TR') {
      return '$spoken sonra $text';
    } else if (_voiceLanguage == 'en-US') {
      return 'In $spoken, $text';
    }
    return 'In $spoken, $text';
  }

  // ============================================================
  // ROTADAN ÇIKMA
  // ============================================================

  void _checkOffRoute(
    LatLng currentLocation, {
    double accuracy = 0.0,
    double speedMps = 0.0,
    _RouteMatch? match,
  }) {
    if (_isRecalculating || routePoints.length < 2 || destination == null) {
      return;
    }

    final DateTime now = DateTime.now();

    if (_lastOffRouteCheck != null &&
        now.difference(_lastOffRouteCheck!) < const Duration(seconds: 3)) {
      return;
    }

    _lastOffRouteCheck = now;

    // Yavaşken (park, depo) yeniden hesaplama tetikleme.
    if (speedMps < 2.0) {
      _offRouteReadings = 0;
      return;
    }

    final _RouteMatch m = match ?? _matchOnRoute(currentLocation);

    // GPS hatası büyükse eşiği büyüt (en fazla 150 m).
    final double threshold = math.min(
      150.0,
      math.max(
        _kOffRouteThresholdMeters,
        (accuracy.isFinite ? accuracy : 0.0) * 1.5,
      ),
    );

    if (m.distance < threshold) {
      _offRouteReadings = 0;
      return;
    }

    _offRouteReadings++;

    if (_offRouteReadings < 2) {
      return;
    }

    _offRouteReadings = 0;

    // Üst üste yeniden hesaplamayı engelle (TomTom kotası).
    if (_lastRecalculationAt != null &&
        now.difference(_lastRecalculationAt!) < _kRecalculationCooldown) {
      return;
    }

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
    _lastRecalculationAt = DateTime.now();

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
      urgent: true,
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
    LatLng currentLocation, {
    _RouteMatch? match,
  }) {
    if (destination == null || !_navigationStarted) {
      return;
    }

    final double distance = Geolocator.distanceBetween(
      currentLocation.latitude,
      currentLocation.longitude,
      destination!.latitude,
      destination!.longitude,
    );

    // Hedef noktası bina merkezi olabilir (yola 100 m uzak). Bu yüzden rota
    // sonuna <=35 m kalınması da varış sayılır.
    double remainingAlong = double.infinity;

    if (match != null &&
        _routeCumulative.isNotEmpty &&
        match.distance <= _kLostTrackMeters) {
      remainingAlong = _routeCumulative.last - match.alongMeters;
    }

    if (distance > 45 && remainingAlong > 35) {
      return;
    }

    _stopNavigation();

    _speak(
      _voiceLanguage == 'tr-TR'
          ? 'Hedefinize ulaştınız.'
          : _voiceLanguage == 'en-US'
              ? 'You have reached your destination.'
              : 'Sie haben Ihr Ziel erreicht.',
      urgent: true,
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

  // ============================================================
  // MESAFE FORMAT (Webfleet / Google Maps Standardı)
  // ============================================================
  String _formatDistance(
    double meters,
  ) {
    // 10 metreden az: Tam sayı (5 m, 8 m)
    if (meters < 10) {
      return '${meters.round()} m';
    }
    // 10-100 metre arası: 10'un katları (20 m, 50 m, 80 m)
    else if (meters < 100) {
      return '${(meters / 10).round() * 10} m';
    }
    // 100-500 metre arası: 50'nin katları (100 m, 150 m, 200 m)
    else if (meters < 500) {
      return '${(meters / 50).round() * 50} m';
    }
    // 500-1000 metre arası: 100'ün katları (500 m, 600 m, 800 m)
    else if (meters < 1000) {
      return '${(meters / 100).round() * 100} m';
    }
    // 1 km ve üzeri: 500 metrenin katları (1.0 km, 1.5 km, 2.0 km, 2.5 km)
    else {
      final double km = (meters / 500).round() * 0.5;
      return '${km.toStringAsFixed(1)} km';
    }
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
  // NOMINATIM (tek yardımcı)
  // ============================================================
  // DİKKAT: Public Nominatim "yazarken otomatik tamamlama"yı yasaklar ve
  // saniyede en fazla 1 istek ister. Yayına çıkmadan önce ücretli/kendi
  // geocoding servisine (Photon, Geoapify, HERE, TomTom Search) geç.

  Future<List<dynamic>> _nominatimSearch(
    String query, {
    int limit = 5,
  }) async {
    final String url = 'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}'
        '&format=json'
        '&limit=$limit'
        '&countrycodes=$_kSearchCountryCodes';

    final http.Response response = await http.get(
      Uri.parse(url),
      headers: const {
        'User-Agent': 'lkw_almanya_navigation_app',
      },
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Adres servisi hata verdi: ${response.statusCode}');
    }

    final dynamic data = jsonDecode(response.body);

    return data is List ? data : <dynamic>[];
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
          _suggestionRequestId++;

          if (!mounted) {
            return;
          }

          setState(() {
            searchSuggestions = <dynamic>[];
            isLoadingSuggestions = false;
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

    final int requestId = ++_suggestionRequestId;

    setState(() {
      isLoadingSuggestions = true;
    });

    try {
      final List<dynamic> results = await _nominatimSearch(query);

      if (!mounted || requestId != _suggestionRequestId) {
        return;
      }

      setState(() {
        searchSuggestions = results;
      });
    } catch (e) {
      debugPrint(
        'SUGGESTION ERROR: $e',
      );
    }

    if (!mounted || requestId != _suggestionRequestId) {
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

    try {
      final List<dynamic> data = await _nominatimSearch(query, limit: 1);

      if (!mounted) {
        return;
      }

      if (data.isEmpty) {
        _showRouteError(
          'Adres bulunamadı.',
        );

        return;
      }

      selectSuggestion(
        data[0],
      );
    } catch (e) {
      debugPrint('ADDRESS SEARCH ERROR: $e');

      if (!mounted) {
        return;
      }

      _showRouteError(
        'Adres servisine ulaşılamadı veya zaman aşımı. Tekrar deneyin.',
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

    bool sheetOpen = true;

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
              if (!sheetOpen) {
                return;
              }

              if (query.trim().length < 3) {
                setModalState(() {
                  localSuggestions = <dynamic>[];
                });

                return;
              }

              setModalState(() {
                localLoading = true;
              });

              try {
                final List<dynamic> results = await _nominatimSearch(query);

                if (!sheetOpen) {
                  return;
                }

                setModalState(() {
                  localSuggestions = results;
                });
              } catch (e) {
                debugPrint('BAŞLANGIÇ ARAMA HATASI: $e');
              }

              if (!sheetOpen) {
                return;
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
      sheetOpen = false;
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

    final bool usedCustomStart = _routeStartPoint != null;

    if (!mounted) {
      return;
    }

    if (showLoading) {
      _showRouteLoading();
    }

    try {
      // ========================================================
      // KAMYON - TomTom Routing API
      // ========================================================

      if (vehicle == 'truck') {
        final VehicleProfile truckProfile =
            _truckProfileToVehicleProfile(_truckProfile);

        final RouteService service = RouteService();

        List<RouteResult> allRoutes;
        try {
          allRoutes = await service
              .fetchAlternativeRoutes(
                from: start,
                to: destinationPoint,
                profile: truckProfile,
                alternatives: 2,
              )
              .timeout(const Duration(seconds: 20));
        } catch (e) {
          debugPrint('⚠️ Alternatif rota alınamadı, ana rota çekiliyor: $e');
          allRoutes = <RouteResult>[
            await service
                .fetchRoute(
                  from: start,
                  to: destinationPoint,
                  profile: truckProfile,
                )
                .timeout(const Duration(seconds: 20)),
          ];
        }

        if (!mounted) return;
        if (showLoading) {
          Navigator.of(context).maybePop();
        }

        final RouteResult result = allRoutes.first;
        final List<LatLng> points = result.points;

        final List<List<LatLng>> truckAlternatives = allRoutes
            .skip(1)
            .map((RouteResult r) => r.points)
            .where((List<LatLng> p) => p.isNotEmpty)
            .toList();

        final List<_NavigationInstruction> instructions =
            _parseTomTomInstructions(result.steps);
        final double totalDistance = result.distanceM;
        final double totalDuration = result.durationS;

        debugPrint(
          '🚚 Ana rota: ${result.distanceKm}, '
          '${truckAlternatives.length} alternatif',
        );

        setState(() {
          routeColor = Colors.green.shade700; // ⬅️ YEŞİL
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
          _lastRouteIndex = 0;
          _offRouteReadings = 0;
          _remainingDistance = totalDistance;
          _remainingDuration = totalDuration;
          _currentInstructionText = instructions.isNotEmpty
              ? instructions.first.text
              : 'Rotayı takip edin.';
          _currentInstructionDistance =
              instructions.isNotEmpty ? instructions.first.distance : 0;
          _closedRoadSections = result.closedRoads;
        });

        // TomTom Traffic'ten kapalı yolları çek
        _fetchTomTomTrafficIncidents(points);

        if (userLocation != null) {
          _isFollowingLocation = true;
          _moveMapWithDirection(
            userLocation!,
            _currentHeading,
          );
          _scheduleNavigationCamera(
            userLocation!,
            _currentHeading,
          );
        }

        _fitRouteOnMap(points);

        // NOT: _drivingStartTime burada ARTIK sıfırlanmıyor (yeniden rota
        // hesaplamada 4,5 saatlik sayaç başa dönüyordu). Bkz. _trackDrivingBlock.

        // Sadece kullanıcının başlattığı rotalar geçmişe eklenir
        // (yeniden hesaplamalar announce:false ile gelir).
        if (announce) {
          _addRouteToHistory(
            destinationPoint,
            'truck',
            addressController.text.isNotEmpty
                ? addressController.text
                : 'Kamyon Rotası',
            totalDistance,
            totalDuration,
          );
        }

        if (announce) {
          await _speak(
            _voiceLanguage == 'tr-TR'
                ? 'Git. Kamyon rotası hazır. Navigasyon başladı.'
                : _voiceLanguage == 'en-US'
                    ? 'Go. Truck route ready. Navigation started.'
                    : 'Los. LKW Route ist bereit. Navigation gestartet.',
            urgent: true,
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

      final http.Response response = await http
          .get(
            url,
          )
          .timeout(const Duration(seconds: 20));

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
          routeColor = Colors.green.shade700; // ⬅️ YEŞİL

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

          _lastRouteIndex = 0;

          _offRouteReadings = 0;

          _remainingDistance = totalDistance;

          _remainingDuration = totalDuration;

          _currentInstructionText = instructions.isNotEmpty
              ? instructions.first.text
              : 'Rotayı takip edin.';

          _currentInstructionDistance =
              instructions.isNotEmpty ? instructions.first.distance : 0;

          _closedRoadSections = <ClosedRoadSection>[];
        });

        _fetchTomTomTrafficIncidents(mainRoute);

        if (userLocation != null) {
          _isFollowingLocation = true;
          _moveMapWithDirection(
            userLocation!,
            _currentHeading,
          );
          _scheduleNavigationCamera(
            userLocation!,
            _currentHeading,
          );
        }

        _fitRouteOnMap(
          mainRoute,
        );

        if (announce) {
          _addRouteToHistory(
            destinationPoint,
            'car',
            addressController.text.isNotEmpty
                ? addressController.text
                : 'Otomobil Rotası',
            totalDistance,
            totalDuration,
          );
        }

        if (announce) {
          if (alternatives.isNotEmpty) {
            await _speak(
              _voiceLanguage == 'tr-TR'
                  ? 'Git. Otomobil rotası hazır. '
                      '${alternatives.length} alternatif rota mevcut.'
                  : _voiceLanguage == 'en-US'
                      ? 'Go. Car route ready. '
                          '${alternatives.length} alternative routes available.'
                      : 'Los. Die Autoroute ist bereit. '
                          '${alternatives.length} alternative Routen verfügbar.',
              urgent: true,
            );
          } else {
            await _speak(
              _voiceLanguage == 'tr-TR'
                  ? 'Git. Otomobil rotası hazır. Navigasyon başladı.'
                  : _voiceLanguage == 'en-US'
                      ? 'Go. Car route ready. Navigation started.'
                      : 'Los. Die Autoroute ist bereit. Navigation gestartet.',
              urgent: true,
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
  // TOMTOM TRAFFIC - KAPALI YOLLARI ÇEK
  // ============================================================
  // Sadece ROTAYA <=150 m olan olaylar gösterilir (eskiden rotanın tüm
  // kutusundaki olaylar çiziliyordu).
  //
  // iconCategory (TomTom Traffic Incident Details): 1 Kaza, 6 Trafik
  // sıkışıklığı, 7 Şerit kapalı, 8 Yol kapalı, 9 Yol çalışması.
  // ⚠️ Bu eşlemeyi TomTom dokümanından bir kez daha doğrula.
  // Eski kod 6'yı "yol çalışması" sayıyordu; sıkışıklığı kapalı yol diye
  // kırmızı çiziyordu.
  Future<void> _fetchTomTomTrafficIncidents(List<LatLng> route) async {
    if (route.length < 2) return;

    double minLat = route.first.latitude;
    double maxLat = route.first.latitude;
    double minLng = route.first.longitude;
    double maxLng = route.first.longitude;

    for (final p in route) {
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

    final service = TomTomRouteService();

    try {
      final incidents = await service
          .fetchTrafficIncidents(
            minPoint: LatLng(minLat, minLng),
            maxPoint: LatLng(maxLat, maxLng),
          )
          .timeout(const Duration(seconds: 20));

      if (incidents.isEmpty) {
        debugPrint('🚧 TomTom Traffic: Trafik olayı bulunamadı.');
        return;
      }

      const Set<int> shownCategories = <int>{1, 8, 9};

      final List<ClosedRoadSection> closedRoads = [];

      for (final incident in incidents) {
        final properties = incident['properties'] as Map<String, dynamic>?;
        if (properties == null) continue;

        final int? iconCategory = (properties['iconCategory'] as num?)?.toInt();
        if (iconCategory == null) continue;

        if (!shownCategories.contains(iconCategory)) continue;

        final geometry = incident['geometry'] as Map<String, dynamic>?;
        if (geometry == null) continue;

        final String geoType = geometry['type']?.toString() ?? '';
        final dynamic coords = geometry['coordinates'];

        final List<LatLng> points = <LatLng>[];

        if (geoType == 'LineString' && coords is List) {
          for (final coord in coords) {
            if (coord is List && coord.length >= 2) {
              points.add(LatLng(
                (coord[1] as num).toDouble(),
                (coord[0] as num).toDouble(),
              ));
            }
          }
        } else if (geoType == 'Point' && coords is List && coords.length >= 2) {
          final LatLng p = LatLng(
            (coords[1] as num).toDouble(),
            (coords[0] as num).toDouble(),
          );

          // Aynı nokta iki kez: gerçek bir "çizgi" uydurmadan nokta olarak çizilir.
          points.add(p);
          points.add(p);
        }

        if (points.isEmpty) continue;

        // Rotaya yakın mı? (ilk, orta, son noktayı dene)
        final List<LatLng> samples = points.length <= 3
            ? points
            : <LatLng>[
                points.first,
                points[points.length ~/ 2],
                points.last,
              ];

        bool nearRoute = false;

        for (final LatLng s in samples) {
          if (_distanceToRouteMeters(s, route, stopBelow: 150.0) <= 150.0) {
            nearRoute = true;
            break;
          }
        }

        if (!nearRoute) continue;

        closedRoads.add(ClosedRoadSection(
          points: points,
          reason: _incidentReason(properties, iconCategory),
        ));
      }

      if (mounted && closedRoads.isNotEmpty) {
        setState(() {
          // Rota servisinden gelen kapalı yolları EZME, ekle.
          _closedRoadSections = <ClosedRoadSection>[
            ..._closedRoadSections,
            ...closedRoads,
          ];
        });
        debugPrint(
            '🚧 TomTom Traffic: rotaya yakın ${closedRoads.length} olay bulundu');
      } else {
        debugPrint('🚧 TomTom Traffic: rotaya yakın olay yok.');
      }
    } catch (e) {
      debugPrint('🚧 TomTom Traffic HATASI: $e');
    }
  }

  // ============================================================
  // ROTA GEÇMİŞİ
  // ============================================================

  Future<void> _loadRouteHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? saved = prefs.getString(_HomePageState._historyStorageKey);
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
      await prefs.setString(_HomePageState._historyStorageKey, encoded);
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

  double _smoothHeading(double newHeading) {
    double diff = newHeading - _currentHeading;
    while (diff > 180) {
      diff -= 360;
    }
    while (diff < -180) {
      diff += 360;
    }

    // ⬇️ İYİLEŞTİRME: 30 derece yerine 45 derece/saniye (daha hızlı tepki)
    const double maxChange = 45.0;
    if (diff.abs() > maxChange) {
      diff = diff.sign * maxChange;
    }

    double result = _currentHeading + diff;
    if (result < 0) result += 360;
    if (result >= 360) result -= 360;
    return result;
  }
}
