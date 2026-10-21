import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../security/registro_seguro.dart';
import '../services/compartir.dart';
import 'common.dart';

/// Botones Compartir (WhatsApp) / Descargar / Imprimir para un PDF.
class DocActions extends StatefulWidget {
  const DocActions({super.key, required this.build, required this.fileName, this.shareText, this.compact = false});

  final Future<Uint8List> Function() build;
  final String fileName;
  final String? shareText;
  final bool compact;

  @override
  State<DocActions> createState() => _DocActionsState();
}

class _DocActionsState extends State<DocActions> {
  String? _busy;
  Uint8List? _cache;

  Future<void> _run(String key, Future<void> Function(Uint8List bytes) action) async {
    if (_busy != null) return;
    setState(() => _busy = key);
    try {
      final bytes = _cache ??= await widget.build();
      await action(bytes);
    } catch (e) {
      registrarError('pdf_$key', e);
      if (mounted) showSnack(context, mensajeErrorSeguro(e, 'No se pudo generar el PDF. Intentá de nuevo.'), error: true);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Widget _spinner() => const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4));

  @override
  Widget build(BuildContext context) {
    final share = FilledButton.icon(
      onPressed: () => _run('share', (b) => compartirArchivo(b, widget.fileName, texto: widget.shareText)),
      icon: _busy == 'share' ? _spinner() : const Icon(Icons.share_rounded),
      label: const Text('Compartir por WhatsApp'),
    );
    final save = OutlinedButton.icon(
      onPressed: () {
        final messenger = ScaffoldMessenger.of(context);
        _run('save', (b) async {
          final path = await guardarArchivo(b, widget.fileName);
          if (path != null) messenger.showSnackBar(const SnackBar(content: Text('Guardado en Descargas')));
        });
      },
      icon: _busy == 'save' ? _spinner() : const Icon(Icons.download_rounded),
      label: const Text('Descargar'),
    );
    final print = OutlinedButton.icon(
      onPressed: () => _run('print', (b) => imprimirPdf(b, widget.fileName)),
      icon: _busy == 'print' ? _spinner() : const Icon(Icons.print_outlined),
      label: const Text('Imprimir'),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        share,
        const SizedBox(height: 10),
        Row(children: [Expanded(child: save), const SizedBox(width: 10), Expanded(child: print)]),
      ],
    );
  }
}
