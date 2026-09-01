import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/models/hub_category.dart';

void main() {
  test('iconFor returns the mapped icon for every known category', () {
    expect(HubCategory.iconFor(HubCategory.housing), Icons.home_rounded);
    expect(HubCategory.iconFor(HubCategory.iowaState), Icons.school_rounded);
    expect(HubCategory.iconFor(HubCategory.bar), Icons.local_bar_rounded);
    expect(HubCategory.iconFor(HubCategory.park), Icons.park_rounded);
    expect(HubCategory.iconFor(HubCategory.business), Icons.storefront_rounded);
    expect(HubCategory.iconFor(HubCategory.landmark), Icons.location_city_rounded);
    expect(HubCategory.iconFor(HubCategory.other), Icons.place_rounded);
  });

  test('iconFor falls back to the Landmark icon for null or an unknown category', () {
    expect(HubCategory.iconFor(null), HubCategory.icons[HubCategory.landmark]);
    expect(HubCategory.iconFor('Something Unrecognized'), HubCategory.icons[HubCategory.landmark]);
  });
}
