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
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    if (dark != GLTheme.dark) {
      GLTheme.dark = dark;
      // Tokens are plain getters, so widgets (incl. const ones and pushed
      // routes) don't depend on them: rebuild every element once, keeping
      // navigation and state.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        void rebuild(Element element) {
          element.markNeedsBuild();
          element.visitChildren(rebuild);
        }

        if (mounted) (context as Element).visitChildren(rebuild);
      });
    }
    return MaterialApp(
      title: 'Grouply',
      debugShowCheckedModeBanner: false,
      theme: GLTheme.data,
      scrollBehavior: CupertinoScrollBehavior(),
      locale: Locale('id', 'ID'),
      supportedLocales: [Locale('id', 'ID')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      navigatorKey: _navigator,
      scaffoldMessengerKey: _messenger,
      home: AnimatedBuilder(
        animation: widget.store,
        builder: (_, _) {
          if (widget.store.loading && !widget.store.authenticated) {
            return _Restoring();
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
}

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
            child: GLIcon('person.3', size: 36),
          ),
          SizedBox(height: 16),
          Text('GROUPLY', style: gl(15, w800, 0.12)),
          SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CupertinoActivityIndicator(radius: 8),
              SizedBox(width: 8),
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
  @override
  Widget build(BuildContext context) {
    final error = widget.store.error;
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
                  child: GLIcon('person.3', size: 22),
                ),
                SizedBox(width: 10),
                Text('GROUPLY', style: gl(15, w800, 0.12)),
              ],
            ),
            SizedBox(height: 18),
            _PreviewCards(),
            SizedBox(height: 18),
            Text(
              'Kerja kelompok yang beneran jalan.',
              style: gl(30, w700, -0.03),
            ),
            SizedBox(height: 8),
            Text(
              'Bagi tugas, kirim hasil, review bareng, dan pantau progres grup dalam satu tempat.',
              style: gl(15, w400, 0, GLTheme.secondary, 4.5),
            ),
            SizedBox(height: 18),
            GLTap.card(
              onTap: () => showLoginSheet(context, widget.store),
              child: Container(
                height: 56,
                alignment: Alignment.center,
                decoration: glBox(
                  Color(GLTheme.dark ? 0xFFECEDEE : 0xFF000000),
                  18,
                ),
                child: Text(
                  'Masuk dengan Akun',
                  style: gl(17, w600, 0, GLTheme.onInk),
                ),
              ),
            ),
            const SizedBox(height: 10),
            GLOutlineButton(
              key: const Key('welcome-signup'),
              title: 'Belum punya akun? Daftar',
              height: 56,
              radius: 18,
              fontSize: 16,
              onPressed: () =>
                  showLoginSheet(context, widget.store, signUp: true),
            ),
            if (error != null) ...[SizedBox(height: 18), GLFormError(error)],
            SizedBox(height: 18),
            Center(
              child: GLTap(
                onTap: () => showPrivacySheet(context),
                child: Container(
                  constraints: BoxConstraints(minHeight: 44),
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

/// Three tilted preview cards (Swift `previewCards`, 220pt tall).
class _PreviewCards extends StatelessWidget {
  const _PreviewCards();
  static final _deg = 3.141592653589793 / 180;
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
                    padding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    decoration: ShapeDecoration(
                      color: GLTheme.butter,
                      shape: glShape(24),
                      shadows: [
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
                        SizedBox(height: 6),
                        Text(
                          'Revisi diminta oleh Nadia',
                          style: gl(13, w400, 0, GLTheme.text2),
                        ),
                        SizedBox(height: 6),
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
                    padding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    decoration: ShapeDecoration(
                      color: GLTheme.surface,
                      shape: glShape(24),
                      shadows: [
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
                        GLChip(
                          label: 'Menunggu review',
                          icon: 'eye',
                          background: GLTheme.lavender,
                          height: 26,
                          fontSize: 12,
                          iconSize: 15,
                        ),
                        SizedBox(height: 8),
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
                      padding: EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 14,
                      ),
                      decoration: BoxDecoration(
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

/// Account sheet in the same Soft Future style as the other GL sheets:
/// Masuk / Daftar toggle, labelled white fields, and an emailed-code reset.
/// The Flutter client has no Sign in with Apple yet.
Future<void> showLoginSheet(
  BuildContext context,
  GrouplyStore store, {
  bool signUp = false,
}) => showGLSheet<void>(
  context,
  title: 'Akun Grouply',
  subtitle: 'Data grup dan tugas tersimpan aman di server Grouply.',
  builder: (_) => _LoginSheet(store: store, signUp: signUp),
);

class _LoginSheet extends StatefulWidget {
  const _LoginSheet({required this.store, this.signUp = false});
  final GrouplyStore store;
  final bool signUp;
  @override
  State<_LoginSheet> createState() => _LoginSheetState();
}

enum _AuthMode { signIn, signUp, forgot }

class _LoginSheetState extends State<_LoginSheet> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();
  var _mode = _AuthMode.signIn;
  bool _busy = false, _codeSent = false, _showPassword = false;
  String? _error, _notice;

  static const _minPassword = 8;

  @override
  void initState() {
    super.initState();
    if (widget.signUp) _mode = _AuthMode.signUp;
    for (final field in [_name, _email, _password, _code]) {
      field.addListener(_changed);
    }
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    for (final field in [_name, _email, _password, _code]) {
      field.dispose();
    }
    super.dispose();
  }

  void _switch(_AuthMode mode) => setState(() {
    _mode = mode;
    _codeSent = false;
    _showPassword = false;
    _error = null;
    _notice = null;
    _password.clear();
    _code.clear();
  });

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _done() {
    _password.clear();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _signIn() => _run(() async {
    await widget.store.signIn(_email.text.trim(), _password.text);
    _done();
  });

  Future<void> _signUp() => _run(() async {
    final signedIn = await widget.store.signUp(
      _name.text,
      _email.text,
      _password.text,
    );
    if (signedIn) return _done();
    if (!mounted) return;
    _switch(_AuthMode.signIn);
    setState(
      () => _notice =
          'Akun dibuat. Buka email konfirmasi yang kami kirim, lalu masuk.',
    );
  });

  Future<void> _sendCode() => _run(() async {
    await widget.store.sendPasswordReset(_email.text);
    if (!mounted) return;
    setState(() {
      _codeSent = true;
      _notice =
          'Jika ${_email.text.trim()} terdaftar, kode 6 digit sudah dikirim. Cek juga folder spam.';
    });
  });

  Future<void> _resetPassword() => _run(() async {
    await widget.store.resetPassword(_email.text, _code.text, _password.text);
    _done();
  });

  bool get _emailValid =>
      RegExp(r'^\S+@\S+\.\S+$').hasMatch(_email.text.trim());
  bool get _passwordStrong => _password.text.length >= _minPassword;

  bool get _ready => switch (_mode) {
    _AuthMode.signIn => _email.text.isNotEmpty && _password.text.isNotEmpty,
    _AuthMode.signUp =>
      _name.text.trim().isNotEmpty && _emailValid && _passwordStrong,
    _AuthMode.forgot =>
      _emailValid &&
          (!_codeSent || (_code.text.trim().length >= 6 && _passwordStrong)),
  };

  VoidCallback get _submit => switch (_mode) {
    _AuthMode.signIn => _signIn,
    _AuthMode.signUp => _signUp,
    _AuthMode.forgot => _codeSent ? _resetPassword : _sendCode,
  };

  void _submitIfReady() => _ready && !_busy ? _submit() : null;

  Widget _input(
    String key,
    TextEditingController controller,
    String hint, {
    TextInputType? keyboard,
    Iterable<String>? autofill,
    int? maxLength,
    bool last = false,
    bool password = false,
    TextStyle? style,
    TextAlign align = TextAlign.start,
    TextCapitalization capitalization = TextCapitalization.none,
  }) => TextField(
    key: Key(key),
    controller: controller,
    enabled: !_busy,
    obscureText: password && !_showPassword,
    keyboardType: keyboard,
    autocorrect: false,
    enableSuggestions: !password,
    autofillHints: autofill,
    maxLength: maxLength,
    textAlign: align,
    textCapitalization: capitalization,
    textInputAction: last ? TextInputAction.done : TextInputAction.next,
    onSubmitted: last ? (_) => _submitIfReady() : null,
    cursorColor: GLTheme.ink,
    style: style ?? gl(16, w400, 0, GLTheme.ink),
    decoration: glInputDecoration(hint: hint).copyWith(
      suffixIcon: password
          ? GLTap(
              label: _showPassword
                  ? 'Sembunyikan kata sandi'
                  : 'Tampilkan kata sandi',
              onTap: () => setState(() => _showPassword = !_showPassword),
              child: SizedBox(
                width: 48,
                height: 48,
                child: GLIcon(
                  _showPassword ? 'eye.slash' : 'eye',
                  size: 20,
                  color: GLTheme.secondary,
                ),
              ),
            )
          : null,
    ),
  );

  Widget _link(String key, String text, VoidCallback onTap) => GLTap(
    key: Key(key),
    onTap: _busy ? null : onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: gl(15, w600).copyWith(decoration: TextDecoration.underline),
      ),
    ),
  );

  /// Masuk / Daftar toggle, styled like the project filter pills.
  Widget _modeToggle() => Container(
    height: 52,
    padding: const EdgeInsets.all(4),
    decoration: ShapeDecoration(
      color: GLTheme.surface,
      shape: StadiumBorder(side: BorderSide(color: GLTheme.border)),
    ),
    child: Row(
      children: [
        for (final (mode, label, key) in [
          (_AuthMode.signIn, 'Masuk', 'auth-to-signin'),
          (_AuthMode.signUp, 'Daftar', 'auth-to-signup'),
        ])
          Expanded(
            child: Semantics(
              selected: _mode == mode,
              button: true,
              child: GLTap(
                key: Key(key),
                onTap: _busy || _mode == mode ? null : () => _switch(mode),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  alignment: Alignment.center,
                  decoration: ShapeDecoration(
                    color: _mode == mode ? GLTheme.ink : Colors.transparent,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    label,
                    style: gl(
                      15,
                      w600,
                      0,
                      _mode == mode ? GLTheme.onInk : GLTheme.secondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _passwordRule() => Row(
    children: [
      GLIcon(
        _passwordStrong ? 'checkmark.circle' : 'info.circle',
        size: 16,
        color: _passwordStrong ? GLTheme.success : GLTheme.secondary,
      ),
      const SizedBox(width: 6),
      Text(
        'Minimal $_minPassword karakter',
        style: gl(
          13,
          w500,
          0,
          _passwordStrong ? GLTheme.success : GLTheme.secondary,
        ),
      ),
    ],
  );

  List<Widget> _accountForm() {
    final signUp = _mode == _AuthMode.signUp;
    return [
      _modeToggle(),
      if (_notice != null)
        GLNotice(
          key: const Key('backend-login-notice'),
          text: _notice!,
          color: GLTheme.mint,
          icon: 'checkmark.circle',
        ),
      if (signUp)
        GLField(
          'Nama',
          required: true,
          trailing: 'Terlihat oleh anggota grup',
          child: _input(
            'backend-name',
            _name,
            'Contoh: Ayu Lestari',
            autofill: const [AutofillHints.name],
            maxLength: 80,
            capitalization: TextCapitalization.words,
          ),
        ),
      GLField(
        'Email',
        required: signUp,
        child: _input(
          'backend-email',
          _email,
          'nama@kampus.ac.id',
          keyboard: TextInputType.emailAddress,
          autofill: const [AutofillHints.username],
        ),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GLField(
            'Kata sandi',
            required: signUp,
            child: _input(
              'backend-password',
              _password,
              signUp ? 'Buat kata sandi' : 'Kata sandi akunmu',
              autofill: [
                signUp ? AutofillHints.newPassword : AutofillHints.password,
              ],
              password: true,
              last: true,
            ),
          ),
          const SizedBox(height: 8),
          if (signUp)
            _passwordRule()
          else
            Align(
              alignment: Alignment.centerRight,
              child: _link('auth-to-forgot', 'Lupa kata sandi?', () {
                _switch(_AuthMode.forgot);
              }),
            ),
        ],
      ),
      if (_error != null)
        GLFormError(_error!, key: const Key('backend-login-error')),
      GLSubmitButton(
        key: Key('backend-${_mode.name}'),
        title: signUp
            ? (_busy ? 'Membuat akun…' : 'Buat akun')
            : (_busy ? 'Masuk…' : 'Masuk'),
        busy: _busy,
        onPressed: _ready ? _submit : null,
      ),
      Text(
        signUp
            ? 'Dengan mendaftar, kamu bisa membuat grup atau bergabung lewat kode undangan.'
            : 'Login Apple belum tersedia di versi Android/Flutter.',
        textAlign: TextAlign.center,
        style: gl(13, w400, 0, GLTheme.secondary, 3),
      ),
    ];
  }

  List<Widget> _forgotForm() => [
    Row(
      children: [
        GLTap(
          key: const Key('auth-back'),
          label: 'Kembali ke Masuk',
          onTap: _busy ? null : () => _switch(_AuthMode.signIn),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: GLTheme.chip,
              shape: BoxShape.circle,
            ),
            child: const GLIcon('arrow.left', size: 20),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Atur ulang kata sandi', style: gl(18, w700, -0.01)),
              const SizedBox(height: 2),
              Text(
                _codeSent
                    ? 'Langkah 2 dari 2 · Masukkan kode'
                    : 'Langkah 1 dari 2 · Kirim kode ke email',
                style: gl(13, w500, 0, GLTheme.secondary),
              ),
            ],
          ),
        ),
      ],
    ),
    if (_notice != null)
      GLNotice(
        key: const Key('backend-login-notice'),
        text: _notice!,
        color: GLTheme.mint,
        icon: 'checkmark.circle',
      ),
    if (!_codeSent)
      GLField(
        'Email akun',
        required: true,
        child: _input(
          'backend-email',
          _email,
          'nama@kampus.ac.id',
          keyboard: TextInputType.emailAddress,
          autofill: const [AutofillHints.username],
          last: true,
        ),
      )
    else ...[
      GLField(
        'Kode dari email',
        required: true,
        child: _input(
          'backend-code',
          _code,
          '••••••',
          keyboard: TextInputType.number,
          autofill: const [AutofillHints.oneTimeCode],
          maxLength: 10,
          align: TextAlign.center,
          style: gl(22, w700, 0.3, GLTheme.ink),
        ),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GLField(
            'Kata sandi baru',
            required: true,
            child: _input(
              'backend-password',
              _password,
              'Buat kata sandi baru',
              autofill: const [AutofillHints.newPassword],
              password: true,
              last: true,
            ),
          ),
          const SizedBox(height: 8),
          _passwordRule(),
        ],
      ),
    ],
    if (_error != null)
      GLFormError(_error!, key: const Key('backend-login-error')),
    GLSubmitButton(
      key: Key(_codeSent ? 'backend-forgot-code' : 'backend-forgot'),
      title: _codeSent
          ? (_busy ? 'Menyimpan…' : 'Simpan kata sandi')
          : (_busy ? 'Mengirim…' : 'Kirim kode'),
      busy: _busy,
      onPressed: _ready ? _submit : null,
    ),
    if (_codeSent)
      Center(child: _link('auth-resend', 'Kirim ulang kode', _sendCode)),
  ];

  @override
  Widget build(BuildContext context) {
    final children = !widget.store.configured
        ? const [
            GLNotice(
              text:
                  'Konfigurasi server belum tersedia. Ikuti flutter/README.md, lalu build ulang aplikasinya.',
            ),
          ]
        : _mode == _AuthMode.forgot
        ? _forgotForm()
        : _accountForm();
    return PopScope(
      canPop: !_busy,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final child in children) ...[
              if (child != children.first) const SizedBox(height: 16),
              child,
            ],
          ],
        ),
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
              if (error != null && error != _dismissedError)
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
                      SizedBox(width: 8),
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
    final color = active ? GLTheme.tabActiveInk : GLTheme.tabInactive;
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
                color: active ? GLTheme.tabActive : Colors.transparent,
                shape: StadiumBorder(),
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
                            constraints: BoxConstraints(
                              minWidth: 18,
                              minHeight: 18,
                            ),
                            padding: EdgeInsets.symmetric(horizontal: 5),
                            alignment: Alignment.center,
                            decoration: ShapeDecoration(
                              color: GLTheme.mint,
                              shape: StadiumBorder(
                                side: BorderSide(
                                  color: GLTheme.tabBar,
                                  width: 2,
                                ),
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
                  SizedBox(height: 1),
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
    padding: EdgeInsets.symmetric(horizontal: 6),
    decoration: ShapeDecoration(
      color: GLTheme.tabBar,
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
        SizedBox(width: 2),
        _button(1, 'Grup', 'person.2'),
        SizedBox(width: 2),
        _button(2, 'Chat', 'bubble.left', badge: unread),
        SizedBox(width: 2),
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
    final end = now.add(Duration(days: 7));
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
                SizedBox(height: 2),
                Text(
                  'Halo, ${user?.text('name') ?? 'teman'}',
                  style: gl(30, w700, -0.03),
                ),
              ],
            ),
          ),
          SizedBox(width: 12),
          GLTap(
            key: Key('open-profile'),
            label: 'Profil dan pengaturan',
            onTap: () => _push(context, ProfileScreen(store: store)),
            child: GLAvatar(user: user, size: 48, fontSize: 15),
          ),
        ],
      ),
      Row(
        children: [
          Icon(
            glSymbol('externaldrive.connected.to.line.below'),
            size: 13,
            color: GLTheme.secondary,
          ),
          SizedBox(width: 6),
          Flexible(
            child: Text(
              'Akun server · Supabase',
              style: gl(12, w500, 0, GLTheme.secondary),
            ),
          ),
        ],
      ),
      if (myGroups.isEmpty)
        _emptyGroups()
      else ...[
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
            SizedBox(height: 12),
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
              SizedBox(height: 12),
              GLSurface(
                padding: EdgeInsets.all(18),
                child: Text(
                  'Belum ada proyek aktif. Buka grup untuk membuat atau melihat proyek.',
                  style: gl(15, w400, 0, GLTheme.secondary, 4),
                ),
              ),
            ],
            for (final project in activeProjects) ...[
              SizedBox(height: 12),
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
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: glBox(GLTheme.surface, 24),
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
            physics: AlwaysScrollableScrollPhysics(
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
                if (i > 0) SizedBox(height: 22),
                children[i],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _cardHeader(String title, int count) => Padding(
    padding: EdgeInsets.only(bottom: 4),
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
      constraints: BoxConstraints(minHeight: 60),
      padding: EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: GLTheme.ink.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          leading,
          SizedBox(width: 12),
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
    padding: EdgeInsets.fromLTRB(18, 18, 18, 8),
    decoration: glBox(GLTheme.butter, 28),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cardHeader('Perlu perhatian', attention.length),
        if (attention.isEmpty)
          Padding(
            padding: EdgeInsets.only(top: 12, bottom: 14),
            child: Row(
              children: [
                GLIcon('checkmark.circle', size: 20, color: GLTheme.text2),
                SizedBox(width: 8),
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
                color: GLTheme.onInk.withValues(alpha: 0.7),
                shape: BoxShape.circle,
              ),
              child: GLIcon(item.icon, size: 20),
            ),
            lines: [
              Text(item.reason, style: gl(13, w600, 0, GLTheme.text2)),
              SizedBox(height: 2),
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
    padding: EdgeInsets.fromLTRB(18, 18, 18, 8),
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
                      color: GLTheme.onInk.withValues(alpha: 0.7),
                      width: 2,
                      strokeAlign: BorderSide.strokeAlignCenter,
                    ),
                  ),
                  child: GLAvatar(user: assignee, size: 40, fontSize: 13),
                ),
                lines: [
                  Text(task.text('title'), style: gl(16, w600)),
                  SizedBox(height: 3),
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
                          background: GLTheme.surface,
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
    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (deadlines.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
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
              padding: EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
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
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(task.text('title'), style: gl(16, w600)),
                        SizedBox(height: 3),
                        Text(
                          '${GLFormat.due(_due(task), task.text('status'), now)} · ${GLStatus.label(task.text('status'))}',
                          style: gl(13, w400, 0, GLTheme.secondary),
                        ),
                      ],
                    ),
                  ),
                  GLIcon('chevron.right', size: 22, color: GLTheme.secondary),
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
        constraints: BoxConstraints(minHeight: 60),
        padding: EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
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
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$actor ${message.text('text')} · $stamp',
                    style: gl(13, w400, 0, GLTheme.text2),
                  ),
                  SizedBox(height: 1),
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
    padding: EdgeInsets.symmetric(vertical: 28, horizontal: 22),
    decoration: glBox(GLTheme.surface, 32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: glBox(GLTheme.mint, 20),
          child: GLIcon('person.badge.plus', size: 28),
        ),
        SizedBox(height: 14),
        Text('Mulai dari grupmu', style: gl(22, w700, -0.02)),
        SizedBox(height: 14),
        Text(
          'Kamu belum tergabung di grup mana pun. Buat grup lalu bagikan kode undangan, atau gabung dengan kode dari temanmu.',
          style: gl(15, w400, 0, GLTheme.secondary, 4),
        ),
        SizedBox(height: 20),
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
            SizedBox(width: 10),
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
        padding: EdgeInsets.fromLTRB(14, 14, 16, 14),
        decoration: glBox(GLTheme.surface, 24, shadow: true),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: glTint(group?.text('tint'), GLTheme.surface),
                shape: BoxShape.circle,
              ),
              child: GLIcon(
                group?.text('icon').isNotEmpty == true
                    ? group!.text('icon')
                    : 'folder',
                size: 22,
              ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(project.text('title'), style: gl(16, w600)),
                  SizedBox(height: 1),
                  Text(
                    '${group?.text('name') ?? ''} · deadline ${due == null ? '-' : GLFormat.date(due)}',
                    style: gl(13, w400, 0, GLTheme.secondary),
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: GLProgressBar(
                          value: tasks.isEmpty ? 0 : done / tasks.length,
                        ),
                      ),
                      SizedBox(width: 10),
                      Text(
                        '$done/${tasks.length} selesai',
                        style: gl(13, w600).copyWith(
                          fontFeatures: [FontFeature.tabularFigures()],
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
