import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import 'package:couchkit_remote/core/di/injector.dart';
import 'package:couchkit_remote/core/navigation/router.dart';
import 'package:couchkit_remote/core/ui/describe_error.dart';
import 'package:couchkit_remote/features/home/home_controller.dart';

class AddPage extends StatefulWidget {
  const AddPage({super.key});

  static const route = '/add';

  @override
  State<AddPage> createState() => _AddPageState();
}

class _AddPageState extends State<AddPage> {
  final _manual = TextEditingController();
  bool _busy = false;
  bool _typing = false;

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  Future<void> _pair(String raw) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    final controller = context.read<HomeController>();
    try {
      final endpoint = await controller.pair(raw);
      if (!mounted) {
        return;
      }
      final extra = controller.discovered;
      showMessage(
        context,
        extra > 0
            ? '${endpoint.kind.label} e mais $extra apps adicionados'
            : '${endpoint.kind.label} adicionado',
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        showMessage(context, describeError(error));
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Adicionar app da TV'),
        actions: [
          IconButton(
            tooltip: _typing ? 'Usar câmera' : 'Digitar endereço',
            icon: Icon(_typing ? Icons.qr_code_scanner : Icons.keyboard),
            onPressed: () => setState(() => _typing = !_typing),
          ),
        ],
      ),
      body: Column(
        children: [
          _adbCard(),
          Expanded(child: _typing ? _manualForm() : _scanner()),
        ],
      ),
    );
  }

  Widget _adbCard() {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: ListTile(
        leading: const Icon(Icons.usb),
        title: const Text('Configurar a TV pelo celular (ADB)'),
        subtitle: const Text(
          'Instala os apps e cadastra a TV sem QR. Só precisa ligar a '
          'Depuração ADB.',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          final router = context.read<Injector>().get<RouterService>();
          Navigator.of(context).pop();
          router.push<void>(context, '/install-tv');
        },
      ),
    );
  }

  Widget _scanner() {
    return Stack(
      children: [
        MobileScanner(
          onDetect: (capture) {
            for (final barcode in capture.barcodes) {
              final value = barcode.rawValue;
              if (value != null && value.isNotEmpty) {
                _pair(value);
                return;
              }
            }
          },
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Sem acesso à câmera. Digite o endereço no ícone do teclado.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: Colors.black54,
            child: Text(
              _busy
                  ? 'Conectando…'
                  : 'Aponte para o QR code na TV (MENU no app).',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _manualForm() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Cole o endereço que aparece embaixo do QR code, incluindo '
            '?k=… (o token é obrigatório).',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _manual,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'http://IP:porta/?k=token',
            ),
            onSubmitted: _pair,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : () => _pair(_manual.text),
            child: Text(_busy ? 'Conectando…' : 'Conectar'),
          ),
        ],
      ),
    );
  }
}
