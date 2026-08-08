import 'package:flutter/material.dart';

// Prompts for a nest name. Used both to name a brand new nest (from the map, unprefilled)
// and to rename an existing one (from My Nests, prefilled via initialName). Pops the
// entered name, or null if canceled/left empty.
class WaypointNameDialog extends StatefulWidget {
  final String? initialName;

  const WaypointNameDialog({super.key, this.initialName});

  @override
  State<WaypointNameDialog> createState() => _WaypointNameDialogState();
}

class _WaypointNameDialogState extends State<WaypointNameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialName == null ? 'Name this nest' : 'Rename this nest'),
      content: TextField(
        key: const Key('waypointNameField'),
        controller: _controller,
        decoration: const InputDecoration(labelText: 'Name'),
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('saveWaypointButton'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
