import 'package:flutter/services.dart';

import 'vehicle_state.dart';

/// Мост к нативному журналу входящих SMS от модулей (SmsInbox в Kotlin).
class SmsInboxBridge {
  static const channel = MethodChannel('ru.larincold/sms');

  /// Вызывается, когда пришло новое SMS, пока приложение запущено.
  void listen(void Function() onChanged) {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'inboxChanged') onChanged();
      return null;
    });
  }

  Future<void> setDevices(List<String> numbers) =>
      channel.invokeMethod<void>('setDevices', {'numbers': numbers});

  Future<List<InboundSms>> drain(int afterSeq) async {
    final rows = await channel.invokeMethod<List<Object?>>('drain', {'after': afterSeq}) ?? const [];
    return rows.whereType<Map<Object?, Object?>>().map(InboundSms.fromMap).toList();
  }

  Future<void> ack(int seq) => channel.invokeMethod<void>('ack', {'seq': seq});

  /// granted, manufacturer (в нижнем регистре), sdk.
  Future<({bool granted, String manufacturer})> state() async {
    final m = await channel.invokeMethod<Map<Object?, Object?>>('state') ?? const {};
    return (granted: m['granted'] == true, manufacturer: (m['manufacturer'] as String?) ?? '');
  }

  Future<bool> request() async => await channel.invokeMethod<bool>('request') ?? false;
  Future<void> appSettings() => channel.invokeMethod<void>('appSettings');
}
