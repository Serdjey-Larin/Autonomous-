/// Применение ответов модуля к состоянию автомобиля и текст строки состояния.
///
/// Три независимые оси (см. отчёт аудита, раздел F.4):
///  1. действие пользователя — pendingCommand / awaitCmd;
///  2. связь с модулем — awaitCmd, ackCmd, lastReply;
///  3. состояние управляющего выхода — outState/outAt, ТОЛЬКО из STATUS.
/// Расчётный отсчёт (endMs, cycleMinutes, startMs, basis) никогда не пишет в ось 3.
library;

import 'device_service.dart';
import 'reply_parser.dart';

/// Ответ ждём не дольше этого — дальше «ответа нет».
const replyTimeout = Duration(minutes: 15);

/// STATUS старше этого считается устаревшим.
const statusFreshness = Duration(minutes: 10);

/// Входящее SMS от модуля (из нативного журнала).
class InboundSms {
  const InboundSms({required this.seq, required this.number, required this.body,
      required this.smscMs, required this.receivedMs});
  final int seq;
  final String number;
  final String body;
  final int smscMs;
  final int receivedMs;

  /// Время, по которому считаем. Часы SMS-центра бывают сбиты — если
  /// расхождение больше 10 минут, берём время приёма телефоном.
  int get effectiveMs =>
      (receivedMs - smscMs).abs() <= const Duration(minutes: 10).inMilliseconds ? smscMs : receivedMs;

  factory InboundSms.fromMap(Map<Object?, Object?> m) => InboundSms(
      seq: (m['seq'] as num).toInt(), number: m['number'] as String,
      body: m['body'] as String, smscMs: (m['smsc'] as num).toInt(),
      receivedMs: (m['received'] as num).toInt());
}

/// Автомобиль, которому принадлежит номер. Только полное совпадение номера.
VehicleConfig? carForNumber(List<VehicleConfig> cars, String number) {
  final n = canonicalNumber(number);
  if (n.isEmpty) return null;
  for (final c in cars) {
    if (canonicalNumber(c.deviceNumber) == n) return c;
  }
  return null;
}

/// Результат применения ответа.
class ApplyResult {
  const ApplyResult({required this.kind, required this.timerChanged});
  final ReplyKind kind;
  /// Изменились endMs/cycleMinutes — нужно перепланировать уведомление таймера.
  final bool timerChanged;
}

ApplyResult applyReply(VehicleConfig car, InboundSms sms) {
  final at = sms.effectiveMs;
  final parsed = parseReply(sms.body);

  // Задержавшийся старый STATUS не должен перезаписать более новый.
  if (parsed.kind == ReplyKind.status && car.outAt != null && at <= car.outAt!) {
    return const ApplyResult(kind: ReplyKind.status, timerChanged: false);
  }
  if (car.lastReplyAt == null || at >= car.lastReplyAt!) {
    car.lastReply = sms.body.trim();
    car.lastReplyAt = at;
  }

  switch (parsed.kind) {
    case ReplyKind.status:
      final s = parsed.status!;
      final oldEnd = car.endMs, oldCycle = car.cycleMinutes;
      car.outState = s.on ? 'on' : 'off';
      car.outAt = at;
      car.battery = s.battery;
      car.leftMin = s.leftMinutes;
      car.timeMin = s.timeMinutes;
      if (s.timeMinutes >= 15 && s.timeMinutes <= 120) car.durationMinutes = s.timeMinutes;
      if (s.on) {
        car.cycleMinutes = s.timeMinutes;
        car.endMs = at + s.leftMinutes * 60000;
        car.startMs = car.endMs! - s.timeMinutes * 60000;
      } else {
        car.endMs = null;
        car.startMs = null;
      }
      car.basis = 'status';
      // Состояние известно — ожидание любой команды закрыто.
      car.awaitCmd = null;
      car.awaitSince = null;
      car.ackCmd = null;
      car.ackAt = null;
      return ApplyResult(kind: ReplyKind.status,
          timerChanged: oldEnd != car.endMs || oldCycle != car.cycleMinutes);
    case ReplyKind.ok:
      final since = car.awaitSince;
      final expected = car.awaitCmd != null && since != null &&
          at >= since - 60000 && at - since <= replyTimeout.inMilliseconds;
      car.ackCmd = expected ? car.awaitCmd : '?';
      car.ackAt = at;
      if (expected) {
        car.awaitCmd = null;
        car.awaitSince = null;
      }
      return const ApplyResult(kind: ReplyKind.ok, timerChanged: false);
    case ReplyKind.other:
    case ReplyKind.invalid:
      return ApplyResult(kind: parsed.kind, timerChanged: false);
  }
}

/// Пользователь подтвердил «Да, отправил». Возвращает true, если отсчёт изменился.
bool applyUserSent(VehicleConfig car, String command, DateTime now) {
  final nowMs = now.millisecondsSinceEpoch;
  car.awaitCmd = command;
  car.awaitSince = nowMs;
  car.ackCmd = null;
  car.ackAt = null;
  if (command == 'START') {
    car.cycleMinutes = car.durationMinutes;
    car.startMs = nowMs;
    car.endMs = nowMs + car.cycleMinutes * 60000;
    car.basis = 'user';
    return true;
  }
  if (command == 'STOP') {
    final had = car.endMs != null;
    car.endMs = null;
    car.startMs = null;
    car.basis = 'user';
    return had;
  }
  if (command.startsWith('TIME:')) {
    final minutes = int.tryParse(command.substring(5));
    if (minutes == null) return false;
    car.durationMinutes = minutes;
    // Во время активного цикла прошивка считает новое время от исходного запуска.
    if (car.endMs != null && car.endMs! > nowMs) {
      final start = car.startMs ?? (car.endMs! - car.cycleMinutes * 60000);
      car.startMs = start;
      car.cycleMinutes = minutes;
      car.endMs = start + minutes * 60000;
      return true;
    }
  }
  return false;
}

String _clock(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

String _volts(double? v) => v == null ? '' : ' · ${v.toStringAsFixed(1).replaceAll('.', ',')} В';

/// Свежий STATUS: не старше 10 минут и (для «включён») расчётное время не вышло.
bool statusFresh(VehicleConfig car, DateTime now) {
  if (car.outAt == null || car.outState == null) return false;
  final nowMs = now.millisecondsSinceEpoch;
  if (nowMs - car.outAt! > statusFreshness.inMilliseconds) return false;
  if (car.outState == 'on' && (car.endMs == null || car.endMs! <= nowMs)) return false;
  return true;
}

/// Выход включён по свежему STATUS — только тогда показываем «работу» цветом.
bool confirmedOn(VehicleConfig car, DateTime now) =>
    car.outState == 'on' && statusFresh(car, now) && car.basis == 'status';

/// Одна строка под циферблатом. Никогда не пишет «отопитель работает».
String statusLine(VehicleConfig car, DateTime now) {
  final nowMs = now.millisecondsSinceEpoch;
  final await_ = car.awaitCmd;
  if (await_ != null && car.awaitSince != null) {
    if (nowMs - car.awaitSince! <= replyTimeout.inMilliseconds) {
      return '$await_ отправлен · ждём ответ модуля';
    }
    return 'Ответа на $await_ нет · проверьте переписку';
  }
  if (car.ackCmd != null && car.ackAt != null && (car.outAt == null || car.ackAt! > car.outAt!)) {
    return car.ackCmd == '?'
        ? 'Модуль ответил OK · запросите STATUS для проверки'
        : 'Модуль принял ${car.ackCmd} · состояние не проверено';
  }
  if (car.outState != null && car.outAt != null) {
    if (statusFresh(car, now)) {
      final what = car.outState == 'on' ? 'Выход включён' : 'Выход выключен';
      return '$what · по SMS в ${_clock(car.outAt!)}${_volts(car.battery)}';
    }
    return 'Данные от ${_clock(car.outAt!)} устарели · запросите STATUS';
  }
  return 'Расчётный таймер · не подтверждает работу отопителя';
}
