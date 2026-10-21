import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/caja_provider.dart';
import 'providers/catalog_provider.dart';
import 'providers/draft_document.dart';
import 'providers/refresh_bus.dart';
import 'providers/settings_provider.dart';
import 'repositories/caja_repository.dart';
import 'repositories/gasto_repository.dart';
import 'repositories/client_repository.dart';
import 'repositories/empleado_repository.dart';
import 'repositories/movement_repository.dart';
import 'repositories/product_repository.dart';
import 'repositories/purchase_repository.dart';
import 'repositories/quote_repository.dart';
import 'repositories/report_repository.dart';
import 'repositories/sale_repository.dart';
import 'repositories/settings_repository.dart';
import 'repositories/supplier_repository.dart';
import 'screens/auth/biometric_lock_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/shell/home_shell.dart';
import 'theme/app_theme.dart';

class BmApp extends StatelessWidget {
  const BmApp({super.key, required this.venta});

  /// La venta en curso, ya recuperada del celular (ver main).
  final DraftDocument venta;

  @override
  Widget build(BuildContext context) {
    final settingsRepo = SettingsRepository();
    final productRepo = ProductRepository();
    final clientRepo = ClientRepository();
    return MultiProvider(
      providers: [
        Provider.value(value: settingsRepo),
        Provider.value(value: productRepo),
        Provider.value(value: clientRepo),
        Provider(create: (_) => SaleRepository()),
        Provider(create: (_) => QuoteRepository()),
        Provider(create: (_) => PurchaseRepository()),
        Provider(create: (_) => SupplierRepository()),
        Provider(create: (_) => MovementRepository()),
        Provider(create: (_) => ReportRepository()),
        Provider(create: (_) => EmpleadoRepository()),
        Provider(create: (_) => CajaRepository()),
        Provider(create: (_) => GastoRepository()),
        ChangeNotifierProvider(create: (_) => AuthProvider(settingsRepo)..iniciar()),
        ChangeNotifierProvider(create: (_) => SettingsProvider(settingsRepo)),
        ChangeNotifierProvider(create: (_) => CatalogProvider(productRepo, clientRepo)),
        ChangeNotifierProvider(create: (_) => RefreshBus()),
        // La caja abierta vive en el servidor: al volver a la app se recupera.
        ChangeNotifierProvider(create: (c) => CajaProvider(c.read<CajaRepository>())),
        // La venta en curso (carrito). Uno solo para toda la app y guardado en el
        // celular: si se corta la señal o se cierra la app, no se pierde.
        ChangeNotifierProvider.value(value: venta),
      ],
      child: MaterialApp(
        title: 'BM. Construcciones',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        locale: const Locale('es'),
        supportedLocales: const [Locale('es'), Locale('es', 'PY')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // Respeta la letra grande del celular, pero con un tope para que nada se desarme.
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.3)),
            child: child!,
          );
        },
        home: const _AuthGate(),
      ),
    );
  }
}

class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Con la huella activada, si la app estuvo en el fondo más de un minuto, al volver se pide.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final auth = context.read<AuthProvider>();
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      auth.marcarEnFondo();
    } else if (state == AppLifecycleState.resumed) {
      auth.bloquearSiCorresponde();
      // Pudo cerrarse o abrirse la caja desde otro celular o la computadora.
      if (auth.estado == EstadoSesion.lista) context.read<CajaProvider>().cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return switch (auth.estado) {
      EstadoSesion.cargando => const Scaffold(body: Center(child: CircularProgressIndicator())),
      EstadoSesion.lista when auth.bloqueado => const BiometricLockScreen(),
      EstadoSesion.lista => const HomeShell(),
      _ => const LoginScreen(),
    };
  }
}
