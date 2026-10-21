import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/quote.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/draft_document.dart';
import '../../providers/refresh_bus.dart';
import '../../providers/settings_provider.dart';
import '../../repositories/quote_repository.dart';
import '../../security/registro_seguro.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../utils/validacion.dart';
import '../../widgets/client_picker.dart';
import '../../widgets/common.dart';
import '../../widgets/doc_editor.dart';
import 'quote_detail_screen.dart';

/// Crear o editar un presupuesto (agregar o quitar materiales, cambiar cantidades).
class QuoteEditorScreen extends StatefulWidget {
  const QuoteEditorScreen({super.key, this.quote});
  final Quote? quote;

  @override
  State<QuoteEditorScreen> createState() => _QuoteEditorScreenState();
}

class _QuoteEditorScreenState extends State<QuoteEditorScreen> {
  final _draft = DraftDocument();
  late final TextEditingController _notes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final q = widget.quote;
    if (q != null) {
      _draft.loadQuote(q, lookup: context.read<CatalogProvider>().productById);
    } else {
      final dias = context.read<SettingsProvider>().settings.quoteValidityDays;
      final hoy = DateTime.now();
      _draft.validUntil = DateTime(hoy.year, hoy.month, hoy.day + dias);
    }
    _notes = TextEditingController(text: _draft.notes);
  }

  @override
  void dispose() {
    _draft.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _draft.validUntil ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, now.month, now.day),
    );
    if (d != null) _draft.validUntil = d;
  }

  Future<void> _save() async {
    if (_draft.isEmpty || _saving) return;
    if (_draft.subtotal > montoMaximo) {
      showSnack(context, 'El total pasa de ${gs(montoMaximo)}. Dividí el presupuesto en dos.', error: true);
      return;
    }
    setState(() => _saving = true);
    final repo = context.read<QuoteRepository>();
    try {
      final q = await repo.save(
            quoteId: widget.quote?.id,
            lines: _draft.lines,
            clientId: _draft.client?.id,
            discount: _draft.discount,
            notes: limpiarTexto(_notes.text, multilinea: true),
            validUntil: _draft.validUntil,
            idempotencyKey: _draft.idempotencyKey,
          );
      if (!mounted) return;
      context.read<RefreshBus>().changed();
      showSnack(context, widget.quote == null ? 'Presupuesto guardado' : 'Presupuesto actualizado');
      if (widget.quote == null) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => QuoteDetailScreen(quoteId: q.id)));
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      registrarError('guardarPresupuesto', e);
      // Ya se había guardado (se cortó la respuesta) y después se cambió: se muestra lo guardado.
      if (esYaRegistrada(e)) {
        final id = widget.quote?.id ?? await repo.findIdByKey(_draft.idempotencyKey).catchError((Object _) => null);
        if (!mounted) return;
        showSnack(context, mensajeErrorSeguro(e), error: true);
        context.read<RefreshBus>().changed();
        if (widget.quote != null) {
          Navigator.pop(context);
        } else if (id != null) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => QuoteDetailScreen(quoteId: id)));
        }
        return;
      }
      if (mounted) showSnack(context, mensajeErrorSeguro(e, 'No se pudo guardar el presupuesto.'), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.quote == null ? 'Nuevo presupuesto' : 'Editar presupuesto N° ${nroDoc(widget.quote!.number)}')),
      body: ListenableBuilder(
        listenable: _draft,
        builder: (context, _) => Column(
          children: [
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      const SectionTitle('Cliente', padding: EdgeInsets.fromLTRB(4, 4, 4, 10)),
                      ClientPickerField(client: _draft.client, onChanged: (c) => _draft.client = c),
                      const SectionTitle('Materiales'),
                      DocLinesEditor(draft: _draft, checkStock: false),
                      const SectionTitle('Total'),
                      DocTotals(draft: _draft, etiquetaTotal: 'TOTAL DEL PRESUPUESTO'),
                      const SizedBox(height: 12),
                      Material(
                        color: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radius), side: const BorderSide(color: AppColors.line)),
                        child: ListTile(
                          leading: const Icon(Icons.event_outlined),
                          title: const Text('Válido hasta'),
                          subtitle: Text(_draft.validUntil == null ? 'Sin fecha' : fechaCorta.format(_draft.validUntil!)),
                          trailing: _draft.validUntil == null
                              ? const Icon(Icons.chevron_right)
                              : IconButton(icon: const Icon(Icons.close), onPressed: () => _draft.validUntil = null),
                          onTap: _pickDate,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _notes,
                        maxLines: 2,
                        textCapitalization: TextCapitalization.sentences,
                        inputFormatters: formatoTexto(Largo.notas),
                        decoration: const InputDecoration(labelText: 'Observaciones (opcional)', hintText: 'Ej: obra en barrio San Miguel, entrega incluida'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: AppColors.line))),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
                    onPressed: _draft.isEmpty || _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : const Icon(Icons.save_outlined),
                    label: Text(_draft.isEmpty ? 'Agregá materiales' : 'Guardar presupuesto · ${gs(_draft.total)}', style: const TextStyle(fontSize: 17)),
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
