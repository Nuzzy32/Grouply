// Gupy, the Grouply mascot, animated live from its layers so motion runs at
// the display refresh rate (docs/DESIGN-onboarding-mascot.md §10).
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'gl.dart';

const _dir = 'assets/mascot';

/// iOS Reduce Motion arrives as `reduceMotion`, Android "Remove animations"
/// as `disableAnimations`; honour both.
bool reduceMotionOf(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context) ||
    View.of(context).platformDispatcher.accessibilityFeatures.reduceMotion;

// Layer boxes on the 2048 px source canvas (rig/*.webp are these crops at 50%).
const _layers = <String, Rect>{
  'ekor_pangkal': Rect.fromLTWH(1150, 1400, 320, 250),
  'ekor_tengah': Rect.fromLTWH(1310, 1298, 380, 332),
  'ekor_ujung': Rect.fromLTWH(1498, 1138, 242, 338),
  'badan': Rect.fromLTWH(516, 858, 938, 1016),
  'lengan_atas_kanan': Rect.fromLTWH(628, 968, 274, 280),
  'lengan_bawah_kanan': Rect.fromLTWH(456, 1106, 316, 346),
  'lengan_atas_kiri': Rect.fromLTWH(1106, 974, 268, 288),
  'lengan_bawah_kiri': Rect.fromLTWH(1234, 1130, 274, 318),
  'kepala': Rect.fromLTWH(482, 192, 1030, 792),
  'mata_ramah': Rect.fromLTWH(518, 296, 942, 480),
  'mata_setengah': Rect.fromLTWH(518, 296, 942, 480),
  'mata_tutup': Rect.fromLTWH(518, 296, 942, 480),
  'mulut_senyum': Rect.fromLTWH(834, 648, 572, 238),
  'mulut_setengah_tertawa': Rect.fromLTWH(854, 668, 506, 240),
  'mulut_tertawa': Rect.fromLTWH(766, 656, 580, 324),
  // Celebrate pose, same canvas, drawn in this order by GupyJump.
  'cel_ekor': Rect.fromLTWH(890, 1034, 916, 482),
  'cel_badan': Rect.fromLTWH(580, 906, 518, 734),
  'cel_kaki_kanan': Rect.fromLTWH(304, 1166, 470, 488),
  'cel_kaki_kiri': Rect.fromLTWH(840, 1414, 528, 458),
  'cel_tangan_kiri': Rect.fromLTWH(858, 866, 732, 314),
  'cel_kepala': Rect.fromLTWH(558, 294, 860, 724),
  'cel_tangan_kanan': Rect.fromLTWH(346, 372, 468, 698),
  // Gupy holding an invitation envelope (GupyPose 'undangan').
  'undangan_badan': Rect.fromLTWH(484, 340, 954, 1534),
  'undangan_amplop': Rect.fromLTWH(822, 1000, 676, 332),
};
const _feet = Offset(985, 1874);
const _neck = Offset(970, 930);
const _shoulderR = Offset(842, 1028);
// Elbow centres; both arm segments end in a circle around them (_src/build.sh).
const _elbowR = Offset(697, 1172);
const _shoulderL = Offset(1160, 1030);
const _elbowL = Offset(1298, 1200);
// Tail joints: base (hidden behind the body), then mid and tip.
const _tailBase = Offset(1260, 1550);
const _tailMid = Offset(1392, 1513);
const _tailTip = Offset(1597, 1386);

/// Feet line on every mascot canvas (layers and poses share the framing).
const gupyFeet = 0.912;

const _waveSeconds = 1.68;
// Upper arm (deg, from the shoulder) and forearm bend (deg, at the elbow)
// through the wave: the elbow lifts out to the side (behind the head, never
// across the chin) while the forearm stands up and does the waving. Splines, so motion never stops on a key.
const _upperKeys = [
  (0.0, 0.0),
  (0.22, 18.0),
  (0.36, 34.0),
  (0.48, 29.0),
  (1.10, 31.0),
  (1.30, 26.0),
  (1.50, -3.0),
  (1.68, 0.0),
];
const _elbowKeys = [
  (0.0, 0.0),
  (0.22, 26.0),
  (0.36, 74.0),
  (0.50, 50.0),
  (0.66, 76.0),
  (0.82, 50.0),
  (0.98, 74.0),
  (1.14, 52.0),
  (1.30, 44.0),
  (1.50, -4.0),
  (1.68, 0.0),
];

double _smooth(double a, double b, double x) {
  final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Cubic Hermite through [keys] (Catmull-Rom tangents, flat at both ends).
double spline(List<(double, double)> keys, double t) {
  if (t <= keys.first.$1) return keys.first.$2;
  if (t >= keys.last.$1) return keys.last.$2;
  var i = 0;
  while (keys[i + 1].$1 < t) {
    i++;
  }
  final (t1, v1) = keys[i];
  final (t2, v2) = keys[i + 1];
  final h = t2 - t1;
  double slope(int j) {
    if (j == 0 || j == keys.length - 1) return 0;
    return (keys[j + 1].$2 - keys[j - 1].$2) /
        (keys[j + 1].$1 - keys[j - 1].$1);
  }

  final m1 = slope(i) * h;
  final m2 = slope(i + 1) * h;
  final u = (t - t1) / h;
  final u2 = u * u;
  final u3 = u2 * u;
  return (2 * u3 - 3 * u2 + 1) * v1 +
      (u3 - 2 * u2 + u) * m1 +
      (-2 * u3 + 3 * u2) * v2 +
      (u3 - u2) * m2;
}

Offset _rotate(Offset d, double deg) {
  final r = deg * math.pi / 180;
  final c = math.cos(r);
  final s = math.sin(r);
  return Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c);
}

/// One rig layer on a [size] canvas: [pivot] (source coords) moved to [at]
/// and rotated [deg] around it.
Widget _layer(
  double size,
  String name,
  Offset pivot,
  Offset at,
  double deg, {
  double scaleX = 1,
  double scaleY = 1,
}) {
  final k = size / 2048;
  final box = _layers[name]!;
  final shift = at - pivot;
  return Positioned(
    left: (box.left + shift.dx) * k,
    top: (box.top + shift.dy) * k,
    width: box.width * k,
    height: box.height * k,
    child: Transform(
      origin: (pivot - box.topLeft) * k,
      transform: Matrix4.identity()
        ..rotateZ(deg * math.pi / 180)
        ..scaleByDouble(scaleX, scaleY, 1, 1),
      child: Image.asset(
        '$_dir/rig/$name.webp',
        fit: BoxFit.fill,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        filterQuality: FilterQuality.medium,
      ),
    ),
  );
}

/// Floor shadow under the feet; [lift] 0..1 narrows it to 90%.
class GupyShadow extends StatelessWidget {
  const GupyShadow({super.key, required this.size, this.lift = 0});
  final double size;
  final double lift;
  @override
  Widget build(BuildContext context) {
    final w = size * 0.5;
    final h = size * 0.07;
    final color = Color(GLTheme.dark ? 0x40000000 : 0x14000000);
    return Positioned(
      left: (size - w) / 2,
      top: size * gupyFeet - h / 2,
      width: w,
      height: h,
      child: Transform.scale(
        scaleX: 1 - 0.1 * lift,
        scaleY: 1 - 0.05 * lift,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.all(Radius.elliptical(w / 2, h / 2)),
            color: color,
            boxShadow: [BoxShadow(color: color, blurRadius: h * 0.6)],
          ),
        ),
      ),
    );
  }
}

/// Precaches every rig layer so they never pop in one by one.
void precacheGupy(BuildContext context) {
  for (final name in _layers.keys) {
    precacheImage(
      AssetImage('$_dir/rig/$name.webp'),
      context,
      onError: (_, _) {},
    );
  }
}

/// The layered Gupy: breathing, sway, tail and arm follow-through and random
/// blinks while [idle]; [waveOnStart] waves once. Tapping waves again.
/// With `idle: false` the ticker stops whenever no wave or blink is playing,
/// so empty states stay still between moments.
class GupyRig extends StatefulWidget {
  const GupyRig({
    super.key,
    required this.size,
    this.idle = true,
    this.waveOnStart = false,
    this.shadow = true,
    this.onWaveEnd,
  });
  final double size;
  final bool idle;
  final bool waveOnStart;
  final bool shadow;
  final VoidCallback? onWaveEnd;
  @override
  State<GupyRig> createState() => GupyRigState();
}

class GupyRigState extends State<GupyRig> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _random = math.Random();
  double _t = 0; // seconds since the ticker (re)started
  double _base = 0; // carried over when the ticker restarts
  double? _waveAt;
  double _nextBlink = 1.4;
  double _blinkAt = -1;
  double _blinkEnd = -1;
  bool _secondBlink = false;
  bool _reduce = false;

  double get _now => _base + _t;

  @override
  void initState() {
    super.initState();
    if (widget.waveOnStart) _waveAt = 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = reduceMotionOf(context);
    precacheGupy(context);
    _sync();
  }

  @override
  void didUpdateWidget(GupyRig oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Waves once (ignored under reduced motion or while already waving).
  void wave() {
    if (_reduce || _waveAt != null) return;
    _waveAt = _now;
    _sync();
  }

  bool get _busy =>
      !_reduce && (widget.idle || _waveAt != null || _now < _blinkEnd);

  void _sync() {
    if (_busy && !_ticker.isActive) {
      _ticker.start();
    } else if (!_busy && _ticker.isActive) {
      _base = _now;
      _t = 0;
      _ticker.stop();
    }
  }

  void _tick(Duration elapsed) {
    _t = elapsed.inMicroseconds / 1e6;
    final now = _now;
    if (now >= _nextBlink && widget.idle) {
      _blinkAt = now;
      _blinkEnd = now + 0.15;
      if (!_secondBlink && _random.nextDouble() < 0.2) {
        _secondBlink = true;
        _nextBlink = now + 0.3;
      } else {
        _secondBlink = false;
        _nextBlink = now + 2.4 + _random.nextDouble() * 3.2;
      }
    }
    final wave = _waveAt;
    if (wave != null && now - wave >= _waveSeconds) {
      _waveAt = null;
      widget.onWaveEnd?.call();
    }
    setState(() {});
    if (!_busy) {
      _base = now;
      _t = 0;
      _ticker.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _reduce ? 0.0 : _now;
    final u = _waveAt == null ? -1.0 : t - _waveAt!;
    final waving = u >= 0;
    final w = waving
        ? _smooth(0, 0.3, u) * (1 - _smooth(1.2, _waveSeconds, u))
        : 0.0;
    // Idle amplitude: full while idle, otherwise only inside a wave.
    final a = _reduce ? 0.0 : (widget.idle ? 1.0 : w);

    final breathPhase = 2 * math.pi * t / 3.2;
    final breath = (1 - math.cos(breathPhase)) / 2 * a;
    final sway = 0.7 * math.sin(2 * math.pi * t / 5.3) * a;
    final body = sway - 1.2 * w;
    final sy = 1 + 0.016 * breath;
    final sx = 1 - 0.005 * breath;
    Offset attach(Offset p) {
      final d = p - _feet;
      return _feet + _rotate(Offset(d.dx * sx, d.dy * sy), body);
    }

    final lagged = math.sin(breathPhase - 0.7) * a;
    final head =
        body +
        1.1 * lagged +
        0.5 * math.sin(2 * math.pi * t / 5.3 - 0.9) * a -
        4.5 * w;
    final armSwing = 1.8 * math.sin(breathPhase - 0.5) * a;
    final upperR = body + armSwing + (waving ? spline(_upperKeys, u) : 0);
    // The forearm trails the upper arm a little (follow-through).
    final forearmR =
        upperR +
        2.2 * math.sin(breathPhase - 1.1) * a +
        (waving ? spline(_elbowKeys, u) : 0);
    final armL = body - armSwing - 3 * w;
    final forearmL = armL - 2.2 * math.sin(breathPhase - 1.1) * a - 4 * w;
    // Tail: a wave travelling base -> tip, each joint adding to the last.
    final tailPhase = 2 * math.pi * t / 2.7;
    final tailBase =
        body +
        (2.4 * math.sin(tailPhase) + 0.8 * math.sin(2 * tailPhase + 1.1)) * a;
    final tailMid = tailBase + 3.0 * math.sin(tailPhase - 0.8) * a;
    final tailTip = tailMid + 4.0 * math.sin(tailPhase - 1.6) * a;
    // Blink: half-closed, closed, half-closed (40 / 60 / 50 ms).
    final blinkPhase = t - _blinkAt;
    final eyes = _reduce || t >= _blinkEnd
        ? 'mata_ramah'
        : (blinkPhase >= 0.04 && blinkPhase < 0.10
              ? 'mata_tutup'
              : 'mata_setengah');
    // Smile -> half laugh -> laugh as the wave ramps in, and back out.
    final mouth = w > 0.6
        ? 'mulut_tertawa'
        : (w > 0.2 ? 'mulut_setengah_tertawa' : 'mulut_senyum');

    Widget layer(
      String name,
      Offset pivot,
      Offset at,
      double deg, {
      double scaleX = 1,
      double scaleY = 1,
    }) => _layer(
      widget.size,
      name,
      pivot,
      at,
      deg,
      scaleX: scaleX,
      scaleY: scaleY,
    );

    final neck = attach(_neck);
    final shoulder = attach(_shoulderR);
    final elbow = shoulder + _rotate(_elbowR - _shoulderR, upperR);
    final tailMidAt =
        attach(_tailBase) + _rotate(_tailMid - _tailBase, tailBase);
    final tailTipAt = tailMidAt + _rotate(_tailTip - _tailMid, tailMid);
    final shoulderL = attach(_shoulderL);
    final elbowL = shoulderL + _rotate(_elbowL - _shoulderL, armL);
    final rightArm = [
      layer('lengan_bawah_kanan', _elbowR, elbow, forearmR),
      layer('lengan_atas_kanan', _shoulderR, shoulder, upperR),
    ];
    return GestureDetector(
      onTap: wave,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: widget.size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (widget.shadow) GupyShadow(size: widget.size),
              layer('ekor_ujung', _tailTip, tailTipAt, tailTip),
              layer('ekor_tengah', _tailMid, tailMidAt, tailMid),
              layer('ekor_pangkal', _tailBase, attach(_tailBase), tailBase),
              layer('badan', _feet, _feet, body, scaleX: sx, scaleY: sy),
              ...rightArm,
              layer('lengan_bawah_kiri', _elbowL, elbowL, forearmL),
              layer('lengan_atas_kiri', _shoulderL, shoulderL, armL),
              layer('kepala', _neck, neck, head),
              layer(eyes, _neck, neck, head),
              layer(mouth, _neck, neck, head),
            ],
          ),
        ),
      ),
    );
  }
}

/// A pose that simply rests (e.g. `santai` sitting on an empty state): no
/// motion, so nothing ticks on screens people work in.
class GupyStill extends StatelessWidget {
  const GupyStill({super.key, required this.pose, required this.size});
  final String pose;
  final double size;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          GupyShadow(size: size),
          Image.asset(
            '$_dir/static/$pose.webp',
            width: size,
            height: size,
            excludeFromSemantics: true,
          ),
        ],
      ),
    ),
  );
}

/// A still pose (clipboard, phone, point, …) that floats ±6 pt and breathes
/// from its feet; still under reduced motion. `undangan` is layered: the
/// envelope bobs and tilts a little behind the float, as if offered.
class GupyPose extends StatefulWidget {
  const GupyPose({super.key, required this.pose, required this.size});
  final String pose;
  final double size;
  @override
  State<GupyPose> createState() => _GupyPoseState();
}

class _GupyPoseState extends State<GupyPose>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: Duration(seconds: 12),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotionOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static const _envelope = Offset(1160, 1166);

  Widget _invite(double t) => SizedBox.square(
    dimension: widget.size,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        _layer(widget.size, 'undangan_badan', Offset.zero, Offset.zero, 0),
        _layer(
          widget.size,
          'undangan_amplop',
          _envelope,
          _envelope + Offset(0, -12 * math.sin(2 * math.pi * t / 3 - 0.9)),
          2.5 * math.sin(2 * math.pi * t / 6 + 0.4),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final image = widget.pose == 'undangan'
        ? null
        : Image.asset(
            '$_dir/static/${widget.pose}.webp',
            width: widget.size,
            height: widget.size,
            excludeFromSemantics: true,
          );
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          final t = _c.value * 12; // 12 s holds whole cycles of 3, 4 and 6 s
          final f = math.sin(2 * math.pi * t / 3);
          final breath = (1 - math.cos(2 * math.pi * t / 4)) / 2;
          final sway = 0.6 * math.sin(2 * math.pi * t / 6);
          return SizedBox.square(
            dimension: widget.size,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                GupyShadow(size: widget.size, lift: (f + 1) / 2),
                Transform.translate(
                  offset: Offset(0, -6 * f),
                  child: Transform(
                    alignment: Alignment(0, gupyFeet * 2 - 1),
                    transform: Matrix4.identity()
                      ..rotateZ(sway * math.pi / 180)
                      ..scaleByDouble(
                        1 - 0.004 * breath,
                        1 + 0.012 * breath,
                        1,
                        1,
                      ),
                    child: child ?? _invite(t),
                  ),
                ),
              ],
            ),
          );
        },
        child: image,
      ),
    );
  }
}

/// The celebrate pose jumping once over [progress] (0..1 = 1.2 s): squash,
/// stretch, a parabolic hop with a little tilt, landing squash and a settle.
/// Arms, legs, tail and head are separate layers that swing with the hop and
/// overshoot after it (follow-through).
class GupyJump extends StatelessWidget {
  const GupyJump({super.key, required this.progress, required this.size});
  final Animation<double> progress;
  final double size;

  static const seconds = 1.2;
  static const _height = 120 / 1254; // of the canvas
  static const _sy = [
    (0.0, 1.0),
    (0.14, 0.90),
    (0.21, 1.08),
    (0.40, 1.0),
    (0.55, 1.03),
    (0.63, 1.02),
    (0.68, 0.91),
    (0.78, 1.04),
    (0.90, 0.985),
    (1.02, 1.005),
    (1.2, 1.0),
  ];
  static const _tilt = [
    (0.0, 0.0),
    (0.14, 1.5),
    (0.30, -3.0),
    (0.55, 2.0),
    (0.68, 0.0),
    (1.2, 0.0),
  ];
  // Limb angles (deg, clockwise) around their joints. Arms dip on the
  // crouch, fling up on take-off and bounce after landing; legs tuck only in
  // the air so the feet stay planted on the ground.
  static const _armR = [
    (0.0, 0.0),
    (0.14, -10.0),
    (0.30, 12.0),
    (0.46, 4.0),
    (0.60, 9.0),
    (0.72, -6.0),
    (0.88, 3.0),
    (1.04, -1.0),
    (1.2, 0.0),
  ];
  static const _armL = [
    (0.0, 0.0),
    (0.14, 10.0),
    (0.30, -14.0),
    (0.48, -5.0),
    (0.70, 9.0),
    (0.86, -3.0),
    (1.02, 1.0),
    (1.2, 0.0),
  ];
  static const _legR = [
    (0.0, 0.0),
    (0.17, 0.0),
    (0.40, 9.0),
    (0.62, 0.0),
    (1.2, 0.0),
  ];
  static const _legL = [
    (0.0, 0.0),
    (0.17, 0.0),
    (0.40, -8.0),
    (0.62, 0.0),
    (1.2, 0.0),
  ];
  static const _tail = [
    (0.0, 0.0),
    (0.14, -4.0),
    (0.30, 8.0),
    (0.50, -3.0),
    (0.68, -8.0),
    (0.84, 5.0),
    (1.0, -2.0),
    (1.2, 0.0),
  ];
  static const _head = [
    (0.0, 0.0),
    (0.14, -2.0),
    (0.30, 3.0),
    (0.50, -1.5),
    (0.70, 2.0),
    (0.88, -0.8),
    (1.2, 0.0),
  ];
  // Joints of the celebrate layers on the 2048 canvas.
  static const _neck = Offset(890, 975);
  static const _shoulderR = Offset(745, 1000);
  static const _shoulderL = Offset(945, 1075);
  static const _hipR = Offset(671, 1372);
  static const _hipL = Offset(969, 1523);
  static const _tailBase = Offset(984, 1378);

  /// Height above the floor (0..1 of the jump) at [t] seconds.
  static double lift(double t) {
    const start = 0.17;
    const end = 0.64;
    if (t <= start || t >= end) return 0;
    final u = (t - start) / (end - start);
    return 4 * u * (1 - u);
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: AnimatedBuilder(
      animation: progress,
      builder: (_, _) {
        final t = progress.value * seconds;
        final sy = spline(_sy, t);
        final up = lift(t);
        Widget part(String name, Offset joint, List<(double, double)> keys) =>
            _layer(size, 'cel_$name', joint, joint, spline(keys, t));
        return SizedBox.square(
          dimension: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              GupyShadow(size: size, lift: up),
              Transform.translate(
                offset: Offset(0, -up * _height * size),
                child: Transform(
                  alignment: Alignment(0, gupyFeet * 2 - 1),
                  transform: Matrix4.identity()
                    ..rotateZ(spline(_tilt, t) * math.pi / 180)
                    // volume-preserving: wider when squashed
                    ..scaleByDouble(1 - (sy - 1) * 0.6, sy, 1, 1),
                  child: SizedBox.square(
                    dimension: size,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        part('ekor', _tailBase, _tail),
                        _layer(size, 'cel_badan', _feet, _feet, 0),
                        part('kaki_kanan', _hipR, _legR),
                        part('kaki_kiri', _hipL, _legL),
                        part('tangan_kiri', _shoulderL, _armL),
                        part('kepala', _neck, _head),
                        part('tangan_kanan', _shoulderR, _armR),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Gupy peeking over the top edge of whatever sits below it (hands on the
/// edge). Rises into place once when it appears; still under reduced motion.
class GupyPeek extends StatefulWidget {
  const GupyPeek({super.key, required this.width});
  final double width;
  static const aspect = 605 / 384;
  @override
  State<GupyPeek> createState() => _GupyPeekState();
}

class _GupyPeekState extends State<GupyPeek>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 650),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotionOf(context)) {
      _c.value = 1;
    } else if (_c.isDismissed) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.width / GupyPeek.aspect;
    return ExcludeSemantics(
      child: ClipRect(
        child: SizedBox(
          width: widget.width,
          height: h,
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, child) => Transform.translate(
              offset: Offset(
                0,
                h * 0.7 * (1 - Curves.easeOutBack.transform(_c.value)),
              ),
              child: child,
            ),
            child: Image.asset(
              '$_dir/static/mengintip.webp',
              width: widget.width,
              height: h,
              excludeFromSemantics: true,
            ),
          ),
        ),
      ),
    );
  }
}

/// A one-time tip card with Gupy peeking over its top edge. Dismissing it is
/// remembered per [id]; it stays hidden when preferences can't be read.
class GupyHint extends StatefulWidget {
  const GupyHint({
    super.key,
    required this.id,
    required this.title,
    required this.text,
  });
  final String id;
  final String title;
  final String text;

  static String prefKey(String id) => 'grouply.hint.$id';

  @override
  State<GupyHint> createState() => _GupyHintState();
}

class _GupyHintState extends State<GupyHint> {
  SharedPreferences? _prefs;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() {
        _prefs = prefs;
        _show = !(prefs.getBool(GupyHint.prefKey(widget.id)) ?? false);
      });
    }, onError: (_) {});
  }

  void _dismiss() {
    setState(() => _show = false);
    _prefs?.setBool(GupyHint.prefKey(widget.id), true);
  }

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: Duration(milliseconds: 250),
    curve: Curves.easeOut,
    alignment: Alignment.topCenter,
    child: !_show
        ? SizedBox(width: double.infinity)
        : Column(
            key: Key('hint-${widget.id}'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(alignment: Alignment(0.75, 0), child: GupyPeek(width: 120)),
              Container(
                padding: EdgeInsets.fromLTRB(18, 16, 18, 14),
                decoration: glBox(GLTheme.mint, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, style: gl(16, w700)),
                    SizedBox(height: 6),
                    Text(widget.text, style: gl(14, w400, 0, GLTheme.text2, 4)),
                    SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: GLTap(
                        key: Key('hint-${widget.id}-ok'),
                        onTap: _dismiss,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 6,
                          ),
                          child: Text('Mengerti', style: gl(15, w600)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
  );
}

/// The GROUPLY mark: Gupy's head on mint (same art as the app icon).
class GupyLogo extends StatelessWidget {
  const GupyLogo({super.key, required this.size, required this.radius});
  final double size;
  final double radius;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: glBox(GLTheme.mint, radius),
      child: Image.asset(
        '$_dir/static/logo.webp',
        fit: BoxFit.cover,
        excludeFromSemantics: true,
      ),
    ),
  );
}
