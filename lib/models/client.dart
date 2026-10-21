import 'json.dart';

class Client {
  final String id;
  final String fullName;
  final String? phone;
  final String? document;
  final String? address;
  final String? notes;

  const Client({required this.id, required this.fullName, this.phone, this.document, this.address, this.notes});

  factory Client.fromMap(Map<String, dynamic> m) => Client(
        id: m['id'] as String,
        fullName: m['full_name'] as String,
        phone: textOrNull(m['phone']),
        document: textOrNull(m['document']),
        address: textOrNull(m['address']),
        notes: textOrNull(m['notes']),
      );

  Map<String, dynamic> toEditable() => {
        'full_name': fullName.trim(),
        'phone': textOrNull(phone),
        'document': textOrNull(document),
        'address': textOrNull(address),
        'notes': textOrNull(notes),
      };

  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}
