import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/refresh_bus.dart';
import '../security/registro_seguro.dart';
import 'common.dart';

/// Carga datos con un Future y los vuelve a pedir cuando cambia algo en la app
/// (RefreshBus) o cuando el usuario tira hacia abajo.
class ReloadingFuture<T> extends StatefulWidget {
  const ReloadingFuture({super.key, required this.load, required this.builder, this.contexto = 'carga'});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;
  final String contexto;

  @override
  State<ReloadingFuture<T>> createState() => ReloadingFutureState<T>();
}

class ReloadingFutureState<T> extends State<ReloadingFuture<T>> {
  T? _data;
  Object? _error;
  bool _loading = true;
  int _seenVersion = -1;
  late RefreshBus _bus;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bus = context.read<RefreshBus>();
    _bus.removeListener(_onBus);
    _bus.addListener(_onBus);
    if (_seenVersion == -1) {
      _seenVersion = _bus.version;
      reload();
    }
  }

  void _onBus() {
    if (_bus.version != _seenVersion) {
      _seenVersion = _bus.version;
      reload();
    }
  }

  Future<void> reload() async {
    if (mounted) setState(() => _loading = _data == null);
    try {
      final d = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      registrarError(widget.contexto, e);
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _bus.removeListener(_onBus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) return const Center(child: CircularProgressIndicator());
    if (_error != null && _data == null) {
      return ErrorRetry(message: mensajeErrorSeguro(_error!, 'Revisá tu conexión e intentá de nuevo.'), onRetry: reload);
    }
    return widget.builder(context, _data as T, reload);
  }
}
