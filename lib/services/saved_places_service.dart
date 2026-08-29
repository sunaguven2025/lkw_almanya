import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/saved_place.dart';

class SavedPlacesService {
  static const String _storageKey = 'saved_places';

  Future<List<SavedPlace>> getPlaces() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    final String? storedData = preferences.getString(_storageKey);

    if (storedData == null || storedData.isEmpty) {
      return <SavedPlace>[];
    }

    try {
      final dynamic decodedData = jsonDecode(storedData);

      if (decodedData is! List) {
        return <SavedPlace>[];
      }

      return decodedData
          .whereType<Map>()
          .map(
            (Map item) => SavedPlace.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList();
    } catch (e) {
      return <SavedPlace>[];
    }
  }

  Future<void> savePlace(SavedPlace place) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    final List<SavedPlace> places = await getPlaces();

    places.removeWhere(
      (SavedPlace item) => item.id == place.id,
    );

    places.insert(
      0,
      place,
    );

    final String encodedData = jsonEncode(
      places.map((SavedPlace item) => item.toJson()).toList(),
    );

    await preferences.setString(
      _storageKey,
      encodedData,
    );
  }

  Future<void> deletePlace(String id) async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    final List<SavedPlace> places = await getPlaces();

    places.removeWhere(
      (SavedPlace item) => item.id == id,
    );

    final String encodedData = jsonEncode(
      places.map((SavedPlace item) => item.toJson()).toList(),
    );

    await preferences.setString(
      _storageKey,
      encodedData,
    );
  }

  Future<void> clearAll() async {
    final SharedPreferences preferences = await SharedPreferences.getInstance();

    await preferences.remove(
      _storageKey,
    );
  }
}
