import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/validacion.dart';
import '../../widgets/brand_mark.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  /// Bloqueada por 5 intentos fallidos: hasta cuándo (con cuenta regresiva).
  DateTime? _bloqueadaHasta;
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    _leerBloqueo();
  }

  @override
  void dispose() {
    _reloj?.cancel();
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _leerBloqueo() async {
    final hasta = await context.read<AuthProvider>().bloqueoLogin.bloqueadoHasta();
    if (!mounted) return;
    setState(() => _bloqueadaHasta = hasta);
    _reloj?.cancel();
    if (hasta == null) return;
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (DateTime.now().isAfter(_bloqueadaHasta!)) {
        _reloj?.cancel();
        setState(() {
          _bloqueadaHasta = null;
          _error = null;
        });
        _leerBloqueo(); // borra el bloqueo vencido: vuelve a tener 5 intentos
      } else {
        setState(() {});
      }
    });
  }

  String get _faltaTexto {
    final resta = _bloqueadaHasta!.difference(DateTime.now());
    final m = resta.inMinutes;
    final s = (resta.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _submit() async {
    if (_bloqueadaHasta != null) return;
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await context.read<AuthProvider>().ingresar(_email.text, _pass.text);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = err;
      if (err != null) _pass.clear();
    });
    if (err != null) await _leerBloqueo();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final hero = Container(
      color: AppColors.ink,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: wide ? MainAxisAlignment.center : MainAxisAlignment.end,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(28, wide ? 0 : 36, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Arriba "VENTA DE MATERIALES" y debajo solo "BM.".
                  Text(
                    context.select<SettingsProvider, String>((p) => p.settings.tagline).toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: wide ? 23 : 17,
                      letterSpacing: 1.4,
                      color: AppColors.yellow,
                    ),
                  ),
                  const SizedBox(height: 6),
                  BrandMark(size: wide ? 96 : 72, color: Colors.white, showRest: false),
                  const SizedBox(height: 14),
                  const Text(
                    'Ventas, stock y presupuestos del negocio.',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final form = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: _form,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Ingresar', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  const Text('Administrador: tu email. Empleados: el usuario que te dieron.', style: TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username, AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s')), LengthLimitingTextInputFormatter(Largo.email)],
                    decoration: const InputDecoration(
                      labelText: 'Email o usuario',
                      hintText: 'Ej: bm@gmail.com o juan.perez',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return 'Escribí tu email o usuario';
                      if (t.contains('@')) return validarEmail(t, obligatorio: true);
                      return RegExp(r'^[a-zA-Z0-9._-]{3,30}$').hasMatch(t) ? null : 'Revisá el usuario (ej: juan.perez)';
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _pass,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.password],
                    inputFormatters: [LengthLimitingTextInputFormatter(72)],
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      hintText: 'La que te dimos al instalar',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        tooltip: _obscure ? 'Mostrar' : 'Ocultar',
                        icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'Escribí tu contraseña' : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (_bloqueadaHasta != null)
                    Container(
                      margin: const EdgeInsets.only(top: 14),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppColors.redSoft, borderRadius: BorderRadius.circular(10)),
                      child: Row(
                        children: [
                          const Icon(Icons.lock_clock_outlined, color: AppColors.red, size: 30),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'App bloqueada por 5 intentos fallidos.\nPodés volver a intentar en $_faltaTexto',
                              style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(top: 14),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppColors.redSoft, borderRadius: BorderRadius.circular(10)),
                      child: Text(_error!, style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600)),
                    ),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _loading || _bloqueadaHasta != null ? null : _submit,
                    child: _loading
                        ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : Text(_bloqueadaHasta != null ? 'Bloqueado · $_faltaTexto' : 'Ingresar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (wide) {
      return Scaffold(
        body: Row(children: [Expanded(flex: 5, child: hero), Expanded(flex: 4, child: form)]),
      );
    }
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: Column(
              children: [
                SizedBox(height: (c.maxHeight * 0.38).clamp(250, 340), width: double.infinity, child: hero),
                form,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
