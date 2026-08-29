import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'favorite_place.dart';
import 'favorites_service.dart';

class FavoritesPage extends StatefulWidget {
  final Function(LatLng location) onNavigate;

  const FavoritesPage({
    super.key,
    required this.onNavigate,
  });

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  final FavoritesService service = FavoritesService();

  List<FavoritePlace> favorites = [];

  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    favorites = await service.getFavorites();

    if (mounted) {
      setState(() {
        loading = false;
      });
    }
  }

  Future<void> remove(FavoritePlace place) async {
    await service.deleteFavorite(place.id);

    await load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Favori Yerler"),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : favorites.isEmpty
              ? const Center(
                  child: Text(
                    "Henüz favori konum eklenmedi.",
                  ),
                )
              : ListView.builder(
                  itemCount: favorites.length,
                  itemBuilder: (context, index) {
                    final place = favorites[index];

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: ListTile(
                        leading: Text(
                          place.icon,
                          style: const TextStyle(fontSize: 28),
                        ),
                        title: Text(place.name),
                        subtitle: Text(
                          place.address,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == "git") {
                              Navigator.pop(context);

                              widget.onNavigate(
                                LatLng(
                                  place.latitude,
                                  place.longitude,
                                ),
                              );
                            }

                            if (value == "sil") {
                              remove(place);
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: "git",
                              child: Row(
                                children: [
                                  Icon(Icons.navigation),
                                  SizedBox(width: 8),
                                  Text("Navigasyona Git"),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: "sil",
                              child: Row(
                                children: [
                                  Icon(Icons.delete, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text("Sil"),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
