import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/client.dart';
import '../providers/catalog_provider.dart';
import '../theme/app_theme.dart';
import 'client_form_sheet.dart';

/// Campo "Cliente (opcional)": un toque para elegir, buscar o crear.
class ClientPickerField extends StatelessWidget {
  const ClientPickerField({super.key, required this.client, required this.onChanged});
  final Client? client;
  final ValueChanged<Client?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radius), side: const BorderSide(color: AppColors.line)),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: () async {
          final r = await pickClient(context);
          if (r != null) onChanged(r.client);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: client == null ? AppColors.concrete : AppColors.yellow,
                child: client == null
                    ? const Icon(Icons.person_add_alt_1_outlined, size: 20, color: AppColors.muted)
                    : Text(client!.initials, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.ink)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(client?.fullName ?? 'Sin cliente', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    Text(
                      client == null
                          ? 'Tocá para elegir o crear (opcional)'
                          : [client!.document, client!.phone].whereType<String>().join(' · ').ifEmpty('Cliente guardado'),
                      style: const TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (client != null)
                IconButton(tooltip: 'Quitar cliente', icon: const Icon(Icons.close), onPressed: () => onChanged(null))
              else
                const Icon(Icons.chevron_right, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// Resultado del selector: `client` null significa "sin cliente".
class ClientPick {
  const ClientPick(this.client);
  final Client? client;
}

Future<ClientPick?> pickClient(BuildContext context) {
  return showModalBottomSheet<ClientPick>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const FractionallySizedBox(heightFactor: 0.88, child: _ClientPickerSheet()),
  );
}

class _ClientPickerSheet extends StatefulWidget {
  const _ClientPickerSheet();

  @override
  State<_ClientPickerSheet> createState() => _ClientPickerSheetState();
}

class _ClientPickerSheetState extends State<_ClientPickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final all = context.watch<CatalogProvider>().clients;
    final list = _q.isEmpty
        ? all
        : all.where((c) => coincide('${c.fullName} ${c.document ?? ''} ${c.phone ?? ''}', _q)).toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por nombre, CI o teléfono'),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          ListTile(
            leading: const CircleAvatar(backgroundColor: AppColors.yellow, child: Icon(Icons.add, color: AppColors.ink)),
            title: Text(_q.trim().isEmpty ? 'Nuevo cliente' : 'Crear "${_q.trim()}"'),
            onTap: () async {
              final c = await showClientForm(context, initialName: _q.trim());
              if (c != null && context.mounted) Navigator.pop(context, ClientPick(c));
            },
          ),
          ListTile(
            leading: const CircleAvatar(backgroundColor: AppColors.concrete, child: Icon(Icons.person_off_outlined, color: AppColors.muted)),
            title: const Text('Sin cliente'),
            subtitle: const Text('El comprobante sale sin nombre'),
            onTap: () => Navigator.pop(context, const ClientPick(null)),
          ),
          const Divider(),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text('No hay clientes con ese nombre', style: TextStyle(color: AppColors.muted)))
                : ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final c = list[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.ink,
                          child: Text(c.initials, style: const TextStyle(color: AppColors.yellow, fontWeight: FontWeight.w800)),
                        ),
                        title: Text(c.fullName),
                        subtitle: Text([c.document, c.phone, c.address].whereType<String>().join(' · ')),
                        onTap: () => Navigator.pop(context, ClientPick(c)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
