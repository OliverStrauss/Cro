import 'package:flutter/material.dart';

import '../../theme.dart';

/// A station coordinate readout in the Radio Log data voice - one call site for "how do we
/// typeset a lat/lng pair" instead of three ad hoc copies. `centered` actually centers the
/// text within its available width (a bare `Text.textAlign` does nothing unless the Text's own
/// box already spans that width, which is exactly the bug this replaces: hub_panel_content
/// centered its avatar/name/subtitle block but left its coordinates line flush left directly
/// underneath).
class CoordinateReadout extends StatelessWidget {
  final double latitude;
  final double longitude;
  final bool centered;

  const CoordinateReadout({super.key, required this.latitude, required this.longitude, this.centered = false});

  @override
  Widget build(BuildContext context) {
    final text = Text(
      '(${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)})',
      style: CroTextStyles.data(),
    );
    return centered ? Center(child: text) : text;
  }
}
