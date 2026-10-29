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

/// Последний ответ STATUS считается актуальным 5 часов, потом «данные устарели».
const statusFreshness = Duration(hours: 5);

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
      // Команда, для которой открывали редактор SMS и ещё не подтверждали:
      // OK от этого модуля в пределах 15 минут подтверждает и отправку, и приём.
      // Отсчёт START начинается с момента ответа модуля.
      final pending = car.pendingCommand, pendingSince = car.pendingSince;
      if (pending != null && pendingSince != null &&
          at >= pendingSince - 60000 && at - pendingSince <= replyTimeout.inMilliseconds) {
        car.pendingCommand = null;
        car.pendingSince = null;
        final changed = applyUserSent(car, pending, DateTime.fromMillisecondsSinceEpoch(at));
        car.awaitCmd = null;
        car.awaitSince = null;
        car.ackCmd = pending;
        car.ackAt = at;
        return ApplyResult(kind: ReplyKind.ok, timerChanged: changed);
      }
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
    case ReplyKind.balance:
      if (car.balanceAt == null || at >= car.balanceAt!) {
        car.balanceRub = parsed.balance;
        car.balanceText = sms.body.trim();
        car.balanceAt = at;
      }
      return const ApplyResult(kind: ReplyKind.balance, timerChanged: false);
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

String _dayClock(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.day)}.${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
}

String _clock(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// Ответ STATUS не старше 5 часов.
bool statusFresh(VehicleConfig car, DateTime now) {
  if (car.outAt == null || car.outState == null) return false;
  return now.millisecondsSinceEpoch - car.outAt! <= statusFreshness.inMilliseconds;
}

/// По STATUS прогрев был запущен, и отсчёт ещё идёт.
bool _runningByStatus(VehicleConfig car, DateTime now) =>
    car.outState == 'on' && car.endMs != null && car.endMs! > now.millisecondsSinceEpoch;

/// После звонка выход переключён, а STATUS ещё не пришёл.
bool afterCall(VehicleConfig car) =>
    car.callAt != null && (car.outAt == null || car.callAt! > car.outAt!);

/// Выход включён по свежему STATUS — только тогда показываем «работу» цветом.
bool confirmedOn(VehicleConfig car, DateTime now) =>
    _runningByStatus(car, now) && statusFresh(car, now) && car.basis == 'status' && !afterCall(car);

/// Пользователь позвонил на модуль: звонок переключает выход, поэтому прежний
/// расчётный отсчёт больше не верен. Точное время даст ответ на STATUS.
void applyCall(VehicleConfig car, DateTime now) {
  car.callAt = now.millisecondsSinceEpoch;
  car.endMs = null;
  car.startMs = null;
  car.basis = null;
  car.awaitCmd = null;
  car.awaitSince = null;
  car.ackCmd = null;
  car.ackAt = null;
}

/// Команда по-человечески, в винительном падеже: «запуск», «остановку».
String commandTitle(String cmd) {
  if (cmd == 'START') return 'запуск';
  if (cmd == 'STOP') return 'остановку';
  if (cmd.startsWith('TIME:')) return 'время ${cmd.substring(5)} мин';
  if (cmd == 'STATUS') return 'запрос состояния';
  if (cmd == 'BALANCE') return 'запрос баланса';
  return cmd;
}

/// Тон плашки состояния (цвет). Зелёный — только по свежему STATUS.
enum StatusTone { on, waiting, warning, off, idle }

/// Ждём ответ модуля на отправленную команду (крутится снежинка).
bool waitingReply(VehicleConfig car, DateTime now) {
  final nowMs = now.millisecondsSinceEpoch;
  final limit = replyTimeout.inMilliseconds;
  if (car.pendingCommand != null && car.pendingSince != null) return nowMs - car.pendingSince! <= limit;
  if (car.awaitCmd != null && car.awaitSince != null) return nowMs - car.awaitSince! <= limit;
  return false;
}

StatusTone statusTone(VehicleConfig car, DateTime now) {
  final nowMs = now.millisecondsSinceEpoch;
  if (waitingReply(car, now)) return StatusTone.waiting;
  if (car.pendingCommand != null || car.awaitCmd != null) return StatusTone.warning;
  if (afterCall(car) && nowMs - car.callAt! <= const Duration(hours: 2).inMilliseconds) return StatusTone.warning;
  if (car.ackCmd != null && car.ackAt != null && (car.outAt == null || car.ackAt! > car.outAt!)) {
    return switch (car.ackCmd) { 'START' => StatusTone.on, 'STOP' => StatusTone.off, _ => StatusTone.idle };
  }
  if (car.outState != null && car.outAt != null) {
    if (!statusFresh(car, now)) return StatusTone.warning;
    return _runningByStatus(car, now) ? StatusTone.on : StatusTone.off;
  }
  return StatusTone.idle;
}

/// Одна строка под циферблатом. «Прогрев запущен» — только по ответу STATUS.
String statusLine(VehicleConfig car, DateTime now) {
  final nowMs = now.millisecondsSinceEpoch;
  final pending = car.pendingCommand;
  if (pending != null && car.pendingSince != null) {
    if (nowMs - car.pendingSince! <= replyTimeout.inMilliseconds) {
      return 'Ждём ответ модуля на ${commandTitle(pending)}';
    }
    return 'Ответа на ${commandTitle(pending)} нет · подтвердите отправку вручную';
  }
  final await_ = car.awaitCmd;
  if (await_ != null && car.awaitSince != null) {
    if (nowMs - car.awaitSince! <= replyTimeout.inMilliseconds) {
      return 'Отправлено: ${commandTitle(await_)} · ждём ответ модуля';
    }
    return 'Ответа на ${commandTitle(await_)} нет · проверьте переписку';
  }
  if (afterCall(car) && nowMs - car.callAt! <= const Duration(hours: 2).inMilliseconds) {
    return 'Звонок переключил прогрев · обновите состояние';
  }
  if (car.ackCmd != null && car.ackAt != null && (car.outAt == null || car.ackAt! > car.outAt!)) {
    return car.ackCmd == '?' ? 'Модуль ответил OK' : 'Модуль принял ${commandTitle(car.ackCmd!)}';
  }
  if (car.outState != null && car.outAt != null) {
    if (statusFresh(car, now)) {
      if (_runningByStatus(car, now)) return 'Прогрев запущен · SMS в ${_clock(car.outAt!)}';
      if (car.outState == 'on') return 'Прогрев завершён по таймеру';
      return 'Прогрев выключен · SMS в ${_clock(car.outAt!)}';
    }
    return 'Данные от ${_dayClock(car.outAt!)} устарели · обновите состояние';
  }
  if (car.endMs != null && car.endMs! > nowMs) return 'Расчётный таймер · ответа модуля нет';
  return 'Готов к запуску';
}

/// Напряжение АКБ из последнего STATUS: «14,6 В» или «—».
String batteryText(VehicleConfig car) =>
    car.battery == null ? '—' : '${car.battery!.toStringAsFixed(1).replaceAll('.', ',')} В';

/// Сумма на плитке «Баланс»: «13 ₽», «−5,20 ₽» или «—».
String balanceAmount(VehicleConfig car) {
  final rub = car.balanceRub;
  if (car.balanceAt == null || rub == null) return '—';
  final abs = rub.abs();
  final text = abs == abs.roundToDouble() ? abs.toStringAsFixed(0) : abs.toStringAsFixed(2).replaceAll('.', ',');
  return '${rub < 0 ? '−' : ''}$text ₽';
}

/// Дата, на которую баланс актуален: «на 29.10, 11:34».
String balanceDate(VehicleConfig car) {
  if (car.balanceAt == null) return 'нажмите, чтобы узнать';
  final t = DateTime.fromMillisecondsSinceEpoch(car.balanceAt!);
  String two(int v) => v.toString().padLeft(2, '0');
  return 'на ${two(t.day)}.${two(t.month)}, ${two(t.hour)}:${two(t.minute)}';
}

/// Зимний снег: с 1 декабря по 30 января включительно.
bool isWinterSeason(DateTime d) => d.month == 12 || (d.month == 1 && d.day <= 30);

/// Подпись плитки «Баланс»: «13 ₽ · 29.10 11:34» или исходная подпись.
String balanceSubtitle(VehicleConfig car) {
  if (car.balanceAt == null) return 'SMS BALANCE';
  final t = DateTime.fromMillisecondsSinceEpoch(car.balanceAt!);
  String two(int v) => v.toString().padLeft(2, '0');
  final when = '${two(t.day)}.${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
  final rub = car.balanceRub;
  if (rub == null) return 'ответ от $when';
  final amount = rub == rub.roundToDouble() ? rub.toStringAsFixed(0) : rub.toStringAsFixed(2).replaceAll('.', ',');
  return '$amount ₽ · $when';
}
