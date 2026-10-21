import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../models/caja.dart';
import '../../providers/settings_provider.dart';
import '../../repositories/caja_repository.dart';
import '../../security/registro_seguro.dart';
import '../../services/pdf_caja.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/common.dart';
import '../../widgets/reloading_future.dart';
import 'caja_screen.dart';

/// Aperturas y cierres de caja (solo administrador). Cada empleado tiene su caja:
/// a qué hora se abrió y se cerró, quién, si sobró o faltó, y el botón para imprimir
/// el comprobante. Si un empleado se olvidó de cerrar, el administrador la cierra.
class CajasScreen extends StatelessWidget {
  const CajasScreen({super.key});

  Future<void> _imprimir(BuildContext context, Caja c) async {
    final negocio = context.read<SettingsProvider>().settings;
    try {
      await Printing.layoutPdf(name: nombreArchivoCaja(c), onLayout: (_) => generarArqueoPdf(c, negocio));
    } catch (e) {
      registrarError('imprimirArqueo', e);
      if (context.mounted) showSnack(context, mensajeErrorSeguro(e, 'No se pudo imprimir. Intentá de nuevo.'), error: true);
    }
  }

  Future<void> _cerrarDeOtro(BuildContext context, Caja c, Future<void> Function() recargar) async {
    try {
      final actual = await context.read<CajaRepository>().get(c.id);
      if (!context.mounted || !actual.abierta) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => CierreCajaScreen(caja: actual)));
      await recargar();
    } catch (e) {
      registrarError('cerrarCajaDeOtro', e);
      if (context.mounted) showSnack(context, mensajeErrorSeguro(e, 'No se pudo abrir la caja.'), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cajas: aperturas y cierres')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ReloadingFuture<List<Caja>>(
            contexto: 'listaCajas',
            load: () => context.read<CajaRepository>().list(),
            builder: (context, cajas, reload) {
              if (cajas.isEmpty) {
                return const EmptyState(icon: Icons.point_of_sale_outlined, title: 'Todavía no se abrió ninguna caja');
              }
              return RefreshIndicator(
                onRefresh: reload,
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: cajas.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final c = cajas[i];
                    final dif = c.difference ?? 0;
                    return Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ComprobanteCajaScreen(caja: c))),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Text('Caja N° ${nroDoc(c.number)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                                      const SizedBox(width: 8),
                                      if (c.abierta)
                                        const Pill('Abierta', color: AppColors.blue)
                                      else if (dif == 0)
                                        const Pill('Cuadrada', color: AppColors.green)
                                      else
                                        Pill(dif > 0 ? 'Sobra ${gs(dif)}' : 'Falta ${gs(-dif)}', color: dif > 0 ? AppColors.green : AppColors.red),
                                    ]),
                                    const SizedBox(height: 4),
                                    Text('Abrió: ${fechaHora.format(c.openedAt)} · ${c.openedByName}', style: const TextStyle(fontSize: 13.5)),
                                    Text(
                                      c.closedAt == null ? 'Cerró: todavía abierta' : 'Cerró: ${fechaHora.format(c.closedAt!)} · ${c.closedByName ?? '—'}',
                                      style: const TextStyle(fontSize: 13.5, color: AppColors.muted),
                                    ),
                                  ],
                                ),
                              ),
                              if (!c.abierta)
                                IconButton(
                                  tooltip: 'Imprimir comprobante',
                                  icon: const Icon(Icons.print_outlined),
                                  onPressed: () => _imprimir(context, c),
                                )
                              else
                                TextButton(
                                  onPressed: () => _cerrarDeOtro(context, c, reload),
                                  child: const Text('Cerrar'),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
