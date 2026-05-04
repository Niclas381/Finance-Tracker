import '../models/prospekt_offer.dart';
import 'prospekt_offers_repository.dart';

abstract class ProspektSearchDataSource {
  Future<List<ProspektOffer>> search({
    required String query,
    String? market,
    double? minPrice,
    double? maxPrice,
    int limit,
    int offset,
  });

  Future<int> count({
    required String query,
    String? market,
    double? minPrice,
    double? maxPrice,
  });

  Future<List<String>> markets();
}

class LocalProspektSearchDataSource implements ProspektSearchDataSource {
  final ProspektOffersRepository _repo;

  LocalProspektSearchDataSource(this._repo);

  @override
  Future<List<ProspektOffer>> search({
    required String query,
    String? market,
    double? minPrice,
    double? maxPrice,
    int limit = 100,
    int offset = 0,
  }) {
    return _repo.searchOffers(
      query: query,
      market: market,
      minPrice: minPrice,
      maxPrice: maxPrice,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<int> count({
    required String query,
    String? market,
    double? minPrice,
    double? maxPrice,
  }) {
    return _repo.countOffers(
      query: query,
      market: market,
      minPrice: minPrice,
      maxPrice: maxPrice,
    );
  }

  @override
  Future<List<String>> markets() => _repo.listMarkets();
}