import '../data/prospekt_offers_repository.dart';
import '../models/prospekt_offer.dart';
import 'prospekt_api_client.dart';

typedef SyncProgress = void Function(String status);

class OffersSyncService {
  final ProspektApiClient api;
  final ProspektOffersRepository repo;

  OffersSyncService({required this.api, required this.repo});

  /// Lädt Angebote vom Server und ersetzt lokal komplett.
  Future<int> syncReplaceAll({SyncProgress? onProgress}) async {
    onProgress?.call('Lade Angebote vom Server…');
    final offers = await api.fetchAllOffers();
    onProgress?.call('Speichere lokal (${offers.length})…');
    final written = await repo.upsertManyReplaceAll(offers);
    onProgress?.call('Sync fertig: $written Angebote');
    return written;
  }
}