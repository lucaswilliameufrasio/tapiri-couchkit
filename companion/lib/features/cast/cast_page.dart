import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:couchkit_remote/core/ui/describe_error.dart';
import 'package:couchkit_remote/data/services/cast_service.dart';

class CastPage extends StatefulWidget {
  const CastPage({required this.service, super.key});

  static const route = '/phonecast';

  final CastService service;

  @override
  State<CastPage> createState() => _CastPageState();
}

class _CastPageState extends State<CastPage> {
  final _link = TextEditingController();
  Timer? _poll;
  CastState? _state;
  double? _progress;

  CastService get _service => widget.service;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _link.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final state = await _service.state();
      if (mounted) {
        setState(() => _state = state);
      }
    } catch (_) {
      // a TV pode estar ocupada; tenta de novo no proximo ciclo
    }
  }

  Future<void> _sendLink() async {
    final text = _link.text.trim();
    if (text.isEmpty) {
      return;
    }
    final message = await guarded(context, () => _service.sendLink(text));
    if (mounted && message != null) {
      showMessage(context, message);
    }
  }

  Future<void> _pickMedia() async {
    final picked = await ImagePicker().pickMedia();
    if (picked != null) {
      await _upload(File(picked.path), picked.mimeType);
    }
  }

  Future<void> _pickFile() async {
    final picked = await FilePicker.pickFile();
    final path = picked?.path;
    if (path != null) {
      await _upload(File(path), null);
    }
  }

  Future<void> _upload(File file, String? mimeType) async {
    setState(() => _progress = 0);
    final message = await guarded(
      context,
      () => _service.sendFile(
        file,
        mimeType: mimeType,
        onProgress: (sent, total) {
          if (mounted && total > 0) {
            setState(() => _progress = sent / total);
          }
        },
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() => _progress = null);
    if (message != null) {
      showMessage(context, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    return Scaffold(
      appBar: AppBar(title: const Text('PhoneCast')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _link,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Link de vídeo, áudio, imagem ou página',
              suffixIcon: IconButton(
                icon: const Icon(Icons.send),
                onPressed: _sendLink,
              ),
            ),
            onSubmitted: (_) => _sendLink(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Fotos e vídeos'),
                  onPressed: _progress == null ? _pickMedia : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Arquivo'),
                  onPressed: _progress == null ? _pickFile : null,
                ),
              ),
            ],
          ),
          if (_progress != null) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress, minHeight: 8),
            const SizedBox(height: 4),
            Text('Enviando… ${(_progress! * 100).toStringAsFixed(0)}%'),
          ],
          const SizedBox(height: 24),
          if (state != null && state.active) _player(context, state),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton.filledTonal(
                tooltip: 'Volume -',
                icon: const Icon(Icons.volume_down),
                onPressed: () => guarded(context, _service.volumeDown),
              ),
              IconButton.filledTonal(
                tooltip: 'Mudo',
                icon: const Icon(Icons.volume_off),
                onPressed: () => guarded(context, _service.mute),
              ),
              IconButton.filledTonal(
                tooltip: 'Volume +',
                icon: const Icon(Icons.volume_up),
                onPressed: () => guarded(context, _service.volumeUp),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _player(BuildContext context, CastState state) {
    final isImage = state.kind == 'image';
    final max = state.durationMs <= 0 ? 1.0 : state.durationMs.toDouble();
    final value = state.positionMs.clamp(0, max.toInt()).toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              state.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (!isImage) ...[
              Slider(
                value: value,
                max: max,
                onChanged: (v) {},
                onChangeEnd: (v) =>
                    guarded(context, () => _service.seekTo((v / 1000).round())),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_clock(state.positionMs)),
                  Text(_clock(state.durationMs)),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.replay_10),
                    onPressed: () =>
                        guarded(context, () => _service.seekBy(-10)),
                  ),
                  IconButton.filled(
                    iconSize: 36,
                    icon: Icon(state.playing ? Icons.pause : Icons.play_arrow),
                    onPressed: () => guarded(context, _service.toggle),
                  ),
                  IconButton(
                    icon: const Icon(Icons.forward_10),
                    onPressed: () =>
                        guarded(context, () => _service.seekBy(10)),
                  ),
                ],
              ),
            ],
            TextButton.icon(
              icon: const Icon(Icons.stop),
              label: const Text('Parar'),
              onPressed: () => guarded(context, _service.stop),
            ),
          ],
        ),
      ),
    );
  }

  String _clock(int ms) {
    final total = ms ~/ 1000;
    final minutes = (total ~/ 60).toString().padLeft(2, '0');
    final seconds = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
