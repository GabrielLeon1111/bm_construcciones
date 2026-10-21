import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../repositories/empleado_repository.dart';
import '../../security/registro_seguro.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';
import '../../widgets/reloading_future.dart';

/// Panel de empleados (solo administrador): los vendedores solo entran a
/// Vender y Presupuesto, y cada venta o presupuesto queda a su nombre.
class EmpleadosScreen extends StatefulWidget {
  const EmpleadosScreen({super.key});

  @override
  State<EmpleadosScreen> createState() => _EmpleadosScreenState();
}

class _EmpleadosScreenState extends State<EmpleadosScreen> {
  final _key = GlobalKey<ReloadingFutureState<List<Empleado>>>();

  Future<void> _recargar() async => _key.currentState?.reload();

  Future<void> _agregar() async {
    final ok = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => const _NuevoEmpleadoSheet());
    if (ok == true) await _recargar();
  }

  Future<void> _accion(String a, Empleado e) async {
    final repo = context.read<EmpleadoRepository>();
    switch (a) {
      case 'clave':
        final clave = await showModalBottomSheet<String>(context: context, isScrollControlled: true, builder: (_) => _ClaveSheet(nombre: e.nombre));
        if (clave == null || !mounted) return;
        await _correr('cambiarClave', () => repo.cambiarClave(e.userId, clave), 'Contraseña cambiada. Avisale a ${e.nombre}.');
      case 'activar':
        final activo = !e.activo;
        final ok = await confirmar(
          context,
          titulo: activo ? 'Activar empleado' : 'Desactivar empleado',
          mensaje: activo
              ? '${e.nombre} va a poder entrar otra vez a Vender y Presupuesto.'
              : '${e.nombre} no va a poder entrar más a la app. Sus ventas y presupuestos quedan registrados.',
          si: activo ? 'Activar' : 'Desactivar',
          peligro: !activo,
        );
        if (!ok || !mounted) return;
        await _correr('activarEmpleado', () => repo.activar(e.userId, activo), activo ? 'Empleado activado' : 'Empleado desactivado');
      case 'eliminar':
        final ok = await confirmar(
          context,
          titulo: 'Eliminar empleado',
          mensaje: 'Solo se puede eliminar si nunca hizo ventas ni presupuestos (por ejemplo, si se creó por error). '
              'Si ya trabajó, desactivalo.',
          si: 'Eliminar',
          peligro: true,
        );
        if (!ok || !mounted) return;
        await _correr('eliminarEmpleado', () => repo.eliminar(e.userId), 'Empleado eliminado');
    }
  }

  Future<void> _correr(String contexto, Future<void> Function() f, String ok) async {
    try {
      await f();
      if (!mounted) return;
      showSnack(context, ok);
      await _recargar();
    } catch (e) {
      registrarError(contexto, e);
      if (mounted) showSnack(context, e is EmpleadoException ? e.mensaje : mensajeErrorSeguro(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Empleados')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_empleado',
        onPressed: _agregar,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Agregar empleado'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ReloadingFuture<List<Empleado>>(
            key: _key,
            contexto: 'empleados',
            load: () => context.read<EmpleadoRepository>().list(),
            builder: (context, lista, reload) {
              final vendedores = lista.where((e) => !e.esAdmin).toList();
              return RefreshIndicator(
                onRefresh: reload,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: AppColors.blueSoft, borderRadius: BorderRadius.circular(12)),
                      child: const Text(
                        'Los empleados solo entran a Vender y Presupuesto. No ven costos ni ganancias, '
                        'no cargan compras, no tocan el stock y no pueden anular ventas.\n'
                        'Cada venta y presupuesto queda con su nombre, el día y la hora.',
                        style: TextStyle(color: AppColors.blue, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SectionTitle('Administrador'),
                    for (final e in lista.where((e) => e.esAdmin))
                      Card(
                        child: ListTile(
                          leading: const CircleAvatar(backgroundColor: AppColors.ink, child: Icon(Icons.verified_user_rounded, color: AppColors.yellow)),
                          title: Text(e.nombre, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: const Text('Acceso a todo'),
                        ),
                      ),
                    SectionTitle('Vendedores (${vendedores.length})'),
                    if (vendedores.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(18),
                          child: Text('Todavía no agregaste empleados. Tocá "Agregar empleado".', style: TextStyle(color: AppColors.muted)),
                        ),
                      )
                    else
                      Card(
                        child: Column(
                          children: [
                            for (var i = 0; i < vendedores.length; i++) ...[
                              if (i > 0) const Divider(indent: 72),
                              _fila(vendedores[i]),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _fila(Empleado e) => ListTile(
        contentPadding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
        leading: CircleAvatar(
          backgroundColor: e.activo ? AppColors.yellowSoft : AppColors.concrete,
          child: Text(
            e.nombre.split(' ').where((p) => p.isNotEmpty).take(2).map((p) => p[0].toUpperCase()).join(),
            style: TextStyle(fontWeight: FontWeight.w800, color: e.activo ? AppColors.ink : AppColors.muted),
          ),
        ),
        title: Row(
          children: [
            Flexible(child: Text(e.nombre, style: const TextStyle(fontWeight: FontWeight.w700))),
            const SizedBox(width: 8),
            if (!e.activo) const Pill('Desactivado', color: AppColors.red),
          ],
        ),
        subtitle: Text('Usuario: ${e.usuario ?? '—'} · desde ${fechaCorta.format(e.creado)}'),
        trailing: PopupMenuButton<String>(
          tooltip: 'Acciones',
          onSelected: (a) => _accion(a, e),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'clave', child: Text('Cambiar contraseña')),
            PopupMenuItem(value: 'activar', child: Text(e.activo ? 'Desactivar' : 'Activar')),
            const PopupMenuItem(value: 'eliminar', child: Text('Eliminar', style: TextStyle(color: AppColors.red))),
          ],
        ),
      );
}

// ---------------- Nuevo empleado ----------------

/// "Juan Pérez" → "juan.perez" (sin tildes ni espacios).
String sugerirUsuario(String nombre, String apellido) {
  String limpio(String s) {
    const de = 'áéíóúüñÁÉÍÓÚÜÑ';
    const a = 'aeiouunAEIOUUN';
    final b = StringBuffer();
    for (final ch in s.trim().split('')) {
      final i = de.indexOf(ch);
      b.write(i >= 0 ? a[i] : ch);
    }
    return b.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  final n = limpio(nombre.split(' ').first);
  final ap = limpio(apellido.split(' ').first);
  return [n, ap].where((p) => p.isNotEmpty).join('.');
}

final _soloLetras = FilteringTextInputFormatter.allow(RegExp(r"[A-Za-zÁÉÍÓÚÜÑáéíóúüñ' -]"));

String? _validarNombre(String? v, String campo) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return 'Escribí el $campo';
  if (t.length < 2) return 'Muy corto';
  return null;
}

String? _validarClave(String? v) {
  final t = v ?? '';
  if (t.isEmpty) return 'Escribí la contraseña';
  if (t.length < 8) return 'Mínimo 8 caracteres (ej: Ventas2026)';
  return null;
}

class _NuevoEmpleadoSheet extends StatefulWidget {
  const _NuevoEmpleadoSheet();

  @override
  State<_NuevoEmpleadoSheet> createState() => _NuevoEmpleadoSheetState();
}

class _NuevoEmpleadoSheetState extends State<_NuevoEmpleadoSheet> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _apellido = TextEditingController();
  final _usuario = TextEditingController();
  final _clave = TextEditingController();
  bool _usuarioEditado = false;
  bool _ver = false;
  bool _guardando = false;
  String? _error;

  void _sugerir() {
    if (_usuarioEditado) return;
    _usuario.text = sugerirUsuario(_nombre.text, _apellido.text);
  }

  Future<void> _guardar() async {
    if (_guardando || !_form.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await context.read<EmpleadoRepository>().crear(
            nombre: _nombre.text.trim(),
            apellido: _apellido.text.trim(),
            usuario: _usuario.text.trim(),
            clave: _clave.text,
          );
      if (!mounted) return;
      showSnack(context, 'Empleado creado. Entra con el usuario "${_usuario.text.trim()}" y su contraseña.');
      Navigator.pop(context, true);
    } catch (e) {
      registrarError('crearEmpleado', e);
      if (mounted) setState(() => _error = e is EmpleadoException ? e.mensaje : mensajeErrorSeguro(e, 'No se pudo crear el empleado.'));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Nuevo empleado', style: Theme.of(context).textTheme.titleLarge),
              const Text('Va a poder entrar solo a Vender y Presupuesto.', style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 16),
              FilaCampos(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _nombre,
                      autofocus: true,
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: [_soloLetras, LengthLimitingTextInputFormatter(40)],
                      decoration: const InputDecoration(labelText: 'Nombre *', hintText: 'Ej: Juan'),
                      validator: (v) => _validarNombre(v, 'nombre'),
                      onChanged: (_) => _sugerir(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _apellido,
                      textCapitalization: TextCapitalization.words,
                      inputFormatters: [_soloLetras, LengthLimitingTextInputFormatter(40)],
                      decoration: const InputDecoration(labelText: 'Apellido *', hintText: 'Ej: Pérez'),
                      validator: (v) => _validarNombre(v, 'apellido'),
                      onChanged: (_) => _sugerir(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _usuario,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._-]')),
                  LengthLimitingTextInputFormatter(30),
                  TextInputFormatter.withFunction((o, n) => n.copyWith(text: n.text.toLowerCase())),
                ],
                decoration: const InputDecoration(
                  labelText: 'Usuario para entrar *',
                  hintText: 'Ej: juan.perez',
                  helperText: 'Con esto entra a la app (en vez del email)',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (v) => RegExp(r'^[a-z0-9._-]{3,30}$').hasMatch((v ?? '').trim())
                    ? null
                    : 'Mínimo 3 letras, sin espacios (ej: juan.perez)',
                onChanged: (_) => _usuarioEditado = true,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _clave,
                obscureText: !_ver,
                inputFormatters: [LengthLimitingTextInputFormatter(72)],
                decoration: InputDecoration(
                  labelText: 'Contraseña *',
                  hintText: 'Mínimo 8 caracteres',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _ver ? 'Ocultar' : 'Mostrar',
                    icon: Icon(_ver ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _ver = !_ver),
                  ),
                ),
                validator: _validarClave,
                onFieldSubmitted: (_) => _guardar(),
              ),
              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(top: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppColors.redSoft, borderRadius: BorderRadius.circular(10)),
                  child: Text(_error!, style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600)),
                ),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                onPressed: _guardando ? null : _guardar,
                icon: _guardando
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Crear empleado'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClaveSheet extends StatefulWidget {
  const _ClaveSheet({required this.nombre});
  final String nombre;

  @override
  State<_ClaveSheet> createState() => _ClaveSheetState();
}

class _ClaveSheetState extends State<_ClaveSheet> {
  final _form = GlobalKey<FormState>();
  final _clave = TextEditingController();
  bool _ver = true;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Nueva contraseña', style: Theme.of(context).textTheme.titleLarge),
            Text('Para ${widget.nombre}', style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _clave,
              autofocus: true,
              obscureText: !_ver,
              inputFormatters: [LengthLimitingTextInputFormatter(72)],
              decoration: InputDecoration(
                labelText: 'Contraseña nueva',
                hintText: 'Mínimo 8 caracteres',
                suffixIcon: IconButton(
                  icon: Icon(_ver ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _ver = !_ver),
                ),
              ),
              validator: _validarClave,
            ),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
              onPressed: () {
                if (_form.currentState!.validate()) Navigator.pop(context, _clave.text);
              },
              child: const Text('Cambiar contraseña'),
            ),
          ],
        ),
      ),
    );
  }
}
