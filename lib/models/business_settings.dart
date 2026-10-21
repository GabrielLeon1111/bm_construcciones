import 'json.dart';

class BusinessSettings {
  final String name;
  final String tagline;
  final String phone;
  final String city;
  final String? address;
  final String? ruc;
  final String? email;
  final String? logoUrl;
  final String? receiptNote;
  final String? quoteNote;
  final int quoteValidityDays;

  const BusinessSettings({
    this.name = 'BM. Construcciones',
    this.tagline = 'Venta de materiales',
    this.phone = '0981000000',
    this.city = 'Carapeguá',
    this.address,
    this.ruc,
    this.email,
    this.logoUrl,
    this.receiptNote,
    this.quoteNote,
    this.quoteValidityDays = 7,
  });

  factory BusinessSettings.fromMap(Map<String, dynamic> m) => BusinessSettings(
        name: (m['name'] as String?) ?? 'BM. Construcciones',
        tagline: (m['tagline'] as String?) ?? 'Venta de materiales',
        phone: (m['phone'] as String?) ?? '',
        city: (m['city'] as String?) ?? '',
        address: textOrNull(m['address']),
        ruc: textOrNull(m['ruc']),
        email: textOrNull(m['email']),
        logoUrl: textOrNull(m['logo_url']),
        receiptNote: textOrNull(m['receipt_note']),
        quoteNote: textOrNull(m['quote_note']),
        quoteValidityDays: toInt(m['quote_validity_days']) == 0 ? 7 : toInt(m['quote_validity_days']),
      );

  Map<String, dynamic> toEditable() => {
        'name': name.trim(),
        'tagline': tagline.trim(),
        'phone': phone.trim(),
        'city': city.trim(),
        'address': textOrNull(address),
        'ruc': textOrNull(ruc),
        'email': textOrNull(email),
        'logo_url': logoUrl,
        'receipt_note': textOrNull(receiptNote),
        'quote_note': textOrNull(quoteNote),
        'quote_validity_days': quoteValidityDays,
      };

  /// "BM. Construcciones" -> ("BM.", "Construcciones") para la marca en dos partes.
  (String, String) get brandParts {
    final n = name.trim();
    final i = n.indexOf(' ');
    if (i <= 0) return (n, '');
    return (n.substring(0, i), n.substring(i + 1));
  }

  BusinessSettings copyWith({String? logoUrl, bool clearLogo = false}) => BusinessSettings(
        name: name,
        tagline: tagline,
        phone: phone,
        city: city,
        address: address,
        ruc: ruc,
        email: email,
        logoUrl: clearLogo ? null : (logoUrl ?? this.logoUrl),
        receiptNote: receiptNote,
        quoteNote: quoteNote,
        quoteValidityDays: quoteValidityDays,
      );
}
