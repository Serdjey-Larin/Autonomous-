import 'package:flutter_test/flutter_test.dart';
import 'package:larin_cold_gsm_control/device_service.dart';
import 'package:larin_cold_gsm_control/reply_parser.dart';
import 'package:larin_cold_gsm_control/vehicle_state.dart';

// Реальные ответы модуля, снятые пробой 29.10.2026.
const statusOff = 'LARIN COLD\nHeater: OFF\nLeft: 0 min\nBattery: 14.6 V\nTime: 30 min';
const statusOn = 'LARIN COLD\nHeater: ON\nLeft: 14 min\nBattery: 14.6 V\nTime: 30 min';
const balance = 'USSD: Vaw balans: 13 rub.';

InboundSms sms(int seq, String number, String body, DateTime at) => InboundSms(
    seq: seq, number: number, body: body,
    smscMs: at.millisecondsSinceEpoch, receivedMs: at.millisecondsSinceEpoch + 4000);

InboundSms smsAt(int seq, String body, DateTime smsc, DateTime received) => InboundSms(
    seq: seq, number: '+79281050233', body: body,
    smscMs: smsc.millisecondsSinceEpoch, receivedMs: received.millisecondsSinceEpoch);

void main() {
  group('parseReply', () {
    test('STATUS OFF from the real module', () {
      final p = parseReply(statusOff);
      expect(p.kind, ReplyKind.status);
      expect(p.status!.on, isFalse);
      expect(p.status!.timeMinutes, 30);
      expect(p.status!.battery, 14.6);
    });
    test('STATUS ON with CRLF, comma and odd spacing', () {
      final p = parseReply('LARIN COLD\r\nheater:on\r\nLeft:  7 min\r\nBattery: 12,4 V\r\nTime:45 min');
      expect(p.kind, ReplyKind.status);
      expect(p.status!.on, isTrue);
      expect(p.status!.leftMinutes, 7);
      expect(p.status!.battery, 12.4);
    });
    test('OK, balance and other replies', () {
      expect(parseReply(' ok \n').kind, ReplyKind.ok);
      final b = parseReply(balance);
      expect(b.kind, ReplyKind.balance);
      expect(b.balance, 13);
      expect(parseReply('USSD: Balans -5,50 руб.').balance, -5.5);
      expect(parseReply('Unknown command').kind, ReplyKind.error);
      expect(parseReply('BALCODE: *100#').kind, ReplyKind.other);
    });
    test('implausible STATUS is rejected', () {
      expect(parseReply('Heater: ON\nLeft: 50 min\nTime: 30 min').kind, ReplyKind.invalid);
      expect(parseReply('Heater: ON\nTime: 30 min').kind, ReplyKind.invalid);
      expect(parseReply('Heater: ON\nLeft: 5 min\nBattery: 99 V\nTime: 30 min').kind, ReplyKind.invalid);
    });
    test('canonical numbers match only in full', () {
      expect(canonicalNumber('8 (928) 105-02-33'), '+79281050233');
      expect(canonicalNumber('+79281050233'), '+79281050233');
      expect(canonicalNumber('105-02-33'), '');
    });
  });

  group('applyReply', () {
    final t0 = DateTime(2026, 10, 29, 7, 0);

    test('STATUS ON corrects the countdown from Left and Time', () {
      final car = VehicleConfig(id: 'a', deviceNumber: '+79281050233', durationMinutes: 30);
      final r = applyReply(car, sms(1, '+79281050233', statusOn, t0));
      expect(r.timerChanged, isTrue);
      expect(car.outState, 'on');
      expect(car.basis, 'status');
      expect(car.endMs, t0.millisecondsSinceEpoch + 14 * 60000);
      expect(car.cycleMinutes, 30);
      expect(confirmedOn(car, t0.add(const Duration(minutes: 1))), isTrue);
    });

    test('STATUS OFF stops the countdown', () {
      final car = VehicleConfig(id: 'a', deviceNumber: '+79281050233');
      applyUserSent(car, 'START', t0);
      expect(car.endMs, isNotNull);
      applyReply(car, sms(1, '+79281050233', statusOff, t0.add(const Duration(minutes: 2))));
      expect(car.endMs, isNull);
      expect(car.outState, 'off');
      expect(car.awaitCmd, isNull);
    });

    test('a delayed older STATUS does not overwrite a newer one', () {
      final car = VehicleConfig(id: 'a', deviceNumber: '+79281050233');
      applyReply(car, sms(2, '+79281050233', statusOff, t0.add(const Duration(minutes: 5))));
      applyReply(car, sms(3, '+79281050233', statusOn, t0));
      expect(car.outState, 'off');
    });

    test('OK confirms only the single awaited command', () {
      final car = VehicleConfig(id: 'a', deviceNumber: '+79281050233');
      applyUserSent(car, 'START', t0);
      applyReply(car, sms(1, '+79281050233', 'OK', t0.add(const Duration(minutes: 1))));
      expect(car.ackCmd, 'START');
      expect(car.outState, isNull, reason: 'OK is not proof of the output state');
      expect(statusLine(car, t0.add(const Duration(minutes: 2))), contains('Модуль принял запуск'));
      // Second unexpected OK is ambiguous.
      applyReply(car, sms(2, '+79281050233', 'OK', t0.add(const Duration(minutes: 3))));
      expect(car.ackCmd, '?');
    });

    test('a reply for one car never changes another car', () {
      final a = VehicleConfig(id: 'a', deviceNumber: '+79281050233');
      final b = VehicleConfig(id: 'b', deviceNumber: '+79281050234');
      final cars = [a, b];
      final m = sms(1, '89281050234', statusOn, t0);
      final car = carForNumber(cars, m.number);
      expect(car, same(b));
      applyReply(car!, m);
      expect(a.outState, isNull);
      expect(b.outState, 'on');
      expect(carForNumber(cars, '+79991050233'), isNull);
    });

    test('TIME during an active cycle is counted from the original start', () {
      final car = VehicleConfig(id: 'a', deviceNumber: '+79281050233', durationMinutes: 30);
      applyUserSent(car, 'START', t0);
      final changed = applyUserSent(car, 'TIME:60', t0.add(const Duration(minutes: 10)));
      expect(changed, isTrue);
      expect(car.cycleMinutes, 60);
      expect(car.endMs, t0.millisecondsSinceEpoch + 60 * 60000);
    });

    test('status line never claims the heater runs without STATUS', () {
      final car = VehicleConfig(id: 'a', deviceNumber: '+79281050233');
      applyUserSent(car, 'START', t0);
      expect(statusLine(car, t0.add(const Duration(minutes: 1))), 'Отправлено: запуск · ждём ответ модуля');
      expect(statusLine(car, t0.add(const Duration(minutes: 20))), contains('Ответа на запуск нет'));
      expect(confirmedOn(car, t0.add(const Duration(minutes: 1))), isFalse);
    });

    test('OK auto-confirms the command whose SMS editor was opened', () {
      final car = VehicleConfig(id: 'a', deviceNumber: '+79281050233', durationMinutes: 30,
          pendingCommand: 'START', pendingSince: t0.millisecondsSinceEpoch);
      expect(statusLine(car, t0.add(const Duration(seconds: 20))), 'Ждём ответ модуля на запуск');
      final okAt = t0.add(const Duration(seconds: 40));
      final r = applyReply(car, sms(1, '+79281050233', 'OK', okAt));
      expect(r.timerChanged, isTrue);
      expect(car.pendingCommand, isNull);
      expect(car.ackCmd, 'START');
      expect(car.endMs, okAt.millisecondsSinceEpoch + 30 * 60000, reason: 'countdown starts at the module reply');
      expect(car.outState, isNull);
      expect(statusLine(car, okAt.add(const Duration(minutes: 1))), contains('Модуль принял запуск'));
    });

    test('OK for STOP stops the countdown; late OK does not confirm', () {
      final car = VehicleConfig(id: 'a', deviceNumber: '+79281050233');
      applyUserSent(car, 'START', t0);
      car.pendingCommand = 'STOP';
      car.pendingSince = t0.add(const Duration(minutes: 5)).millisecondsSinceEpoch;
      applyReply(car, sms(1, '+79281050233', 'OK', t0.add(const Duration(minutes: 6))));
      expect(car.endMs, isNull);
      expect(car.ackCmd, 'STOP');
      final late = VehicleConfig(id: 'b', deviceNumber: '+79281050234',
          pendingCommand: 'START', pendingSince: t0.millisecondsSinceEpoch);
      applyReply(late, sms(2, '+79281050234', 'OK', t0.add(const Duration(minutes: 30))));
      expect(late.pendingCommand, 'START');
      expect(late.endMs, isNull);
      expect(statusLine(late, t0.add(const Duration(minutes: 31))), contains('подтвердите отправку вручную'));
    });

    test('balance reply is stored for the tile', () {
      final car = VehicleConfig(id: 'a', deviceNumber: '+79281050233');
      applyReply(car, sms(1, '+79281050233', balance, t0));
      expect(car.balanceRub, 13);
      expect(balanceSubtitle(car), startsWith('13 ₽ · '));
      expect(VehicleConfig.fromJson(car.toJson()).balanceRub, 13);
    });

    test('a call keeps the old timer until STATUS after the call shows the real one', () {
      final car = VehicleConfig(id: 'a', deviceNumber: '+79281050233', durationMinutes: 30);
      applyReply(car, sms(1, '+79281050233', statusOff, t0));
      applyCall(car, t0.add(const Duration(minutes: 1)));
      expect(car.outState, 'off', reason: 'opening the dialer is not proof of a call');
      expect(statusLine(car, t0.add(const Duration(minutes: 2))), 'После звонка ждём ответ модуля');
      expect(statusTone(car, t0.add(const Duration(minutes: 2))), StatusTone.waiting);
      expect(statusLine(car, t0.add(const Duration(minutes: 12))), startsWith('Прогрев выключен'),
          reason: 'cancelled call: after 10 min the last known state is shown again');
      applyReply(car, sms(2, '+79281050233', statusOn, t0.add(const Duration(minutes: 3))));
      expect(afterCall(car), isFalse);
      expect(car.endMs, t0.add(const Duration(minutes: 3)).millisecondsSinceEpoch + 14 * 60000);
      expect(confirmedOn(car, t0.add(const Duration(minutes: 4))), isTrue);
      expect(statusLine(car, t0.add(const Duration(minutes: 4))), startsWith('Прогрев запущен'));
    });

    test('OK texts are short', () {
      final car = VehicleConfig(id: 'a', deviceNumber: '+79281050233',
          pendingCommand: 'STOP', pendingSince: t0.millisecondsSinceEpoch);
      applyReply(car, sms(1, '+79281050233', 'OK', t0.add(const Duration(seconds: 30))));
      expect(statusLine(car, t0.add(const Duration(minutes: 1))), 'Модуль принял остановку');
      applyReply(car, sms(2, '+79281050233', 'OK', t0.add(const Duration(minutes: 2))));
      expect(statusLine(car, t0.add(const Duration(minutes: 3))), 'Модуль ответил OK');
    });

    test('state survives JSON round trip', () {
      final car = VehicleConfig(id: 'a', deviceNumber: '+79281050233');
      applyReply(car, sms(1, '+79281050233', statusOn, t0));
      final back = VehicleConfig.fromJson(car.toJson());
      expect(back.outState, 'on');
      expect(back.battery, 14.6);
      expect(back.endMs, car.endMs);
      expect(back.basis, 'status');
    });
  });
  group('1.6.0 screen texts', () {
    final t0 = DateTime(2026, 10, 29, 7, 0);
    test('commands read as words', () {
      expect(commandTitle('START'), 'запуск');
      expect(commandTitle('STOP'), 'остановку');
      expect(commandTitle('TIME:45'), 'время 45 мин');
    });
    test('idle and estimate lines', () {
      final car = VehicleConfig(id: 'a');
      expect(statusLine(car, t0), 'Готов к запуску');
      expect(statusTone(car, t0), StatusTone.idle);
      car.endMs = t0.add(const Duration(minutes: 10)).millisecondsSinceEpoch;
      expect(statusLine(car, t0), 'Расчётный таймер · ответа модуля нет');
    });
    test('waiting spinner only within reply timeout', () {
      final car = VehicleConfig(id: 'a', pendingCommand: 'START', pendingSince: t0.millisecondsSinceEpoch);
      expect(waitingReply(car, t0.add(const Duration(minutes: 1))), isTrue);
      expect(statusTone(car, t0.add(const Duration(minutes: 1))), StatusTone.waiting);
      expect(waitingReply(car, t0.add(const Duration(minutes: 16))), isFalse);
      expect(statusTone(car, t0.add(const Duration(minutes: 16))), StatusTone.warning);
    });
    test('status tones follow STATUS only', () {
      final car = VehicleConfig(id: 'a', deviceNumber: '+79281050233');
      applyReply(car, sms(1, '+79281050233', statusOn, t0));
      expect(statusTone(car, t0.add(const Duration(minutes: 1))), StatusTone.on);
      expect(statusLine(car, t0.add(const Duration(minutes: 1))), 'Прогрев запущен · SMS в 07:00');
      expect(batteryText(car), '14,6 В');
      expect(statusTone(car, t0.add(const Duration(minutes: 30))), StatusTone.off);
      expect(statusLine(car, t0.add(const Duration(minutes: 30))), 'Прогрев завершён по таймеру');
      applyReply(car, sms(2, '+79281050233', statusOff, t0.add(const Duration(minutes: 31))));
      expect(statusTone(car, t0.add(const Duration(minutes: 32))), StatusTone.off);
      expect(statusLine(car, t0.add(const Duration(minutes: 32))), 'Прогрев выключен · SMS в 07:31');
    });
    test('balance tile shows amount and date of the SMS', () {
      final car = VehicleConfig(id: 'a');
      expect(balanceAmount(car), '—');
      expect(balanceDate(car), 'нажмите, чтобы узнать');
      car.balanceRub = 13; car.balanceAt = DateTime(2026, 10, 29, 11, 34).millisecondsSinceEpoch;
      expect(balanceAmount(car), '13 ₽');
      expect(balanceDate(car), 'на 29.10, 11:34');
      car.balanceRub = -5.2;
      expect(balanceAmount(car), '−5,20 ₽');
    });
    test('balance is always shown in rubles', () {
      expect(parseReply('USSD: Balans 250.50 RUR').balance, 250.5);
      expect(parseReply('Баланс: -5,20р').balance, -5.2);
      expect(parseReply('USSD: Vash balans 87').balance, 87);
      final car = VehicleConfig(id: 'a', balanceRub: 250.5, balanceAt: 1);
      expect(balanceAmount(car), '250,50 ₽');
    });
    test('last STATUS stays valid for 5 hours', () {
      final car = VehicleConfig(id: 'a', deviceNumber: '+79281050233');
      applyReply(car, sms(1, '+79281050233', statusOn, t0));
      expect(statusLine(car, t0.add(const Duration(minutes: 13))), 'Прогрев запущен · SMS в 07:00');
      expect(confirmedOn(car, t0.add(const Duration(minutes: 13))), isTrue);
      expect(statusLine(car, t0.add(const Duration(hours: 4))), 'Прогрев завершён по таймеру');
      expect(statusLine(car, t0.add(const Duration(hours: 5, minutes: 1))), 'Данные от 29.10 07:00 устарели · обновите состояние');
      expect(statusTone(car, t0.add(const Duration(hours: 5, minutes: 1))), StatusTone.warning);
    });
    test('balance tile is highlighted only below 50 ₽', () {
      final car = VehicleConfig(id: 'a');
      expect(balanceLow(car), isFalse);
      car.balanceAt = 1; car.balanceRub = 49.9;
      expect(balanceLow(car), isTrue);
      car.balanceRub = 50;
      expect(balanceLow(car), isFalse);
      car.balanceRub = -3;
      expect(balanceLow(car), isTrue);
    });
    test('START while running: «уже идёт» and the pending START is closed', () {
      final car = VehicleConfig(id: 'a', deviceNumber: '+79281050233',
          pendingCommand: 'START', pendingSince: t0.millisecondsSinceEpoch);
      const already = 'LARIN COLD\nAlready running\nHeater: ON\nLeft: 20 min\nBattery: 14.6 V\nTime: 30 min';
      expect(parseReply(already).status!.already, isTrue);
      expect(parseReply(statusOn).status!.already, isFalse);
      applyReply(car, sms(1, '+79281050233', already, t0.add(const Duration(seconds: 40))));
      expect(car.pendingCommand, isNull);
      expect(statusLine(car, t0.add(const Duration(minutes: 1))), 'Прогрев уже идёт · SMS в 07:00');
      expect(statusTone(car, t0.add(const Duration(minutes: 1))), StatusTone.on);
      applyReply(car, sms(2, '+79281050233', statusOn, t0.add(const Duration(minutes: 2))));
      expect(statusLine(car, t0.add(const Duration(minutes: 3))), 'Прогрев запущен · SMS в 07:02');
    });
    test('module silent: hint about the SIM balance', () {
      final car = VehicleConfig(id: 'a', deviceNumber: '+79281050233',
          pendingCommand: 'START', pendingSince: t0.millisecondsSinceEpoch);
      expect(replyOverdue(car, t0.add(const Duration(minutes: 2))), isFalse);
      expect(replyOverdue(car, t0.add(const Duration(minutes: 6))), isTrue);
      applyReply(car, sms(1, '+79281050233', statusOn, t0.add(const Duration(minutes: 7))));
      expect(replyOverdue(car, t0.add(const Duration(minutes: 8))), isFalse);
      applyCall(car, t0.add(const Duration(minutes: 10)));
      expect(replyOverdue(car, t0.add(const Duration(minutes: 14))), isFalse,
          reason: 'a call may have been cancelled in the dialer: no «module silent» alarm');
    });
    test('winter snow season is 1 December – 31 January', () {
      expect(isWinterSeason(DateTime(2026, 11, 30)), isFalse);
      expect(isWinterSeason(DateTime(2026, 12, 1)), isTrue);
      expect(isWinterSeason(DateTime(2027, 1, 30)), isTrue);
      expect(isWinterSeason(DateTime(2027, 1, 31)), isTrue);
      expect(isWinterSeason(DateTime(2027, 2, 1)), isFalse);
    });
  });

  group('1.7.2: старые SMS, отказы, смена номера (отчёт Астры)', () {
    final t0 = DateTime(2026, 10, 29, 7, 0);
    Duration s(int v) => Duration(seconds: v);
    Duration m(int v) => Duration(minutes: v);

    test('OK сформирован за 30 с до нового START — START не подтверждает', () {
      final car = VehicleConfig(id: 'a', deviceNumber: '+79281050233', durationMinutes: 30,
          pendingCommand: 'START', pendingSince: t0.millisecondsSinceEpoch, cmdAt: t0.millisecondsSinceEpoch);
      applyReply(car, smsAt(1, 'OK', t0.subtract(s(30)), t0.add(s(10))));
      expect(car.pendingCommand, 'START');
      expect(car.endMs, isNull);
      expect(car.ackCmd, '?');
    });

    test('STATUS часовой давности не заменяет более новое «выключен»', () {
      final car = VehicleConfig(id: 'a', deviceNumber: '+79281050233');
      applyReply(car, smsAt(1, statusOff, t0, t0.add(s(5))));
      applyReply(car, smsAt(2, statusOn, t0.subtract(m(60)), t0.add(m(5))));
      expect(car.outState, 'off');
      expect(car.endMs, isNull);
    });

    test('STATUS, сформированный до STOP, после STOP не включает отсчёт', () {
      final car = VehicleConfig(id: 'a', deviceNumber: '+79281050233');
      applyReply(car, smsAt(1, statusOn, t0, t0.add(s(5))));
      final stopAt = t0.add(m(5));
      car.pendingCommand = 'STOP'; car.pendingSince = stopAt.millisecondsSinceEpoch;
      car.cmdAt = stopAt.millisecondsSinceEpoch;
      final endBefore = car.endMs;
      applyReply(car, smsAt(2, statusOn, t0.add(m(4)), t0.add(m(6))));
      expect(car.pendingCommand, 'STOP', reason: 'старый ответ не снимает ожидание остановки');
      expect(car.endMs, endBefore);
      expect(car.outAt, t0.millisecondsSinceEpoch);
      applyReply(car, smsAt(3, statusOff, t0.add(m(5)).add(s(30)), t0.add(m(6))));
      expect(car.pendingCommand, isNull);
      expect(car.outState, 'off');
    });

    test('SMS-центр «спешит» — берётся время получения', () {
      final sms = smsAt(1, 'OK', t0.add(m(10)), t0);
      expect(sms.effectiveMs, t0.millisecondsSinceEpoch);
      final late = smsAt(2, 'OK', t0.subtract(m(90)), t0);
      expect(late.effectiveMs, t0.subtract(m(90)).millisecondsSinceEpoch);
    });

    test('после окончания отсчёта индикатор не зелёный', () {
      final car = VehicleConfig(id: 'a', deviceNumber: '+79281050233', durationMinutes: 30,
          pendingCommand: 'START', pendingSince: t0.millisecondsSinceEpoch);
      applyReply(car, smsAt(1, 'OK', t0.add(s(30)), t0.add(s(35))));
      expect(statusTone(car, t0.add(m(5))), StatusTone.on);
      expect(car.secondsLeft(t0.add(const Duration(hours: 2))), 0);
      expect(statusTone(car, t0.add(const Duration(hours: 2))), StatusTone.off);
      expect(statusLine(car, t0.add(const Duration(hours: 2))), 'Прогрев завершён по таймеру');
    });

    test('DENIED завершает ожидание и показывает причину', () {
      final car = VehicleConfig(id: 'a', deviceNumber: '+79281050233',
          pendingCommand: 'TIME:60', pendingSince: t0.millisecondsSinceEpoch);
      final r = applyReply(car, smsAt(1, 'DENIED', t0.add(s(30)), t0.add(s(35))));
      expect(r.kind, ReplyKind.error);
      expect(car.pendingCommand, isNull);
      expect(statusLine(car, t0.add(m(1))), 'Модуль отклонил: команда доступна только мастер-номеру');
      expect(statusTone(car, t0.add(m(1))), StatusTone.warning);
      expect(statusLine(car, t0.add(m(40))), isNot(contains('отклонил')));
    });

    test('тексты отказов прошивки', () {
      expect(parseReply('ERROR TIME 15-120').kind, ReplyKind.error);
      expect(moduleErrorText('UNKNOWN COMMAND'), 'модуль не знает такой команды');
      expect(moduleErrorText('NO GSM NETWORK'), 'у модуля нет сети');
      expect(moduleErrorText('USSD TIMEOUT'), 'оператор не ответил на запрос баланса');
      expect(parseReply('USSD: Vaw balans: 13 rub.').kind, ReplyKind.balance);
      expect(parseReply('USSD MENU: Balans 137 r.').kind, ReplyKind.balance);
    });

    test('смена номера модуля стирает данные прежнего модуля', () {
      final car = VehicleConfig(id: 'a', deviceNumber: '+79281050233');
      applyReply(car, smsAt(1, statusOn, t0, t0.add(s(5))));
      applyReply(car, smsAt(2, balance, t0, t0.add(s(5))));
      car.forgetModuleData();
      expect(car.battery, isNull);
      expect(car.balanceAt, isNull);
      expect(car.lastReply, isNull);
      expect(car.outState, isNull);
      expect(car.endMs, isNull);
      expect(statusLine(car, t0.add(m(1))), 'Готов к запуску');
    });
  });

  group('1.7.3: звонок и устаревшие команды', () {
    final t0 = DateTime(2026, 10, 30, 7, 0);
    test('открытие номеронабирателя не сбрасывает идущий отсчёт', () {
      final car = VehicleConfig(id: 'a', deviceNumber: '+79281050233');
      applyReply(car, smsAt(1, statusOn, t0, t0.add(const Duration(seconds: 5))));
      final end = car.endMs;
      applyCall(car, t0.add(const Duration(minutes: 2)));
      expect(car.endMs, end);
      expect(confirmedOn(car, t0.add(const Duration(minutes: 3))), isFalse);
      expect(confirmedOn(car, t0.add(const Duration(minutes: 13))), isTrue);
    });
    test('«Old command ignored» показывается понятным текстом', () {
      const ignored = 'LARIN COLD\nOld command ignored\nHeater: OFF\nLeft: 0 min\nBattery: 14.6 V\nTime: 30 min';
      final p = parseReply(ignored);
      expect(p.kind, ReplyKind.status);
      expect(p.status!.ignored, isTrue);
      expect(p.status!.already, isFalse);
      final car = VehicleConfig(id: 'a', deviceNumber: '+79281050233');
      applyReply(car, smsAt(1, ignored, t0, t0.add(const Duration(seconds: 5))));
      expect(statusLine(car, t0.add(const Duration(minutes: 1))), 'Старая команда не выполнена · прогрев выключен');
      expect(VehicleConfig.fromJson(car.toJson()).outIgnored, isTrue);
    });
  });
  group('1.8.2 balance code reply', () {
    test('BALCODE reply is parsed and stored', () {
      expect(balanceCodeReply('BALCODE: *100#'), '*100#');
      expect(balanceCodeReply('BALCODE: NOT SET'), '');
      expect(balanceCodeReply('Heater: OFF'), isNull);
      final car = VehicleConfig(deviceNumber: '+79990000000');
      final t = DateTime(2026, 10, 30, 11).millisecondsSinceEpoch;
      applyReply(car, InboundSms(seq: 1, number: '+79990000000', body: 'BALCODE: *102#', receivedMs: t, smscMs: t));
      expect(car.moduleUssd, '*102#');
      expect(VehicleConfig.fromJson(car.toJson()).moduleUssd, '*102#');
    });
  });
}
