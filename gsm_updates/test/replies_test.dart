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
      expect(parseReply('Unknown command').kind, ReplyKind.other);
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

    test('a call resets the estimate until STATUS shows the real timer', () {
      final car = VehicleConfig(id: 'a', deviceNumber: '+79281050233', durationMinutes: 30);
      applyReply(car, sms(1, '+79281050233', statusOff, t0));
      applyCall(car, t0.add(const Duration(minutes: 1)));
      expect(car.endMs, isNull);
      expect(statusLine(car, t0.add(const Duration(minutes: 2))), 'Звонок переключил прогрев · обновите состояние');
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
    test('winter snow season is 1 December – 30 January', () {
      expect(isWinterSeason(DateTime(2026, 11, 30)), isFalse);
      expect(isWinterSeason(DateTime(2026, 12, 1)), isTrue);
      expect(isWinterSeason(DateTime(2027, 1, 30)), isTrue);
      expect(isWinterSeason(DateTime(2027, 1, 31)), isFalse);
    });
  });
}
