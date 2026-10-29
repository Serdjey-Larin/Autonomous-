/// Фирменный стиль Larin Cold Start: цвета и шрифт логотипа, «наклейки»
/// с белой обводкой, скошенные кнопки, кольцо таймера и снежинки.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

const brandFont = 'Exo2';

class Brand {
  static const green = Color(0xFF1FA54A);
  static const greenShadow = Color(0xFF14803A);
  static const greenRing = Color(0xFFBFE8CB);
  static const gloss = Color(0xFF8FE6A6);
  static const blue = Color(0xFF0B57C4);
  static const blueRing = Color(0xFF9CC7F2);
  static const text = Color(0xFF08306E);
  static const muted = Color(0xFF4E6A8E);
  static const canvas = Color(0xFFF3F9FF);
  static const track = Color(0xFFE2F1FF);
  static const line = Color(0xFFD4E8FA);
  static const lineSoft = Color(0xFFCFE3F7);
  static const red = Color(0xFFC8323C);
  static const redShadow = Color(0xFF8F1F27);
  static const redRing = Color(0xFFF2C9CC);
  static const orange = Color(0xFFB5531C);
  static const orangeText = Color(0xFF8A4B1D);
  static const orangeBg = Color(0xFFFFF7F1);
  static const orangeRing = Color(0xFFF6D2B8);
  static const snowBlue = Color(0xFF7FC3FF);
  static const snowLight = Color(0xFFA9D8FF);
}

/// Курсив логотипа: 800/900 italic.
TextStyle brandItalic(double size, {Color color = Brand.text, FontWeight weight = FontWeight.w900,
        double? letterSpacing, double? height}) =>
    TextStyle(fontFamily: brandFont, fontSize: size, fontWeight: weight, fontStyle: FontStyle.italic,
        color: color, letterSpacing: letterSpacing, height: height);

TextStyle brandText(double size, {Color color = Brand.text, FontWeight weight = FontWeight.w700, double? height}) =>
    TextStyle(fontFamily: brandFont, fontSize: size, fontWeight: weight, color: color, height: height);

const _skew = -0.1745; // −10°, как у кнопок на логотипе

// ---------------------------------------------------------------------------
// Снежинка с логотипа: шесть острых лучей с изогнутыми усиками.

Path _arm() => Path()
  ..moveTo(-1.3, -1.6)
  ..lineTo(-0.9, -5)
  ..cubicTo(-2.2, -5.6, -3.4, -6.8, -4.3, -8.8)
  ..cubicTo(-2.9, -8, -1.8, -7.4, -0.7, -7.2)
  ..lineTo(0, -11.5)
  ..lineTo(0.7, -7.2)
  ..cubicTo(1.8, -7.4, 2.9, -8, 4.3, -8.8)
  ..cubicTo(3.4, -6.8, 2.2, -5.6, 0.9, -5)
  ..lineTo(1.3, -1.6)
  ..close();

/// Контур снежинки радиусом 11.5 вокруг (0,0).
final Path logoSnowflake = () {
  final arm = _arm();
  final p = Path();
  for (var i = 0; i < 6; i++) {
    p.addPath(arm, Offset.zero, matrix4: Matrix4.rotationZ(i * math.pi / 3).storage);
  }
  p.addOval(Rect.fromCircle(center: Offset.zero, radius: 2.4));
  return p;
}();

void paintLogoSnowflake(Canvas canvas, Offset center, double radius, Color color, {double angle = 0, Color? outline}) {
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(angle);
  canvas.scale(radius / 11.5);
  canvas.drawPath(logoSnowflake, Paint()..color = color);
  if (outline != null) {
    canvas.drawPath(logoSnowflake, Paint()
      ..color = outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..strokeJoin = StrokeJoin.round);
  }
  canvas.restore();
}

void _paintSimpleFlake(Canvas canvas, Offset c, double r, Color color, double width, double angle) {
  final p = Paint()
    ..color = color
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round;
  for (var i = 0; i < 3; i++) {
    final a = angle + i * math.pi / 3 + math.pi / 2;
    final d = Offset(math.cos(a), math.sin(a)) * r;
    canvas.drawLine(c - d, c + d, p);
  }
}

class LogoSnowflake extends StatelessWidget {
  const LogoSnowflake({super.key, this.size = 18, this.color = Brand.green});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _FlakePainter(color, 0));
}

class _FlakePainter extends CustomPainter {
  _FlakePainter(this.color, this.angle);
  final Color color;
  final double angle;
  @override
  void paint(Canvas canvas, Size size) =>
      paintLogoSnowflake(canvas, size.center(Offset.zero), size.shortestSide / 2, color, angle: angle);
  @override
  bool shouldRepaint(_FlakePainter old) => old.color != color || old.angle != angle;
}

/// Снежинка, которая медленно вращается, пока ждём ответ модуля.
/// При системном отключении анимаций стоит на месте.
class SnowSpinner extends StatefulWidget {
  const SnowSpinner({super.key, this.size = 16, this.color = Brand.blue});
  final double size;
  final Color color;
  @override
  State<SnowSpinner> createState() => _SnowSpinnerState();
}

class _SnowSpinnerState extends State<SnowSpinner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
            size: Size.square(widget.size), painter: _FlakePainter(widget.color, _c.value * math.pi / 3 * 2)),
      );
}

// ---------------------------------------------------------------------------
// Зимний снег (1 декабря – 30 января). Рисуется одним CustomPainter позади
// содержимого; когда приложение свёрнуто, кадры не рисуются.

class _Flake {
  const _Flake(this.x, this.size, this.speed, this.phase, this.sway, this.logo, this.color);
  final double x, size, speed, phase, sway;
  final bool logo;
  final Color color;
}

class Snowfall extends StatefulWidget {
  const Snowfall({super.key});
  @override
  State<Snowfall> createState() => _SnowfallState();
}

class _SnowfallState extends State<Snowfall> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(minutes: 10));
  static final List<_Flake> _flakes = () {
    final r = math.Random(29);
    return List.generate(16, (i) {
      final logo = i % 5 == 2;
      return _Flake(
        (i + r.nextDouble() * .8) / 16, // равномерно по ширине
        logo ? 9 + r.nextDouble() * 3 : 3.5 + r.nextDouble() * 4,
        42 + r.nextDouble() * 40, // пикселей в секунду
        r.nextDouble() * 1000,
        8 + r.nextDouble() * 14,
        logo,
        i.isEven ? Brand.snowBlue : Brand.snowLight,
      );
    });
  }();

  @override
  void initState() { super.initState(); _c.repeat(); }
  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(child: CustomPaint(painter: _SnowPainter(_c, _flakes), size: Size.infinite)),
      );
}

class _SnowPainter extends CustomPainter {
  _SnowPainter(this.c, this.flakes) : super(repaint: c);
  final AnimationController c;
  final List<_Flake> flakes;
  @override
  void paint(Canvas canvas, Size size) {
    final t = c.value * 600; // секунды
    for (final f in flakes) {
      final span = size.height + 40;
      final y = (f.phase + t * f.speed) % span - 20;
      final x = f.x * size.width + math.sin(t / 2.2 + f.phase) * f.sway;
      final angle = (t * .35 + f.phase) % (math.pi * 2);
      if (f.logo) {
        paintLogoSnowflake(canvas, Offset(x, y), f.size, Brand.green.withValues(alpha: .45), angle: angle);
      } else {
        _paintSimpleFlake(canvas, Offset(x, y), f.size, f.color, f.size > 6 ? 1.6 : 1.9, angle);
      }
    }
  }

  @override
  bool shouldRepaint(_SnowPainter old) => false;
}

/// Светлые косые «штрихи скорости», как на логотипе.
class SpeedStreaks extends StatelessWidget {
  const SpeedStreaks({super.key});
  @override
  Widget build(BuildContext context) => const IgnorePointer(child: CustomPaint(painter: _StreaksPainter(), size: Size.infinite));
}

class _StreaksPainter extends CustomPainter {
  const _StreaksPainter();
  @override
  void paint(Canvas canvas, Size size) {
    void streak(double x, double y, double w, double h, Color c) {
      canvas.save();
      canvas.translate(x, y);
      canvas.transform(Matrix4.skewX(-0.61).storage); // −35°
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), Radius.circular(h / 2)), Paint()..color = c);
      canvas.restore();
    }
    streak(-40, 34, 260, 7, const Color(0xFFCFEAFF));
    streak(10, 52, 180, 5, const Color(0xFFDDF1FF));
    streak(size.width * .38, 104, 280, 6, const Color(0xFFD6EEFF));
  }

  @override
  bool shouldRepaint(_StreaksPainter old) => false;
}

// ---------------------------------------------------------------------------
// Карточки и кнопки.

/// Белая «наклейка»: белая обводка 3 и тонкое голубое кольцо снаружи.
class StickerCard extends StatelessWidget {
  const StickerCard({super.key, required this.child, this.padding = const EdgeInsets.all(16),
      this.radius = 24, this.ring = Brand.line, this.color = Colors.white, this.shadow = false});
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color ring;
  final Color color;
  final bool shadow;
  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(color: ring, spreadRadius: 2),
            if (shadow) const BoxShadow(color: Color(0x1A0B57C4), blurRadius: 24, offset: Offset(0, 10)),
          ],
        ),
        child: child,
      );
}

/// Скошенная кнопка ЗАПУСК / СТОП с «твёрдой» тенью снизу.
class SkewButton extends StatefulWidget {
  const SkewButton({super.key, required this.label, required this.color, required this.shadow,
      required this.ring, required this.onPressed, this.icon, this.height = 60, this.fontSize = 19});
  final String label;
  final Color color, shadow, ring;
  final VoidCallback onPressed;
  final Widget? icon;
  final double height, fontSize;
  @override
  State<SkewButton> createState() => _SkewButtonState();
}

class _SkewButtonState extends State<SkewButton> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final drop = _down ? 1.0 : 4.0;
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onPressed,
        child: Padding(
          padding: EdgeInsets.only(top: 4 - drop, bottom: drop),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.skewX(_skew),
            child: Container(
              height: widget.height,
              decoration: BoxDecoration(
                color: widget.color,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(color: widget.shadow, offset: Offset(0, drop)),
                  BoxShadow(color: widget.ring, spreadRadius: 2, offset: Offset(0, drop)),
                ],
              ),
              alignment: Alignment.center,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.skewX(-_skew),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (widget.icon != null) ...[widget.icon!, const SizedBox(width: 8)],
                  Text(widget.label, style: brandItalic(widget.fontSize, color: Colors.white, letterSpacing: .5)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Скошенная «фишка» выбора времени.
class SkewChip extends StatelessWidget {
  const SkewChip({super.key, required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          onTap: onTap,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.skewX(_skew),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? Brand.blue : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: selected ? Colors.white : Brand.line, width: 2),
                boxShadow: selected ? const [BoxShadow(color: Brand.blueRing, spreadRadius: 2)] : null,
              ),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.skewX(-_skew),
                child: Text(label,
                    style: selected
                        ? brandItalic(14, color: Colors.white)
                        : brandText(14, color: Brand.text)),
              ),
            ),
          ),
        ),
      );
}

/// Значок START рядом с логотипом.
class StartBadge extends StatelessWidget {
  const StartBadge({super.key});
  @override
  Widget build(BuildContext context) => Transform(
        transform: Matrix4.skewX(-0.21),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          decoration: BoxDecoration(
            color: Brand.green,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Brand.greenShadow, offset: Offset(0, 3))],
          ),
          child: Transform(
            transform: Matrix4.skewX(0.21),
            child: Text('START', style: brandItalic(22, color: Colors.white, letterSpacing: 1)),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Кольцо таймера.

class RingPainter extends CustomPainter {
  RingPainter({required this.fraction, required this.color});
  /// Доля оставшегося времени 0..1.
  final double fraction;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final k = size.shortestSide / 256;
    final c = size.center(Offset.zero);
    final r = 110 * k;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(c, r, Paint()
      ..color = Brand.track
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20 * k);
    if (fraction <= 0) return;
    final sweep = 2 * math.pi * fraction.clamp(0.0, 1.0);
    Paint arc(Color color, double w) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -math.pi / 2, sweep, false, arc(Colors.white, 24 * k));
    canvas.drawArc(rect, -math.pi / 2, sweep, false, arc(color, 18 * k));
    if (sweep > .2) {
      final gloss = color == Brand.green ? Brand.gloss : const Color(0xFF8FBCF2);
      canvas.drawArc(Rect.fromCircle(center: c, radius: 114 * k), -math.pi / 2 + .04, sweep - .08, false,
          arc(gloss, 3 * k));
    }
  }

  @override
  bool shouldRepaint(RingPainter old) => old.fraction != fraction || old.color != color;
}

/// Значок питания (белый) для кнопки ЗАПУСК и нижнего меню.
class PowerGlyph extends StatelessWidget {
  const PowerGlyph({super.key, this.size = 22, this.color = Colors.white, this.width = 2.8});
  final double size;
  final Color color;
  final double width;
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _PowerPainter(color, width));
}

class _PowerPainter extends CustomPainter {
  _PowerPainter(this.color, this.width);
  final Color color;
  final double width;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    // Как в макете: дуга M7 6.5 a8 8 0 1 0 10 0 и вертикаль 2.5–10.5.
    canvas.drawArc(Rect.fromCircle(center: const Offset(12, 13), radius: 8), -0.92, 4.98, false, p);
    canvas.drawLine(const Offset(12, 2.5), const Offset(12, 10.5), p);
  }

  @override
  bool shouldRepaint(_PowerPainter old) => old.color != color;
}
