/// Настройка телефона, чтобы ответы модуля принимались и при закрытом
/// приложении: шаги по производителю, их состояние и что открыть.
library;

/// Что приложение знает о телефоне (из нативного канала `state`).
class PhoneState {
  const PhoneState({
    this.granted = false,
    this.manufacturer = '',
    this.brand = '',
    this.model = '',
    this.sdk = 0,
    this.notifications = true,
    this.battery = false,
    this.installer = '',
    this.bgReplyAt = 0,
  });

  /// Разрешение RECEIVE_SMS выдано.
  final bool granted;
  final String manufacturer, brand, model;
  final int sdk;

  /// Уведомления приложения включены.
  final bool notifications;

  /// Приложение исключено из оптимизации батареи (Android «Без ограничений»).
  final bool battery;

  /// Кто установил приложение (пусто — неизвестно / из файла).
  final String installer;

  /// Когда последний раз пришло уведомление об ответе при закрытом приложении (мс), 0 — ни разу.
  final int bgReplyAt;

  factory PhoneState.fromMap(Map<Object?, Object?> m) => PhoneState(
        granted: m['granted'] == true,
        manufacturer: (m['manufacturer'] as String?) ?? '',
        brand: (m['brand'] as String?) ?? '',
        model: (m['model'] as String?) ?? '',
        sdk: (m['sdk'] as num?)?.toInt() ?? 0,
        notifications: m['notifications'] != false,
        battery: m['battery'] == true,
        installer: (m['installer'] as String?) ?? '',
        bgReplyAt: (m['bgReplyAt'] as num?)?.toInt() ?? 0,
      );
}

enum Vendor { xiaomi, huawei, honor, samsung, oppo, vivo, other }

Vendor vendorOf(PhoneState s) {
  final m = '${s.manufacturer} ${s.brand}'.toLowerCase();
  if (m.contains('xiaomi') || m.contains('redmi') || m.contains('poco')) return Vendor.xiaomi;
  if (m.contains('honor')) return Vendor.honor;
  if (m.contains('huawei')) return Vendor.huawei;
  if (m.contains('samsung')) return Vendor.samsung;
  if (m.contains('oppo') || m.contains('realme') || m.contains('oneplus')) return Vendor.oppo;
  if (m.contains('vivo') || m.contains('iqoo')) return Vendor.vivo;
  return Vendor.other;
}

String vendorName(Vendor v) => switch (v) {
      Vendor.xiaomi => 'Xiaomi',
      Vendor.huawei => 'Huawei',
      Vendor.honor => 'Honor',
      Vendor.samsung => 'Samsung',
      Vendor.oppo => 'Realme / OPPO / OnePlus',
      Vendor.vivo => 'vivo',
      Vendor.other => 'этом телефоне',
    };

/// Магазины приложений ставят через системный установщик по сессии —
/// «ограниченные настройки» Android 13+ таких приложений не касаются.
const knownStores = {
  'ru.vk.store', // RuStore
  'com.android.vending', // Google Play
  'com.huawei.appmarket',
  'com.hihonor.appmarket',
  'com.xiaomi.market',
  'com.xiaomi.mipicks',
  'com.sec.android.app.samsungapps',
  'com.heytap.market',
  'com.oppo.market',
  'com.bbk.appstore',
};

bool installedFromStore(PhoneState s) => knownStores.contains(s.installer);

/// Кнопка «Разрешить» для SMS, вероятно, серая: Android 13+ и установка не из магазина.
bool likelyRestricted(PhoneState s) => s.sdk >= 33 && !installedFromStore(s);

enum StepStatus { done, todo, unverified }

class SetupStep {
  const SetupStep(this.id, this.title, this.subtitle, this.status, this.action);
  final String id, title, subtitle;
  final StepStatus status;

  /// Что открыть: 'sms' (запрос разрешения), 'notifications', 'battery',
  /// 'autostart', 'miuiActivity', 'app'.
  final String action;
}

/// Шаги для этого телефона. Автозапуск и подобные настройки оболочек система
/// не сообщает: они «не проверены», пока не пришло уведомление при закрытом
/// приложении — это и есть доказательство, что всё работает.
List<SetupStep> setupSteps(PhoneState s) {
  final verified = s.bgReplyAt > 0;
  StepStatus known(bool ok) => ok ? StepStatus.done : StepStatus.todo;
  final unknown = verified ? StepStatus.done : StepStatus.unverified;
  const proven = 'Проверено: уведомление пришло';
  final steps = <SetupStep>[
    SetupStep('sms', 'Приём SMS от модуля', s.granted ? 'Разрешено' : 'Нужно разрешить', known(s.granted), 'sms'),
    SetupStep('notifications', 'Уведомления', s.notifications ? 'Включены' : 'Выключены — уведомления не придут',
        known(s.notifications), 'notifications'),
  ];
  final battery = SetupStep('battery', 'Батарея: без ограничений',
      s.battery ? 'Телефон не усыпляет приложение' : 'Иначе телефон может усыпить приложение', known(s.battery), 'battery');
  switch (vendorOf(s)) {
    case Vendor.xiaomi:
      steps.add(SetupStep('autostart', 'Автозапуск', verified ? proven : 'Без него Xiaomi не передаёт SMS закрытому приложению',
          unknown, 'autostart'));
      steps.add(SetupStep('miui', 'Контроль активности', verified ? proven : 'Выберите «Нет ограничений»', unknown, 'miuiActivity'));
    case Vendor.huawei:
    case Vendor.honor:
      steps.add(SetupStep('autostart', 'Запуск приложений',
          verified ? proven : 'Выберите «Вручную» и включите все три переключателя', unknown, 'autostart'));
    case Vendor.samsung:
      steps.add(battery);
      steps.add(SetupStep('sleep', 'Не в «Спящих приложениях»',
          verified ? proven : 'Батарея → Ограничения в фоне: уберите приложение из спящих', unknown, 'app'));
    case Vendor.oppo:
    case Vendor.vivo:
      steps.add(SetupStep('autostart', 'Автозапуск', verified ? proven : 'Разрешите запуск в фоне', unknown, 'autostart'));
      steps.add(battery);
    case Vendor.other:
      steps.add(battery);
  }
  return steps;
}

int stepsDone(List<SetupStep> steps) => steps.where((s) => s.status == StepStatus.done).length;
bool setupComplete(List<SetupStep> steps) => stepsDone(steps) == steps.length;

/// Нужна ли плашка на главном экране. Если хоть раз пришло уведомление при
/// закрытом приложении, фоновый приём доказанно работает — плашка не нужна,
/// даже если какой-то шаг (например, батарея) остался жёлтым.
bool setupHintWanted(PhoneState s) {
  if (s.granted && s.bgReplyAt > 0) return false;
  return !setupComplete(setupSteps(s));
}
