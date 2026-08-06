import 'package:flutter/material.dart';

// Must stay in sync with api/Services/FriendColorPalette.cs's palette - there's no shared
// schema/codegen between the .NET backend and Flutter frontend in this repo, so a change
// on one side needs a matching manual edit on the other.
const List<String> friendColorPalette = [
  '#E53935',
  '#1E88E5',
  '#43A047',
  '#FB8C00',
  '#8E24AA',
  '#00ACC1',
  '#FDD835',
  '#6D4C41',
];

Color hexToColor(String hex) {
  final normalized = hex.replaceFirst('#', '');
  return Color(int.parse('ff$normalized', radix: 16));
}
