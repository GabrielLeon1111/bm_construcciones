import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../../models/business_settings.dart';
import '../../models/doc_line.dart';
import '../../providers/settings_provider.dart';
import '../../security/registro_seguro.dart';
import '../../services/pdf_documento.dart';
import '../../theme/app_theme.dart';
import '../../utils/validacion.dart';
import '../../widgets/common.dart';

/// Datos del negocio: salen en los comprobantes y presupuestos.
class BusinessScreen extends StatefulWidget {
  const BusinessScreen({super.key});

  @override
  State<BusinessScreen> createState() => _BusinessScreenState();
}

class _BusinessScreenState extends State<BusinessScreen> {
  final _form = GlobalKey<FormState>();
  late BusinessSettings _s = context.read<SettingsProvider>().settings;
  late final _name = TextEditingController(text: _s.name);
  late final _tagline = TextEditingController(text: _s.tagline);
  late final _phone = TextEditingController(text: _s.phone);
  late final _city = TextEditingController(text: _s.city);
  late final _address = TextEditingController(text: _s.address ?? '');
  late final _ruc = TextEditingController(text: _s.ruc ?? '');
  late final _email = TextEditingController(text: _s.email ?? '');
  late final _receiptNote = TextEditingController(text: _s.receiptNote ?? '');
  late final _quoteNote = TextEditingController(text: _s.quoteNote ?? '');
  late int _validity = _s.quoteValidityDays;
  bool _saving = false;
  bool _uploading = false;

  BusinessSettings get _current => BusinessSettings(
        name: limpiarTexto(_name.text),
        tagline: limpiarTexto(_tagline.text),
        phone: limpiarTexto(_phone.text),
        city: limpiarTexto(_city.text),
        address: limpiarTexto(_address.text),
        ruc: limpiarTexto(_ruc.text).replaceAll('.', ''),
        email: limpiarTexto(_email.text),
        logoUrl: context.read<SettingsProvider>().settings.logoUrl,
        receiptNote: limpiarTexto(_receiptNote.text, multilinea: true),
        quoteNote: limpiarTexto(_quoteNote.text, multilinea: true),
        quoteValidityDays: _validity,
      );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final ok = await runSafe(context, 'guardarNegocio', () => context.read<SettingsProvider>().guardar(_current), ok: 'Datos guardados');
    if (mounted) setState(() => _saving = false);
    if (ok && mounted) _s = context.read<SettingsProvider>().settings;
  }

  Future<void> _pickLogo() async {
    try {
      final img = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, maxHeight: 800, imageQuality: 90);
      if (img == null || !mounted) return;
      setState(() => _uploading = true);
      final bytes = await img.readAsBytes();
      final ext = img.name.contains('.') ? img.name.split('.').last : 'png';
      if (!mounted) return;
      await runSafe(context, 'subirLogo', () => context.read<SettingsProvider>().subirLogo(bytes, ext), ok: 'Logo actualizado');
    } catch (e) {
      registrarError('elegirLogo', e);
      if (mounted) showSnack(context, mensajeErrorSeguro(e, 'No se pudo cargar la imagen.'), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _preview() {
    final negocio = _current;
    final ejemplo = DatosDocumento(
      tipo: TipoDocumento.venta,
      numero: 1,
      fecha: DateTime.now(),
      cliente: 'Cliente de ejemplo',
      documento: '1.234.567',
      telefono: '0981 000000',
      lineas: const [
        DocLine(description: 'Arena lavada', unit: 'camión', quantity: 0.5, unitPrice: 600000),
        DocLine(description: 'Triturada', unit: 'kg', quantity: 3000, unitPrice: 170),
        DocLine(description: 'Varilla 8', unit: 'unidad', quantity: 2, unitPrice: 40000),
        DocLine(description: 'Varilla 4', unit: 'unidad', quantity: 2, unitPrice: 20000),
        DocLine(description: 'Cemento', unit: 'bolsa', quantity: 2, unitPrice: 70000),
        DocLine(description: 'Cal', unit: 'bolsa', quantity: 2, unitPrice: 30000),
        DocLine(description: 'Caño de 100', unit: 'unidad', quantity: 3, unitPrice: 75000),
        DocLine(description: 'Murocal', unit: 'lt', quantity: 1, unitPrice: 0, isGift: true),
      ],
      subtotal: 1355000,
      descuento: 0,
      total: 1355000,
      metodoPago: 'efectivo',
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Así sale el comprobante')),
          body: PdfPreview(
            build: (_) => generarDocumentoPdf(ejemplo, negocio),
            canChangeOrientation: false,
            canChangePageFormat: false,
            canDebug: false,
            pdfFileName: 'Ejemplo_comprobante.pdf',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final logo = context.watch<SettingsProvider>().settings.logoUrl;
    return Scaffold(
      appBar: AppBar(title: const Text('Datos del negocio')),
      body: Form(
        key: _form,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                const SectionTitle('Logo del comprobante', padding: EdgeInsets.fromLTRB(4, 4, 4, 10)),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(color: AppColors.concrete, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
                          clipBehavior: Clip.antiAlias,
                          child: logo == null
                              ? const Icon(Icons.image_outlined, size: 36, color: AppColors.muted)
                              : Image.network(logo, fit: BoxFit.contain, errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Va en el recuadro de la derecha, debajo del celular (como el muñequito del talonario).',
                                  style: TextStyle(color: AppColors.muted)),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: _uploading ? null : _pickLogo,
                                    icon: _uploading
                                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                        : const Icon(Icons.upload_rounded),
                                    label: Text(logo == null ? 'Subir imagen' : 'Cambiar'),
                                  ),
                                  if (logo != null)
                                    TextButton(
                                      onPressed: () => runSafe(context, 'quitarLogo', () => context.read<SettingsProvider>().quitarLogo()),
                                      child: const Text('Quitar'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SectionTitle('Encabezado'),
                TextFormField(
                  controller: _name,
                  inputFormatters: formatoTexto(Largo.nombre),
                  decoration: const InputDecoration(
                    labelText: 'Nombre del negocio *',
                    hintText: 'Ej: BM. Construcciones',
                    helperText: 'La primera palabra sale grande (ej: "BM.")',
                  ),
                  validator: validarTexto(campo: 'el nombre', obligatorio: true, max: Largo.nombre),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _tagline,
                  inputFormatters: formatoTexto(Largo.titulo),
                  decoration: const InputDecoration(labelText: 'Título del comprobante *', hintText: 'Ej: Venta de materiales'),
                  validator: validarTexto(campo: 'el título', obligatorio: true, max: Largo.titulo),
                ),
                const SizedBox(height: 12),
                FilaCampos(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 +()-]')), LengthLimitingTextInputFormatter(Largo.telefono)],
                        decoration: const InputDecoration(labelText: 'Celular *', hintText: 'Ej: 0981 000000'),
                        validator: (v) => validarTelefono(v, obligatorio: true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _city,
                        inputFormatters: formatoTexto(Largo.ciudad),
                        decoration: const InputDecoration(labelText: 'Ciudad *', hintText: 'Ej: Carapeguá'),
                        validator: validarTexto(campo: 'la ciudad', obligatorio: true, max: Largo.ciudad),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _address,
                  inputFormatters: formatoTexto(Largo.direccion),
                  decoration: const InputDecoration(labelText: 'Dirección (opcional)', hintText: 'Ej: Ruta 1 km 84'),
                  validator: validarTexto(campo: 'la dirección', max: Largo.direccion),
                ),
                const SizedBox(height: 12),
                FilaCampos(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _ruc,
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.-]')), LengthLimitingTextInputFormatter(Largo.documento)],
                        decoration: const InputDecoration(labelText: 'RUC (opcional)', hintText: 'Ej: 80012345-6'),
                        validator: validarRuc,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s')), LengthLimitingTextInputFormatter(Largo.email)],
                        decoration: const InputDecoration(labelText: 'Email (opcional)', hintText: 'Ej: bm@gmail.com'),
                        validator: validarEmail,
                      ),
                    ),
                  ],
                ),
                const SectionTitle('Notas al pie'),
                TextFormField(
                  controller: _receiptNote,
                  maxLines: 2,
                  inputFormatters: formatoTexto(Largo.notas),
                  decoration: const InputDecoration(labelText: 'En la nota de venta (opcional)', hintText: 'Ej: Gracias por su compra'),
                  validator: validarTexto(campo: 'la nota', max: Largo.notas, multilinea: true),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _quoteNote,
                  maxLines: 2,
                  inputFormatters: formatoTexto(Largo.notas),
                  decoration: const InputDecoration(labelText: 'En el presupuesto (opcional)', hintText: 'Ej: Precios sujetos a cambio sin previo aviso'),
                  validator: validarTexto(campo: 'la nota', max: Largo.notas, multilinea: true),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: const [3, 5, 7, 10, 15, 30].contains(_validity) ? _validity : 7,
                  decoration: const InputDecoration(labelText: 'Validez de los presupuestos'),
                  items: [for (final d in const [3, 5, 7, 10, 15, 30]) DropdownMenuItem(value: d, child: Text('$d días'))],
                  onChanged: (v) => setState(() => _validity = v ?? 7),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(onPressed: _preview, icon: const Icon(Icons.visibility_outlined), label: const Text('Ver cómo sale el comprobante')),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Text('Guardar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
