import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';

/// Marca del negocio como en el talonario: "BM." grande con serifa y
/// "CONSTRUCCIONES" al lado.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 56, this.color = AppColors.ink, this.showTagline = false, this.taglineColor, this.showRest = true});

  final double size;

  /// false: solo "BM." (sin "CONSTRUCCIONES"), como en el login.
  final bool showRest;
  final Color color;
  final bool showTagline;
  final Color? taglineColor;

  @override
  Widget build(BuildContext context) {
    final s = context.select<SettingsProvider, (String, String, String)>((p) {
      final (a, b) = p.settings.brandParts;
      return (a, b, p.settings.tagline);
    });
    final (initials, rest, tagline) = s;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTagline)
          Padding(
            padding: EdgeInsets.only(bottom: size * 0.06),
            child: Text(
              tagline.toUpperCase(),
              style: TextStyle(
                fontFamily: 'Barlow',
                fontWeight: FontWeight.w800,
                fontSize: size * 0.24,
                letterSpacing: size * 0.02,
                color: taglineColor ?? color,
              ),
            ),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(initials, style: TextStyle(fontFamily: 'DMSerif', fontSize: size, height: 1, color: color)),
            if (showRest && rest.isNotEmpty) ...[
              SizedBox(width: size * 0.16),
              Flexible(
                child: Text(
                  rest.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'DMSerif', fontSize: size * 0.36, height: 1, letterSpacing: size * 0.01, color: color),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Franja diagonal amarilla y negra (cinta de obra).
class HazardStripes extends StatelessWidget {
  const HazardStripes({super.key, this.height = 10});
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: _StripesPainter()));
}

class _StripesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AppColors.yellow);
    final dark = Paint()..color = AppColors.ink;
    final w = size.height * 1.4;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (double x = -size.height; x < size.width + size.height; x += w * 2) {
      final path = Path()
        ..moveTo(x, size.height)
        ..lineTo(x + w, size.height)
        ..lineTo(x + w + size.height, 0)
        ..lineTo(x + size.height, 0)
        ..close();
      canvas.drawPath(path, dark);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
