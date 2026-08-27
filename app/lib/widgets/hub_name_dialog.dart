import 'package:flutter/material.dart';

// Prompts an admin for a new Hub's name and an optional category (e.g. "Library", "Gym").
// Pops a HubNameDialogResult, or null if canceled/left with an empty name.
class HubNameDialogResult {
  final String name;
  final String? category;

  HubNameDialogResult({required this.name, this.category});
}

class HubNameDialog extends StatefulWidget {
  const HubNameDialog({super.key});

  @override
  State<HubNameDialog> createState() => _HubNameDialogState();
}

class _HubNameDialogState extends State<HubNameDialog> {
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Name this Hub'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('hubNameField'),
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Name'),
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('hubCategoryField'),
            controller: _categoryController,
            decoration: const InputDecoration(labelText: 'Category (optional)'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('saveHubButton'),
          onPressed: () => Navigator.of(context).pop(
            HubNameDialogResult(
              name: _nameController.text,
              category: _categoryController.text.trim().isEmpty ? null : _categoryController.text.trim(),
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
