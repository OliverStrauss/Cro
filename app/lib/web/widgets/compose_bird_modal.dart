import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/compose_bird_dialog.dart';
import '../../widgets/send_bird_dialog.dart';

/// The web "Send a bird" modal: a 620px card wrapping the exact same ComposeBirdForm the
/// phone app's ComposeBirdDialog uses (see compose_bird_dialog.dart) - the type/payload/
/// media/origin/destination/public logic lives in exactly one place, only the surrounding
/// chrome differs between platforms.
class ComposeBirdModal extends StatelessWidget {
  final List<SendBirdDestination> origins;
  final List<SendBirdDestination> destinations;
  final ValueChanged<ComposeBirdResult> onSubmit;

  const ComposeBirdModal({
    super.key,
    required this.origins,
    required this.destinations,
    required this.onSubmit,
  });

  static Future<void> show(
    BuildContext context, {
    required List<SendBirdDestination> origins,
    required List<SendBirdDestination> destinations,
    required ValueChanged<ComposeBirdResult> onSubmit,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => ComposeBirdModal(origins: origins, destinations: destinations, onSubmit: onSubmit),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      key: const Key('composeBirdModal'),
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 26, 28, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Send a bird', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const Text(
                  'Pick a type, write what it carries, and choose where it flies',
                  style: TextStyle(fontSize: 12.5, color: CroColors.fog),
                ),
                const SizedBox(height: 20),
                ComposeBirdForm(
                  origins: origins,
                  destinations: destinations,
                  onCancel: () => Navigator.of(context).pop(),
                  onSubmit: (result) {
                    Navigator.of(context).pop();
                    onSubmit(result);
                  },
                  submitLabel: 'Release the bird',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
