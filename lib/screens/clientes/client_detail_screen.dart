import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/client.dart';
import '../../models/quote.dart';
import '../../models/sale.dart';
import '../../providers/catalog_provider.dart';
import '../../repositories/client_repository.dart';
import '../../services/compartir.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/client_form_sheet.dart';
import '../../widgets/common.dart';
import '../../widgets/reloading_future.dart';
import '../presupuestos/quotes_screen.dart';
import '../ventas/sales_screen.dart';

class ClientDetailScreen extends StatefulWidget {
  const ClientDetailScreen({super.key, required this.client});
  final Client client;

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  late Client _c = widget.client;

  Future<void> _delete() async {
    final ok = await confirmar(context,
        titulo: 'Eliminar cliente',
        mensaje: 'Sus ventas y presupuestos quedan guardados, pero sin el cliente vinculado.',
        si: 'Eliminar',
        peligro: true);
    if (!ok || !mounted) return;
    final done = await runSafe(context, 'eliminarCliente', () => context.read<ClientRepository>().delete(_c.id), ok: 'Cliente eliminado');
    if (done && mounted) {
      context.read<CatalogProvider>().removeClient(_c.id);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wa = telefonoWhatsapp(_c.phone);
    return Scaffold(
      appBar: AppBar(
        title: Text(_c.fullName),
        actions: [
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final r = await showClientForm(context, client: _c);
              if (r != null) setState(() => _c = r);
            },
          ),
          PopupMenuButton<String>(
            onSelected: (_) => _delete(),
            itemBuilder: (_) => const [PopupMenuItem(value: 'del', child: Text('Eliminar', style: TextStyle(color: AppColors.red)))],
          ),
        ],
      ),
      body: ReloadingFuture<(List<Sale>, List<Quote>)>(
        contexto: 'historialCliente',
        load: () => context.read<ClientRepository>().history(_c.id),
        builder: (context, data, reload) {
          final (sales, quotes) = data;
          final active = sales.where((s) => !s.isVoided);
          final total = active.fold<int>(0, (a, s) => a + s.netTotal);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          KeyValueRow('WhatsApp', _c.phone ?? '—'),
                          KeyValueRow('CI / RUC', _c.document ?? '—'),
                          KeyValueRow('Dirección', _c.address ?? '—'),
                          if (_c.notes != null) KeyValueRow('Notas', _c.notes!),
                        ],
                      ),
                    ),
                  ),
                  if (wa != null) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => abrirWhatsapp(wa, texto: 'Hola ${_c.fullName.split(' ').first}, '),
                      icon: const Icon(Icons.chat_outlined),
                      label: const Text('Escribir por WhatsApp'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _stat('Compró en total', gs(total))),
                      const SizedBox(width: 10),
                      Expanded(child: _stat('Compras', '${active.length}')),
                      const SizedBox(width: 10),
                      Expanded(child: _stat('Presupuestos', '${quotes.length}')),
                    ],
                  ),
                  const SectionTitle('Ventas'),
                  if (sales.isEmpty)
                    const Text('Todavía no le vendiste.', style: TextStyle(color: AppColors.muted))
                  else
                    for (final s in sales) Padding(padding: const EdgeInsets.only(bottom: 8), child: SaleTile(sale: s)),
                  const SectionTitle('Presupuestos'),
                  if (quotes.isEmpty)
                    const Text('Sin presupuestos.', style: TextStyle(color: AppColors.muted))
                  else
                    for (final q in quotes) Padding(padding: const EdgeInsets.only(bottom: 8), child: QuoteTile(quote: q)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _stat(String label, String value) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
              const SizedBox(height: 2),
              FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
            ],
          ),
        ),
      );
}
