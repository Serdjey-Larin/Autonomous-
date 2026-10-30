import 'package:flutter/services.dart';

import 'phone_setup.dart';
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

  /// Номера модулей (фильтр приёма) и названия машин (для уведомлений).
  /// Номера модулей (фильтр приёма), названия машин и ожидаемая команда —
  /// чтобы при закрытом приложении фоновая часть вела таймер так же, как экран.
  Future<void> setDevices(List<({String number, String id, String name, String? pending,
      int? pendingSince, int? cmdAt, int duration, int? outAt})> cars) =>
      channel.invokeMethod<void>('setDevices', {
        'numbers': [for (final c in cars) c.number],
        'cars': [for (final c in cars) {'number': c.number, 'id': c.id, 'name': c.name,
          'pending': c.pending, 'pendingSince': c.pendingSince, 'cmdAt': c.cmdAt, 'duration': c.duration,
          'outAt': c.outAt}],
      });

  /// Удалить из журнала всё, что пришло с этого номера (машина удалена или номер сменён).
  Future<void> forget(String number) => channel.invokeMethod<void>('forget', {'number': number});

  Future<List<InboundSms>> drain(int afterSeq) async {
    final rows = await channel.invokeMethod<List<Object?>>('drain', {'after': afterSeq}) ?? const [];
    return rows.whereType<Map<Object?, Object?>>().map(InboundSms.fromMap).toList();
  }

  Future<void> ack(int seq) => channel.invokeMethod<void>('ack', {'seq': seq});

  /// Разрешение SMS, производитель, модель, уведомления, батарея, установщик.
  Future<PhoneState> state() async =>
      PhoneState.fromMap(await channel.invokeMethod<Map<Object?, Object?>>('state') ?? const {});

  /// Открыть экран системы: 'app', 'notifications', 'battery', 'autostart', 'miuiActivity'.
  /// false — специальный экран не нашёлся, открыты «Сведения о приложении».
  Future<bool> open(String kind) async => await channel.invokeMethod<bool>('open', {'kind': kind}) ?? false;

  Future<bool> request() async => await channel.invokeMethod<bool>('request') ?? false;
  Future<void> appSettings() => channel.invokeMethod<void>('appSettings');
}
