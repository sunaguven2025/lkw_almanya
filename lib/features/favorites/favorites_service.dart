import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'favorite_place.dart';

class FavoritesService {
  static const String storageKey = "favorite_places";

  Future<List<FavoritePlace>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();

    final String? data = prefs.getString(storageKey);

    if (data == null) {
      return [];
    }

    final List list = jsonDecode(data);

    return list
        .map((e) => FavoritePlace.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> saveFavorites(List<FavoritePlace> favorites) async {
    final prefs = await SharedPreferences.getInstance();

    final String data = jsonEncode(favorites.map((e) => e.toMap()).toList());

    await prefs.setString(storageKey, data);
  }

  Future<void> addFavorite(FavoritePlace place) async {
    final list = await getFavorites();

    list.removeWhere((e) => e.id == place.id);

    list.insert(0, place);

    await saveFavorites(list);
  }

  Future<void> deleteFavorite(String id) async {
    final list = await getFavorites();

    list.removeWhere((e) => e.id == id);

    await saveFavorites(list);
  }

  Future<void> clearFavorites() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(storageKey);
  }
}
