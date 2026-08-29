import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';

import '../models/bird.dart';
import '../theme.dart';
import 'send_bird_dialog.dart';

class ComposeBirdResult {
  final String type;
  final String name;
  final String originNestId;
  final String destinationId;
  final String? content;
  final bool isPublic;
  final List<int>? mediaBytes;
  final String? mediaContentType;
  final String? mediaFilename;

  ComposeBirdResult({
    required this.type,
    required this.name,
    required this.originNestId,
    required this.destinationId,
    this.content,
    required this.isPublic,
    this.mediaBytes,
    this.mediaContentType,
    this.mediaFilename,
  });
}

// Thin AlertDialog wrapper around ComposeBirdForm - kept as its own widget (rather than
// callers using ComposeBirdForm directly) so every existing call site's `showDialog(builder:
// (_) => ComposeBirdDialog(...))` keeps working unchanged. The web shell's compose modal
// (compose_bird_modal.dart) wraps the same ComposeBirdForm in a 620px Dialog shell instead of
// this AlertDialog chrome - the actual field/validation/media logic lives in exactly one
// place either way.
class ComposeBirdDialog extends StatelessWidget {
  final List<SendBirdDestination> origins;
  final List<SendBirdDestination> destinations;
  final AudioRecorder? recorder;
  final ImagePicker? imagePicker;

  const ComposeBirdDialog({
    super.key,
    required this.origins,
    required this.destinations,
    this.recorder,
    this.imagePicker,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Spawn a bird'),
      content: SingleChildScrollView(
        child: ComposeBirdForm(
          origins: origins,
          destinations: destinations,
          recorder: recorder,
          imagePicker: imagePicker,
          onCancel: () => Navigator.of(context).pop(),
          onSubmit: (result) => Navigator.of(context).pop(result),
        ),
      ),
    );
  }
}

// The actual spawn-and-send form: pick a type, fill that type's required payload, pick
// where it departs from (only asked when the caller owns 2 nests) and where it's headed,
// optionally flag it public, then Cancel/Send. Renders its own Cancel/Send row (rather than
// relying on a host AlertDialog's `actions`) so it's a fully self-contained widget any
// dialog/modal shell can embed without needing to mirror its internal validity state.
class ComposeBirdForm extends StatefulWidget {
  final List<SendBirdDestination> origins;
  final List<SendBirdDestination> destinations;
  final AudioRecorder? recorder;
  final ImagePicker? imagePicker;
  final VoidCallback onCancel;
  final ValueChanged<ComposeBirdResult> onSubmit;
  final String submitLabel;

  const ComposeBirdForm({
    super.key,
    required this.origins,
    required this.destinations,
    this.recorder,
    this.imagePicker,
    required this.onCancel,
    required this.onSubmit,
    this.submitLabel = 'Send',
  });

  @override
  State<ComposeBirdForm> createState() => _ComposeBirdFormState();
}

class _ComposeBirdFormState extends State<ComposeBirdForm> {
  late final AudioRecorder _recorder = widget.recorder ?? AudioRecorder();
  late final ImagePicker _imagePicker = widget.imagePicker ?? ImagePicker();

  String _type = BirdType.cro;
  final _nameController = TextEditingController();
  final _contentController = TextEditingController();
  String? _originNestId;
  String? _destinationId;
  bool _isPublic = false;

  bool _isRecording = false;
  List<int>? _audioBytes;
  StreamSubscription<Uint8List>? _audioSub;
  List<int>? _imageBytes;
  String? _imageFilename;

  @override
  void initState() {
    super.initState();
    if (widget.origins.length == 1) {
      _originNestId = widget.origins.first.nestId;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contentController.dispose();
    _audioSub?.cancel();
    if (widget.recorder == null) {
      _recorder.dispose();
    }
    super.dispose();
  }

  bool get _payloadIsValid => switch (_type) {
        BirdType.cro => _contentController.text.trim().isNotEmpty,
        BirdType.parrot => _audioBytes != null && _audioBytes!.isNotEmpty,
        BirdType.pigeon => _imageBytes != null,
        BirdType.raven => _contentController.text.trim().isNotEmpty && _imageBytes != null,
        _ => false,
      };

  bool get _canSave =>
      _nameController.text.trim().isNotEmpty &&
      _originNestId != null &&
      _destinationId != null &&
      _payloadIsValid;

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _recorder.stop();
      await _audioSub?.cancel();
      setState(() => _isRecording = false);
      return;
    }

    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is needed to record a Parrot clip')),
        );
      }
      return;
    }

    _audioBytes = [];
    final stream = await _recorder.startStream(const RecordConfig());
    _audioSub = stream.listen((chunk) {
      _audioBytes!.addAll(chunk);
    });
    setState(() => _isRecording = true);
  }

  Future<void> _pickImage() async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _imageFilename = picked.name;
    });
  }

  void _save() {
    final needsAudio = _type == BirdType.parrot;
    final needsImage = _type == BirdType.pigeon || _type == BirdType.raven;
    widget.onSubmit(ComposeBirdResult(
      type: _type,
      name: _nameController.text.trim(),
      originNestId: _originNestId!,
      destinationId: _destinationId!,
      content: _contentController.text.trim().isEmpty ? null : _contentController.text.trim(),
      isPublic: _isPublic,
      mediaBytes: needsAudio ? _audioBytes : (needsImage ? _imageBytes : null),
      mediaContentType: needsAudio ? 'audio/wav' : (needsImage ? 'image/jpeg' : null),
      mediaFilename: needsAudio ? 'clip.wav' : (needsImage ? (_imageFilename ?? 'photo.jpg') : null),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final type in BirdType.all)
              ChoiceChip(
                key: Key('birdTypeChip_$type'),
                label: Text(type),
                selected: _type == type,
                onSelected: (_) => setState(() {
                  _type = type;
                  _audioBytes = null;
                  _imageBytes = null;
                  _imageFilename = null;
                }),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          BirdType.description(_type),
          style: const TextStyle(fontSize: 12, color: CroColors.fog),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('composeBirdNameField'),
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'Name'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        ..._buildPayloadFields(),
        const SizedBox(height: 12),
        if (widget.origins.length > 1)
          DropdownButton<String>(
            key: const Key('composeBirdOriginDropdown'),
            value: _originNestId,
            isExpanded: true,
            hint: const Text('Depart from'),
            items: widget.origins.map((o) => DropdownMenuItem(value: o.nestId, child: Text(o.label))).toList(),
            onChanged: (value) => setState(() => _originNestId = value),
          ),
        DropdownButton<String>(
          key: const Key('composeBirdDestinationDropdown'),
          value: _destinationId,
          isExpanded: true,
          hint: const Text('Send to'),
          items: widget.destinations.map((d) => DropdownMenuItem(value: d.nestId, child: Text(d.label))).toList(),
          onChanged: (value) => setState(() => _destinationId = value),
        ),
        SwitchListTile(
          key: const Key('composeBirdPublicSwitch'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Public'),
          subtitle: const Text('Anyone can read and react to this'),
          value: _isPublic,
          onChanged: (value) => setState(() => _isPublic = value),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              key: const Key('cancelComposeBirdButton'),
              onPressed: widget.onCancel,
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            TextButton(
              key: const Key('confirmComposeBirdButton'),
              onPressed: _canSave ? _save : null,
              child: Text(widget.submitLabel),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildPayloadFields() {
    switch (_type) {
      case BirdType.cro:
        return [
          TextField(
            key: const Key('composeBirdContentField'),
            controller: _contentController,
            decoration: const InputDecoration(labelText: 'Message'),
            maxLines: 3,
            onChanged: (_) => setState(() {}),
          ),
        ];
      case BirdType.parrot:
        return [
          Row(
            children: [
              IconButton(
                key: const Key('composeBirdRecordButton'),
                icon: Icon(_isRecording ? Icons.stop_circle : Icons.mic),
                color: _isRecording ? Theme.of(context).colorScheme.error : null,
                onPressed: _toggleRecording,
              ),
              Text(
                _isRecording ? 'Recording...' : (_audioBytes != null ? 'Clip recorded' : 'Tap to record'),
              ),
            ],
          ),
        ];
      case BirdType.pigeon:
        return [
          Row(
            children: [
              IconButton(
                key: const Key('composeBirdPickImageButton'),
                icon: const Icon(Icons.image),
                onPressed: _pickImage,
              ),
              Text(_imageFilename ?? 'No image chosen'),
            ],
          ),
        ];
      case BirdType.raven:
        return [
          TextField(
            key: const Key('composeBirdContentField'),
            controller: _contentController,
            decoration: const InputDecoration(labelText: 'Message'),
            maxLines: 3,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                key: const Key('composeBirdPickImageButton'),
                icon: const Icon(Icons.image),
                onPressed: _pickImage,
              ),
              Text(_imageFilename ?? 'No image chosen'),
            ],
          ),
        ];
      default:
        return const [];
    }
  }
}
