import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/store.dart';
import 'features/chat_screens.dart';
import 'features/profile_screen.dart';
import 'features/workspace_screens.dart';
import 'ui/gl.dart';

String? taskIDFromLink(Uri uri) {
  if (uri.scheme != 'grouply' ||
      uri.host != 'task' ||
      uri.pathSegments.length != 1 ||
      uri.pathSegments.single.trim().isEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  return uri.pathSegments.single;
}

class GrouplyApp extends StatefulWidget {
  const GrouplyApp({super.key, required this.store, this.enableLinks = true});
  final GrouplyStore store;
  final bool enableLinks;

  @override
  State<GrouplyApp> createState() => _GrouplyAppState();
}

class _GrouplyAppState extends State<GrouplyApp> {
  final _navigator = GlobalKey<NavigatorState>();
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  StreamSubscription<Uri>? _links;
  String _actor = '';
  String? _pendingTask;

  @override
  void initState() {
    super.initState();
    _actor = widget.store.currentUserID;
    widget.store.addListener(_changed);
    if (widget.enableLinks) {
      final links = AppLinks();
      _links = links.uriLinkStream.listen(
        _openLink,
        onError: (_) {
          _linkError('Tautan belum dapat dibuka.');
        },
      );
    }
  }

  void _linkError(String message) {
    final context = _navigator.currentContext;
    if (context == null) return;
    showGLConfirm(
      context,
      title: 'Tautan tidak dapat dibuka',
      text: message,
      ok: 'Mengerti',
      info: true,
    );
  }

  void _openLink(Uri uri) {
    final id = taskIDFromLink(uri);
    if (id == null) {
      _linkError('Tautan Grouply tidak dikenali.');
      return;
    }
    _pendingTask = id;
    _changed();
  }

  void _changed() {
    final actor = widget.store.currentUserID;
    final identityChanged = actor != _actor;
    _actor = actor;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (identityChanged) {
        _navigator.currentState?.popUntil((route) => route.isFirst);
      }
      if (!widget.store.authenticated ||
          widget.store.loading ||
          _pendingTask == null) {
        return;
      }
      final id = _pendingTask!;
      _pendingTask = null;
      final task = widget.store.task(id);
      final project = task == null
          ? null
          : widget.store.project(task.text('projectID'));
      final group = project == null
          ? null
          : widget.store.group(project.text('groupID'));
      if (group == null ||
          !group.ids('memberIDs').contains(widget.store.currentUserID)) {
        _linkError('Tugas tidak ditemukan atau akses sudah dicabut.');
        return;
      }
      _navigator.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => TaskScreen(store: widget.store, taskID: id),
        ),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    widget.store.removeListener(_changed);
    _links?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Grouply',
    debugShowCheckedModeBanner: false,
    theme: GLTheme.data,
    scrollBehavior: const CupertinoScrollBehavior(),
    locale: const Locale('id', 'ID'),
    supportedLocales: const [Locale('id', 'ID')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    navigatorKey: _navigator,
    scaffoldMessengerKey: _messenger,
    home: AnimatedBuilder(
      animation: widget.store,
      builder: (_, _) {
        if (widget.store.loading && !widget.store.authenticated) {
          return const _Restoring();
        }
        return widget.store.authenticated
            ? _Shell(
                key: ValueKey(widget.store.currentUserID),
                store: widget.store,
              )
            : _Welcome(store: widget.store);
      },
    ),
  );
}

/// Swift `profilePersonas` with the seed's names/tints, shown before a demo
/// snapshot is loaded.
const _personas = [
  (id: 'u1', name: 'Alex', tint: '#DED2FF', role: 'Koordinator'),
  (id: 'u2', name: 'Raka', tint: '#C9F2D6', role: 'Pelaksana'),
  (id: 'u3', name: 'Nadia', tint: '#F9E9BE', role: 'Reviewer'),
  (id: 'u4', name: 'Dimas', tint: '#D8EAF4', role: 'Anggota'),
  (id: 'u5', name: 'Sinta', tint: '#F6CED1', role: 'Anggota'),
  (id: 'u6', name: 'Bima', tint: '#C9F2D6', role: 'Koordinator'),
  (id: 'u7', name: 'Laras', tint: '#D8EAF4', role: 'Anggota'),
];

/// Swift `WelcomeView.restoring`.
class _Restoring extends StatelessWidget {
  const _Restoring();
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: GLTheme.background,
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: glBox(GLTheme.mint, 26),
            child: const GLIcon('person.3', size: 36),
          ),
          const SizedBox(height: 16),
          Text('GROUPLY', style: gl(15, w800, 0.12)),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CupertinoActivityIndicator(radius: 8),
              const SizedBox(width: 8),
              Text(
                'Memulihkan sesi…',
                style: gl(14, w400, 0, GLTheme.secondary),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Swift `WelcomeView.welcome`.
class _Welcome extends StatefulWidget {
  const _Welcome({required this.store});
  final GrouplyStore store;
  @override
  State<_Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<_Welcome> {
  bool _busy = false;
  String? _error;

  Future<void> _persona(String id, String name) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final store = widget.store;
      await store.startDemo();
      if (store.currentUserID != id) await store.switchDemoUser(id);
      if (mounted) showGLToast(context, 'Masuk sebagai $name');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error ?? widget.store.error;
    return Scaffold(
      backgroundColor: GLTheme.background,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            24,
            10,
            24,
            32 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: glBox(GLTheme.mint, 14),
                  child: const GLIcon('person.3', size: 22),
                ),
                const SizedBox(width: 10),
                Text('GROUPLY', style: gl(15, w800, 0.12)),
              ],
            ),
            const SizedBox(height: 18),
            const _PreviewCards(),
            const SizedBox(height: 18),
            Text(
              'Kerja kelompok yang beneran jalan.',
              style: gl(30, w700, -0.03),
            ),
            const SizedBox(height: 8),
            Text(
              'Bagi tugas, kirim hasil, review bareng, dan pantau progres grup dalam satu tempat.',
              style: gl(15, w400, 0, GLTheme.secondary, 4.5),
            ),
            const SizedBox(height: 18),
            GLTap.card(
              onTap: _busy ? null : () => showLoginSheet(context, widget.store),
              child: Container(
                height: 56,
                alignment: Alignment.center,
                decoration: glBox(Colors.black, 18),
                child: Text(
                  'Masuk dengan Akun',
                  style: gl(17, w600, 0, Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Akun Supabase terpisah dari persona demo di bawah.',
              textAlign: TextAlign.center,
              style: gl(12, w400, 0, GLTheme.secondary),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.center,
                  decoration: const ShapeDecoration(
                    color: GLTheme.butter,
                    shape: StadiumBorder(),
                  ),
                  child: Text('DEMO', style: gl(11, w700, 0.06)),
                ),
                const SizedBox(width: 6),
                Text('Masuk cepat sebagai', style: gl(13, w600)),
                if (_busy) ...[
                  const SizedBox(width: 8),
                  const CupertinoActivityIndicator(radius: 7),
                ],
              ],
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = (constraints.maxWidth - 8) / 2;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final persona in _personas)
                      SizedBox(
                        width: width,
                        child: _PersonaButton(
                          name: persona.name,
                          tint: persona.tint,
                          role: persona.role,
                          onTap: _busy
                              ? null
                              : () => _persona(persona.id, persona.name),
                        ),
                      ),
                  ],
                );
              },
            ),
            if (error != null) ...[
              const SizedBox(height: 18),
              GLFormError(error),
            ],
            const SizedBox(height: 18),
            Center(
              child: GLTap(
                onTap: () => showPrivacySheet(context),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  alignment: Alignment.center,
                  child: Text(
                    'Privasi & data',
                    style: gl(
                      14,
                      w600,
                    ).copyWith(decoration: TextDecoration.underline),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonaButton extends StatelessWidget {
  const _PersonaButton({
    required this.name,
    required this.tint,
    required this.role,
    required this.onTap,
  });
  final String name;
  final String tint;
  final String role;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => GLTap(
    onTap: onTap,
    label: 'Masuk demo sebagai $name, $role',
    child: Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
      decoration: glBox(Colors.white, 16, border: GLTheme.border),
      child: Row(
        children: [
          GLAvatar(user: {'name': name, 'tint': tint}, size: 32, fontSize: 11),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: gl(14, w600),
                ),
                Text(
                  role,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: gl(12, w400, 0, GLTheme.secondary),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Three tilted preview cards (Swift `previewCards`, 220pt tall).
class _PreviewCards extends StatelessWidget {
  const _PreviewCards();
  static const _deg = 3.141592653589793 / 180;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: 220,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth, h = constraints.maxHeight;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: h * 0.06,
                width: w * 0.7,
                child: Transform.rotate(
                  angle: -3 * _deg,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 16,
                    ),
                    decoration: ShapeDecoration(
                      color: GLTheme.butter,
                      shape: glShape(24),
                      shadows: const [
                        BoxShadow(
                          color: Color(0x1F000000),
                          blurRadius: 24,
                          offset: Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Perlu perhatian', style: gl(14, w700)),
                        const SizedBox(height: 6),
                        Text(
                          'Revisi diminta oleh Nadia',
                          style: gl(13, w400, 0, GLTheme.text2),
                        ),
                        const SizedBox(height: 6),
                        Text('Tulis script DDL SQL', style: gl(15, w600)),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: w * 0.34,
                top: h * 0.34,
                width: w * 0.66,
                child: Transform.rotate(
                  angle: 2.5 * _deg,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 16,
                    ),
                    decoration: ShapeDecoration(
                      color: Colors.white,
                      shape: glShape(24),
                      shadows: const [
                        BoxShadow(
                          color: Color(0x24000000),
                          blurRadius: 28,
                          offset: Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const GLChip(
                          label: 'Menunggu review',
                          icon: 'eye',
                          background: GLTheme.lavender,
                          height: 26,
                          fontSize: 12,
                          iconSize: 15,
                        ),
                        const SizedBox(height: 8),
                        Text('Draft diagram ERD', style: gl(15, w600)),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: w * 0.08,
                bottom: 0,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: w * 0.62),
                  child: Transform.rotate(
                    angle: -1.5 * _deg,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 14,
                      ),
                      decoration: const BoxDecoration(
                        color: GLTheme.lavender,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(18),
                          topRight: Radius.circular(18),
                          bottomRight: Radius.circular(18),
                          bottomLeft: Radius.circular(6),
                        ),
                      ),
                      child: Text('ERD udah aku kirim ya!', style: gl(14)),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

/// Swift `BackendLoginView` — inset-grouped form in a sheet. The Flutter
/// client has no Sign in with Apple yet, so only email/password is offered.
Future<void> showLoginSheet(BuildContext context, GrouplyStore store) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFFF2F2F7),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => _LoginSheet(store: store),
    );

class _LoginSheet extends StatefulWidget {
  const _LoginSheet({required this.store});
  final GrouplyStore store;
  @override
  State<_LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<_LoginSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _email.addListener(_changed);
    _password.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.signIn(_email.text.trim(), _password.text);
      _password.clear();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _section(List<Widget> rows, {String? header, String? footer}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (header != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
                child: Text(
                  header.toUpperCase(),
                  style: gl(13, w400, 0, const Color(0xFF6D6D72)),
                ),
              ),
            Container(
              decoration: glBox(Colors.white, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0)
                      const Padding(
                        padding: EdgeInsets.only(left: 16),
                        child: GLHairline(color: Color(0xFFE5E5EA)),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      child: rows[i],
                    ),
                  ],
                ],
              ),
            ),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
                child: Text(
                  footer,
                  style: gl(13, w400, 0, const Color(0xFF6D6D72)),
                ),
              ),
          ],
        ),
      );

  InputDecoration get _plain => const InputDecoration(
    border: InputBorder.none,
    isDense: true,
    contentPadding: EdgeInsets.symmetric(vertical: 2),
  );

  @override
  Widget build(BuildContext context) {
    final configured = widget.store.configured;
    final ready = _email.text.isNotEmpty && _password.text.isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text('Masuk Akun', style: gl(17, w600)),
                Positioned(
                  left: 16,
                  child: GLTap(
                    onTap: _busy ? null : () => Navigator.of(context).pop(),
                    child: Text(
                      'Batal',
                      style: gl(17, w400, 0, const Color(0xFF007AFF)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _section([
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Kerja bareng, di akunmu sendiri.',
                        style: gl(22, w700),
                      ),
                    ],
                  ),
                  Text(
                    'Data grup dan tugas disimpan di Supabase. Akun ini terpisah dari persona demo.',
                    style: gl(15, w400, 0, GLTheme.secondary),
                  ),
                ]),
                if (configured)
                  _section(
                    [
                      TextField(
                        key: const Key('backend-email'),
                        controller: _email,
                        enabled: !_busy,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.username],
                        textInputAction: TextInputAction.next,
                        style: gl(17),
                        decoration: _plain.copyWith(hintText: 'Email akun'),
                      ),
                      TextField(
                        key: const Key('backend-password'),
                        controller: _password,
                        enabled: !_busy,
                        obscureText: true,
                        autofillHints: const [AutofillHints.password],
                        style: gl(17),
                        decoration: _plain.copyWith(hintText: 'Kata sandi'),
                        onSubmitted: (_) => ready && !_busy ? _signIn() : null,
                      ),
                      _busy
                          ? const SizedBox(
                              height: 58,
                              child: Center(
                                child: CupertinoActivityIndicator(),
                              ),
                            )
                          : GLPrimaryButton(
                              key: const Key('backend-signin'),
                              title: 'Masuk ke Server',
                              icon: 'arrow.right',
                              onPressed: ready ? _signIn : null,
                            ),
                    ],
                    header: 'Akun email',
                    footer:
                        'Gunakan akun email yang sudah terdaftar. Login Apple, pendaftaran, dan pemulihan akun belum tersedia di versi Android/Flutter.',
                  )
                else
                  _section([
                    const GLNotice(
                      text:
                          'Konfigurasi server belum tersedia. Ikuti flutter/README.md, lalu build ulang aplikasinya.',
                    ),
                  ]),
                if (_error != null)
                  _section([
                    Text(
                      _error!,
                      key: const Key('backend-login-error'),
                      style: gl(17, w400, 0, const Color(0xFFFF3B30)),
                    ),
                  ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Root shell: tab content plus the Swift floating ink tab bar
/// (left/right 12, bottom 22, height 68, capsule, 56pt buttons).
class _Shell extends StatefulWidget {
  const _Shell({super.key, required this.store});
  final GrouplyStore store;
  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  int _tab = 0;
  String? _dismissedError;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final screens = [
      _Home(store: store, openTab: (index) => setState(() => _tab = index)),
      GroupsScreen(store: store),
      ChatsScreen(store: store),
      MyTasksScreen(store: store),
    ];
    final groupIDs = store.groups
        .where((group) => group.ids('memberIDs').contains(store.currentUserID))
        .map((group) => group.text('id'))
        .toSet();
    final unread = store.messages
        .where(
          (message) =>
              groupIDs.contains(message.text('groupID')) &&
              message.text('taskID').isEmpty &&
              message.text('senderID') != store.currentUserID &&
              !store.blockedUserIDs.contains(message.text('senderID')) &&
              !store.readMessageIDs.contains(message.text('id')),
        )
        .length;
    final media = MediaQuery.of(context);
    final error = store.error;
    return Scaffold(
      backgroundColor: GLTheme.background,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Column(
            children: [
              // Swift `safeAreaInset(edge: .top)` server error strip.
              if (!store.demoMode && error != null && error != _dismissedError)
                Container(
                  width: double.infinity,
                  color: GLTheme.butter,
                  padding: EdgeInsets.fromLTRB(
                    12,
                    media.padding.top + 12,
                    12,
                    12,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(child: Text(error, style: gl(13))),
                      const SizedBox(width: 8),
                      GLTap(
                        onTap: () => setState(() => _dismissedError = error),
                        child: Text('Tutup', style: gl(13, w600)),
                      ),
                    ],
                  ),
                ),
              Expanded(
                // Content ends 86pt above the safe area, under the tab bar.
                child: MediaQuery(
                  data: media.copyWith(
                    padding: media.padding.copyWith(
                      bottom: media.padding.bottom + 86,
                    ),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(_tab),
                    child: screens[_tab],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 22,
            child: _TabBar(
              index: _tab,
              unread: unread,
              onSelect: (index) => setState(() => _tab = index),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.index,
    required this.unread,
    required this.onSelect,
  });
  final int index;
  final int unread;
  final ValueChanged<int> onSelect;

  Widget _button(int i, String label, String icon, {int badge = 0}) {
    final active = index == i;
    final color = active ? GLTheme.ink : Colors.white.withValues(alpha: 0.78);
    return Expanded(
      child: Semantics(
        selected: active,
        button: true,
        label: badge > 0 ? '$label, $badge pesan baru' : label,
        child: ExcludeSemantics(
          child: GestureDetector(
            key: Key('tab-$i'),
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelect(i),
            child: Container(
              height: 56,
              decoration: ShapeDecoration(
                color: active ? Colors.white : Colors.transparent,
                shape: const StadiumBorder(),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      GLIcon(
                        active ? '$icon.fill' : icon,
                        // SF tab glyphs read larger than Cupertino's at 23.
                        size: 27,
                        color: color,
                      ),
                      if (badge > 0)
                        Positioned(
                          right: -8,
                          top: -2,
                          child: Container(
                            constraints: const BoxConstraints(
                              minWidth: 18,
                              minHeight: 18,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            alignment: Alignment.center,
                            decoration: const ShapeDecoration(
                              color: GLTheme.mint,
                              shape: StadiumBorder(
                                side: BorderSide(color: GLTheme.ink, width: 2),
                              ),
                            ),
                            child: Text(
                              '$badge',
                              textScaler: TextScaler.noScaling,
                              style: gl(11, w700, 0, GLTheme.ink),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      textScaler: TextScaler.noScaling,
                      style: gl(12, w600, 0, color),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
    height: 68,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    decoration: const ShapeDecoration(
      color: GLTheme.ink,
      shape: StadiumBorder(),
      shadows: [
        BoxShadow(
          color: Color(0x66000000),
          blurRadius: 30,
          offset: Offset(0, 16),
        ),
      ],
    ),
    child: Row(
      children: [
        _button(0, 'Beranda', 'house'),
        const SizedBox(width: 2),
        _button(1, 'Grup', 'person.2'),
        const SizedBox(width: 2),
        _button(2, 'Chat', 'bubble.left', badge: unread),
        const SizedBox(width: 2),
        _button(3, 'Tugas Saya', 'checkmark.circle'),
      ],
    ),
  );
}

/// Swift `ActivityStyle` — icon + tint keyed by the activity verb.
({String icon, Color tint}) _activityStyle(String verb) {
  if (verb.startsWith('mengirim')) {
    return (icon: 'square.and.arrow.up', tint: GLTheme.lavender);
  }
  if (verb.startsWith('menyetujui')) {
    return (icon: 'checkmark.circle', tint: GLTheme.mint);
  }
  if (verb.startsWith('meminta')) {
    return (icon: 'arrow.uturn.backward', tint: GLTheme.coral);
  }
  if (verb.startsWith('membuat')) return (icon: 'checklist', tint: GLTheme.sky);
  if (verb.startsWith('mengalihkan')) {
    return (icon: 'arrow.left.arrow.right', tint: GLTheme.sky);
  }
  return (icon: 'pencil', tint: GLTheme.butter);
}

/// Swift `HomeView` (Beranda).
class _Home extends StatelessWidget {
  const _Home({required this.store, required this.openTab});
  final GrouplyStore store;
  final ValueChanged<int> openTab;

  String get _me => store.currentUserID;

  void _push(BuildContext context, Widget screen) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => screen));

  bool _member(String groupID) =>
      store.group(groupID)?.ids('memberIDs').contains(_me) ?? false;

  DateTime _due(JsonMap task) => task.date('dueAt') ?? DateTime(9999);

  @override
  Widget build(BuildContext context) {
    final now = store.now;
    final myGroups = store.groups
        .where((group) => group.ids('memberIDs').contains(_me))
        .toList();
    // Prototype `liveTasks`: tasks in non-archived projects of my groups.
    final live = store.tasks.where((task) {
      final project = store.project(task.text('projectID'));
      return project != null &&
          project.text('status') != 'archived' &&
          _member(project.text('groupID'));
    }).toList();
    final mineOpen = live.where(
      (t) =>
          t.text('assigneeID') == _me &&
          t.text('status') != 'done' &&
          t.text('status') != 'in_review',
    );
    final attention = <({JsonMap task, String icon, String reason})>[
      for (final t in mineOpen.where(
        (t) => t.text('status') == 'needs_revision',
      ))
        (
          task: t,
          icon: 'arrow.uturn.backward',
          reason: () {
            final subs = (t['submissions'] as List? ?? []).whereType<JsonMap>();
            final by = subs.isEmpty
                ? null
                : store.user(subs.last.text('reviewerID'))?.text('name');
            return 'Revisi diminta${by == null ? '' : ' oleh $by'}';
          }(),
        ),
      for (final t in mineOpen.where(
        (t) =>
            t.text('status') != 'needs_revision' &&
            GLFormat.isOverdue(_due(t), t.text('status'), now),
      ))
        (
          task: t,
          icon: 'exclamationmark.circle',
          reason: 'Terlambat sejak ${GLFormat.date(_due(t))}',
        ),
    ];
    final reviews = live
        .where(
          (t) => t.text('reviewerID') == _me && t.text('status') == 'in_review',
        )
        .toList();
    final skip = attention.map((item) => item.task.text('id')).toSet();
    final end = now.add(const Duration(days: 7));
    final deadlines =
        mineOpen
            .where(
              (t) =>
                  !skip.contains(t.text('id')) &&
                  !_due(t).isBefore(now) &&
                  !_due(t).isAfter(end),
            )
            .toList()
          ..sort((a, b) => _due(a).compareTo(_due(b)));
    final activeProjects = store.projects
        .where(
          (p) => p.text('status') == 'active' && _member(p.text('groupID')),
        )
        .toList();
    final activity =
        store.messages
            .where(
              (m) =>
                  m.text('kind') == 'activity' &&
                  m.text('taskID').isEmpty &&
                  _member(m.text('groupID')) &&
                  store.task(m.text('targetTaskID')) != null,
            )
            .toList()
          ..sort(
            (a, b) => (b.date('createdAt') ?? DateTime(0)).compareTo(
              a.date('createdAt') ?? DateTime(0),
            ),
          );
    final user = store.user(_me);

    final children = <Widget>[
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  GLFormat.longDate(now),
                  style: gl(15, w400, 0, GLTheme.secondary),
                ),
                const SizedBox(height: 2),
                Text(
                  'Halo, ${user?.text('name') ?? 'teman'}',
                  style: gl(30, w700, -0.03),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GLTap(
            key: const Key('open-profile'),
            label: 'Profil dan pengaturan',
            onTap: () => _push(context, ProfileScreen(store: store)),
            child: GLAvatar(user: user, size: 48, fontSize: 15),
          ),
        ],
      ),
      Row(
        children: [
          Icon(
            glSymbol(
              store.demoMode
                  ? 'iphone'
                  : 'externaldrive.connected.to.line.below',
            ),
            size: 13,
            color: GLTheme.secondary,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              store.demoMode
                  ? 'Demo lokal · data contoh'
                  : 'Akun server · Supabase',
              style: gl(12, w500, 0, GLTheme.secondary),
            ),
          ),
        ],
      ),
      if (myGroups.isEmpty)
        _emptyGroups()
      else ...[
        if (store.demoMode && store.error != null)
          GLNotice(text: store.error!, color: GLTheme.coral),
        _attentionCard(context, attention),
        if (reviews.isNotEmpty) _reviewCard(context, reviews, now),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GLSectionHeading(
              title: 'Deadline terdekat',
              actionTitle: 'Semua tugas',
              onAction: () => openTab(3),
            ),
            const SizedBox(height: 12),
            _deadlineList(context, deadlines, now),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GLSectionHeading(
              title: 'Proyek aktif',
              actionTitle: 'Semua grup',
              onAction: () => openTab(1),
            ),
            if (activeProjects.isEmpty) ...[
              const SizedBox(height: 12),
              GLSurface(
                padding: const EdgeInsets.all(18),
                child: Text(
                  'Belum ada proyek aktif. Buka grup untuk membuat atau melihat proyek.',
                  style: gl(15, w400, 0, GLTheme.secondary, 4),
                ),
              ),
            ],
            for (final project in activeProjects) ...[
              const SizedBox(height: 12),
              GLTap.card(
                onTap: () => _push(
                  context,
                  ProjectScreen(store: store, projectID: project.text('id')),
                ),
                child: _HomeProjectCard(store: store, project: project),
              ),
            ],
          ],
        ),
        if (activity.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Aktivitas terbaru', style: gl(21, w700, -0.02)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                decoration: glBox(Colors.white, 24),
                child: Column(
                  children: [
                    for (final message in activity.take(3))
                      _activityRow(context, message, now),
                  ],
                ),
              ),
            ],
          ),
      ],
    ];

    return Scaffold(
      backgroundColor: GLTheme.background,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator.adaptive(
          onRefresh: store.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(
              20,
              10,
              20,
              MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: 22),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _cardHeader(String title, int count) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Expanded(child: Text(title, style: gl(19, w700, -0.02))),
        GLCountBadge(count: count),
      ],
    ),
  );

  Widget _row({
    required Widget leading,
    required List<Widget> lines,
    required Color chevron,
    required VoidCallback onTap,
  }) => GLTap(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: GLTheme.ink.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: lines,
            ),
          ),
          GLIcon('chevron.right', size: 22, color: chevron),
        ],
      ),
    ),
  );

  Widget _attentionCard(
    BuildContext context,
    List<({JsonMap task, String icon, String reason})> attention,
  ) => Container(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
    decoration: glBox(GLTheme.butter, 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cardHeader('Perlu perhatian', attention.length),
        if (attention.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 14),
            child: Row(
              children: [
                const GLIcon(
                  'checkmark.circle',
                  size: 20,
                  color: GLTheme.text2,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Semua aman, tidak ada yang mendesak.',
                    style: gl(15, w400, 0, GLTheme.text2),
                  ),
                ),
              ],
            ),
          ),
        for (final item in attention)
          _row(
            onTap: () => _push(
              context,
              TaskScreen(store: store, taskID: item.task.text('id')),
            ),
            chevron: GLTheme.text2,
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                shape: BoxShape.circle,
              ),
              child: GLIcon(item.icon, size: 20),
            ),
            lines: [
              Text(item.reason, style: gl(13, w600, 0, GLTheme.text2)),
              const SizedBox(height: 2),
              Text(item.task.text('title'), style: gl(16, w600)),
            ],
          ),
      ],
    ),
  );

  Widget _reviewCard(
    BuildContext context,
    List<JsonMap> reviews,
    DateTime now,
  ) => Container(
    padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
    decoration: glBox(GLTheme.lavender, 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cardHeader('Menunggu review kamu', reviews.length),
        for (final task in reviews)
          Builder(
            builder: (context) {
              final subs = (task['submissions'] as List? ?? [])
                  .whereType<JsonMap>()
                  .toList();
              final submitted = subs.isEmpty
                  ? null
                  : subs.last.date('createdAt');
              final hours = submitted == null
                  ? null
                  : now.difference(submitted).inHours;
              final assignee = store.user(task.text('assigneeID'));
              return _row(
                onTap: () => _push(
                  context,
                  TaskScreen(store: store, taskID: task.text('id')),
                ),
                chevron: GLTheme.text3,
                leading: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.7),
                      width: 2,
                      strokeAlign: BorderSide.strokeAlignCenter,
                    ),
                  ),
                  child: GLAvatar(user: assignee, size: 40, fontSize: 13),
                ),
                lines: [
                  Text(task.text('title'), style: gl(16, w600)),
                  const SizedBox(height: 3),
                  // flex-wrap: the stale chip drops to its own line when it doesn't fit.
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Dari ${assignee?.text('name') ?? 'anggota'} · revisi ${subs.length}',
                        style: gl(13, w400, 0, GLTheme.text3),
                      ),
                      if (hours != null && hours > 48)
                        GLChip(
                          label: 'Menunggu $hours jam',
                          icon: 'list.bullet.clipboard',
                          background: Colors.white,
                          outlined: true,
                          height: 24,
                          fontSize: 12,
                          iconSize: 15,
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
      ],
    ),
  );

  Widget _deadlineList(
    BuildContext context,
    List<JsonMap> deadlines,
    DateTime now,
  ) => GLSurface(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (deadlines.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'Tidak ada deadline 7 hari ke depan.',
              style: gl(15, w400, 0, GLTheme.secondary),
            ),
          ),
        for (final task in deadlines)
          GLTap(
            onTap: () => _push(
              context,
              TaskScreen(store: store, taskID: task.text('id')),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: GLTheme.border)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 50,
                    height: 54,
                    decoration: glBox(GLTheme.muted, 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${_due(task).toLocal().day}',
                          style: gl(20, w700),
                        ),
                        Text(
                          GLFormat.weekday(_due(task)),
                          style: gl(12, w600, 0, GLTheme.secondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(task.text('title'), style: gl(16, w600)),
                        const SizedBox(height: 3),
                        Text(
                          '${GLFormat.due(_due(task), task.text('status'), now)} · ${GLStatus.label(task.text('status'))}',
                          style: gl(13, w400, 0, GLTheme.secondary),
                        ),
                      ],
                    ),
                  ),
                  const GLIcon(
                    'chevron.right',
                    size: 22,
                    color: GLTheme.secondary,
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  Widget _activityRow(BuildContext context, JsonMap message, DateTime now) {
    final style = _activityStyle(message.text('text'));
    final sender = message.text('senderID');
    final actor = sender == _me
        ? 'Kamu'
        : store.user(sender)?.text('name') ?? 'Anggota';
    final target = store.task(message.text('targetTaskID'));
    final stamp = GLFormat.activityStamp(message.date('createdAt') ?? now, now);
    return GLTap(
      onTap: target == null
          ? null
          : () => _push(
              context,
              TaskScreen(store: store, taskID: target.text('id')),
            ),
      child: Container(
        constraints: const BoxConstraints(minHeight: 60),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: GLTheme.border)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: glBox(style.tint, 14),
              child: GLIcon(style.icon, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$actor ${message.text('text')} · $stamp',
                    style: gl(13, w400, 0, GLTheme.text2),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    target?.text('title') ?? 'Tugas tidak tersedia',
                    style: gl(15, w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyGroups() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 22),
    decoration: glBox(Colors.white, 32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: glBox(GLTheme.mint, 20),
          child: const GLIcon('person.badge.plus', size: 28),
        ),
        const SizedBox(height: 14),
        Text('Mulai dari grupmu', style: gl(22, w700, -0.02)),
        const SizedBox(height: 14),
        Text(
          'Kamu belum tergabung di grup mana pun. Buat grup lalu bagikan kode undangan, atau gabung dengan kode dari temanmu.',
          style: gl(15, w400, 0, GLTheme.secondary, 4),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: GLInkButton(
                radius: 18,
                height: 52,
                onPressed: () => openTab(1),
                child: Text('Buat grup', style: gl(15, w600)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GLOutlineButton(
                title: 'Gabung dengan kode',
                height: 52,
                radius: 18,
                onPressed: () => openTab(1),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// Swift `HomeProjectCard`.
class _HomeProjectCard extends StatelessWidget {
  const _HomeProjectCard({required this.store, required this.project});
  final GrouplyStore store;
  final JsonMap project;
  @override
  Widget build(BuildContext context) {
    final group = store.group(project.text('groupID'));
    final tasks = store.tasks
        .where((t) => t.text('projectID') == project.text('id'))
        .toList();
    final done = tasks.where((t) => t.text('status') == 'done').length;
    final due = project.date('dueAt');
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
        decoration: glBox(Colors.white, 24, shadow: true),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: glHex(group?.text('tint'), Colors.white),
                shape: BoxShape.circle,
              ),
              child: GLIcon(
                group?.text('icon').isNotEmpty == true
                    ? group!.text('icon')
                    : 'folder',
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(project.text('title'), style: gl(16, w600)),
                  const SizedBox(height: 1),
                  Text(
                    '${group?.text('name') ?? ''} · deadline ${due == null ? '-' : GLFormat.date(due)}',
                    style: gl(13, w400, 0, GLTheme.secondary),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: GLProgressBar(
                          value: tasks.isEmpty ? 0 : done / tasks.length,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '$done/${tasks.length} selesai',
                        style: gl(13, w600).copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
