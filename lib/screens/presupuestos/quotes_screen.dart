import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/quote.dart';
import '../../providers/catalog_provider.dart';
import '../../repositories/quote_repository.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';
import '../../widgets/reloading_future.dart';
import 'quote_detail_screen.dart';
import 'quote_editor_screen.dart';

class QuotesScreen extends StatefulWidget {
  const QuotesScreen({super.key});

  @override
  State<QuotesScreen> createState() => _QuotesScreenState();
}

class _QuotesScreenState extends State<QuotesScreen> {
  String? _status = 'pendiente';
  String _q = '';
  final _key = GlobalKey<ReloadingFutureState<List<Quote>>>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Presupuestos')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab_presupuesto',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QuoteEditorScreen())),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nuevo presupuesto'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por cliente, N° o material'),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final s in const [('pendiente', 'Pendientes'), ('vendido', 'Vendidos'), ('anulado', 'Anulados'), (null, 'Todos')])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s.$2),
                      selected: _status == s.$1,
                      onSelected: (_) {
                        setState(() => _status = s.$1);
                        _key.currentState?.reload();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ReloadingFuture<List<Quote>>(
              key: _key,
              contexto: 'listaPresupuestos',
              load: () => context.read<QuoteRepository>().list(status: _status),
              builder: (context, quotes, reload) {
                final list = _q.isEmpty
                    ? quotes
                    : quotes.where((q) => coincide('${q.number} ${nroDoc(q.number)} ${q.displayClient} ${q.items.map((i) => i.description).join(' ')}', _q)).toList();
                if (list.isEmpty) {
                  return const EmptyState(
                    icon: Icons.request_quote_outlined,
                    title: 'No hay presupuestos',
                    message: 'Armá uno para una obra o pedido y compartilo por WhatsApp.',
                  );
                }
                return RefreshIndicator(
                  onRefresh: reload,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => QuoteTile(quote: list[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class QuoteTile extends StatelessWidget {
  const QuoteTile({super.key, required this.quote});
  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final q = quote;
    final (label, color) = switch (q.status) {
      'vendido' => ('Vendido', AppColors.green),
      'anulado' => ('Anulado', AppColors.red),
      _ => q.isExpired ? ('Vencido', AppColors.orange) : ('Pendiente', AppColors.blue),
    };
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => QuoteDetailScreen(quoteId: q.id))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text('N° ${nroDoc(q.number)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Pill(label, color: color),
                    ]),
                    const SizedBox(height: 2),
                    Text(q.displayClient, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    Text(
                      '${fechaCorta.format(q.createdAt)} · ${q.items.length} ítems${q.validUntil != null && q.isPending ? ' · vence ${fechaCorta.format(q.validUntil!)}' : ''}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Text(gs(q.total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
            ],
          ),
        ),
      ),
    );
  }
}
