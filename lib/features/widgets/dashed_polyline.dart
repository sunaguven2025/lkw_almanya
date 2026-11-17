import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../services/route_service.dart';

/// Kapalı yol / yol çalışması bölümlerini KESİK ÇİZGİ olarak çizer.
/// flutter_map sürümünden bağımsızdır (çizgiyi kendisi parçalara böler).
/// Konum: lib/features/widgets/dashed_polyline.dart

// ============================================================
// KAPALI YOL RENK VE KALINLIK SABİTLERİ
// ============================================================

const Color kClosedRoadColor =
    Color(0xFFF57C00); // Turuncu (Material Orange 700)
const double kClosedRoadStrokeWidth = 4.5;
const double kClosedRoadBorderWidth = 0.0;

const double _dashMeters = 12.0;
const double _gapMeters = 8.0;

// ============================================================
// TREN YOLU DESENİ (Google Maps tarzı) İÇİN EK SABİTLER
// ============================================================
// Alt katman: turuncu sürekli çizgi (gövde)
// Üst katman: beyaz kesikli çizgi (travers)

const Color kClosedRoadDashedColor = Color(0xFFFFFFFF); // Beyaz
const double kClosedRoadBaseWidth = 5.0; // Alt katman kalınlığı
const double kClosedRoadDashWidth = 2.5; // Üst katman kalınlığı

// ============================================================
// ÖNBELLEK
// ============================================================

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
    if (section.points.length < 2) continue;

    // Katman 1: ALT — Turuncu, sürekli kalın çizgi (tren yolu gövdesi)
    result.add(
      Polyline(
        points: section.points,
        strokeWidth: kClosedRoadBaseWidth,
        color: kClosedRoadColor,
        borderStrokeWidth: 0.0,
      ),
    );

    // Katman 2: ÜST — Beyaz kesikli çizgi (tren yolu traversleri)
    result.addAll(
      dashedPolylines(
        section.points,
        color: kClosedRoadDashedColor,
        strokeWidth: kClosedRoadDashWidth,
        borderWidth: 0.0,
        dashMeters: 6.0,
        gapMeters: 6.0,
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
