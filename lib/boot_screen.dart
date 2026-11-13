import 'dart:math' as math;

import 'package:flutter/material.dart';

const bootDuration = Duration(milliseconds: 4500);
const _neon = Color(0xff72ff48);

class BootScreen extends StatelessWidget {
  const BootScreen({super.key, required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: bootDuration,
        builder: (context, time, _) {
          final reveal =
              Curves.easeOutCubic.transform(((time - .13) * 3).clamp(0, 1));
          const commands = [
            '> SELECT * FROM SYSTEM_METRICS',
            '> STREAM :: CPU / RAM / DISK',
            '> SESSION :: BASEL_GHANEM',
            '> DASHBOARD :: READY',
          ];
          return Opacity(
            opacity: ((1 - time) * 16).clamp(0, 1),
            child: ColoredBox(
              color: const Color(0xff020b06),
              child: Stack(fit: StackFit.expand, children: [
                CustomPaint(painter: _DataRain(time)),
                Center(
                    child: Opacity(
                  opacity: reveal,
                  child: Transform.translate(
                    offset: Offset(0, (1 - reveal) * 18),
                    child: Container(
                      width: 420,
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xf0041409),
                        border: Border.all(color: _neon.withValues(alpha: .55)),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                              color: _neon.withValues(alpha: .19),
                              blurRadius: 44)
                        ],
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.terminal_rounded,
                            color: _neon, size: 31),
                        const SizedBox(height: 10),
                        Text(name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xffdbffce),
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              shadows: [Shadow(color: _neon, blurRadius: 20)],
                            )),
                        const SizedBox(height: 15),
                        Directionality(
                            textDirection: TextDirection.ltr,
                            child: Text(
                              commands[math.min(3, (time * 4).floor())],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontFamily: 'Consolas',
                                  fontSize: 12,
                                  color: _neon),
                            )),
                        const SizedBox(height: 17),
                        Directionality(
                            textDirection: TextDirection.ltr,
                            child: LinearProgressIndicator(
                              value: time,
                              minHeight: 3,
                              color: _neon,
                              backgroundColor: const Color(0xff183521),
                            )),
                      ]),
                    ),
                  ),
                )),
              ]),
            ),
          );
        },
      );
}

class _DataRain extends CustomPainter {
  const _DataRain(this.time);

  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xff113223)
      ..strokeWidth = 1;
    final beam = Paint()..color = _neon.withValues(alpha: .23);
    final glyphs = List.generate(
        10,
        (digit) => TextPainter(
              text: TextSpan(
                  text: '$digit',
                  style: const TextStyle(
                    color: _neon,
                    fontFamily: 'Consolas',
                    fontSize: 13,
                  )),
              textDirection: TextDirection.ltr,
            )..layout());
    for (var row = 0.0; row < size.height; row += 22) {
      canvas.drawLine(Offset(0, row), Offset(size.width, row), grid);
    }
    for (var column = 0; column * 22 < size.width; column++) {
      final x = column * 22.0;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
      final cycle = size.height + 210;
      final head =
          ((column * 137 + time * (510 + column % 5 * 86)) % cycle) - 30;
      for (var trail = 8; trail >= 0; trail--) {
        final y = head - trail * 20;
        if (y < -16 || y > size.height) continue;
        final digit = (column * 7 + trail * 3 + (time * 53).floor()) % 10;
        final bounds = Rect.fromLTWH(x + 4, y, 14, 18);
        canvas.saveLayer(
            bounds,
            Paint()
              ..color = Colors.white.withValues(alpha: .82 - trail * .085));
        glyphs[digit].paint(canvas, bounds.topLeft);
        canvas.restore();
      }
    }
    final scan = time * size.height;
    canvas.drawRect(Rect.fromLTWH(0, scan, size.width, 2), beam);
    for (final glyph in glyphs) {
      glyph.dispose();
    }
  }

  @override
  bool shouldRepaint(_DataRain oldDelegate) => oldDelegate.time != time;
}
