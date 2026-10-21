import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/catalog_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/client_form_sheet.dart';
import '../../widgets/common.dart';
import 'client_detail_screen.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final catalog = context.watch<CatalogProvider>();
    final list = _q.isEmpty
        ? catalog.clients
        : catalog.clients.where((c) => coincide('${c.fullName} ${c.document ?? ''} ${c.phone ?? ''} ${c.address ?? ''}', _q)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_cliente',
        onPressed: () => showClientForm(context),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Cliente'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por nombre, CI, teléfono o dirección'),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? EmptyState(
                    icon: Icons.people_alt_outlined,
                    title: catalog.clients.isEmpty ? 'Todavía no hay clientes' : 'No se encontró "$_q"',
                    message: catalog.clients.isEmpty ? 'También se pueden crear al vender o presupuestar.' : null,
                  )
                : RefreshIndicator(
                    onRefresh: catalog.cargarClientes,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final c = list[i];
                        return Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            leading: CircleAvatar(
                              backgroundColor: AppColors.ink,
                              child: Text(c.initials, style: const TextStyle(color: AppColors.yellow, fontWeight: FontWeight.w800)),
                            ),
                            title: Text(c.fullName),
                            subtitle: Text([c.phone, c.document, c.address].whereType<String>().join(' · ')),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ClientDetailScreen(client: c))),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
