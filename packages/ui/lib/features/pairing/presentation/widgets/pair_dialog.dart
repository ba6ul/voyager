import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../devices/domain/device_repository.dart';
import '../cubit/pairing_cubit.dart';
import '../pairing_text.dart';

/// Opens the pairing form. The cubit lives only as long as the dialog.
Future<void> showPairDialog(BuildContext context) {
  final repository = context.read<DeviceRepository>();
  return showDialog<void>(
    context: context,
    builder: (_) => BlocProvider(
      create: (_) => PairingCubit(repository),
      child: const PairDialog(),
    ),
  );
}

/// Pairs a phone's Wireless debugging from the two values its pairing dialog
/// shows, so no terminal command is needed.
class PairDialog extends StatefulWidget {
  const PairDialog({super.key});

  @override
  State<PairDialog> createState() => _PairDialogState();
}

class _PairDialogState extends State<PairDialog> {
  final _address = TextEditingController();
  final _code = TextEditingController();

  @override
  void dispose() {
    _address.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PairingCubit, PairingState>(
      builder: (context, state) {
        final working = state.phase == PairingPhase.working;
        final done = state.phase == PairingPhase.succeeded;
        return AlertDialog(
          title: const Text('Pair wirelessly'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pairingSteps,
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 12),
                TextField(
                  controller: _address,
                  enabled: !working && !done,
                  decoration: const InputDecoration(
                    labelText: 'Address (ip:port)',
                    hintText: '192.168.1.8:37123',
                  ),
                  keyboardType: TextInputType.url,
                ),
                TextField(
                  controller: _code,
                  enabled: !working && !done,
                  decoration: const InputDecoration(labelText: 'Pairing code'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  onSubmitted: (_) => _submit(context),
                ),
                if (state.message != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (working)
                        const Padding(
                          padding: EdgeInsets.only(right: 8, top: 2),
                          child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                      Expanded(
                        child: Text(
                          state.message!,
                          style: TextStyle(
                            color: state.phase == PairingPhase.failed
                                ? Theme.of(context).colorScheme.error
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(done ? 'Done' : 'Close'),
            ),
            if (!done)
              FilledButton(
                onPressed: working ? null : () => _submit(context),
                child: const Text('Pair'),
              ),
          ],
        );
      },
    );
  }

  void _submit(BuildContext context) =>
      context.read<PairingCubit>().pair(_address.text, _code.text);
}
