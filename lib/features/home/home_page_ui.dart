// ignore_for_file: curly_braces_in_flow_control_structures
part of 'home_page.dart';

// setState burada bir extension üzerinden çağrılıyor. Extension'lar Dart'ın
// miras zincirinin parçası sayılmadığı için analyzer bunu "protected üyeye
// dışarıdan erişim" olarak işaretliyor; ancak bu extension SADECE
// _HomePageState (bir State<HomePage> alt sınıfı) üzerinde tanımlı olduğundan
// çağrı güvenli ve doğrudur. Bu dosyaya özel olarak susturuyoruz.
// ignore_for_file: invalid_use_of_protected_member

// ================================================================
// ARAYÜZ (tüm _build... widget fonksiyonları, bottom sheet'ler,
// harita kontrolleri)
// Bu dosya home_page.dart'ın parçasıdır (part of), bu yüzden
// _HomePageState'in private alan/metodlarına doğrudan erişebilir.
// ================================================================

extension _HomePageUIX on _HomePageState {
  Future<void> _loadStops() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? saved = prefs.getString(_HomePageState._stopsStorageKey);
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
      await prefs.setString(_HomePageState._stopsStorageKey, encoded);
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

        // API cevabı rota hesaplandıktan sonra geldiği için kontrol burada
        // yapılmalı. Rota hesaplama fonksiyonundaki hemen-sonraki kontrol,
        // liste henüz boş olduğu için etkisiz kalıyordu.
        _checkRouteRestrictions();
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
            modifier: _orsModifier(step['type']),
          ),
        );
      }
    }

    return result;
  }

  String _orsModifier(dynamic value) {
    final int? type =
        value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

    switch (type) {
      case 0:
        return 'left';
      case 1:
        return 'right';
      case 2:
        return 'sharp left';
      case 3:
        return 'sharp right';
      case 4:
        return 'slight left';
      case 5:
        return 'slight right';
      case 6:
        return 'straight';
      case 7:
      case 8:
        return 'roundabout';
      case 9:
        return 'uturn';
      default:
        return '';
    }
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
            modifier:
                maneuver is Map ? maneuver['modifier']?.toString() ?? '' : '',
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
            tileColor: Colors.white,
            leading: const Icon(
              Icons.location_on,
              color: AppTheme.primaryBlue,
            ),
            title: Text(
              item['display_name']?.toString() ?? '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              // DÜZELTME (FIX): Liste teması (mavi/grimsi)
              // sonucu öneri metni silik çıkıyordu. Metin
              // artık opak siyah yazıldı; temadan bağımsız
              // her zaman okunaklı.
              style: const TextStyle(
                color: Colors.black,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
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

  // DÜZELTME (FIX): Manevra modifier'ı -> ikon eşlemesi.
  // "ok ters" sorununun kökü buydu; sabit turn_right kalmadı.
  IconData _maneuverIcon(String modifier) {
    final String m = modifier.toLowerCase().trim();
    if (m.contains('sharp left') || m == 'sharp left') {
      return Icons.turn_sharp_left;
    }
    if (m.contains('slight left') || m.contains('left')) {
      return Icons.turn_left;
    }
    if (m.contains('sharp right') || m == 'sharp right') {
      return Icons.turn_sharp_right;
    }
    if (m.contains('slight right') || m.contains('right')) {
      return Icons.turn_right;
    }
    if (m == 'straight' || m == 'continue') {
      return Icons.straight;
    }
    if (m.contains('uturn')) {
      return Icons.u_turn_left;
    }
    if (m.contains('merge') || m.contains('on ramp')) {
      return Icons.merge_type;
    }
    if (m.contains('fork')) {
      return Icons.fork_left;
    }
    if (m.contains('roundabout') || m.contains('rotary')) {
      return Icons.roundabout_left;
    }
    return Icons.navigation;
  }

  String get _currentModifier {
    if (_navigationInstructions.isEmpty) {
      return '';
    }
    final int i = _currentInstructionIndex.clamp(
      0,
      _navigationInstructions.length - 1,
    );
    final _NavigationInstruction instruction = _navigationInstructions[i];
    final String modifier = instruction.modifier.toLowerCase().trim();

    if (modifier.isNotEmpty) {
      return modifier;
    }

    // Bazı rota servisleri "rechts halten" gibi talimatlarda modifier
    // göndermiyor. İkonu metinden tamamlayarak düz ok yerine doğru dönüş
    // ikonunu gösteriyoruz.
    final String text = instruction.text.toLowerCase();

    if (RegExp(
      r'\b(rechts|right)\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      return 'right';
    }

    if (RegExp(
      r'\b(links|left)\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      return 'left';
    }

    if (RegExp(
      r'\b(geradeaus|weiter|continue|straight|nördlich|südlich|östlich|westlich)\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      return 'straight';
    }

    return '';
  }

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
              child: Icon(
                _maneuverIcon(_currentModifier),
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
                      color: Colors.black87,
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
              child: Icon(
                // DÜZELTME (FIX): Alt kart için de aynı dinamik
                // manevra ikonu kullanılıyor; sabit navigation
                // ikonu yerine sağ/sol/düz oku.
                _maneuverIcon(_currentModifier),
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
}
