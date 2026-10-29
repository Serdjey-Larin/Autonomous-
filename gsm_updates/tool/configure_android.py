from pathlib import Path
import shutil
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
android = root / 'android/app/src/main'
ns = '{http://schemas.android.com/apk/res/android}'
ET.register_namespace('android', ns[1:-1])
p = android / 'AndroidManifest.xml'
tree = ET.parse(p)
m = tree.getroot()
# READ_SMS (чтение базы сообщений) не нужен и не допускается; только RECEIVE_SMS для новых SMS.
for e in list(m.findall('uses-permission')):
    if e.get(ns+'name') in ['android.permission.RECEIVE_SMS','android.permission.READ_SMS']:
        m.remove(e)
for permission in ['POST_NOTIFICATIONS','SCHEDULE_EXACT_ALARM','RECEIVE_BOOT_COMPLETED','VIBRATE','RECEIVE_SMS']:
    ET.SubElement(m, 'uses-permission', {ns+'name': 'android.permission.'+permission})
queries = m.find('queries')
if queries is None: queries = ET.SubElement(m, 'queries')
i = ET.SubElement(queries, 'intent')
ET.SubElement(i, 'action', {ns+'name': 'android.intent.action.SENDTO'})
ET.SubElement(i, 'data', {ns+'scheme': 'smsto'})
a = m.find('application')
a.set(ns+'label', 'LARIN GSM')
a.set(ns+'allowBackup', 'false')
a.set(ns+'icon', '@mipmap/ic_launcher')
a.set(ns+'roundIcon', '@mipmap/ic_launcher')
for receiver in list(a.findall('receiver')):
    if receiver.get(ns+'name') == '.SmsReceiver': a.remove(receiver)
sms = ET.SubElement(a, 'receiver', {ns+'name': '.SmsReceiver', ns+'exported': 'true',
                                    ns+'permission': 'android.permission.BROADCAST_SMS'})
sms_filter = ET.SubElement(sms, 'intent-filter')
ET.SubElement(sms_filter, 'action', {ns+'name': 'android.provider.Telephony.SMS_RECEIVED'})
ET.SubElement(a, 'receiver', {ns+'name': '.AlarmReceiver', ns+'exported':'false'})
r = ET.SubElement(a, 'receiver', {ns+'name': '.AlarmRestoreReceiver', ns+'exported':'false'})
f = ET.SubElement(r, 'intent-filter')
for action in ['android.intent.action.BOOT_COMPLETED','android.intent.action.TIME_SET','android.intent.action.TIMEZONE_CHANGED','android.intent.action.MY_PACKAGE_REPLACED','android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED']:
    ET.SubElement(f,'action',{ns+'name':action})
tree.write(p, encoding='unicode')
kotlin = android/'kotlin/ru/larincold/larin_cold_gsm_control'
kotlin.mkdir(parents=True, exist_ok=True)
for source in (root/'native').glob('*.kt'):
    shutil.copy2(source, kotlin/source.name)
assert (kotlin/'SmsReceiver.kt').exists(), 'SmsReceiver.kt not copied'
# Native vector icon: large power symbol and three GSM bars, inside adaptive safe zone.
res = android/'res'
for folder in ['drawable', 'mipmap-anydpi', 'mipmap-anydpi-v26']:
    (res/folder).mkdir(parents=True, exist_ok=True)
foreground = '''<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">
<path android:strokeColor="#FFFFFF" android:strokeWidth="6" android:strokeLineCap="round" android:fillColor="#00000000" android:pathData="M42,35 A21,21 0,1 0,66 35 M54,29 L54,48"/>
<path android:fillColor="#6FE1FF" android:pathData="M72,32 L76,32 L76,38 L72,38 Z M78,28 L82,28 L82,38 L78,38 Z M84,23 L88,23 L88,38 L84,38 Z"/>
</vector>'''
# Keep foreground entirely within radius 33: shift small GSM accent inward.
foreground=foreground.replace('M72,32 L76,32 L76,38 L72,38 Z M78,28 L82,28 L82,38 L78,38 Z M84,23 L88,23 L88,38 L84,38 Z','M66,27 L69,27 L69,31 L66,31 Z M71,24 L74,24 L74,31 L71,31 Z M76,21 L79,21 L79,31 L76,31 Z')
(res/'drawable/launcher_foreground.xml').write_text(foreground)
(res/'drawable/launcher_background.xml').write_text('<shape xmlns:android="http://schemas.android.com/apk/res/android"><solid android:color="#075BAB"/></shape>')
(res/'mipmap-anydpi-v26/ic_launcher.xml').write_text('<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"><background android:drawable="@drawable/launcher_background"/><foreground android:drawable="@drawable/launcher_foreground"/></adaptive-icon>')
# Legacy vector has a filled tile; Android 8+ uses the adaptive resources above.
legacy=foreground.replace('<path ', '<path android:fillColor="#075BAB" android:pathData="M0,0 L108,0 L108,108 L0,108 Z"/><path ',1)
(res/'mipmap-anydpi/ic_launcher.xml').write_text(legacy)
# Release signing with a permanent LARIN COLD key (never the runner's random debug key).
# The keystore path and passwords come from environment variables set by CI from
# GitHub Secrets. Without them a local release build falls back to the debug key,
# but CI refuses to build (see the workflow) and verifies the certificate afterwards.
gradle_file = root/'android/app/build.gradle.kts'
g = gradle_file.read_text()
if 'LARIN_KEYSTORE_PATH' not in g:
    debug_line = 'signingConfig = signingConfigs.getByName("debug")'
    assert g.count(debug_line) == 1, 'Flutter template changed: release signing line not found'
    signing_block = '''    signingConfigs {
        create("release") {
            val larinKeystore = System.getenv("LARIN_KEYSTORE_PATH")
            if (!larinKeystore.isNullOrBlank()) {
                storeFile = file(larinKeystore)
                storePassword = System.getenv("LARIN_KEYSTORE_PASSWORD")?.trim()
                keyAlias = System.getenv("LARIN_KEY_ALIAS")?.trim()
                keyPassword = System.getenv("LARIN_KEY_PASSWORD")?.trim()
            }
        }
    }

    buildTypes {'''
    assert g.count('    buildTypes {') == 1, 'Flutter template changed: buildTypes block not found'
    g = g.replace('    buildTypes {', signing_block, 1)
    g = g.replace(debug_line, 'signingConfig = if (System.getenv("LARIN_KEYSTORE_PATH").isNullOrBlank()) '
                  'signingConfigs.getByName("debug") else signingConfigs.getByName("release")', 1)
    gradle_file.write_text(g)
assert 'signingConfigs.getByName("release")' in gradle_file.read_text()
pub = root/'pubspec.yaml'
s = pub.read_text()
import re
pub.write_text(re.sub(r'^version:.*$', 'version: 1.5.0+150', s, flags=re.M))
assert any(e.get(ns+'name') == 'android.permission.RECEIVE_SMS' for e in m.findall('uses-permission'))
assert not any(e.get(ns+'name') == 'android.permission.READ_SMS' for e in m.findall('uses-permission'))
assert m.find("./application/receiver[@{0}name='.SmsReceiver']".format(ns)).get(ns+'permission') == 'android.permission.BROADCAST_SMS'
assert a.get(ns+'label') == 'LARIN GSM'
print('Android SMS receiver, permission, launcher icon and version configured')

(res/'drawable/notification_icon.xml').write_text('<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24"><path android:strokeColor="#FFFFFFFF" android:strokeWidth="2" android:strokeLineCap="round" android:fillColor="#00000000" android:pathData="M7,5 A9,9 0,1 0,17 5 M12,2 L12,12"/></vector>')
