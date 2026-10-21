import '../config/supabase_config.dart';
import '../models/reports.dart';
import 'rangos.dart';

class ReportRepository {
  // RPC dashboard_summary: todos los números del inicio en una sola llamada.
  Future<DashboardData> dashboard() async {
    final data = await supa.rpc('dashboard_summary');
    return DashboardData.fromMap(Map<String, dynamic>.from(data as Map));
  }

  // RPC sales_report: arqueo de un rango de fechas (inclusive).
  Future<SalesReport> salesReport(DateTime from, DateTime to) async {
    final data = await supa.rpc('sales_report', params: {'p_from': fechaSql(from), 'p_to': fechaSql(to)});
    return SalesReport.fromMap(from, to, Map<String, dynamic>.from(data as Map));
  }
}
