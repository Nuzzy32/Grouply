// Port of Grouply/Features/ProfileViews.swift (profile, notif, blocked, about
// and the profile sheets). Layout values mirror the SwiftUI source 1:1.
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/store.dart';
import '../ui/gl.dart';

String _failureText(Object failure) => failure is GrouplyException
    ? failure.message
    : 'Perubahan belum terkonfirmasi. Muat ulang sebelum mencoba lagi.';

void _checkIdentity(GrouplyStore store, String actor) {
  if (!store.authenticated || store.currentUserID != actor) {
    throw const GrouplyException(
      'Akun telah berubah. Ulangi dari profil aktif.',
    );
  }
}

/// `@AppStorage("grouply.local.*")` — simulated notification permission and
/// preferences, stored on the device only.
class _LocalPrefs extends ChangeNotifier {
  static final shared = _LocalPrefs();
  final _values = <String, Object>{
    'perm': 'off',
    'deadline': true,
    'review': true,
    'comment': true,
    'chat': false,
  };
  bool _loaded = false;

  String get perm => _values['perm'] as String;
  bool flag(String key) => _values[key] as bool;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in _values.keys.toList()) {
        final value = prefs.get('grouply.local.$key');
        if (value != null && value.runtimeType == _values[key].runtimeType) {
          _values[key] = value;
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  void set(String key, Object value) {
    _values[key] = value;
    notifyListeners();
    SharedPreferences.getInstance()
        .then(
          (prefs) => value is bool
              ? prefs.setBool('grouply.local.$key', value)
              : prefs.setString('grouply.local.$key', value as String),
        )
        .catchError((_) => false);
  }
}

// MARK: - Shared bits

/// `.glDetailScreen()` with the profile padding (20 horizontal, 4 top, 32 bottom).
class _ProfileScaffold extends StatelessWidget {
  const _ProfileScaffold({
    required this.title,
    required this.children,
    this.spacing = 16,
    this.onRefresh,
  });
  final String title;
  final List<Widget> children;
  final double spacing;
  final Future<void> Function()? onRefresh;
  @override
  Widget build(BuildContext context) {
    Widget list = ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      children: [
        GLDetailHeader(title),
        for (final child in children) ...[SizedBox(height: spacing), child],
      ],
    );
    if (onRefresh != null) {
      list = RefreshIndicator.adaptive(onRefresh: onRefresh!, child: list);
    }
    return Scaffold(
      backgroundColor: GLTheme.background,
      body: SafeArea(child: _ink(list)),
    );
  }
}

Widget _ink(Widget child) => DefaultTextStyle.merge(
  style: const TextStyle(color: GLTheme.ink),
  child: IconTheme.merge(
    data: const IconThemeData(color: GLTheme.ink),
    child: child,
  ),
);

/// White grouped list (`border-radius:24px;padding:4px 16px`).
class _ProfileGroup extends StatelessWidget {
  const _ProfileGroup({required this.children, this.vertical = 4});
  final List<Widget> children;
  final double vertical;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.symmetric(horizontal: 16, vertical: vertical),
    decoration: glBox(Colors.white, 24),
    child: Column(children: children),
  );
}

/// `.profileDivider()` — 1pt bottom rule drawn over the row.
const _divider = BoxDecoration(
  border: Border(bottom: BorderSide(color: GLTheme.border)),
);

/// 44pt capsule outline button ("Edit", "Buka blokir").
class _PillButton extends StatelessWidget {
  const _PillButton({required this.title, required this.onTap});
  final String title;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => GLTap(
    onTap: onTap,
    child: Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      decoration: const ShapeDecoration(
        shape: StadiumBorder(side: BorderSide(color: GLTheme.ink, width: 1.5)),
      ),
      child: Text(title, style: gl(14, w600)),
    ),
  );
}

/// iOS switch from the prototype's `sw()` (#34C759 / #D5D8DB).
class _ProfileSwitch extends StatelessWidget {
  const _ProfileSwitch({required this.on, required this.onChanged});
  final bool on;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) => CupertinoSwitch(
    value: on,
    activeTrackColor: const Color(0xFF34C759),
    inactiveTrackColor: const Color(0xFFD5D8DB),
    onChanged: (_) => onChanged(),
  );
}

/// Dashed `#9AA0A6` 1.5pt rounded border (`StrokeStyle(dash: [5, 4])`).
class _Dashed extends StatelessWidget {
  const _Dashed({
    required this.radius,
    required this.padding,
    required this.child,
  });
  final double radius;
  final EdgeInsetsGeometry padding;
  final Widget child;
  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _DashPainter(radius),
    child: Container(width: double.infinity, padding: padding, child: child),
  );
}

class _DashPainter extends CustomPainter {
  const _DashPainter(this.radius);
  final double radius;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF9AA0A6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.75),
          Radius.circular(radius),
        ),
      );
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.radius != radius;
}

class _DashedNote extends StatelessWidget {
  const _DashedNote(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => _Dashed(
    radius: 14,
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
    child: Text(text, style: gl(13, w400, 0, GLTheme.secondary, 2.5)),
  );
}

/// Capsule tag ("PROTOTIPE", "DEMO").
Widget _tag(String text, double height, double em) => Container(
  height: height,
  padding: const EdgeInsets.symmetric(horizontal: 8),
  alignment: Alignment.center,
  decoration: const ShapeDecoration(
    color: GLTheme.butter,
    shape: StadiumBorder(),
  ),
  child: Text(text, style: gl(11, w700, em)),
);

/// Filled sheet button (`height:54px;border-radius:18px;font-size:16px`).
class _FilledButton extends StatelessWidget {
  const _FilledButton({
    required this.title,
    required this.onTap,
    this.height = 54,
    this.radius = 18,
    this.fontSize = 16,
    this.background = GLTheme.ink,
    this.busy = false,
  });
  final String title;
  final VoidCallback onTap;
  final double height, radius, fontSize;
  final Color background;
  final bool busy;
  @override
  Widget build(BuildContext context) => GLTap(
    onTap: busy ? null : onTap,
    child: Opacity(
      opacity: busy ? 0.6 : 1,
      child: Container(
        height: height,
        alignment: Alignment.center,
        decoration: glBox(background, radius),
        child: Text(title, style: gl(fontSize, w600, 0, Colors.white)),
      ),
    ),
  );
}

Widget _column(
  List<Widget> children,
  double spacing, {
  bool center = false,
  Key? key,
}) => Column(
  key: key,
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: center
      ? CrossAxisAlignment.center
      : CrossAxisAlignment.stretch,
  children: [
    for (var i = 0; i < children.length; i++) ...[
      if (i > 0) SizedBox(height: spacing),
      children[i],
    ],
  ],
);

/// Prototype sheet without the title row (perm, personas, privacy draw their own).
Future<T?> _showBareSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double horizontal = 20,
  bool centered = false,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: GLTheme.background,
  barrierColor: const Color(0x66000000),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
  ),
  builder: (context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(horizontal, 10, horizontal, 34),
    child: _ink(
      DefaultTextStyle.merge(
        textAlign: centered ? TextAlign.center : TextAlign.start,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: centered
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 5,
                decoration: const ShapeDecoration(
                  color: Color(0xFFC4C7C5),
                  shape: StadiumBorder(),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Builder(builder: builder),
          ],
        ),
      ),
    ),
  ),
);

// MARK: - Profil

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.store});

  final GrouplyStore store;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _busy = false;

  GrouplyStore get store => widget.store;
  bool get _disabled => _busy || store.loading || !store.authenticated;

  @override
  void initState() {
    super.initState();
    _LocalPrefs.shared.load();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_disabled) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (failure) {
      if (mounted) {
        showGLToast(context, _failureText(failure), kind: GLToastKind.err);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _push(Widget screen) => Navigator.of(
    context,
  ).push(CupertinoPageRoute<void>(builder: (_) => screen));

  Future<void> _signOut() async {
    final actor = store.currentUserID;
    if (!await showGLConfirm(
          context,
          title: 'Keluar dari GROUPLY?',
          text: 'Kamu perlu masuk lagi untuk membuka grup dan tugasmu.',
          ok: 'Keluar',
          destructive: true,
        ) ||
        !mounted) {
      return;
    }
    await _run(() async {
      _checkIdentity(store, actor);
      await store.signOut();
    });
  }

  Future<void> _resetDemo() async {
    if (!await showGLConfirm(
          context,
          title: 'Reset data demo?',
          text:
              'Semua perubahan di prototipe (grup, proyek, tugas, pesan, laporan) kembali ke data awal. Tidak ada data server yang terpengaruh.',
          ok: 'Reset',
          destructive: true,
        ) ||
        !mounted) {
      return;
    }
    final overlay = Navigator.of(context, rootNavigator: true).context;
    await _run(() async {
      await store.resetDemo();
      if (overlay.mounted) showGLToast(overlay, 'Data demo direset');
    });
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Semantics(
      header: true,
      child: Text(text.toUpperCase(), style: gl(14, w700, 0.04, GLTheme.text2)),
    ),
  );

  Widget _navRow(
    String icon,
    Color tint,
    String title,
    String subtitle,
    VoidCallback onTap, {
    bool divider = false,
  }) => GLTap(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 60),
      foregroundDecoration: divider ? _divider : null,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: glBox(tint, 13),
            child: GLIcon(icon, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: gl(16, w600)),
                Text(subtitle, style: gl(13, w400, 0, GLTheme.secondary)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const GLIcon('chevron.right', size: 22, color: GLTheme.secondary),
        ],
      ),
    ),
  );

  Widget _actionRow(
    String icon,
    String title,
    VoidCallback? onTap, {
    Color color = GLTheme.ink,
    bool divider = false,
    Key? key,
  }) => GLTap(
    key: key,
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 56),
      foregroundDecoration: divider ? _divider : null,
      child: Row(
        children: [
          GLIcon(icon, size: 22, color: color),
          const SizedBox(width: 12),
          Text(title, style: gl(16, w600, 0, color)),
          const Spacer(),
        ],
      ),
    ),
  );

  Widget _profileCard() {
    final me = store.user(store.currentUserID);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: glBox(Colors.white, 28),
      child: Row(
        children: [
          GLAvatar(user: me, size: 64, fontSize: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(me?.text('name') ?? '', style: gl(20, w700)),
                const SizedBox(height: 2),
                Text(
                  me?.text('email') ?? '',
                  style: gl(14, w400, 0, GLTheme.secondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          _PillButton(
            title: 'Edit',
            onTap: _disabled ? null : () => _showEditName(context, store),
          ),
        ],
      ),
    );
  }

  Widget _demoBox() => _Dashed(
    radius: 24,
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
    child: _column([
      Row(
        children: [
          _tag('PROTOTIPE', 22, 0.04),
          const SizedBox(width: 6),
          Flexible(child: Text('Pengaturan demo', style: gl(13, w700, 0.04))),
        ],
      ),
      Text(
        'Hanya untuk pengujian. Tidak ada di aplikasi produksi.',
        style: gl(13, w400, 0, GLTheme.text3, 2.5),
      ),
      Row(
        children: [
          Expanded(
            child: GLOutlineButton(
              title: 'Ganti persona',
              height: 44,
              radius: 14,
              fontSize: 14,
              onPressed: _disabled ? null : () => _showPersonas(context, store),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GLOutlineButton(
              title: 'Reset data demo',
              height: 44,
              radius: 14,
              fontSize: 14,
              onPressed: _disabled ? null : _resetDemo,
            ),
          ),
        ],
      ),
    ], 10),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([store, _LocalPrefs.shared]),
    builder: (context, _) {
      final me = store.currentUserID;
      final perm = _LocalPrefs.shared.perm;
      final blocked = store.blockedUserIDs.length;
      final reports = store.reports
          .where((row) => row.text('reporterID') == me)
          .length;
      return _ProfileScaffold(
        title: 'Profil',
        onRefresh: store.demoMode ? null : () => _run(store.refresh),
        children: [
          if (store.error != null)
            GLNotice(text: store.error!, color: GLTheme.coral),
          if (!store.authenticated)
            const GLNotice(
              text: 'Sesi telah berakhir. Masuk kembali untuk membuka profil.',
            )
          else ...[
            _profileCard(),
            _sectionLabel('Preferensi'),
            _ProfileGroup(
              children: [
                _navRow(
                  'bell',
                  GLTheme.butter,
                  'Notifikasi',
                  perm == 'on'
                      ? 'Izin aktif'
                      : perm == 'denied'
                      ? 'Diblokir di Pengaturan iOS'
                      : 'Izin belum aktif',
                  () => _push(_NotifScreen(store: store)),
                  divider: true,
                ),
                _navRow(
                  'info.circle',
                  GLTheme.sky,
                  'Tentang GROUPLY',
                  'Versi, privasi, moderasi',
                  () => _push(_AboutScreen(store: store)),
                ),
              ],
            ),
            _sectionLabel('Keamanan'),
            _ProfileGroup(
              children: [
                _navRow(
                  'nosign',
                  GLTheme.coral,
                  'Pengguna diblokir',
                  blocked > 0 ? '$blocked pengguna' : 'Tidak ada',
                  () => _push(_BlockedScreen(store: store)),
                  divider: true,
                ),
                _navRow(
                  'flag',
                  const Color(0xFFECEEEB),
                  'Pelaporan',
                  '$reports laporan tersimpan ${store.demoMode ? 'lokal' : 'di server'}',
                  () => _push(_AboutScreen(store: store)),
                ),
              ],
            ),
            _sectionLabel('Akun'),
            _ProfileGroup(
              children: [
                _actionRow(
                  'rectangle.portrait.and.arrow.right',
                  'Keluar akun',
                  _disabled ? null : _signOut,
                  divider: true,
                ),
                _actionRow(
                  'trash',
                  'Hapus akun',
                  _disabled ? null : () => _showDelete(context, store),
                  color: GLTheme.danger,
                  key: const ValueKey('delete-account'),
                ),
              ],
            ),
            if (store.demoMode) _demoBox(),
          ],
        ],
      );
    },
  );
}

// MARK: - Notifikasi

class _NotifScreen extends StatelessWidget {
  const _NotifScreen({required this.store});
  final GrouplyStore store;

  Widget _row(String key, String label, String sub) {
    final prefs = _LocalPrefs.shared;
    final on = prefs.flag(key);
    void toggle() => prefs.set(key, !on);
    return Semantics(
      value: on ? 'Aktif' : 'Nonaktif',
      child: GLTap(
        onTap: toggle,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(vertical: 10),
          foregroundDecoration: _divider,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: gl(16, w600)),
                    const SizedBox(height: 2),
                    Text(sub, style: gl(13, w400, 0, GLTheme.secondary, 1.5)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _ProfileSwitch(on: on, onChanged: toggle),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _LocalPrefs.shared,
    builder: (context, _) {
      final perm = _LocalPrefs.shared.perm;
      void tap() {
        if (perm == 'on') {
          showGLToast(
            context,
            'Untuk mencabut izin, buka Pengaturan iOS (simulasi).',
            kind: GLToastKind.info,
          );
        } else if (perm == 'denied') {
          showGLToast(
            context,
            'Buka Pengaturan iOS untuk mengizinkan notifikasi (simulasi).',
            kind: GLToastKind.info,
          );
        } else {
          _showPerm(context);
        }
      }

      return _ProfileScaffold(
        title: 'Notifikasi',
        children: [
          Semantics(
            value: perm == 'on' ? 'Aktif' : 'Nonaktif',
            child: GLTap(
              onTap: tap,
              child: Container(
                constraints: const BoxConstraints(minHeight: 68),
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 16,
                ),
                decoration: glBox(Colors.white, 24),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: glBox(GLTheme.butter, 14),
                      child: const GLIcon('bell.badge', size: 21),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Izinkan notifikasi', style: gl(16, w600)),
                          const SizedBox(height: 1),
                          Text(
                            perm == 'on'
                                ? 'GROUPLY boleh mengirim notifikasi'
                                : perm == 'denied'
                                ? 'Ditolak · ubah lewat Pengaturan iOS'
                                : 'Ketuk untuk mengaktifkan',
                            style: gl(13, w400, 0, GLTheme.secondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _ProfileSwitch(on: perm == 'on', onChanged: tap),
                  ],
                ),
              ),
            ),
          ),
          // Flutter client has no push transport yet; the toggle is a local simulation.
          const GLNotice(
            text:
                'Push notification belum tersedia di aplikasi ini. Izin dan pilihan di sini hanya simulasi lokal; belum ada notifikasi yang dikirim ke perangkat.',
          ),
          if (perm != 'on')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'Pilihan di bawah tersimpan dan berlaku setelah izin notifikasi aktif.',
                style: gl(13, w400, 0, GLTheme.text3, 2.5),
              ),
            ),
          _ProfileGroup(
            children: [
              _row(
                'deadline',
                'Deadline mendekat',
                'H-1 sebelum deadline tugasmu',
              ),
              _row(
                'review',
                'Review & revisi',
                'Saat hasilmu direview atau ada yang perlu kamu review',
              ),
              _row(
                'comment',
                'Komentar di tugasku',
                'Diskusi tugas yang kamu kerjakan atau review',
              ),
              _row('chat', 'Pesan chat grup', 'Semua pesan baru di chat grup'),
            ],
          ),
        ],
      );
    },
  );
}

// MARK: - Pengguna diblokir

class _BlockedScreen extends StatefulWidget {
  const _BlockedScreen({required this.store});
  final GrouplyStore store;
  @override
  State<_BlockedScreen> createState() => _BlockedScreenState();
}

class _BlockedScreenState extends State<_BlockedScreen> {
  bool _busy = false;
  GrouplyStore get store => widget.store;

  Future<void> _unblock(String id) async {
    if (_busy || store.loading || !store.authenticated) return;
    final name = store.user(id)?.text('name') ?? 'Pengguna';
    setState(() => _busy = true);
    try {
      await store.mutate('unblockUser', {'id': id});
      if (mounted) {
        showGLToast(
          context,
          '$name tidak lagi diblokir',
          kind: GLToastKind.info,
        );
      }
    } catch (failure) {
      if (mounted) {
        showGLToast(context, _failureText(failure), kind: GLToastKind.err);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => _ProfileScaffold(
      title: 'Pengguna diblokir',
      children: [
        Text(
          'Pesan dari pengguna yang kamu blokir disembunyikan. Mereka tetap anggota grup dan tugas bersama tetap berjalan.',
          style: gl(14, w400, 0, GLTheme.text3, 3.5),
        ),
        if (store.blockedUserIDs.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 22),
            decoration: glBox(Colors.white, 28),
            child: _column([
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: glBox(GLTheme.mint, 20),
                  child: const GLIcon('checkmark.shield', size: 28),
                ),
              ),
              Text(
                'Belum ada yang kamu blokir',
                textAlign: TextAlign.center,
                style: gl(18, w700),
              ),
              Text(
                'Kamu bisa memblokir dari detail anggota, atau dengan menekan lama sebuah pesan.',
                textAlign: TextAlign.center,
                style: gl(15, w400, 0, GLTheme.secondary, 4),
              ),
            ], 10),
          )
        else
          _ProfileGroup(
            vertical: 0,
            children: [
              for (final id in store.blockedUserIDs)
                Container(
                  constraints: const BoxConstraints(minHeight: 64),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  foregroundDecoration: _divider,
                  child: Row(
                    children: [
                      GLAvatar(user: store.user(id), size: 44, fontSize: 14),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          store.user(id)?.text('name') ?? 'Pengguna',
                          style: gl(16, w600),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _PillButton(
                        title: 'Buka blokir',
                        onTap: _busy ? null : () => _unblock(id),
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    ),
  );
}

// MARK: - Tentang

class _AboutScreen extends StatelessWidget {
  const _AboutScreen({required this.store});
  final GrouplyStore store;

  String _status(JsonMap report) {
    if (store.demoMode) return 'Tersimpan lokal';
    return switch (report.text('status')) {
      'dismissed' => 'Selesai ditinjau',
      'removed' => 'Pesan dihapus moderator',
      _ => 'Menunggu peninjauan',
    };
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final cloud = !store.demoMode;
      final reports = store.reports
          .where((row) => row.text('reporterID') == store.currentUserID)
          .toList();
      return _ProfileScaffold(
        title: 'Tentang GROUPLY',
        spacing: 14,
        children: [
          GLCard(
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: glBox(GLTheme.mint, 18),
                  child: const GLIcon('person.3', size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('GROUPLY', style: gl(17, w700)),
                      Text(
                        'Versi 0.3 · prototipe desain',
                        style: gl(13, w400, 0, GLTheme.secondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          GLCard(
            child: _column([
              Text('Pelaporan & moderasi', style: gl(16, w700)),
              Text(
                cloud
                    ? 'Tekan lama pesan untuk melaporkan atau memblokir pengirimnya. Laporan masuk antrean privat di server dan dapat ditinjau operator berwenang. Belum ada jaminan waktu respons.'
                    : 'Tekan lama pesan untuk melaporkan atau memblokir pengirimnya. Dalam demo, laporan hanya disimpan di perangkat, bukan dikirim kepada moderator.',
                style: gl(14, w400, 0, GLTheme.text3, 5),
              ),
              for (final report in reports)
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 12,
                  ),
                  decoration: glBox(GLTheme.muted, 14),
                  child: Row(
                    children: [
                      const GLIcon('flag', size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${report.text('reason')} · Pesan dari ${_sender(report)}',
                          style: gl(14),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _status(report),
                        style: gl(12, w400, 0, GLTheme.secondary),
                      ),
                    ],
                  ),
                ),
            ], 8),
          ),
          GLCard(
            child: _column([
              Text('Privasi', style: gl(16, w700)),
              Text(
                'Akun memakai nama dan identitas login. Pada mode server, akses grup, tugas, dan pesan diperiksa melalui membership dan aturan backend.',
                style: gl(14, w400, 0, GLTheme.text3, 5),
              ),
            ], 8),
          ),
        ],
      );
    },
  );

  String _sender(JsonMap report) {
    final message = store.messages
        .where((row) => row['id'] == report['messageID'])
        .firstOrNull;
    final name = message == null
        ? null
        : store.user(message.text('senderID'))?.text('name');
    return name ?? 'anggota';
  }
}

// MARK: - Sheets

void _showEditName(BuildContext context, GrouplyStore store) => showGLSheet(
  context,
  title: 'Edit profil',
  builder: (_) => _EditNameSheet(store: store),
);

class _EditNameSheet extends StatefulWidget {
  const _EditNameSheet({required this.store});
  final GrouplyStore store;
  @override
  State<_EditNameSheet> createState() => _EditNameSheetState();
}

class _EditNameSheetState extends State<_EditNameSheet> {
  late final _name = TextEditingController(
    text: widget.store.user(widget.store.currentUserID)?.text('name') ?? '',
  );
  late final _actor = widget.store.currentUserID;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _name.text.trim();
    if (value.characters.length < 2) {
      return setState(() => _error = 'Nama minimal 2 karakter.');
    }
    if (value.characters.length > 30) {
      return setState(() => _error = 'Nama maksimal 30 karakter.');
    }
    setState(() => _busy = true);
    try {
      _checkIdentity(widget.store, _actor);
      await widget.store.mutate('updateProfile', {'name': value});
      if (!mounted) return;
      showGLToast(context, 'Nama diperbarui di semua grup');
      Navigator.of(context).pop();
    } catch (failure) {
      if (mounted) setState(() => _error = _failureText(failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _column([
    GLField(
      'Nama tampilan',
      child: GLTextField(
        controller: _name,
        maxLength: 30,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (_) => _save(),
      ),
    ),
    Text(
      'Nama baru terlihat di semua grup, chat, dan tugas.',
      style: gl(13, w400, 0, GLTheme.secondary),
    ),
    if (_error != null) GLFormError(_error!),
    GLSubmitButton(
      title: _busy ? 'Menyimpan…' : 'Simpan',
      busy: _busy,
      onPressed: _save,
    ),
  ], 16);
}

void _showPerm(BuildContext context) => _showBareSheet(
  context,
  horizontal: 24,
  centered: true,
  builder: (_) => const _PermSheet(),
);

class _PermSheet extends StatefulWidget {
  const _PermSheet();
  @override
  State<_PermSheet> createState() => _PermSheetState();
}

class _PermSheetState extends State<_PermSheet> {
  bool _simulate = false;

  void _finish(String perm, String toast, GLToastKind kind) {
    _LocalPrefs.shared.set('perm', perm);
    showGLToast(context, toast, kind: kind);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 200),
    child: !_simulate
        ? _column(key: const ValueKey(1), [
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                width: 72,
                height: 72,
                decoration: glBox(GLTheme.lavender, 26),
                child: const GLIcon('bell.badge', size: 36),
              ),
            ),
            Text(
              'Dapat kabar yang penting saja',
              textAlign: TextAlign.center,
              style: gl(22, w700, -0.02),
            ),
            Text(
              'Kami memberi tahu saat kamu ditugaskan, hasil kerjamu direview, ada komentar di tugasmu, atau deadline sudah dekat. Isi pesan tidak tampil di lock screen.',
              textAlign: TextAlign.center,
              style: gl(15, w400, 0, GLTheme.secondary, 4.5),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _FilledButton(
                title: 'Lanjutkan',
                height: 56,
                radius: 20,
                fontSize: 17,
                onTap: () => setState(() => _simulate = true),
              ),
            ),
            GLTap(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                height: 48,
                alignment: Alignment.center,
                child: Text('Nanti saja', style: gl(16, w600)),
              ),
            ),
          ], 14)
        : _column(key: const ValueKey(2), [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: const ShapeDecoration(
                  color: GLTheme.butter,
                  shape: StadiumBorder(),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const GLIcon('flask', size: 16),
                    const SizedBox(width: 5),
                    Text('SIMULASI PROTOTIPE', style: gl(12, w700, 0.04)),
                  ],
                ),
              ),
            ),
            _Dashed(
              radius: 22,
              padding: const EdgeInsets.all(18),
              child: _column(
                [
                  Text(
                    'Di sini aplikasi iOS akan menampilkan dialog izin sistem.',
                    textAlign: TextAlign.center,
                    style: gl(16, w600),
                  ),
                  Text(
                    'Pilih hasil yang ingin disimulasikan.',
                    textAlign: TextAlign.center,
                    style: gl(14, w400, 0, GLTheme.secondary),
                  ),
                ],
                8,
                center: true,
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: GLOutlineButton(
                    title: 'Ditolak',
                    height: 52,
                    radius: 18,
                    onPressed: () => _finish(
                      'denied',
                      'Izin ditolak. Kamu tetap bisa cek Beranda.',
                      GLToastKind.info,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _FilledButton(
                    title: 'Diizinkan',
                    height: 52,
                    fontSize: 15,
                    onTap: () =>
                        _finish('on', 'Notifikasi aktif', GLToastKind.ok),
                  ),
                ),
              ],
            ),
          ], 12),
  );
}

Widget _keyed(Key key, Widget child) => KeyedSubtree(key: key, child: child);

void _showPersonas(BuildContext context, GrouplyStore store) => _showBareSheet(
  context,
  builder: (sheet) => ListenableBuilder(
    listenable: store,
    builder: (sheet, _) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _tag('DEMO', 24, 0.06),
            const SizedBox(width: 8),
            Expanded(child: Text('Ganti persona', style: gl(22, w700, -0.02))),
            GLTap(
              label: 'Tutup',
              onTap: () => Navigator.of(sheet).pop(),
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Color(0xFFECEEEB),
                  shape: BoxShape.circle,
                ),
                child: const GLIcon('xmark', size: 22),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8), // spacing 14, padding(.top, -6)
        Text(
          'Hanya untuk menguji sudut pandang tiap anggota. Semua persona memakai data yang sama.',
          style: gl(14, w400, 0, GLTheme.text3, 2.5),
        ),
        const SizedBox(height: 14),
        _column([
          for (final persona in demoPersonas)
            if (store.user(persona.id) case final user?
                when user.text('email').isNotEmpty)
              _keyed(
                ValueKey('switch-persona-${persona.id}'),
                _personaRow(sheet, store, persona.id, persona.role, user),
              ),
        ], 8),
      ],
    ),
  ),
);

Widget _personaRow(
  BuildContext sheet,
  GrouplyStore store,
  String id,
  String role,
  JsonMap user,
) {
  final on = store.currentUserID == id;
  return Semantics(
    selected: on,
    child: GLTap(
      onTap: () async {
        if (on) return;
        try {
          await store.switchDemoUser(id);
          if (!sheet.mounted) return;
          showGLToast(
            sheet,
            'Demo: sekarang melihat sebagai ${user.text('name')}',
            kind: GLToastKind.info,
          );
          Navigator.of(sheet).pop();
        } catch (failure) {
          if (sheet.mounted) {
            showGLToast(sheet, _failureText(failure), kind: GLToastKind.err);
          }
        }
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.only(top: 8, bottom: 8, left: 8, right: 14),
        decoration: glBox(
          Colors.white,
          18,
          border: on ? GLTheme.ink : GLTheme.border,
          borderWidth: 1.5,
        ),
        child: Row(
          children: [
            GLAvatar(user: user, size: 40, fontSize: 13),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.text('name'), style: gl(16, w600)),
                  Text(role, style: gl(13, w400, 0, GLTheme.secondary)),
                ],
              ),
            ),
            if (on) Text('Aktif', style: gl(13, w700)),
          ],
        ),
      ),
    ),
  );
}

void _showDelete(BuildContext context, GrouplyStore store) => showGLSheet(
  context,
  title: 'Hapus akun',
  builder: (_) => _DeleteSheet(store: store),
);

class _DeleteSheet extends StatefulWidget {
  const _DeleteSheet({required this.store});
  final GrouplyStore store;
  @override
  State<_DeleteSheet> createState() => _DeleteSheetState();
}

class _DeleteSheetState extends State<_DeleteSheet> {
  final _text = TextEditingController();
  late final _actor = widget.store.currentUserID;
  var _step = 1;
  String? _error;
  bool _busy = false;

  GrouplyStore get store => widget.store;
  bool get _cloud => !store.demoMode;

  /// Prototype rule: groups I coordinate that still have other members.
  List<JsonMap> get _blockers => store.groups
      .where(
        (row) =>
            row.ids('memberIDs').contains(store.currentUserID) &&
            row.text('coordinatorID') == store.currentUserID &&
            (!_cloud || row.ids('memberIDs').length > 1),
      )
      .toList();

  bool get _hasActiveAssignments => store.tasks.any(
    (row) =>
        row.text('status') != 'done' &&
        (row.text('assigneeID') == store.currentUserID ||
            row.text('reviewerID') == store.currentUserID),
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Widget _line(String icon, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      GLIcon(icon, size: 20, color: GLTheme.ink),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: gl(15, w400, 0, null, 4.5))),
    ],
  );

  Future<void> _delete() async {
    if (_text.text.trim().toUpperCase() != 'HAPUS') {
      return setState(() => _error = 'Ketik HAPUS untuk konfirmasi.');
    }
    final cloud = _cloud;
    setState(() => _busy = true);
    try {
      _checkIdentity(store, _actor);
      await store.mutate('deleteAccount', {});
      if (!mounted) return;
      showGLToast(
        context,
        cloud
            ? 'Akun dihapus.'
            : 'Simulasi: akun dihapus dari data demo lokal. Tidak ada data server yang dihapus.',
        kind: GLToastKind.info,
      );
      Navigator.of(context).pop();
    } catch (failure) {
      if (mounted) setState(() => _error = _failureText(failure));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final blockers = _blockers, active = _hasActiveAssignments;
    final clear = blockers.isEmpty && !active;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: _step == 1
          ? _column(key: const ValueKey(1), [
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 18,
                ),
                decoration: glBox(Colors.white, 22),
                child: _column([
                  _line(
                    'trash',
                    _cloud
                        ? 'Akun login dan profil di server akan dihapus permanen.'
                        : 'Ini simulasi penghapusan akun demo, bukan akun server.',
                  ),
                  _line(
                    'clock.arrow.circlepath',
                    'Hasil kerja dan pesanmu di grup tetap ada, ditampilkan sebagai “Pengguna terhapus”.',
                  ),
                  _line(
                    'arrow.left.arrow.right',
                    'Alihkan peran pelaksana/reviewer pada semua tugas yang belum selesai terlebih dahulu, termasuk di proyek arsip. Tidak ada pengalihan otomatis.',
                  ),
                  if (_cloud)
                    _line(
                      'person.crop.circle.badge.minus',
                      'Jika kamu satu-satunya anggota, grup kehilangan akses anggota dan undangannya dinonaktifkan. Riwayat kerja tetap disimpan tanpa identitas akunmu.',
                    ),
                ], 10),
              ),
              if (blockers.isNotEmpty)
                GLNotice(
                  text:
                      'Serahkan peran koordinator dulu di: ${blockers.map((row) => row.text('name')).join(', ')}.',
                  icon: 'person.badge.shield.checkmark',
                ),
              if (active)
                const GLNotice(
                  text:
                      'Masih ada tugas yang belum selesai dengan kamu sebagai pelaksana atau reviewer. Minta koordinator membuka kembali proyek bila perlu, lalu alihkan tugasnya.',
                  icon: 'checklist',
                ),
              if (_error != null) GLFormError(_error!),
              _FilledButton(
                title: 'Lanjutkan',
                background: clear ? GLTheme.ink : const Color(0xFFB4B8BC),
                onTap: () => setState(() {
                  if (blockers.isNotEmpty) {
                    _error =
                        'Serahkan peran koordinator dulu sebelum menghapus akun.';
                  } else if (active) {
                    _error =
                        'Alihkan semua tugas aktif dan peran reviewer sebelum menghapus akun.';
                  } else {
                    _error = null;
                    _step = 2;
                  }
                }),
              ),
            ], 12)
          : _column(key: const ValueKey(2), [
              Text.rich(
                const TextSpan(
                  children: [
                    TextSpan(text: 'Ketik '),
                    TextSpan(
                      text: 'HAPUS',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    TextSpan(text: ' untuk konfirmasi.'),
                  ],
                ),
                style: gl(15),
              ),
              Semantics(
                label: 'Ketik HAPUS',
                textField: true,
                child: TextField(
                  controller: _text,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.characters,
                  cursorColor: GLTheme.ink,
                  style: gl(17, w600, 0.08, GLTheme.ink),
                  decoration: glInputDecoration().copyWith(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 15,
                    ),
                  ),
                  onSubmitted: (_) => _delete(),
                ),
              ),
              if (!_cloud)
                const _DashedNote(
                  'Simulasi: hanya data demo lokal yang berubah. Tidak ada data server yang dihapus. Pakai “Reset data demo” untuk mengembalikan.',
                ),
              if (_error != null) GLFormError(_error!),
              _keyed(
                const ValueKey('confirm-delete-account'),
                _FilledButton(
                  title: _busy
                      ? 'Menghapus…'
                      : _cloud
                      ? 'Hapus akun'
                      : 'Hapus akun (simulasi)',
                  background: GLTheme.danger,
                  busy: _busy,
                  onTap: _delete,
                ),
              ),
            ], 12),
    );
  }
}

/// Prototype `sheetPrivacy` (`ProfilePrivacySheet`); also opened from Welcome.
/// [cloud] mirrors Swift `store.isCloudMode` (signed in to the server).
Future<void> showPrivacySheet(
  BuildContext context, {
  bool cloud = false,
}) => _showBareSheet(
  context,
  builder: (sheet) => _column([
    Text('Privasi & data', style: gl(22, w700, -0.02)),
    Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
      decoration: glBox(Colors.white, 22),
      child: DefaultTextStyle.merge(
        style: gl(15, w400, 0, GLTheme.ink, 4.5),
        child: _column([
          const Text(
            'GROUPLY memakai nama dan identitas login untuk akunmu. Persona demo terpisah dari akun server.',
          ),
          const Text(
            'Proyek, tugas, dan pesan hanya terlihat oleh anggota grup terkait.',
          ),
          if (cloud) ...const [
            Text(
              'Laporan dan isi pesan yang dilaporkan dapat ditinjau operator berwenang. Blokir menyembunyikan pesan untukmu, bukan mengeluarkan anggota atau menghentikan tugas bersama.',
            ),
            Text(
              'Penghapusan akun menghapus identitas login dan profil. Pesan, hasil kerja, dan review bersama tetap disimpan tanpa identitas akun; hapus informasi pribadi dalam kontribusi sebelum membagikannya. Kebijakan retensi untuk rilis publik belum disahkan.',
            ),
          ],
          Text(
            cloud
                ? 'Data akun ini tersimpan di Supabase. Sesi login disimpan aman di Keychain.'
                : 'Data demo disimpan di perangkat ini saja.',
            style: const TextStyle(color: GLTheme.secondary),
          ),
        ], 10),
      ),
    ),
    _FilledButton(title: 'Mengerti', onTap: () => Navigator.of(sheet).pop()),
  ], 14),
);
