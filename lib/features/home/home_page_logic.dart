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

      // DÜZELTME (FIX): 0.48 çok yavaştı, anonslar geç geliyordu.
      // 0.55 normal hız; hâlâ yavaş gelirse 0.6-0.7 yapılabilir.
      await _tts.setSpeechRate(
        0.55,
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

        if (_navigationStarted && routePoints.length >= 2) {
          // Navigasyon sırasında pusula heading'i düşük hızda veya araç
          // dururken eski/hatalı kalabilir. Oku rota üzerindeki bir sonraki
          // noktaya göre hizalayarak gerçek sürüş yönünü gösteriyoruz.
          heading = _routeBearing(location);
        } else if (position.heading >= 0 &&
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

          // Konum setState'i haritayı yeniden oluşturduğunda bazı
          // flutter_map sürümleri kamerayı MapOptions'taki başlangıç
          // zoom'una geri alabiliyor. Kamerayı frame sonrasında tekrar
          // sürücüye kilitleyerek navigasyon zoom'unu koruyoruz.
          _scheduleNavigationCamera(
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
      double zoom = mapController.camera.zoom;

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

  void _scheduleNavigationCamera(
    LatLng location,
    double heading,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_navigationStarted || !_isFollowingLocation) {
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
      routePoints = <LatLng>[];
      alternativeRoutePoints = <List<LatLng>>[];
      _routeRestrictions = <_RouteRestriction>[];
      _routeRestrictionWarning = '';
      _speedLimits = <_SpeedLimitSegment>[];
      _currentSpeedLimit = 0;
      _truckParkings = <_TruckParking>[];
      _fuelStations = <_FuelStation>[];
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

    // Talimatı "en yakın manevra" ile seçmek, başlangıçtaki "Yola çıkın"
    // talimatının uzun süre aktif kalmasına neden oluyordu. Bunun yerine
    // aracın rota üzerindeki ilerlemesini ölçüp, geride kalan talimatları
    // atlıyor ve sıradaki manevrayı gösteriyoruz.
    final int currentRouteIndex = _nearestRoutePointIndex(currentLocation);
    int nextInstructionIndex = _currentInstructionIndex;

    for (int i = _currentInstructionIndex;
        i < _navigationInstructions.length;
        i++) {
      final _NavigationInstruction candidate = _navigationInstructions[i];

      if (candidate.location == null) {
        continue;
      }

      final int instructionRouteIndex =
          _nearestRoutePointIndex(candidate.location!);

      if (instructionRouteIndex >= currentRouteIndex) {
        nextInstructionIndex = i;
        break;
      }

      // Bu manevra geride kaldı; sonraki talimata ilerlemeye devam et.
      nextInstructionIndex = i;
    }

    if (nextInstructionIndex > _currentInstructionIndex) {
      _currentInstructionIndex = nextInstructionIndex;
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

      // DÜZELTME (FIX): Talimat metni hiç güncellenmiyordu; üst
      // kart her zaman "Yola çıkın" sabit kalıyordu.
      _currentInstructionText = instruction.text;

      _currentInstructionDistance = distance;

      _speakNavigationInstructionIfNeeded(instruction, distance);
    }

    // Kalan mesafeyi yalnızca talimat değiştiğinde değil, her GPS
    // güncellemesinde rota geometrisi üzerinden hesapla. Aksi halde alt
    // karttaki mesafe (ör. 241 m) bir sonraki manevraya kadar sabit kalır.
    double remaining = 0;

    if (routePoints.length >= 2) {
      final int routeIndex = _nearestRoutePointIndex(currentLocation);

      remaining = Geolocator.distanceBetween(
        currentLocation.latitude,
        currentLocation.longitude,
        routePoints[routeIndex].latitude,
        routePoints[routeIndex].longitude,
      );

      for (int i = routeIndex; i < routePoints.length - 1; i++) {
        remaining += Geolocator.distanceBetween(
          routePoints[i].latitude,
          routePoints[i].longitude,
          routePoints[i + 1].latitude,
          routePoints[i + 1].longitude,
        );
      }
    }

    _remainingDistance = remaining;

    double totalInstructionDistance = 0;
    double totalInstructionDuration = 0;

    for (final _NavigationInstruction item in _navigationInstructions) {
      totalInstructionDistance += item.distance;
      totalInstructionDuration += item.duration;
    }

    if (totalInstructionDistance > 0) {
      final double ratio =
          (remaining / totalInstructionDistance).clamp(0.0, 1.0).toDouble();
      _remainingDuration = totalInstructionDuration * ratio;
    } else {
      _remainingDuration = 0;
    }

    if (mounted) {
      setState(() {});
    }
  }

  int _nearestRoutePointIndex(LatLng location) {
    if (routePoints.isEmpty) {
      return 0;
    }

    double nearestDistance = double.infinity;
    int nearestIndex = 0;

    for (int i = 0; i < routePoints.length; i++) {
      final LatLng point = routePoints[i];
      final double distance = Geolocator.distanceBetween(
        location.latitude,
        location.longitude,
        point.latitude,
        point.longitude,
      );

      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearestIndex = i;
      }
    }

    return nearestIndex;
  }

  double _routeBearing(LatLng location) {
    if (routePoints.length < 2) {
      return _currentHeading;
    }

    final int nearestIndex = _nearestRoutePointIndex(location);
    int nextIndex = nearestIndex + 1;

    while (nextIndex < routePoints.length - 1 &&
        Geolocator.distanceBetween(
              routePoints[nearestIndex].latitude,
              routePoints[nearestIndex].longitude,
              routePoints[nextIndex].latitude,
              routePoints[nextIndex].longitude,
            ) <
            2) {
      nextIndex++;
    }

    final LatLng from = routePoints[nearestIndex];
    final int safeNextIndex =
        nextIndex.clamp(0, routePoints.length - 1).toInt();
    final LatLng to = routePoints[safeNextIndex];

    final double lat1 = from.latitude * math.pi / 180;
    final double lat2 = to.latitude * math.pi / 180;
    final double deltaLongitude =
        (to.longitude - from.longitude) * math.pi / 180;

    final double y = math.sin(deltaLongitude) * math.cos(lat2);
    final double x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(deltaLongitude);

    final double bearing = math.atan2(y, x) * 180 / math.pi;
    return (bearing + 360) % 360;
  }

  // ============================================================
  // DÖNÜŞ TALİMATINI SESLENDİR
  // ============================================================

  Future<void> _speakNavigationInstructionIfNeeded(
    _NavigationInstruction instruction,
    double distance,
  ) async {
    // Rota servisleri otoyollarda çok sayıda "düz devam et / A45 üzerinde
    // devam et" adımı döndürebilir. Bunları seslendirmek, düz yolda sürekli
    // ve gereksiz anons yapılmasına neden olur. Talimat ekranda görünmeye
    // devam eder; yalnızca gerçek manevralar seslendirilir.
    if (!_isVoiceRelevantInstruction(instruction)) {
      instruction.spokenFar = true;
      instruction.spokenNear = true;
      instruction.spokenNow = true;
      return;
    }

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

  bool _isVoiceRelevantInstruction(_NavigationInstruction instruction) {
    final String modifier = instruction.modifier.toLowerCase().trim();
    final String text = instruction.text.toLowerCase().trim();

    if (modifier == 'straight' || modifier == 'continue') {
      return false;
    }

    // Bazı ORS cevaplarında modifier boş gelebiliyor. Metin açıkça düz
    // ilerlemeyi anlatıyorsa yine seslendirmiyoruz; "sağda kal", çıkış,
    // rampa ve dönüş gibi ifadeler bu filtreden geçer.
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

      if (!mounted || requestId != _suggestionRequestId) {
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

        // DÜZELTME (FIX): Navigasyon başlar başlamaz kamera
        // sürücü konumuna kilitlenip zoom 17 yapıyor; eski
        // sürümde harita "sabit" kalıyordu.
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
          points,
        );

        _fetchRouteRestrictions(points);
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
          // DÜZELTME (FIX): Google Maps gibi başta "Git / Go / Los"
          // anonsu ekliyoruz; sadece "rotanız hazır" yetmiyordu.
          await _speak(
            _voiceLanguage == 'tr-TR'
                ? 'Git. Kamyon rotası hazır. Navigasyon başladı.'
                : _voiceLanguage == 'en-US'
                    ? 'Go. Truck route ready. Navigation started.'
                    : 'Los. LKW Route ist bereit. Navigation gestartet.',
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

        // DÜZELTME (FIX): Aynı zoom kilitleme düzeltmesi
        // otomobil (OSRM) kolu için.
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

        _fetchRouteRestrictions(mainRoute);
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
                  ? 'Git. Otomobil rotası hazır. '
                      '${alternatives.length} alternatif rota mevcut.'
                  : _voiceLanguage == 'en-US'
                      ? 'Go. Car route ready. '
                          '${alternatives.length} alternative routes available.'
                      : 'Los. Die Autoroute ist bereit. '
                          '${alternatives.length} alternative Routen verfügbar.',
            );
          } else {
            await _speak(
              _voiceLanguage == 'tr-TR'
                  ? 'Git. Otomobil rotası hazır. Navigasyon başladı.'
                  : _voiceLanguage == 'en-US'
                      ? 'Go. Car route ready. Navigation started.'
                      : 'Los. Die Autoroute ist bereit. Navigation gestartet.',
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

  // ============================================================
  // DURAKLAR
  // ============================================================
}
