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

/// Допуск на расхождение часов SMS-центра и телефона при сравнении с моментом команды.
const clockSkew = Duration(seconds: 20);

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

  /// Когда модуль отправил SMS (часы SMS-центра). Задержанное SMS сохраняет
  /// своё настоящее, старое время и не выглядит свежим. Только время «из
  /// будущего» (центр спешит больше чем на 2 мин) заменяется временем приёма.
  int get effectiveMs =>
      smscMs - receivedMs > const Duration(minutes: 2).inMilliseconds ? receivedMs : smscMs;

  /// SMS — ответ на команду, отправленную в момент [since] (часы телефона):
  /// получено после неё, сформировано не раньше неё (с допуском на часы)
  /// и не позже 15 минут.
  bool answers(int? since) {
    if (since == null) return false;
    final at = effectiveMs;
    return receivedMs >= since && at >= since - clockSkew.inMilliseconds &&
        at - since <= replyTimeout.inMilliseconds;
  }

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
  // Ссылка для «ответ ли это на последнюю команду»: момент команды по часам телефона.
  final cmdRef = car.cmdAt ?? car.pendingSince ?? car.awaitSince;

  switch (parsed.kind) {
    case ReplyKind.status:
      final s = parsed.status!;
      // STATUS, сформированный ДО последней команды (START/STOP/TIME/звонок),
      // пришёл с задержкой: он устарел для состояния и таймера. Берём только АКБ.
      final cmdMark = car.cmdAt ?? car.pendingSince;
      if (cmdMark != null && at < cmdMark - clockSkew.inMilliseconds) {
        if (car.outAt == null || at > car.outAt!) car.battery = s.battery ?? car.battery;
        return const ApplyResult(kind: ReplyKind.status, timerChanged: false);
      }
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
      car.outAlready = s.already;
      car.outIgnored = s.ignored;
      // STATUS в ответ на отправленную команду: её отправка и приём подтверждены.
      final pend = car.pendingCommand;
      if (pend != null && sms.answers(car.pendingSince) &&
          (pend == 'START' || pend == 'STOP' || pend.startsWith('TIME:') || pend == 'STATUS')) {
        car.pendingCommand = null;
        car.pendingSince = null;
      }
      // Состояние известно — ожидание любой команды закрыто.
      car.awaitCmd = null;
      car.awaitSince = null;
      car.ackCmd = null;
      car.ackAt = null;
      return ApplyResult(kind: ReplyKind.status,
          timerChanged: oldEnd != car.endMs || oldCycle != car.cycleMinutes);
    case ReplyKind.ok:
      // «OK» подтверждает команду, только если получен после неё и сформирован
      // не раньше неё: OK на прошлую команду новую не подтверждает.
      // Отсчёт START начинается с момента ответа модуля.
      final pending = car.pendingCommand;
      if (pending != null && sms.answers(car.pendingSince)) {
        car.pendingCommand = null;
        car.pendingSince = null;
        final changed = applyUserSent(car, pending, DateTime.fromMillisecondsSinceEpoch(at));
        car.awaitCmd = null;
        car.awaitSince = null;
        car.ackCmd = pending;
        car.ackAt = at;
        return ApplyResult(kind: ReplyKind.ok, timerChanged: changed);
      }
      final expected = car.awaitCmd != null && sms.answers(cmdRef);
      car.ackCmd = expected ? car.awaitCmd : '?';
      car.ackAt = at;
      if (expected) {
        car.awaitCmd = null;
        car.awaitSince = null;
      }
      return const ApplyResult(kind: ReplyKind.ok, timerChanged: false);
    case ReplyKind.error:
      // Отказ модуля: ожидание ответа на команду закрывается, причина видна.
      if (car.errorAt == null || at >= car.errorAt!) {
        car.errorText = parsed.reason;
        car.errorAt = at;
      }
      if (car.pendingCommand != null && sms.answers(car.pendingSince)) {
        car.pendingCommand = null;
        car.pendingSince = null;
      }
      if (car.awaitCmd != null && sms.answers(cmdRef)) {
        car.awaitCmd = null;
        car.awaitSince = null;
      }
      return const ApplyResult(kind: ReplyKind.error, timerChanged: false);
    case ReplyKind.balance:
      if (car.balanceAt == null || at >= car.balanceAt!) {
        car.balanceRub = parsed.balance;
        car.balanceText = sms.body.trim();
        car.balanceAt = at;
      }
      return const ApplyResult(kind: ReplyKind.balance, timerChanged: false);
    case ReplyKind.other:
      final code = balanceCodeReply(sms.body);
      if (code != null && (car.moduleUssdAt == null || at >= car.moduleUssdAt!)) {
        car.moduleUssd = code;
        car.moduleUssdAt = at;
      }
      return ApplyResult(kind: parsed.kind, timerChanged: false);
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

/// Звонок был недавно (10 мин), а STATUS после него ещё не пришёл.
/// Прошивка v1.5.6+ присылает STATUS звонившему через несколько секунд.
const callReplyWindow = Duration(minutes: 10);
bool callRecent(VehicleConfig car, DateTime now) =>
    afterCall(car) && now.millisecondsSinceEpoch - car.callAt! <= callReplyWindow.inMilliseconds;

/// Выход включён по свежему STATUS — только тогда показываем «работу» цветом.
bool confirmedOn(VehicleConfig car, DateTime now) =>
    _runningByStatus(car, now) && statusFresh(car, now) && car.basis == 'status' && !callRecent(car, now);

/// Пользователь открыл номеронабиратель для звонка на модуль. Состоялся ли
/// вызов, приложение не знает (журнал звонков не читаем), поэтому прежний
/// таймер и сигнал НЕ сбрасываются: состояние изменит только STATUS после звонка.
void applyCall(VehicleConfig car, DateTime now) {
  car.callAt = now.millisecondsSinceEpoch;
  car.cmdAt = car.callAt;
}

/// Отказ модуля показываем 30 минут, пока после него не пришёл новый ответ.
bool _recentError(VehicleConfig car, DateTime now) {
  final e = car.errorAt;
  if (e == null || car.errorText == null) return false;
  if (now.millisecondsSinceEpoch - e > const Duration(minutes: 30).inMilliseconds) return false;
  if (car.outAt != null && car.outAt! > e) return false;
  if (car.ackAt != null && car.ackAt! > e) return false;
  return true;
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
  return callRecent(car, now);
}

StatusTone statusTone(VehicleConfig car, DateTime now) {
  final nowMs = now.millisecondsSinceEpoch;
  if (waitingReply(car, now)) return StatusTone.waiting;
  if (car.pendingCommand != null || car.awaitCmd != null) return StatusTone.warning;
  if (_recentError(car, now)) return StatusTone.warning;
  if (car.ackCmd != null && car.ackAt != null && (car.outAt == null || car.ackAt! > car.outAt!)) {
    // «Модуль принял запуск» зелёный, только пока не вышло время цикла.
    if (car.ackCmd == 'START') {
      return car.endMs != null && car.endMs! > nowMs ? StatusTone.on : StatusTone.off;
    }
    return car.ackCmd == 'STOP' ? StatusTone.off : StatusTone.idle;
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
  if (_recentError(car, now)) return 'Модуль отклонил: ${car.errorText}';
  if (callRecent(car, now)) return 'После звонка ждём ответ модуля';
  if (car.ackCmd != null && car.ackAt != null && (car.outAt == null || car.ackAt! > car.outAt!)) {
    if (car.ackCmd == 'START' && (car.endMs == null || car.endMs! <= nowMs)) return 'Прогрев завершён по таймеру';
    return car.ackCmd == '?' ? 'Модуль ответил OK' : 'Модуль принял ${commandTitle(car.ackCmd!)}';
  }
  if (car.outState != null && car.outAt != null) {
    if (statusFresh(car, now)) {
      if (_runningByStatus(car, now)) {
        if (car.outIgnored) return 'Старая команда не выполнена · прогрев идёт';
        return '${car.outAlready ? 'Прогрев уже идёт' : 'Прогрев запущен'} · SMS в ${_clock(car.outAt!)}';
      }
      if (car.outState == 'on') return 'Прогрев завершён по таймеру';
      if (car.outIgnored) return 'Старая команда не выполнена · прогрев выключен';
      return '${car.outAlready ? 'Прогрев уже выключен' : 'Прогрев выключен'} · SMS в ${_clock(car.outAt!)}';
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

/// Порог «мало денег»: ниже него плитка баланса подсвечивается оранжевым.
const lowBalanceRub = 50.0;

/// Баланс известен и меньше 50 ₽.
bool balanceLow(VehicleConfig car) =>
    car.balanceAt != null && car.balanceRub != null && car.balanceRub! < lowBalanceRub;

/// Дата, на которую баланс актуален: «на 29.10, 11:34».
String balanceDate(VehicleConfig car) {
  if (car.balanceAt == null) return 'нажмите, чтобы узнать';
  final t = DateTime.fromMillisecondsSinceEpoch(car.balanceAt!);
  String two(int v) => v.toString().padLeft(2, '0');
  return 'на ${two(t.day)}.${two(t.month)}, ${two(t.hour)}:${two(t.minute)}';
}

/// Модуль молчит дольше обычного: команда или звонок были, а ответа нет.
/// Обычно ответ приходит за минуту; самая частая причина молчания — на SIM
/// модуля кончились деньги (входящие команды и звонки работают, SMS не уходят).
bool replyOverdue(VehicleConfig car, DateTime now) {
  final nowMs = now.millisecondsSinceEpoch;
  bool late(int? since, Duration after) =>
      since != null && nowMs - since > after.inMilliseconds && nowMs - since <= const Duration(hours: 2).inMilliseconds;
  if (car.pendingCommand != null && late(car.pendingSince, const Duration(minutes: 5))) return true;
  if (car.awaitCmd != null && late(car.awaitSince, const Duration(minutes: 5))) return true;
  return false;
}

/// Зимний снег: с 1 декабря по 31 января включительно.
bool isWinterSeason(DateTime d) => d.month == 12 || d.month == 1;

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
