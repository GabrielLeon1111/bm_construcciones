import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/draft_document.dart';
import '../../theme/app_theme.dart';
import '../../widgets/brand_mark.dart';
import '../../widgets/common.dart';
import '../caja/cajas_screen.dart';
import '../clientes/clients_screen.dart';
import '../empleados/empleados_screen.dart';
import '../gastos/gastos_screen.dart';
import '../movimientos/movements_screen.dart';
import '../negocio/business_screen.dart';
import '../reportes/report_screen.dart';
import '../ventas/sales_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final usuario = context.select<AuthProvider, String?>((a) => a.usuario);
    final correo = context.select<AuthProvider, String?>((a) => a.email);
    // Los empleados entran con usuario: se muestra eso y no el email interno.
    final email = usuario != null ? 'Usuario: $usuario' : correo;
    final nombre = context.select<AuthProvider, String?>((a) => a.nombre);
    final esAdmin = context.select<AuthProvider, bool>((a) => a.esAdmin);
    void go(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

    final items = [
      if (esAdmin) ...[
        (Icons.badge_outlined, 'Empleados', 'Crear vendedores: solo entran a Vender y Presupuesto', () => go(const EmpleadosScreen())),
        (Icons.people_alt_outlined, 'Clientes', 'Datos y todo lo que compró cada uno', () => go(const ClientsScreen())),
        (Icons.point_of_sale_outlined, 'Cajas', 'Aperturas y cierres, quién y a qué hora, imprimir el arqueo', () => go(const CajasScreen())),
        (Icons.request_quote_outlined, 'Gastos', 'Alquiler, sueldos, flete, luz, combustible... y la ganancia real', () => go(const GastosScreen())),
        (Icons.receipt_long_outlined, 'Ventas', 'Lo vendido hoy, historial, reimprimir y anular', () => go(const SalesScreen())),
        (Icons.swap_vert_rounded, 'Movimientos', 'Entradas, salidas y ajustes de stock', () => go(const MovementsScreen())),
        (
          Icons.insert_chart_outlined_rounded,
          'Reportes y arqueo',
          'Cuánto invertiste, vendiste y ganaste (PDF/Excel)',
          () => go(const ReportScreen()),
        ),
        (Icons.storefront_outlined, 'Datos del negocio', 'Nombre, celular, logo y notas del comprobante', () => go(const BusinessScreen())),
      ],
    ];

    return Scaffold(
      appBar: AppBar(title: Text(esAdmin ? 'Más' : 'Mi cuenta')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(14)),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: BrandMark(size: 46, color: Colors.white, showTagline: true, taglineColor: AppColors.yellow),
                    ),
                    if (nombre != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          '$nombre${esAdmin ? ' · Administrador' : ' · Vendedor'}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                      ),
                    if (email != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          email,
                          style: const TextStyle(color: Colors.white60),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (items.isNotEmpty)
                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        if (i > 0) const Divider(indent: 68),
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(color: AppColors.yellowSoft, borderRadius: BorderRadius.circular(10)),
                            child: Icon(items[i].$1, color: AppColors.ink),
                          ),
                          title: Text(items[i].$2),
                          subtitle: Text(items[i].$3),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: items[i].$4,
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              const Card(child: _BiometriaTile()),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.logout_rounded, color: AppColors.red),
                  title: const Text('Cerrar sesión', style: TextStyle(color: AppColors.red)),
                  onTap: () async {
                    if (await confirmar(context, titulo: 'Cerrar sesión', mensaje: '¿Seguro que querés salir?', si: 'Salir') && context.mounted) {
                      context.read<DraftDocument>().clear();
                      await context.read<AuthProvider>().salir();
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Activar o desactivar la entrada con huella / Face ID en este celular.
class _BiometriaTile extends StatefulWidget {
  const _BiometriaTile();

  @override
  State<_BiometriaTile> createState() => _BiometriaTileState();
}

class _BiometriaTileState extends State<_BiometriaTile> {
  bool? _activada;
  bool _disponible = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final b = context.read<AuthProvider>().biometria;
    final activada = await b.activada();
    final disponible = await b.disponible();
    if (mounted) {
      setState(() {
        _activada = activada;
        _disponible = disponible;
      });
    }
  }

  Future<void> _cambiar(bool valor) async {
    final b = context.read<AuthProvider>().biometria;
    if (valor) {
      if (!_disponible) {
        showSnack(context, 'Este celular no tiene huella ni Face ID configurada.', error: true);
        return;
      }
      // Se confirma con la huella antes de activarla.
      if (!await b.verificar()) {
        if (mounted) {
          showSnack(context, 'No se pudo verificar tu huella / Face ID.', error: true);
        }
        return;
      }
    }
    await b.activar(valor);
    if (!mounted) return;
    setState(() => _activada = valor);
    showSnack(context, valor ? 'Listo: la próxima vez entrás con tu huella / Face ID' : 'Entrada con huella desactivada');
  }

  @override
  Widget build(BuildContext context) => SwitchListTile(
    secondary: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: AppColors.yellowSoft, borderRadius: BorderRadius.circular(10)),
      child: const Icon(Icons.fingerprint, color: AppColors.ink),
    ),
    title: const Text('Entrar con huella / Face ID'),
    subtitle: Text(_disponible ? 'Más rápido, sin escribir la contraseña' : 'No disponible en este dispositivo'),
    value: _activada ?? false,
    onChanged: _activada == null ? null : _cambiar,
  );
}
