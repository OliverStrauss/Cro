import 'package:flutter/material.dart';

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
  static const restaurant = 'Restaurant';
  static const coffee = 'Coffee';
  static const grocery = 'Grocery';
  static const other = 'Other';

  static const all = [
    housing,
    iowaState,
    bar,
    park,
    business,
    landmark,
    restaurant,
    coffee,
    grocery,
    other,
  ];

  // Default avatar icon shown for a hub with no approved photo yet.
  static const Map<String, IconData> icons = {
    housing: Icons.home_rounded,
    iowaState: Icons.school_rounded,
    bar: Icons.local_bar_rounded,
    park: Icons.park_rounded,
    business: Icons.storefront_rounded,
    landmark: Icons.location_city_rounded,
    restaurant: Icons.restaurant_rounded,
    coffee: Icons.local_cafe_rounded,
    grocery: Icons.local_grocery_store_rounded,
    other: Icons.place_rounded,
  };

  static IconData iconFor(String? category) => icons[category] ?? icons[landmark]!;
}
