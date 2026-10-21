# BM Construcciones · Ventas, stock y presupuestos

![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-0175C2?logo=dart&logoColor=white)
![Supabase](https://img.shields.io/badge/Supabase-3FCF8E?logo=supabase&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?logo=postgresql&logoColor=white)
![Android](https://img.shields.io/badge/Android-3DDC84?logo=android&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-0078D6?logo=windows&logoColor=white)

App para **BM Construcciones**, venta de materiales de construcción en Carapeguá (Paraguay).
Maneja ventas, caja, inventario, compras, presupuestos, gastos y reportes desde el **celular
(APK de Android)** o desde la **computadora (Windows)**. Los datos se guardan en **Supabase**, así que
todos los dispositivos ven lo mismo al instante.

> La app está pensada primero para el celular: todas las pantallas se adaptan a pantallas angostas
> y se amplían en tablets y en la computadora.

---

## Índice

1. [Qué hace](#qué-hace)
2. [Roles: administrador y vendedor](#roles-administrador-y-vendedor)
3. [Tecnologías](#tecnologías)
4. [Estructura del proyecto](#estructura-del-proyecto)
5. [Puesta en marcha](#puesta-en-marcha)
6. [Base de datos (Supabase)](#base-de-datos-supabase)
7. [Compilar e instalar](#compilar-e-instalar)
8. [Pruebas](#pruebas)
9. [Seguridad](#seguridad)
10. [Convenciones del código](#convenciones-del-código)
11. [Problemas comunes](#problemas-comunes)
12. [Autor](#autor)

---

## Qué hace

### Vender
- Antes de vender se **abre la caja** con un monto inicial. Una vez abierta, la caja no se pierde
  aunque se cierre la app: solo se cierra cuando el empleado lo hace.
- Buscador de productos, carrito y cobro en **efectivo, transferencia, QR o pago mixto**.
- **Cantidades enteras** para lo que se vende por unidad, y **fracciones de carga** para arena y
  piedra (1/4, 1/3, 1/2, 2/3, 3/4, carga completa…), con el precio sugerido y editable. El stock se
  descuenta de a fracciones hasta completar la carga.
- **Descuento por producto** (en % o en guaraníes) y descuento al total de la venta.
- **Comprobante en PDF** con el nombre de quien atendió, para imprimir, descargar o compartir.
- **No se pierde la venta sin señal:** el carrito y el cobro quedan guardados en el teléfono y, al
  reintentar, la venta no se duplica (claves de idempotencia).
- Pestaña **Ventas de hoy** con cada movimiento del día; se reinicia a las 00:00. El administrador
  puede **anular** ventas indicando el motivo.

### Caja
- Apertura con monto inicial, **retiros de dinero** (efectivo o transferencia) con quién recibe,
  descripción opcional y comprobante con firmas.
- **Cierre con conteo de billetes y monedas** (100.000, 50.000, 20.000, 10.000, 5.000, 2.000 y
  monedas de 1.000, 500, 100 y 50). Lo que entró por transferencia se calcula solo.
- Muestra lo esperado, lo contado y si sobra o falta. La caja se cierra aunque no cuadre, y la
  diferencia queda registrada.
- **Arqueo en PDF** con el detalle por método de pago, quién abrió y cerró, fecha, hora y firmas.
- **Una caja por empleado**, como en los supermercados. El administrador ve todas las aperturas y
  cierres, imprime los arqueos y puede cerrar la caja de otro empleado.

### Inventario y compras
- Productos por categoría: cemento, hierros, ladrillos, arena y piedra, cal, Murocal, postes, caños
  y plomería, etc.
- Los productos **entran siempre por una compra**: proveedor, número de factura y día de compra,
  y compra por cargas con el precio de cada carga.
- **Costo promedio** automático, stock mínimo, alertas de stock bajo o agotado, ajustes de stock,
  mercadería averiada y devoluciones a proveedores.
- Historial de movimientos: entradas, salidas y ajustes.

### Presupuestos
- Presupuestos con los mismos productos y descuentos que una venta, en PDF listo para compartir,
  y convertibles en venta.

### Gastos del negocio
- Se registra cada gasto con su **categoría**: alquiler, sueldos, pago a empleados, flete, luz (ANDE),
  agua, internet y teléfono, combustible, repuestos y reparaciones, mantenimiento, impuestos,
  limpieza, útiles, publicidad, comida y bebida, y otros.
- Cada gasto lleva el monto, una descripción opcional, el **número de factura opcional** y el día y
  la hora en que se hizo.
- Reporte **diario, semanal, mensual** o por rango de fechas: total, desglose por categoría y
  detalle por día, con filtro por categoría.
- Los gastos se pueden anular con motivo: dejan de restar, pero quedan en el historial.

### Reportes e inicio
- **Inicio:** lo vendido hoy, la ganancia, los cobros por método, la semana, el mes y el año, la
  evolución de 12 meses, lo vendido por categoría y los productos más vendidos.
- **Reportes y arqueo:** lo invertido en compras, lo vendido, el costo de lo vendido, la ganancia,
  los gastos y la **ganancia real** (*ganancia de ventas − gastos − averiados*), además de la
  ganancia por producto.
- Exportación a **PDF y Excel**.

### Otros
- **Clientes**, con su historial de compras.
- **Empleados:** el administrador crea los usuarios de los vendedores.
- **Datos del negocio:** nombre, celular, logo y notas que salen en los comprobantes.
- Entrada con **huella / Face ID** y **bloqueo por intentos fallidos**: después de 5 intentos el
  ingreso queda bloqueado 30 minutos, y desde el 2.º intento se avisa cuántos quedan.

---

## Roles: administrador y vendedor

| | Administrador | Vendedor (empleado) |
|---|:---:|:---:|
| Vender y presupuestar | ✅ | ✅ |
| Abrir, retirar y cerrar **su** caja | ✅ | ✅ |
| Ver costos y ganancias | ✅ | ❌ (las columnas de costo están ocultas en la base) |
| Anular ventas | ✅ | ❌ |
| Inventario, compras, gastos, reportes, clientes, empleados, cajas de todos | ✅ | ❌ |

El rol vive en `app_members.role` y en el `app_metadata` del usuario, que solo puede cambiar el
servidor. La app usa el rol solo para mostrar u ocultar pantallas; **quien decide qué se puede leer o
escribir es la base de datos** (RLS y funciones con `assert_admin()`).

---

## Tecnologías

| Parte | Herramienta |
|---|---|
| App | Flutter (Dart ^3.13), Material 3, `provider` |
| Servidor | Supabase: Postgres, Auth, RLS, funciones RPC `SECURITY DEFINER` y una Edge Function en Deno |
| PDF e impresión | `pdf`, `printing` |
| Excel | `excel` |
| Guardado local | `shared_preferences` (venta en curso, bloqueo de login), `flutter_secure_storage` |
| Biometría | `local_auth` |
| Compartir | `share_plus`, `url_launcher`, `path_provider` |
| Instalador de Windows | Inno Setup 6 |

---

## Estructura del proyecto

```
lib/
├── main.dart              Arranque (si falla, muestra un aviso en vez de quedar trabada)
├── app.dart               Providers y tema
├── config/                Conexión a Supabase (claves inyectadas al compilar)
├── models/                Producto, venta, compra, caja, gasto, reportes…
├── repositories/          Acceso a Supabase (tablas y RPC)
├── providers/             Estado: sesión, catálogo, venta en curso, caja, refresco
├── screens/
│   ├── auth/              Ingreso, huella / Face ID
│   ├── shell/             Navegación principal (según el rol)
│   ├── inicio/            Panel de inicio
│   ├── vender/            Venta, cobro, comprobante
│   ├── caja/              Apertura, retiros, cierre con conteo, lista de cajas
│   ├── ventas/            Historial, ventas de hoy, devoluciones, anulación
│   ├── presupuestos/      Presupuestos
│   ├── inventario/        Productos, stock, ajustes, averiados
│   ├── compras/           Compras a proveedores
│   ├── gastos/            Gastos del negocio
│   ├── reportes/          Reportes y arqueo (PDF / Excel)
│   ├── clientes/  empleados/  movimientos/  negocio/  mas/
├── security/              Bloqueo por intentos, biometría, errores seguros
├── services/              PDF (comprobantes, caja, reportes) y compartir archivos
├── theme/  utils/  widgets/
supabase/
├── migrations/            Esquema, funciones y políticas, en orden
└── functions/empleados/   Edge Function para crear y administrar empleados
windows/installer/         Script de Inno Setup
test/                      Pruebas de modelos, pantallas y PDF
```

---

## Puesta en marcha

### Requisitos
- Flutter estable (Dart 3.13 o superior): `flutter doctor` sin errores.
- Para Android: Android Studio con el SDK.
- Para Windows: Visual Studio con "Desarrollo para el escritorio con C++".
- Un proyecto de Supabase.

### 1. Clonar e instalar dependencias
```bash
git clone <url-del-repositorio>
cd bm_construcciones
flutter pub get
```

### 2. Configurar las claves
Copiá `.env.example` como `.env` y completalo con los datos de Supabase
(*Project Settings → API*):

```env
SUPABASE_URL=https://TU-PROYECTO.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

> `.env` está en `.gitignore` y **no se sube**. Solo lleva la clave **pública** (*publishable*):
> nunca pongas ahí la clave `service_role` / `secret`.

### 3. Ejecutar
```bash
flutter run --dart-define-from-file=.env
```

> **Importante:** todos los comandos de `run` y `build` necesitan `--dart-define-from-file=.env`.
> Sin eso la app muestra "No se pudo abrir la app", porque no tiene con qué conectarse.

---

## Base de datos (Supabase)

### Migraciones
Los archivos de `supabase/migrations/` se aplican **en orden**:

| Migración | Contenido |
|---|---|
| `init_bm_schema` | Tablas base: productos, clientes, ventas, compras, presupuestos, movimientos |
| `idempotencia_y_stock` | Claves contra operaciones duplicadas, stock atómico |
| `validaciones_servidor` | Validaciones de textos, montos y cantidades en la base |
| `averiados` / `devoluciones_proveedores` | Mercadería averiada y devoluciones |
| `productos_por_carga` | Venta por fracciones de carga (arena, piedra) |
| `asociar_cliente` / `pago_mixto` | Cliente en la venta, pagos combinados |
| `dia_de_compra` | Proveedor, factura y día de compra |
| `seguridad_revision` | Endurecimiento de políticas y funciones |
| `empleados` / `costos_solo_admin` | Roles y columnas de costo ocultas al vendedor |
| `caja` / `caja_por_empleado` | Caja con apertura, retiros, cierre con conteo, una por empleado |
| `descuento_por_producto` | Descuento por línea en ventas y presupuestos |
| `gastos` | Gastos del negocio y ganancia real en los reportes |

Con la CLI de Supabase:
```bash
supabase link --project-ref <ref-del-proyecto>
supabase db push
```

> Algunas funciones se ajustaron directamente en el servidor (`create_sale`, `save_quote`,
> `sales_report`, `dashboard_summary`) y la migración correspondiente lo deja anotado. Ante una
> duda, la definición vigente es la de la base: `select pg_get_functiondef('public.<función>'::regprocedure);`.

### Edge Function `empleados`
Crea empleados, los activa o desactiva, les cambia la contraseña y los elimina. Usa la clave de
servicio, que vive **solo** en el servidor. Verifica que quien la llama sea administrador.
```bash
supabase functions deploy empleados
```

### Primer administrador
1. Crealo en *Authentication → Users*.
2. Agregalo a `app_members` con `role = 'admin'` y `active = true`.
3. Poné `{"role": "admin"}` en su `app_metadata`.

---

## Compilar e instalar

### Android (APK)
```bash
flutter build apk --release --dart-define-from-file=.env
# Sale en: build/app/outputs/flutter-apk/app-release.apk
```
Se copia al celular y se instala. Hay que permitir "instalar apps de origen desconocido".

> En `android/app/build.gradle.kts` la minificación (R8) está **desactivada**: con R8 se eliminaba
> el plugin de `shared_preferences` y la app quedaba trabada en el ícono.

### Windows (instalador)
```bash
flutter build windows --release --dart-define-from-file=.env
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /DVersion=1.0.0 /DSalida=%USERPROFILE%\Downloads windows\installer\bm_construcciones.iss
```
- El instalador no pide permiso de administrador.
- Crea accesos en el escritorio y en el menú Inicio, e incluye las DLL de Visual C++.
- Las versiones nuevas se instalan encima de la anterior (mismo `AppId`).
- Si Windows SmartScreen avisa, tocá **Más información → Ejecutar de todas formas**: el instalador
  no está firmado.

### Web (solo para pruebas en la red local)
```bash
flutter build web --release --dart-define-from-file=.env
cd build/web && python -m http.server 8765 --bind 0.0.0.0
# En el celular, con el mismo WiFi: http://<IP-de-la-compu>:8765
```

### Ícono
El ícono es la mascota (`assets/images/mascota.jpg`). Para regenerarlo:
`dart run flutter_launcher_icons`.

---

## Pruebas

```bash
flutter analyze
flutter test
```

Cubren cantidades y fracciones, validaciones, descuentos, la venta guardada sin señal, la caja
(conteo, retiros, cierre), los empleados, las ventas del día, los gastos y la ganancia real, y los
PDF. Las pruebas de pantallas usan ancho de celular (390 px) para detectar textos que no entran.

Las funciones del servidor se prueban dentro de un bloque `DO` que termina con `raise exception`,
así se deshace todo y no quedan datos de prueba.

---

## Seguridad

- **RLS en todas las tablas.** Los vendedores no pueden escribir directo: todo pasa por funciones
  RPC que validan permisos (`assert_can_write()`, `assert_admin()`), datos y stock.
- **Costos ocultos al vendedor** con permisos por columna. El administrador los lee con
  `productos_admin()` y `ventas_admin()`.
- **Idempotencia:** cada venta, compra, caja, retiro y gasto lleva una clave única. Si se envía dos
  veces, no se duplica. Si llega la misma clave con otros datos, el servidor responde `BM409`.
- **Validación doble:** en la app (formatos, solo números o solo letras donde corresponde) y en la
  base (checks y funciones).
- **Errores seguros:** nunca se muestra al usuario la respuesta cruda del servidor
  (`lib/security/registro_seguro.dart`).
- **Bloqueo de login:** 5 intentos fallidos bloquean el ingreso 30 minutos.
- **Claves:** la app solo lleva la clave pública. La clave de servicio está únicamente en la Edge
  Function.

---

## Convenciones del código

- **Todo en español:** textos de la app, comentarios, mensajes de error y nombres de dominio
  (`registrarGasto`, `cajaAbierta`…), con voseo ("tocá", "fijate").
- **Montos en guaraníes** como `int`, sin decimales, con punto de miles (`gs(150000)` → `Gs. 150.000`).
- Fechas y horas de Paraguay (`America/Asuncion`). Los "días" de los reportes van de 00:00 a 23:59.
- **Celular primero:** toda pantalla nueva se prueba a 390 px de ancho.

---

## Problemas comunes

| Problema | Solución |
|---|---|
| "No se pudo abrir la app" | Se compiló sin `--dart-define-from-file=.env`, o el `.env` está incompleto. |
| La APK queda trabada en el ícono | Revisar que R8 / minify siga desactivado en `build.gradle.kts`. |
| Windows avisa que el instalador no es confiable | Es por la falta de firma: **Más información → Ejecutar de todas formas**. |
| El celular no abre la versión web | El celular y la compu tienen que estar en el mismo WiFi, y el firewall tiene que permitir el puerto 8765. |
| "Esta operación ya se registró con otros datos" (`BM409`) | Se reintentó una operación que ya había entrado. Revisá el historial antes de cargarla de nuevo. |

---

## Autor

Desarrollado por [@GabrielLeon1111](https://github.com/GabrielLeon1111) para un negocio real de
materiales de construcción, que lo usa en el día a día: ventas en el mostrador, caja por empleado,
control de stock y reportes de ganancia.

**Lo que muestra este proyecto:**
- App multiplataforma (Android, Windows y web) con Flutter.
- Backend en Postgres / Supabase con seguridad a nivel de fila, permisos por columna y funciones
  transaccionales.
- Operaciones idempotentes a prueba de cortes de señal.
- Generación de PDF y Excel, roles de usuario y pruebas automáticas.

## Licencia

El código se publica como **portafolio**: se puede ver y estudiar libremente. Para usarlo con fines
comerciales hay que pedir permiso al autor. © 2026 · Todos los derechos reservados.
