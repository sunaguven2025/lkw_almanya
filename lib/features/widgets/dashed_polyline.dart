import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../services/route_service.dart';

/// Kapalı yol / yol çalışması bölümlerini KESİK ÇİZGİ olarak çizer.
/// flutter_map sürümünden bağımsızdır (çizgiyi kendisi parçalara böler).
/// Konum: lib/features/widgets/dashed_polyline.dart

const Color kClosedRoadColor = Color(0xFFE53935);
const double kClosedRoadStrokeWidth = 12.0;
const double kClosedRoadBorderWidth = 2.5;

const double _dashMeters = 14.0;
const double _gapMeters = 10.0;

List<ClosedRoadSection>? _cachedSource;
List<Polyline> _cachedDashes = <Polyline>[];

/// Her yeniden çizimde yeniden hesaplamamak için liste kimliğine göre önbellek.
/// (_closedRoadSections her değiştiğinde yeni liste atanıyor.)
List<Polyline> closedRoadDashes(List<ClosedRoadSection> sections) {
  if (identical(_cachedSource, sections)) {
    return _cachedDashes;
  }

  final List<Polyline> result = <Polyline>[];

  for (final ClosedRoadSection section in sections) {
    result.addAll(
      dashedPolylines(
        section.points,
        color: kClosedRoadColor,
        strokeWidth: kClosedRoadStrokeWidth,
        borderWidth: kClosedRoadBorderWidth,
      ),
    );
  }

  _cachedSource = sections;
  _cachedDashes = result;

  return result;
}

/// [points] çizgisini [dashMeters] çizgi / [gapMeters] boşluk olarak böler.
/// İki aynı noktadan oluşan "nokta olay" tek bir nokta (yuvarlak) çıkar.
List<Polyline> dashedPolylines(
  List<LatLng> points, {
  required Color color,
  required double strokeWidth,
  double borderWidth = 0.0,
  double dashMeters = _dashMeters,
  double gapMeters = _gapMeters,
}) {
  final List<Polyline> result = <Polyline>[];

  if (points.length < 2) {
    return result;
  }

  Polyline make(List<LatLng> pts) {
    return Polyline(
      points: pts,
      strokeWidth: strokeWidth,
      color: color,
      borderStrokeWidth: borderWidth,
      borderColor: Colors.white,
    );
  }

  List<LatLng> current = <LatLng>[points.first];
  bool drawing = true;
  double remaining = dashMeters;

  for (int i = 0; i < points.length - 1; i++) {
    LatLng a = points[i];
    final LatLng b = points[i + 1];

    double segLen = Geolocator.distanceBetween(
      a.latitude,
      a.longitude,
      b.latitude,
      b.longitude,
    );

    while (segLen > remaining) {
      final double t = remaining / segLen;

      final LatLng cut = LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );

      if (drawing) {
        current.add(cut);
        result.add(make(current));
        current = <LatLng>[];
      } else {
        current = <LatLng>[cut];
      }

      drawing = !drawing;
      remaining = drawing ? dashMeters : gapMeters;

      a = cut;

      segLen = Geolocator.distanceBetween(
        a.latitude,
        a.longitude,
        b.latitude,
        b.longitude,
      );
    }

    remaining -= segLen;

    if (drawing) {
      current.add(b);
    }
  }

  if (drawing && current.length >= 2) {
    result.add(make(current));
  }

  return result;
}
