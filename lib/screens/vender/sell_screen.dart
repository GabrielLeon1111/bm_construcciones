import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../providers/caja_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/formato.dart';
import '../caja/caja_screen.dart';
import '../ventas/ventas_hoy.dart';
import 'checkout_panel.dart';

/// Vender, con dos pestañas (como Inventario con Productos y Movimientos):
///  - Nueva venta: arriba se busca el producto por nombre y se agrega; debajo, los
///    materiales, el cliente, el método de pago y el total.
///  - Ventas de hoy: cada venta del día (a quién, cuánto, cómo pagó) con la opción
///    de anularla. Se reinicia sola a las 00:00.
class SellScreen extends StatelessWidget {
  const SellScreen({super.key});

  static Future<void> addToCart(BuildContext context, Product p) => agregarAlCarrito(context, p);

  @override
  Widget build(BuildContext context) {
    // Primero se abre la caja; recién después aparece la venta.
    final estado = context.select<CajaProvider, EstadoCaja>((p) => p.estado);
    if (estado == EstadoCaja.cargando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (estado == EstadoCaja.cerrada) {
      return Scaffold(
        appBar: AppBar(title: const Text('Abrir caja')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: const [AperturaCajaPanel()],
            ),
          ),
        ),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Vender'),

          bottom: const TabBar(
            labelStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            tabs: [
              Tab(text: 'Nueva venta'),
              Tab(text: 'Ventas de hoy'),
            ],
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: const Column(
              children: [
                _BarraCaja(),
                Expanded(
                  child: TabBarView(
                    children: [
                      CheckoutPanel(embedded: true),
                      Padding(padding: EdgeInsets.only(top: 12), child: VentasHoyPanel()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Arriba de Vender: estado de TU caja (cada empleado tiene la suya, como en el
/// supermercado). Abierta: "Retiro de dinero" y "Cerrar caja". Cerrada: "Abrir caja"
/// (sin tu caja abierta no podés cobrar).
class _BarraCaja extends StatelessWidget {
  const _BarraCaja();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<CajaProvider>();
    final c = p.caja;
    switch (p.estado) {
      case EstadoCaja.cargando:
      case EstadoCaja.desconocido:
        return const SizedBox.shrink();
      case EstadoCaja.cerrada:
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: BoxDecoration(color: AppColors.orangeSoft, borderRadius: BorderRadius.circular(12)),
          child: Row(
            children: [
              const Icon(Icons.lock_outline_rounded, color: AppColors.orange),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Tu caja está cerrada: abrila para poder cobrar.', style: TextStyle(color: AppColors.orange, fontWeight: FontWeight.w800)),
              ),
              FilledButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CajaScreen())),
                child: const Text('Abrir caja'),
              ),
            ],
          ),
        );
      case EstadoCaja.abierta:
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CajaScreen())),
                child: Row(
                  children: [
                    const Icon(Icons.point_of_sale_rounded, color: AppColors.yellow, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tu caja N° ${nroDoc(c!.number)} · abierta desde las ${hora.format(c.openedAt)}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: Colors.white54),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Theme(
                data: Theme.of(context).copyWith(
                  outlinedButtonTheme: OutlinedButtonThemeData(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38)),
                  ),
                ),
                child: BotonesCaja(caja: c, compacto: true),
              ),
            ],
          ),
        );
    }
  }
}
