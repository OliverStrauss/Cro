import 'package:flutter/material.dart';

import '../models/hub_category.dart';
import '../services/profile_service.dart';

// Prompts for a new Hub's name, category (picked from HubCategory.all rather than typed as
// free text), and an optional photo - shown to both an admin (creating outright) and anyone
// else (submitting a suggestion), so the photo travels with the suggestion instead of only
// being addable after an admin approves it (see HubPanelContent._suggestPicture). Pops a
// HubNameDialogResult, or null if canceled/left with an empty name.
class HubNameDialogResult {
  final String name;
  final String category;
  final List<int>? imageBytes;
  final String? imageFilename;
  final String? imageContentType;

  HubNameDialogResult({
    required this.name,
    required this.category,
    this.imageBytes,
    this.imageFilename,
    this.imageContentType,
  });
}

class HubNameDialog extends StatefulWidget {
  final ProfileService profileService;

  const HubNameDialog({super.key, required this.profileService});

  @override
  State<HubNameDialog> createState() => _HubNameDialogState();
}

class _HubNameDialogState extends State<HubNameDialog> {
  final _nameController = TextEditingController();
  String _category = HubCategory.other;
  List<int>? _imageBytes;
  String? _imageFilename;
  String? _imageContentType;
  String? _imageError;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    setState(() => _imageError = null);
    try {
      final xFile = await widget.profileService.pickImage();
      if (xFile == null) return;
      final bytes = await xFile.readAsBytes();
      setState(() {
        _imageBytes = bytes;
        _imageFilename = xFile.name;
        _imageContentType = xFile.mimeType ?? 'image/jpeg';
      });
    } catch (e) {
      setState(() => _imageError = e.toString());
    }
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
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('hubImagePickButton'),
              onPressed: _pickImage,
              icon: const Icon(Icons.photo_camera, size: 18),
              label: Text(_imageBytes == null ? 'Add a photo (optional)' : 'Photo selected — tap to change'),
            ),
          ),
          if (_imageError != null) ...[
            const SizedBox(height: 6),
            Text(_imageError!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 12)),
          ],
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
              imageBytes: _imageBytes,
              imageFilename: _imageFilename,
              imageContentType: _imageContentType,
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
