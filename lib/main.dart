import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'app.dart';
import 'config/supabase_config.dart';
import 'providers/draft_document.dart';
import 'security/registro_seguro.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    Intl.defaultLocale = 'es';
    await initializeDateFormatting('es');
    await SupabaseConfig.init();
    // La venta que quedó a medias (sin señal, app cerrada) vuelve tal cual.
    final venta = DraftDocument(storageKey: 'venta_en_curso');
    await venta.restaurar();
    runApp(BmApp(venta: venta));
  } catch (e) {
    // Si algo falla al abrir, se muestra un aviso en vez de quedar trabada en el ícono.
    registrarError('arranque', e);
    runApp(const _ErrorArranque());
  }
}

class _ErrorArranque extends StatelessWidget {
  const _ErrorArranque();

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 56, color: Color(0xFFC62828)),
                    const SizedBox(height: 16),
                    const Text(
                      'No se pudo abrir la app',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Cerrala y volvé a abrirla. Si sigue igual, revisá que tengas internet o avisá a soporte.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(onPressed: main, child: const Text('Reintentar')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}
