import 'package:flutter_test/flutter_test.dart';
import 'package:larin_cold_gsm_control/phone_setup.dart';

void main() {
  test('Xiaomi: SMS, notifications, autostart, activity control; unverified until a background reply', () {
    const s = PhoneState(granted: true, manufacturer: 'xiaomi', brand: 'redmi', model: 'Redmi Note 13', sdk: 34);
    final steps = setupSteps(s);
    expect(steps.map((e) => e.id), ['sms', 'notifications', 'autostart', 'miui']);
    expect(stepsDone(steps), 2);
    expect(steps[2].status, StepStatus.unverified);
    expect(steps[2].action, 'autostart');
    const verified = PhoneState(granted: true, manufacturer: 'xiaomi', sdk: 34, bgReplyAt: 1);
    expect(setupComplete(setupSteps(verified)), isTrue);
  });

  test('Samsung: battery is detectable, sleeping apps proven by a background reply', () {
    const s = PhoneState(granted: true, manufacturer: 'samsung', sdk: 35, battery: true);
    final steps = setupSteps(s);
    expect(steps.map((e) => e.id), ['sms', 'notifications', 'battery', 'sleep']);
    expect(steps[2].status, StepStatus.done);
    expect(steps[3].status, StepStatus.unverified);
    const noBattery = PhoneState(granted: true, manufacturer: 'samsung', sdk: 35, bgReplyAt: 1);
    expect(setupSteps(noBattery)[2].status, StepStatus.todo, reason: 'a measured setting is never assumed');
  });

  test('Pixel / other: SMS, notifications, battery', () {
    const s = PhoneState(granted: false, manufacturer: 'google', sdk: 35, battery: true, notifications: false);
    final steps = setupSteps(s);
    expect(steps.map((e) => e.id), ['sms', 'notifications', 'battery']);
    expect(steps[0].status, StepStatus.todo);
    expect(steps[1].status, StepStatus.todo);
    expect(stepsDone(steps), 1);
  });

  test('Realme, Honor and vivo are recognised', () {
    expect(vendorOf(const PhoneState(manufacturer: 'realme')), Vendor.oppo);
    expect(vendorOf(const PhoneState(manufacturer: 'oneplus')), Vendor.oppo);
    expect(vendorOf(const PhoneState(manufacturer: 'honor')), Vendor.honor);
    expect(vendorOf(const PhoneState(manufacturer: 'huawei')), Vendor.huawei);
    expect(vendorOf(const PhoneState(manufacturer: 'vivo')), Vendor.vivo);
  });

  test('grey «Allow» button is expected only for file installs on Android 13+', () {
    expect(likelyRestricted(const PhoneState(sdk: 34, installer: 'com.google.android.packageinstaller')), isTrue);
    expect(likelyRestricted(const PhoneState(sdk: 34, installer: '')), isTrue);
    expect(likelyRestricted(const PhoneState(sdk: 34, installer: 'ru.vk.store')), isFalse);
    expect(likelyRestricted(const PhoneState(sdk: 31, installer: '')), isFalse);
    final m = PhoneState.fromMap({'granted': true, 'manufacturer': 'samsung', 'sdk': 35, 'battery': true,
      'installer': 'ru.vk.store', 'bgReplyAt': 5, 'notifications': true, 'model': 'SM-A556'});
    expect(m.granted && m.battery && m.bgReplyAt == 5 && m.installer == 'ru.vk.store', isTrue);
  });
}
