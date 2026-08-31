import 'package:flutter/material.dart';

import '../models/hub_category.dart';

// Prompts an admin for a new Hub's name and category, picked from HubCategory.all rather
// than typed as free text. Pops a HubNameDialogResult, or null if canceled/left with an
// empty name.
class HubNameDialogResult {
  final String name;
  final String category;

  HubNameDialogResult({required this.name, required this.category});
}

class HubNameDialog extends StatefulWidget {
  const HubNameDialog({super.key});

  @override
  State<HubNameDialog> createState() => _HubNameDialogState();
}

class _HubNameDialogState extends State<HubNameDialog> {
  final _nameController = TextEditingController();
  String _category = HubCategory.other;

  @override
  void dispose() {
    _nameController.dispose();
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
          DropdownButtonFormField<String>(
            key: const Key('hubCategoryField'),
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              for (final category in HubCategory.all) DropdownMenuItem(value: category, child: Text(category)),
            ],
            onChanged: (value) => setState(() => _category = value ?? HubCategory.other),
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
              category: _category,
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
