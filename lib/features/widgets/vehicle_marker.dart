import 'package:flutter/material.dart';

/// Haritada kullanıcı konumu için kuş bakışı araç simgesi.
/// Araç YUKARI bakar; yönü Marker/Transform.rotate belirler.
///
/// Konum: lib/features/widgets/vehicle_marker.dart
class VehicleMarker extends StatelessWidget {
  final bool isTruck;

  /// Simgenin genişliği (mantıksal piksel). Kamyonda boy = genişlik * ~2,1.
  final double width;

  const VehicleMarker({
    super.key,
    this.isTruck = true,
    this.width = 20,
  });

  @override
  Widget build(BuildContext context) {
    final double height = isTruck ? width * 2.1 : width * 1.75;

    return Center(
      child: CustomPaint(
        size: Size(width, height),
        painter: _VehiclePainter(isTruck: isTruck),
      ),
    );
  }
}

class _VehiclePainter extends CustomPainter {
  final bool isTruck;

  _VehiclePainter({required this.isTruck});

  static const Color _carColor = Color(0xFF1565C0);
  static const Color _cabColor = Color(0xFFEF6C00);
  static const Color _trailerColor = Color(0xFFECEFF1);
  static const Color _glassColor = Color(0xFF263238);

  final Paint _shadow = Paint()
    ..color = const Color(0x66000000)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

  final Paint _outline = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.8
    ..color = Colors.white;

  final Paint _glass = Paint()..color = _glassColor;

  void _drawBody(Canvas canvas, RRect rrect, Color fill) {
    canvas.drawRRect(rrect.shift(const Offset(0, 1.5)), _shadow);
    canvas.drawRRect(rrect, Paint()..color = fill);
    canvas.drawRRect(rrect, _outline);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    if (isTruck) {
      final double cabH = h * 0.30;
      final double gap = h * 0.04;

      // Dorse
      final RRect trailer = RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.04, cabH + gap, w * 0.92, h - cabH - gap),
        const Radius.circular(3),
      );
      _drawBody(canvas, trailer, _trailerColor);

      // Çekici (kabin)
      final RRect cab = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, w, cabH),
        Radius.circular(w * 0.28),
      );
      _drawBody(canvas, cab, _cabColor);

      // Ön cam
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.14, cabH * 0.26, w * 0.72, cabH * 0.34),
          const Radius.circular(2.5),
        ),
        _glass,
      );
      return;
    }

    // Otomobil
    final RRect body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      Radius.circular(w * 0.42),
    );
    _drawBody(canvas, body, _carColor);

    // Ön cam
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.14, h * 0.22, w * 0.72, h * 0.20),
        const Radius.circular(3),
      ),
      _glass,
    );

    // Arka cam
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.18, h * 0.68, w * 0.64, h * 0.12),
        const Radius.circular(2),
      ),
      _glass,
    );
  }

  @override
  bool shouldRepaint(covariant _VehiclePainter oldDelegate) {
    return oldDelegate.isTruck != isTruck;
  }
}
