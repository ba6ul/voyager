import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../devices/domain/device_repository.dart';
import '../pairing_text.dart';

enum PairingPhase { editing, working, succeeded, failed }

class PairingState extends Equatable {
  const PairingState({this.phase = PairingPhase.editing, this.message});

  final PairingPhase phase;

  /// What to tell the user: a validation problem, progress, or the result.
  final String? message;

  @override
  List<Object?> get props => [phase, message];
}

/// Drives the pairing form: checks the input, asks the daemon to pair and
/// follows its status events to a result.
class PairingCubit extends Cubit<PairingState> {
  PairingCubit(this._repository) : super(const PairingState()) {
    _subscription = _repository.pairingStatus.listen(_onStatus);
  }

  final DeviceRepository _repository;
  late final StreamSubscription<PairingStatus> _subscription;

  Future<void> pair(String address, String code) async {
    if (state.phase == PairingPhase.working) return;
    final problem = addressError(address) ?? codeError(code);
    if (problem != null) {
      emit(PairingState(phase: PairingPhase.failed, message: problem));
      return;
    }
    emit(const PairingState(
        phase: PairingPhase.working,
        message: 'Contacting the background service…'));
    try {
      await _repository.pair(address: address.trim(), code: code.trim());
    } catch (e) {
      if (isClosed) return;
      emit(PairingState(
          phase: PairingPhase.failed, message: 'Could not start pairing: $e'));
    }
  }

  void _onStatus(PairingStatus status) {
    // Events only matter to a pairing this form started.
    if (state.phase != PairingPhase.working) return;
    final message = describePairing(status);
    if (!isFinalPairingStage(status.stage)) {
      emit(PairingState(phase: PairingPhase.working, message: message));
    } else {
      emit(PairingState(
        phase: pairingSucceeded(status.stage)
            ? PairingPhase.succeeded
            : PairingPhase.failed,
        message: message,
      ));
    }
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
