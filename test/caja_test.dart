import 'package:bm_construcciones/models/business_settings.dart';
import 'package:bm_construcciones/models/caja.dart';
import 'package:bm_construcciones/services/pdf_caja.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

Map<String, dynamic> _cajaCerrada() => {
      'id': 'c1',
      'number': 3,
      'status': 'cerrada',
      'opened_by_name': 'Juan Pérez',
      'opened_by_username': 'juan.perez',
      'opened_by_role': 'vendedor',
      'opened_at': '2026-10-21T11:00:00Z',
      'opening_amount': 100000,
      'closed_by_name': 'Cesar',
      'closed_at': '2026-10-21T22:00:00Z',
      'sales_count': 5,
      'cash_sales': 850000,
      'transfer_sales': 400000,
      'withdrawals_total': 150000,
      'withdrawals_cash': 50000,
      'withdrawals_transfer': 100000,
      'expected_cash': 900000,
      'expected_transfer': 300000,
      'denominations': {'100000': 8, '50000': 1, '20000': 2, '10000': 0, '5000': 1, '2000': 0, '1000': 0, '500': 0, '100': 0, '50': 0},
      'counted_cash': 895000,
      'difference': -5000,
      'withdrawals': [
        {
          'id': 'w1',
          'number': 1,
          'amount': 50000,
          'method': 'efectivo',
          'received_by_name': 'Pedro Gómez',
          'description': 'Pago de flete',
          'given_by_name': 'Juan Pérez',
          'created_by_name': 'Juan Pérez',
          'created_at': '2026-10-21T15:00:00Z',
        },
        {
          'id': 'w2',
          'number': 2,
          'amount': 100000,
          'method': 'transferencia',
          'received_by_name': 'Cesar',
          'given_by_name': 'Juan Pérez',
          'created_by_name': 'Juan Pérez',
          'created_at': '2026-10-21T16:00:00Z',
        },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    Intl.defaultLocale = 'es';
    await initializeDateFormatting('es');
  });

  test('el conteo de billetes y monedas suma bien', () {
    expect(totalContado({100000: 8, 50000: 1, 20000: 2, 5000: 1, 50: 3}), 800000 + 50000 + 40000 + 5000 + 150);
    expect(denominacionesCaja, [100000, 50000, 20000, 10000, 5000, 2000, 1000, 500, 100, 50]);
  });

  test('retiros: efectivo hasta el monto de apertura; transferencia hasta lo que entró', () {
    final c = Caja.fromMap(_cajaCerrada());
    expect(c.withdrawalsCash, 50000);
    expect(c.withdrawalsTransfer, 100000);
    expect(c.disponibleParaRetiro('efectivo'), 50000); // 100.000 de apertura − 50.000 ya retirado
    expect(c.disponibleParaRetiro('transferencia'), 300000); // 400.000 − 100.000
    expect(c.retiros.first.metodoTexto, 'Efectivo');
    expect(c.denominations[100000], 8);
  });

  test('lista del administrador: sin totales, se suman de los retiros', () {
    final m = _cajaCerrada()
      ..remove('withdrawals_total')
      ..remove('withdrawals_cash')
      ..remove('withdrawals_transfer');
    m['cash_withdrawals'] = m.remove('withdrawals');
    final c = Caja.fromMap(m);
    expect(c.withdrawalsTotal, 150000);
    expect(c.withdrawalsCash, 50000);
    expect(c.withdrawalsTransfer, 100000);
  });

  test('se generan el comprobante del arqueo y el del retiro', () async {
    final c = Caja.fromMap(_cajaCerrada());
    const negocio = BusinessSettings();
    final arqueo = await generarArqueoPdf(c, negocio);
    final retiro = await generarRetiroPdf(c.retiros.first, negocio);
    expect(String.fromCharCodes(arqueo.take(4)), '%PDF');
    expect(String.fromCharCodes(retiro.take(4)), '%PDF');
  });
}
