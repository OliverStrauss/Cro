import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cro_app/utils/color_utils.dart';

void main() {
  test('hexToColor parses a hex string into an opaque Color', () {
    expect(hexToColor('#E53935'), const Color(0xFFE53935));
  });

  test('every palette entry parses without error', () {
    for (final hex in friendColorPalette) {
      expect(() => hexToColor(hex), returnsNormally);
    }
  });
}
