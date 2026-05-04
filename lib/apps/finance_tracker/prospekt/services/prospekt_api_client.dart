import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/prospekt_offer.dart';

class ProspektApiClient {
  final String baseUrl;

  /// Beispiel: http://10.171.219.157:8000
  const ProspektApiClient({required this.baseUrl});

  Uri _u(String path, [Map<String, String>? q]) {
    final cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$cleanBase$cleanPath').replace(queryParameters: q);
  }

  /// Erwartet ein public Read-Only Endpoint am Server.
  /// Passe die Pfade an deinen Server an, falls sie anders heißen.
  Future<List<ProspektOffer>> fetchAllOffers({int limit = 5000}) async {
    final uri = _u('/public/api/offers', {'limit': '$limit'});

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('fetchAllOffers failed: ${res.statusCode} ${res.body}');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map) return const [];

    final items = decoded['offers'];
    if (items is! List) return const [];

    return items
        .whereType<Map>()
        .map((m) {
          final market = (m['market'] ?? '').toString();
          final title = (m['title'] ?? '').toString();
          final price = _asDouble(m['price_eur']);
          final qty = (m['quantity'] ?? '').toString();
          return ProspektOffer(
            market: market,
            title: title,
            priceEur: price,
            quantity: qty,
          );
        })
        .toList();
  }

  double _asDouble(Object? v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }
}