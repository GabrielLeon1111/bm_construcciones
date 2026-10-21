import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/client.dart';
import '../providers/catalog_provider.dart';
import '../repositories/client_repository.dart';
import '../security/registro_seguro.dart';
import '../utils/validacion.dart';
import 'common.dart';

/// Alta o edición de cliente. Devuelve el cliente guardado.
Future<Client?> showClientForm(BuildContext context, {Client? client, String? initialName}) {
  return showModalBottomSheet<Client>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ClientForm(client: client, initialName: initialName),
  );
}

class _ClientForm extends StatefulWidget {
  const _ClientForm({this.client, this.initialName});
  final Client? client;
  final String? initialName;

  @override
  State<_ClientForm> createState() => _ClientFormState();
}

class _ClientFormState extends State<_ClientForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.client?.fullName ?? widget.initialName ?? '');
  late final _phone = TextEditingController(text: widget.client?.phone ?? '');
  late final _doc = TextEditingController(text: widget.client?.document ?? '');
  late final _address = TextEditingController(text: widget.client?.address ?? '');
  late final _notes = TextEditingController(text: widget.client?.notes ?? '');
  bool _saving = false;
  /// Id del cliente nuevo, fijo mientras el formulario está abierto (evita duplicados).
  final String _newId = const Uuid().v4();

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    final data = Client(
      id: widget.client?.id ?? '',
      fullName: limpiarTexto(_name.text),
      phone: limpiarTexto(_phone.text),
      document: limpiarTexto(_doc.text),
      address: limpiarTexto(_address.text),
      notes: limpiarTexto(_notes.text, multilinea: true),
    );
    try {
      final repo = context.read<ClientRepository>();
      final saved = widget.client == null ? await repo.create(_newId, data) : await repo.update(widget.client!.id, data);
      if (!mounted) return;
      context.read<CatalogProvider>().upsertClient(saved);
      Navigator.pop(context, saved);
    } catch (e) {
      registrarError('guardarCliente', e);
      if (mounted) showSnack(context, mensajeErrorSeguro(e, 'No se pudo guardar el cliente.'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
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
              Text(widget.client == null ? 'Nuevo cliente' : 'Editar cliente', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                autofocus: widget.client == null,
                textCapitalization: TextCapitalization.words,
                inputFormatters: formatoTexto(Largo.nombre),
                decoration: const InputDecoration(labelText: 'Nombre y apellido *', hintText: 'Ej: Juan Pérez', prefixIcon: Icon(Icons.person_outline)),
                validator: validarTexto(campo: 'el nombre', obligatorio: true, max: Largo.nombre),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +()-]')), LengthLimitingTextInputFormatter(Largo.telefono)],
                decoration: const InputDecoration(labelText: 'WhatsApp (opcional)', hintText: 'Ej: 0981 123456', prefixIcon: Icon(Icons.phone_outlined)),
                validator: validarTelefono,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _doc,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.-]')), LengthLimitingTextInputFormatter(Largo.documento)],
                decoration: const InputDecoration(labelText: 'CI / RUC (opcional)', hintText: 'Ej: 1.234.567 o 1234567-8', prefixIcon: Icon(Icons.badge_outlined)),
                validator: validarDocumento,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: formatoTexto(Largo.direccion),
                decoration: const InputDecoration(labelText: 'Dirección / obra (opcional)', hintText: 'Ej: Barrio San Pedro, calle 5 casi Ruta 2', prefixIcon: Icon(Icons.place_outlined)),
                validator: validarTexto(campo: 'la dirección', max: Largo.direccion),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 2,
                inputFormatters: formatoTexto(Largo.notas),
                decoration: const InputDecoration(labelText: 'Notas (opcional)', hintText: 'Ej: paga siempre por transferencia'),
                validator: validarTexto(campo: 'las notas', max: Largo.notas, multilinea: true),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('Guardar cliente'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
