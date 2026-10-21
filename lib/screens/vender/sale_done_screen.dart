import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/sale.dart';
import '../../providers/settings_provider.dart';
import '../../services/pdf_documento.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../../widgets/doc_actions.dart';
import '../ventas/sale_detail_screen.dart';

/// Venta registrada: comprobante listo para compartir.
class SaleDoneScreen extends StatelessWidget {
  const SaleDoneScreen({super.key, required this.sale});
  final Sale sale;

  @override
  Widget build(BuildContext context) {
    final negocio = context.read<SettingsProvider>().settings;
    final datos = DatosDocumento.deVenta(sale);
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, actions: [
        IconButton(tooltip: 'Cerrar', icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
      ]),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: const BoxDecoration(color: AppColors.greenSoft, shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded, size: 52, color: AppColors.green),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Venta registrada', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  'Nota de venta N° ${nroDoc(sale.number)} · ${sale.detallePago}'
                  '${sale.changeAmount > 0 ? '\nVuelto: ${gs(sale.changeAmount)}' : ''}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
                  decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    children: [
                      const Text('TOTAL A PAGAR', style: TextStyle(color: AppColors.yellow, fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1.2)),
                      FittedBox(
                        child: Text(gs(sale.total), style: const TextStyle(color: AppColors.yellow, fontSize: 40, fontWeight: FontWeight.w900)),
                      ),
                      if (sale.clientName != null)
                        Text(sale.clientName!, style: const TextStyle(color: Colors.white70, fontSize: 15)),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                DocActions(
                  fileName: datos.nombreArchivo,
                  shareText: 'Nota de venta N° ${nroDoc(sale.number)} - ${negocio.name}',
                  build: () => generarDocumentoPdf(datos, negocio),
                ),
                const SizedBox(height: 18),
                TextButton.icon(
                  onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: sale.id))),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Ver detalle de la venta'),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.concrete, foregroundColor: AppColors.ink, minimumSize: const Size(0, 50)),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.add_shopping_cart_rounded),
                  label: const Text('Nueva venta'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
