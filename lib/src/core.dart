import 'dart:async';

import 'package:flutter/services.dart';

import 'messages.g.dart';

/// Why the OhrTech Agent refused or couldn't do what the app asked. Every call throws one of these.
sealed class OhrException implements Exception {
  const OhrException(this.message);

  /// What happened, for logs.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// This app is not one the organisation installed on this device through OhrTech.
final class OhrNotManaged extends OhrException {
  const OhrNotManaged(super.message);
}

/// The fleet doesn't let this app use [area].
final class OhrNotAllowed extends OhrException {
  const OhrNotAllowed(super.message, this.area);
  final String area;
}

/// The fleet locks the setting or network [key].
final class OhrFleetLocked extends OhrException {
  const OhrFleetLocked(super.message, this.key);
  final String key;
}

/// This device, OS or Agent can't do it. [needsAgent]: the Agent version that can, when the Agent is only too old.
final class OhrUnsupported extends OhrException {
  const OhrUnsupported(super.message, this.reason, this.needsAgent);
  final String reason;
  final int? needsAgent;
}

/// A value the app passed is invalid: [field], and why.
final class OhrInvalidConfig extends OhrException {
  const OhrInvalidConfig(super.message, this.field, this.reason);
  final String field;
  final String reason;
}

/// The Agent tried and it failed, or the Agent can't be reached.
final class OhrFailed extends OhrException {
  const OhrFailed(super.message, this.reason);
  final String reason;
}

/// The hub refused a request it checks itself (a certificate: [reason] says why).
final class OhrRefused extends OhrException {
  const OhrRefused(super.message, this.reason);
  final String reason;
}

/// The plugin's [PlatformException] as the [OhrException] it stands for.
OhrException ohrException(Object error) {
  if (error is OhrException) return error;
  if (error is! PlatformException) return OhrFailed(error.toString(), error.toString());
  final message = error.message ?? error.code;
  final d = error.details is Map ? (error.details as Map) : const {};
  String s(String k) => d[k]?.toString() ?? message;
  return switch (error.code) {
    'NotManaged' => OhrNotManaged(message),
    'NotAllowed' => OhrNotAllowed(message, s('area')),
    'FleetLocked' => OhrFleetLocked(message, s('key')),
    'Unsupported' => OhrUnsupported(message, s('reason'), (d['needsAgent'] as num?)?.toInt()),
    'InvalidConfig' => OhrInvalidConfig(message, s('field'), s('reason')),
    'Refused' => OhrRefused(message, s('reason')),
    _ => OhrFailed(message, s('reason')),
  };
}

/// The plugin's host API (one per isolate).
final OhrHostApi hostApi = OhrHostApi();

/// Runs a host call, with its errors as [OhrException].
Future<T> call<T>(Future<T> Function(OhrHostApi api) f) async {
  try {
    return await f(hostApi);
  } catch (e) {
    throw ohrException(e);
  }
}

/// The same for the synchronous host calls (no Agent involved).
Future<T> callLocal<T>(Future<T> Function(OhrHostApi api) f) => call(f);

/// One broadcast stream per kind of change, shared by every listener (an event channel takes one): the
/// plugin watches the Agent from the first listener to the last cancel. Errors arrive as [OhrException].
Stream<T> shared<S, T>(Stream<S> Function() open, T Function(S) map) {
  Stream<T>? stream;
  return Stream<T>.multi((controller) {
    stream ??= open().map(map).handleError((Object e) => throw ohrException(e));
    final sub = stream!.listen(controller.addSync, onError: controller.addErrorSync, onDone: controller.closeSync);
    controller.onCancel = sub.cancel;
  }, isBroadcast: true);
}
