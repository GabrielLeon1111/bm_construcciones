import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/caja_provider.dart';
import '../../providers/catalog_provider.dart';
import '../../providers/draft_document.dart';
import '../../providers/settings_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brand_mark.dart';
import '../../widgets/common.dart';
import '../auth/biometric_lock_screen.dart';
import '../inicio/dashboard_screen.dart';
import '../inventario/inventory_screen.dart';
import '../mas/more_screen.dart';
import '../presupuestos/quotes_screen.dart';
import '../vender/sell_screen.dart';

/// Barra fija con 5 botones (abajo en el celular, a la izquierda en la computadora).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  /// Pestaña activa. Se puede cambiar desde cualquier pantalla (ej: "convertir en venta" → Vender).
  static final tab = ValueNotifier<int>(0);

  static void irA(BuildContext context, int index) {
    Navigator.of(context).popUntil((r) => r.isFirst);
    tab.value = index;
  }

  /// Ir a Vender (para el administrador es la 2.ª pestaña; para el vendedor, la 1.ª).
  static void irAVender(BuildContext context) => irA(context, context.read<AuthProvider>().esAdmin ? 1 : 0);

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int get _index => HomeShell.tab.value;

  // Compras está dentro de Inventario; en su lugar va Presupuestos.
  static const _pantallasAdmin = [DashboardScreen(), SellScreen(), InventoryScreen(), QuotesScreen(), MoreScreen()];
  // Empleados: solo Vender y Presupuesto (y Más, con su cuenta y "Cerrar sesión").
  static const _pantallasVendedor = [SellScreen(), QuotesScreen(), MoreScreen()];

  @override
  void initState() {
    super.initState();
    // Cada vez que alguien entra, arranca en la primera pestaña.
    HomeShell.tab.value = 0;
    HomeShell.tab.addListener(_onTab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SettingsProvider>().cargar();
      context.read<CatalogProvider>().cargarTodo();
      // Si había una caja abierta (aunque se haya cerrado la app), se recupera.
      context.read<CajaProvider>().cargar();
      if (context.read<AuthProvider>().consumirRecienIngreso()) ofrecerBiometria(context);
    });
  }

  void _onTab() => setState(() {});

  @override
  void dispose() {
    HomeShell.tab.removeListener(_onTab);
    super.dispose();
  }

  void ir(int i) => HomeShell.tab.value = i;

  @override
  Widget build(BuildContext context) {
    final licenseOk = context.select<SettingsProvider, bool>((s) => s.licenseOk);
    final cartCount = context.select<DraftDocument, int>((d) => d.itemCount);
    final esAdmin = context.select<AuthProvider, bool>((a) => a.esAdmin);
    final pantallas = esAdmin ? _pantallasAdmin : _pantallasVendedor;
    final index = _index.clamp(0, pantallas.length - 1);

    Widget venderIcon(bool selected) => Badge(
          isLabelVisible: cartCount > 0,
          label: Text('$cartCount'),
          backgroundColor: AppColors.red,
          child: Icon(selected ? Icons.point_of_sale : Icons.point_of_sale_outlined),
        );

    final body = Column(
      children: [
        if (!licenseOk) const _LicenseBanner(),
        Expanded(child: IndexedStack(index: index, children: pantallas)),
      ],
    );

    if (isWide(context)) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: index,
              onDestinationSelected: ir,
              labelType: NavigationRailLabelType.all,
              minWidth: 96,
              leading: const Padding(
                padding: EdgeInsets.fromLTRB(8, 20, 8, 28),
                child: BrandMark(size: 34, color: Colors.white),
              ),
              destinations: [
                if (esAdmin)
                  const NavigationRailDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard), label: Text('Inicio')),
                NavigationRailDestination(icon: venderIcon(false), selectedIcon: venderIcon(true), label: const Text('Vender')),
                if (esAdmin)
                  const NavigationRailDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: Text('Inventario')),
                const NavigationRailDestination(icon: Icon(Icons.request_quote_outlined), selectedIcon: Icon(Icons.request_quote), label: Text('Presupuestos')),
                NavigationRailDestination(
                  icon: Icon(esAdmin ? Icons.more_horiz : Icons.account_circle_outlined),
                  selectedIcon: Icon(esAdmin ? Icons.more_horiz : Icons.account_circle),
                  label: Text(esAdmin ? 'Más' : 'Mi cuenta'),
                ),
              ],
            ),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: ir,
        destinations: [
          if (esAdmin)
            const NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard), label: 'Inicio'),
          NavigationDestination(icon: venderIcon(false), selectedIcon: venderIcon(true), label: 'Vender'),
          if (esAdmin)
            const NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2), label: 'Inventario'),
          const NavigationDestination(icon: Icon(Icons.request_quote_outlined), selectedIcon: Icon(Icons.request_quote), label: 'Presupuesto'),
          NavigationDestination(
            icon: Icon(esAdmin ? Icons.more_horiz : Icons.account_circle_outlined),
            selectedIcon: Icon(esAdmin ? Icons.more_horiz : Icons.account_circle),
            label: esAdmin ? 'Más' : 'Mi cuenta',
          ),
        ],
      ),
    );
  }
}

class _LicenseBanner extends StatelessWidget {
  const _LicenseBanner();

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.red,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: const [
                Icon(Icons.lock_clock_outlined, color: Colors.white),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'El período de prueba terminó. Podés consultar los datos, pero no registrar ventas ni compras. Comunicate con soporte.',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
