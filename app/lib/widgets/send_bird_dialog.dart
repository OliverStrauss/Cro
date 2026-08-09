import 'package:flutter/material.dart';

class SendBirdDestination {
  final String nestId;
  final String label;

  SendBirdDestination({required this.nestId, required this.label});
}

class SendBirdResult {
  final String nestId;
  final String? content;

  SendBirdResult({required this.nestId, this.content});
}

// Picks a destination nest (the sender's own others, or a friend's) and an optional
// message, then pops a SendBirdResult - the caller is responsible for actually calling
// BirdService.sendBird, same "dialog only collects input" split as WaypointNameDialog.
class SendBirdDialog extends StatefulWidget {
  final List<SendBirdDestination> destinations;

  const SendBirdDialog({super.key, required this.destinations});

  @override
  State<SendBirdDialog> createState() => _SendBirdDialogState();
}

class _SendBirdDialogState extends State<SendBirdDialog> {
  String? _selectedNestId;
  final _contentController = TextEditingController();

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Send this bird'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.destinations.isEmpty)
            const Text('No other nests to send to yet.')
          else
            DropdownButton<String>(
              key: const Key('sendBirdDestinationDropdown'),
              value: _selectedNestId,
              isExpanded: true,
              hint: const Text('Choose a destination'),
              items: widget.destinations
                  .map((d) => DropdownMenuItem(value: d.nestId, child: Text(d.label)))
                  .toList(),
              onChanged: (value) => setState(() => _selectedNestId = value),
            ),
          TextField(
            key: const Key('sendBirdMessageField'),
            controller: _contentController,
            decoration: const InputDecoration(labelText: 'Message (optional)'),
            maxLines: 3,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        TextButton(
          key: const Key('confirmSendBirdButton'),
          onPressed: _selectedNestId == null
              ? null
              : () => Navigator.of(context).pop(SendBirdResult(
                    nestId: _selectedNestId!,
                    content: _contentController.text.trim().isEmpty ? null : _contentController.text.trim(),
                  )),
          child: const Text('Send'),
        ),
      ],
    );
  }
}
