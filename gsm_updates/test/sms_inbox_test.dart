import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:larin_cold_gsm_control/sms_inbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ru.larincold/sms');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() { messenger.setMockMethodCallHandler(channel, null); });
  test('restores a received reply with its original timestamp', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => {
      'allowed': true,
      'messages': '[{"body":"Heater: ON","receivedAt":2000,"sentAt":1000}]',
    });
    final snapshot = await SmsInbox().snapshot();
    expect(snapshot.allowed, true);
    expect(snapshot.replies.single.status!.on, true);
    expect(snapshot.replies.single.sentAt.millisecondsSinceEpoch, 1000);
  });
  test('denied permission returns no status', () async {
    messenger.setMockMethodCallHandler(channel, (call) async => {
      'allowed': false, 'messages': '[]',
    });
    final snapshot = await SmsInbox().snapshot();
    expect(snapshot.allowed, false);
    expect(snapshot.replies, isEmpty);
  });
  test('module configuration passes the full number to the receiver', () async {
    MethodCall? received;
    messenger.setMockMethodCallHandler(channel, (call) async { received = call; return null; });
    await SmsInbox().configure('+79991234567');
    expect(received!.method, 'configure');
    expect(received!.arguments, {'number': '+79991234567'});
  });
}
