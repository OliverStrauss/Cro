import 'package:flutter/material.dart';

// Prompts for a nest name. Used both to name a brand new nest (from the map, unprefilled)
// and to rename an existing one (from My Nests, prefilled via initialName). Pops the
// entered name, or null if canceled/left empty. kindLabel is display-only (e.g. "Public
// nest") so naming a brand-new nest isn't blind about which slot it's filling - it doesn't
// affect what gets saved, since the kind was already decided before this dialog opens.
class WaypointNameDialog extends StatefulWidget {
  final String? initialName;
  final String? kindLabel;

  const WaypointNameDialog({super.key, this.initialName, this.kindLabel});

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
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.kindLabel != null) ...[
            Text(
              widget.kindLabel!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            key: const Key('waypointNameField'),
            controller: _controller,
            decoration: const InputDecoration(labelText: 'Name'),
            autofocus: true,
          ),
        ],
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
