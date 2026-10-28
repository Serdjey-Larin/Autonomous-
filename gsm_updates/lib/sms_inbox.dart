import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'heater_status.dart';

class ModuleReply {
  ModuleReply(this.body, this.receivedAt, this.sentAt);
  final String body;
  final DateTime receivedAt;
  final DateTime sentAt;
  HeaterStatus? get status => HeaterStatus.parse(body);
}

class SmsInbox {
  static const _channel = MethodChannel('ru.larincold/sms');
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  void listen(VoidCallback changed) {
    if (supported) _channel.setMethodCallHandler((call) async {
      if (call.method == 'smsChanged') changed();
    });
  }
  void dispose() { if (supported) _channel.setMethodCallHandler(null); }
  Future<void> configure(String number) async {
    if (supported) await _channel.invokeMethod<void>('configure', {'number': number});
  }
  Future<bool> requestPermission() async => supported &&
      (await _channel.invokeMethod<bool>('requestPermission') ?? false);
  Future<void> openSettings() async {
    if (supported) await _channel.invokeMethod<void>('openSettings');
  }
  Future<({bool allowed, List<ModuleReply> replies})> snapshot() async {
    if (!supported) return (allowed: false, replies: <ModuleReply>[]);
    final data = await _channel.invokeMapMethod<String, dynamic>('snapshot') ?? {};
    final rows = jsonDecode(data['messages'] as String? ?? '[]') as List;
    return (allowed: data['allowed'] == true, replies: rows.map((row) => ModuleReply(
      row['body'] as String,
      DateTime.fromMillisecondsSinceEpoch(row['receivedAt'] as int),
      DateTime.fromMillisecondsSinceEpoch(row['sentAt'] as int),
    )).toList());
  }
}
