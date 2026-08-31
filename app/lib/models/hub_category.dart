// The fixed set of category labels a Hub can be tagged with, mirroring
// api/Services/HubCategoryCatalog.cs. Kept manually in sync with the backend, same
// convention as BirdType in bird.dart.
class HubCategory {
  static const housing = 'Housing';
  static const iowaState = 'Iowa State';
  static const bar = 'Bar';
  static const park = 'Park';
  static const business = 'Business';
  static const landmark = 'Landmark';
  static const other = 'Other';

  static const all = [housing, iowaState, bar, park, business, landmark, other];
}
