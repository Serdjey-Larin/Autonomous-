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

/// Цвета, которые зависят от темы (светлая / тёмная). Читать через [Palette.of].
@immutable
class Palette extends ThemeExtension<Palette> {
  const Palette({
    required this.dark,
    required this.canvas, required this.card, required this.sticker, required this.ring, required this.cardRing,
    required this.text, required this.muted, required this.accent, required this.numbers,
    required this.track, required this.line, required this.lineSoft, required this.chipOn, required this.chipOnRing,
    required this.warmBg, required this.warmRing, required this.warmLabel, required this.warmValue,
    required this.streaks, required this.nav, required this.navBorder, required this.cardShadow,
    required this.greenRing, required this.redRing, required this.greenShadow, required this.redShadow,
    required this.onBg, required this.onText, required this.onRing,
    required this.waitBg, required this.waitText, required this.waitRing,
    required this.warnBg, required this.warnText, required this.warnRing, required this.warnDot,
    required this.offBg, required this.offText, required this.offRing, required this.offDot,
    required this.pillButton,
  });
  final bool dark;
  final Color canvas, card, sticker, ring, cardRing, text, muted, accent, numbers, track, line, lineSoft,
      chipOn, chipOnRing, warmBg, warmRing, warmLabel, warmValue, nav, navBorder, cardShadow,
      greenRing, redRing, greenShadow, redShadow,
      onBg, onText, onRing, waitBg, waitText, waitRing, warnBg, warnText, warnRing, warnDot,
      offBg, offText, offRing, offDot, pillButton;
  final List<Color> streaks;

  static const light = Palette(
    dark: false,
    canvas: Color(0xFFF3F9FF), card: Colors.white, sticker: Colors.white, ring: Color(0xFFD4E8FA),
    cardRing: Color(0xFFCFE7FB), text: Color(0xFF08306E), muted: Color(0xFF4E6A8E),
    accent: Color(0xFF0B57C4), numbers: Color(0xFF0B57C4), track: Color(0xFFE2F1FF),
    line: Color(0xFFD4E8FA), lineSoft: Color(0xFFCFE3F7), chipOn: Color(0xFF0B57C4), chipOnRing: Color(0xFF9CC7F2),
    warmBg: Color(0xFFFFF7F1), warmRing: Color(0xFFF6D2B8), warmLabel: Color(0xFF8A4B1D), warmValue: Color(0xFFB5531C),
    streaks: [Color(0xFFCFEAFF), Color(0xFFDDF1FF), Color(0xFFD6EEFF)],
    nav: Colors.white, navBorder: Color(0xFFE2F0FC), cardShadow: Color(0x1A0B57C4),
    greenRing: Color(0xFFBFE8CB), redRing: Color(0xFFF2C9CC),
    greenShadow: Color(0xFF14803A), redShadow: Color(0xFF8F1F27),
    onBg: Color(0xFFE5F7EA), onText: Color(0xFF11683A), onRing: Color(0xFFBFE8CB),
    waitBg: Color(0xFFE6F0FF), waitText: Color(0xFF0B57C4), waitRing: Color(0xFFC9DDF7),
    warnBg: Color(0xFFFFF4DD), warnText: Color(0xFF7A5000), warnRing: Color(0xFFF3DDA8), warnDot: Color(0xFFE0A100),
    offBg: Color(0xFFEEF3F9), offText: Color(0xFF4E6A8E), offRing: Color(0xFFD6E2EF), offDot: Color(0xFF9AAFC6),
    pillButton: Colors.white,
  );

  static const darkPalette = Palette(
    dark: true,
    canvas: Color(0xFF061A38), card: Color(0xFF0D2A55), sticker: Color(0xFF0D2A55), ring: Color(0xFF1D4C8A),
    cardRing: Color(0xFF1D4C8A), text: Color(0xFFEAF5FF), muted: Color(0xFFA9C3E3),
    accent: Color(0xFF8FD0FF), numbers: Colors.white, track: Color(0xFF173F75),
    line: Color(0xFF1D4C8A), lineSoft: Color(0xFF1D4C8A), chipOn: Color(0xFF1F7BE0), chipOnRing: Color(0xFF1D4C8A),
    warmBg: Color(0xFF2A1E1A), warmRing: Color(0xFF7A4A26), warmLabel: Color(0xFFF3C6A2), warmValue: Color(0xFFFFB27A),
    streaks: [Color(0xFF12396B), Color(0xFF0F3060), Color(0xFF10335F)],
    nav: Color(0xFF081F42), navBorder: Color(0xFF12396B), cardShadow: Color(0x59000000),
    greenRing: Color(0x00000000), redRing: Color(0x00000000),
    greenShadow: Color(0xFF0E6B30), redShadow: Color(0xFF7A1A22),
    onBg: Color(0xFF0F3B33), onText: Color(0xFFA8F0C4), onRing: Color(0xFF1F6A4A),
    waitBg: Color(0xFF10305E), waitText: Color(0xFF8FD0FF), waitRing: Color(0xFF1D4C8A),
    warnBg: Color(0xFF33290E), warnText: Color(0xFFFFD27A), warnRing: Color(0xFF6B5520), warnDot: Color(0xFFFFC23D),
    offBg: Color(0xFF12294A), offText: Color(0xFFA9C3E3), offRing: Color(0xFF24497A), offDot: Color(0xFF7D97B8),
    pillButton: Color(0x1FFFFFFF),
  );

  static Palette of(BuildContext context) => Theme.of(context).extension<Palette>() ?? light;

  @override
  Palette copyWith() => this;
  @override
  Palette lerp(Palette? other, double t) => t < .5 || other == null ? this : other;
}

/// Курсив логотипа: 800/900 italic. Без цвета — берётся цвет текста темы.
TextStyle brandItalic(double size, {Color? color, FontWeight weight = FontWeight.w900,
        double? letterSpacing, double? height}) =>
    TextStyle(fontFamily: brandFont, fontSize: size, fontWeight: weight, fontStyle: FontStyle.italic,
        color: color, letterSpacing: letterSpacing, height: height);

TextStyle brandText(double size, {Color? color, FontWeight weight = FontWeight.w700, double? height}) =>
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
// Зимний снег (1 декабря – 31 января). Рисуется одним CustomPainter позади
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
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(painter: _StreaksPainter(Palette.of(context).streaks), size: Size.infinite));
}

class _StreaksPainter extends CustomPainter {
  const _StreaksPainter(this.colors);
  final List<Color> colors;
  @override
  void paint(Canvas canvas, Size size) {
    void streak(double x, double y, double w, double h, Color c) {
      canvas.save();
      canvas.translate(x, y);
      canvas.transform(Matrix4.skewX(-0.61).storage); // −35°
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), Radius.circular(h / 2)), Paint()..color = c);
      canvas.restore();
    }
    streak(-40, 34, 260, 7, colors[0]);
    streak(10, 52, 180, 5, colors[1]);
    streak(size.width * .38, 104, 280, 6, colors[2]);
  }

  @override
  bool shouldRepaint(_StreaksPainter old) => old.colors != colors;
}

// ---------------------------------------------------------------------------
// Карточки и кнопки.

/// Белая «наклейка»: белая обводка 3 и тонкое голубое кольцо снаружи.
class StickerCard extends StatelessWidget {
  const StickerCard({super.key, required this.child, this.padding = const EdgeInsets.all(16),
      this.radius = 24, this.ring, this.color, this.shadow = false});
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? ring;
  final Color? color;
  final bool shadow;
  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? p.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: p.sticker, width: 3),
        boxShadow: [
          BoxShadow(color: ring ?? p.ring, spreadRadius: 2),
          if (shadow) BoxShadow(color: p.cardShadow, blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: child,
    );
  }
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
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
        button: true,
        selected: selected,
        child: GestureDetector(
          onTap: onTap,
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.skewX(_skew),
            // Без alignment и фиксированной высоты: внутри Wrap фишка по ширине текста,
            // иначе Container растягивается на всю строку.
            child: Container(
              constraints: const BoxConstraints(minWidth: 44),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? p.chipOn : (p.dark ? Colors.transparent : Colors.white),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: selected ? Colors.white : p.line, width: 2),
                boxShadow: selected ? [BoxShadow(color: p.chipOnRing, spreadRadius: 2)] : null,
              ),
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.skewX(-_skew),
                child: Text(label, textAlign: TextAlign.center,
                    style: selected
                        ? brandItalic(14, color: Colors.white)
                        : brandText(14, color: p.text)),
              ),
            ),
          ),
        ),
      );
  }
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
            boxShadow: [BoxShadow(color: Palette.of(context).greenShadow, offset: const Offset(0, 3))],
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
  RingPainter({required this.fraction, required this.color, this.track = const Color(0xFFE2F1FF), this.glow = false});
  final Color track;
  /// Тёмная тема: мягкое свечение под дугой.
  final bool glow;
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
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20 * k);
    if (fraction <= 0) return;
    final sweep = 2 * math.pi * fraction.clamp(0.0, 1.0);
    Paint arc(Color color, double w) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    if (glow) {
      canvas.drawArc(rect, -math.pi / 2, sweep, false, arc(color.withValues(alpha: .45), 22 * k)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
    }
    canvas.drawArc(rect, -math.pi / 2, sweep, false, arc(Colors.white, 24 * k));
    canvas.drawArc(rect, -math.pi / 2, sweep, false, arc(color, 18 * k));
    if (sweep > .2) {
      final gloss = color == Brand.green ? Brand.gloss : const Color(0xFF8FBCF2);
      canvas.drawArc(Rect.fromCircle(center: c, radius: 114 * k), -math.pi / 2 + .04, sweep - .08, false,
          arc(gloss, 3 * k));
    }
  }

  @override
  bool shouldRepaint(RingPainter old) =>
      old.fraction != fraction || old.color != color || old.track != track || old.glow != glow;
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
