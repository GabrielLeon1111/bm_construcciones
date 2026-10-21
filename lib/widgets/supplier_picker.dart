import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/supplier.dart';
import '../providers/catalog_provider.dart';
import '../repositories/supplier_repository.dart';
import '../security/registro_seguro.dart';
import '../theme/app_theme.dart';
import '../utils/validacion.dart';
import 'common.dart';

/// Elegir un proveedor guardado o crear uno nuevo (queda guardado para la próxima).
Future<Supplier?> pickSupplier(BuildContext context) {
  return showModalBottomSheet<Supplier>(
    context: context,
    isScrollControlled: true,
    builder: (c) => FractionallySizedBox(
      heightFactor: 0.85,
      child: Padding(padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(c).bottom), child: const _SupplierPicker()),
    ),
  );
}

class _SupplierPicker extends StatefulWidget {
  const _SupplierPicker();

  @override
  State<_SupplierPicker> createState() => _SupplierPickerState();
}

class _SupplierPickerState extends State<_SupplierPicker> {
  late final Future<List<Supplier>> _future = context.read<SupplierRepository>().list();
  String _q = '';
  bool _nuevo = false;

  @override
  Widget build(BuildContext context) {
    if (_nuevo) return _NuevoProveedor(nombreInicial: _q, onCancel: () => setState(() => _nuevo = false));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            autofocus: true,
            inputFormatters: formatoTexto(Largo.proveedor),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar proveedor (ej: arenera)'),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
            onPressed: () => setState(() => _nuevo = true),
            icon: const Icon(Icons.add_business_outlined),
            label: Text(_q.trim().isEmpty ? 'Nuevo proveedor' : 'Nuevo proveedor: "${_q.trim()}"'),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: FutureBuilder<List<Supplier>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
              if (snap.hasError) {
                registrarError('proveedores', snap.error!);
                return Center(child: Text(mensajeErrorSeguro(snap.error!, 'No se pudieron cargar los proveedores.')));
              }
              final list = snap.data!.where((s) => _q.isEmpty || coincide('${s.name} ${s.ruc ?? ''}', _q)).toList();
              if (list.isEmpty) {
                return const EmptyState(
                  icon: Icons.storefront_outlined,
                  title: 'Sin proveedores guardados',
                  message: 'Tocá "Nuevo proveedor" para cargar el primero. Queda guardado para la próxima compra.',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (_, i) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.storefront_outlined),
                    title: Text(list[i].name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: list[i].detalle.isEmpty ? null : Text(list[i].detalle),
                    onTap: () => Navigator.pop(context, list[i]),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NuevoProveedor extends StatefulWidget {
  const _NuevoProveedor({required this.nombreInicial, required this.onCancel});
  final String nombreInicial;
  final VoidCallback onCancel;

  @override
  State<_NuevoProveedor> createState() => _NuevoProveedorState();
}

class _NuevoProveedorState extends State<_NuevoProveedor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.nombreInicial.trim());
  final _phone = TextEditingController();
  final _ruc = TextEditingController();
  bool _saving = false;
  final String _id = const Uuid().v4();

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final s = await context.read<SupplierRepository>().create(
            _id,
            name: limpiarTexto(_name.text),
            phone: limpiarTexto(_phone.text).isEmpty ? null : limpiarTexto(_phone.text),
            ruc: limpiarTexto(_ruc.text).isEmpty ? null : limpiarTexto(_ruc.text),
          );
      if (mounted) Navigator.pop(context, s);
    } catch (e) {
      registrarError('nuevoProveedor', e);
      if (mounted) showSnack(context, mensajeErrorSeguro(e, 'No se pudo guardar el proveedor.'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Text('Nuevo proveedor', style: Theme.of(context).textTheme.titleLarge),
          const Text('Queda guardado para elegirlo en las próximas compras.', style: TextStyle(color: AppColors.muted)),
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            inputFormatters: formatoTexto(Largo.proveedor),
            decoration: const InputDecoration(labelText: 'Nombre *', hintText: 'Ej: Arenera San José'),
            validator: validarTexto(campo: 'el nombre', obligatorio: true, max: Largo.proveedor),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +()-]')), LengthLimitingTextInputFormatter(Largo.telefono)],
            decoration: const InputDecoration(labelText: 'Celular (opcional)', hintText: 'Ej: 0981 123456'),
            validator: validarTelefono,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _ruc,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.-]')), LengthLimitingTextInputFormatter(Largo.documento)],
            decoration: const InputDecoration(labelText: 'RUC (opcional)', hintText: 'Ej: 80012345-6'),
            validator: validarDocumento,
          ),
          const SizedBox(height: 20),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Text('Guardar proveedor'),
          ),
          TextButton(onPressed: widget.onCancel, child: const Text('Volver a la lista')),
        ],
      ),
    );
  }
}
