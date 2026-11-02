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
a.set(ns+'label', 'Larin Cold Start')
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
# Native vector icon (1.5.2): power symbol + green snowflake from the LARIN COLD logo,
# six sharp rays with curved barbs. Everything stays inside the adaptive safe zone (radius 33).
res = android/'res'
for folder in ['drawable', 'mipmap-anydpi', 'mipmap-anydpi-v26']:
    (res/folder).mkdir(parents=True, exist_ok=True)
SNOW_ARM = 'M-1.3,-1.6 L-0.9,-5 C-2.2,-5.6 -3.4,-6.8 -4.3,-8.8 C-2.9,-8 -1.8,-7.4 -0.7,-7.2 L0,-11.5 L0.7,-7.2 C1.8,-7.4 2.9,-8 4.3,-8.8 C3.4,-6.8 2.2,-5.6 0.9,-5 L1.3,-1.6 Z'
snow_rays = ''.join(
    '<group android:rotation="%d"><path android:fillColor="#2FBF4F" android:strokeColor="#E8FFF0" '
    'android:strokeWidth="0.6" android:strokeLineJoin="round" android:pathData="%s"/></group>' % (angle, SNOW_ARM)
    for angle in range(0, 360, 60))
foreground = (
    '<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" '
    'android:viewportWidth="108" android:viewportHeight="108">'
    '<path android:strokeColor="#FFFFFF" android:strokeWidth="6" android:strokeLineCap="round" '
    'android:fillColor="#00000000" android:pathData="M43,37.3 A20,20 0,1 0,65 37.3 M54,31.3 L54,50.3"/>'
    '<path android:fillColor="#075BAB" android:pathData="M55.5,69.5 a14,14 0 1,0 28,0 a14,14 0 1,0 -28,0"/>'
    '<group android:translateX="69.5" android:translateY="69.5" android:scaleX="0.95" android:scaleY="0.95">'
    + snow_rays +
    '<path android:fillColor="#2FBF4F" android:strokeColor="#E8FFF0" android:strokeWidth="0.6" '
    'android:pathData="M-2.4,0 a2.4,2.4 0 1,0 4.8,0 a2.4,2.4 0 1,0 -4.8,0"/>'
    '</group></vector>')
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
# Только ARM: иначе на x86_64-устройстве нашлись бы библиотеки плагинов без libflutter.so.
g = gradle_file.read_text()
if 'abiFilters' not in g:
    anchor = '    defaultConfig {'
    assert g.count(anchor) == 1, 'Flutter template changed: defaultConfig not found'
    g = g.replace(anchor, anchor + '\n        ndk { abiFilters += listOf("armeabi-v7a", "arm64-v8a") }', 1)
    # Библиотеки плагинов для x86 иногда попадают в APK мимо abiFilters — исключаем явно.
    g = g.replace('android {', 'android {\n    packaging { jniLibs { excludes += listOf("lib/x86/**", "lib/x86_64/**") } }', 1)
    gradle_file.write_text(g)
assert 'abiFilters' in gradle_file.read_text()
import re
# Имя пакета в магазине (RuStore): короткое и постоянное. Пространство имён Kotlin
# (namespace) остаётся ru.larincold.larin_cold_gsm_control — пользователю оно не видно.
g = gradle_file.read_text()
g = re.sub(r'applicationId\s*=\s*"[^"]+"', 'applicationId = "ru.larincold.start"', g)
gradle_file.write_text(g)
assert 'applicationId = "ru.larincold.start"' in gradle_file.read_text()
pub = root/'pubspec.yaml'
s = pub.read_text()
import re
pub.write_text(re.sub(r'^version:.*$', 'version: 1.8.5+185', s, flags=re.M))
assert any(e.get(ns+'name') == 'android.permission.RECEIVE_SMS' for e in m.findall('uses-permission'))
assert not any(e.get(ns+'name') == 'android.permission.READ_SMS' for e in m.findall('uses-permission'))
assert m.find("./application/receiver[@{0}name='.SmsReceiver']".format(ns)).get(ns+'permission') == 'android.permission.BROADCAST_SMS'
assert a.get(ns+'label') == 'Larin Cold Start'

# Заставка 1.6.0: значок приложения (питание + снежинка) на светлом фоне логотипа.
# Android 12+: системная заставка с анимацией — снежинка проворачивается и
# «раскрывается», дуга питания прорисовывается (до 1 с). До Android 12 — статичная.
splash_rays = snow_rays
splash_icon = (
    '<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="288dp" android:height="288dp" '
    'android:viewportWidth="108" android:viewportHeight="108">'
    '<group android:pivotX="54" android:pivotY="54" android:scaleX="1" android:scaleY="1">'
    '<path android:fillColor="#075BAB" android:pathData="M20.25,54 a33.75,33.75 0 1,0 67.5,0 a33.75,33.75 0 1,0 -67.5,0"/>'
    '<path android:name="power" android:strokeColor="#FFFFFF" android:strokeWidth="6" android:strokeLineCap="round" '
    'android:fillColor="#00000000" android:trimPathEnd="1" android:pathData="M43,37.3 A20,20 0,1 0,65 37.3 M54,31.3 L54,50.3"/>'
    '<path android:fillColor="#075BAB" android:pathData="M55.5,69.5 a14,14 0 1,0 28,0 a14,14 0 1,0 -28,0"/>'
    '<group android:translateX="69.5" android:translateY="69.5" android:scaleX="0.95" android:scaleY="0.95">'
    '<group android:name="snow">'
    + splash_rays +
    '<path android:fillColor="#2FBF4F" android:strokeColor="#E8FFF0" android:strokeWidth="0.6" '
    'android:pathData="M-2.4,0 a2.4,2.4 0 1,0 4.8,0 a2.4,2.4 0 1,0 -4.8,0"/>'
    '</group></group></group></vector>')
(res/'drawable/splash_icon.xml').write_text(splash_icon)
(res/'animator').mkdir(parents=True, exist_ok=True)
(res/'animator/splash_snow.xml').write_text(
    '<set xmlns:android="http://schemas.android.com/apk/res/android">'
    '<objectAnimator android:propertyName="rotation" android:valueFrom="-120" android:valueTo="0" android:valueType="floatType" '
    'android:duration="900" android:interpolator="@android:interpolator/decelerate_cubic"/>'
    '<objectAnimator android:propertyName="scaleX" android:valueFrom="0.2" android:valueTo="1" android:valueType="floatType" '
    'android:duration="700" android:interpolator="@android:anim/overshoot_interpolator"/>'
    '<objectAnimator android:propertyName="scaleY" android:valueFrom="0.2" android:valueTo="1" android:valueType="floatType" '
    'android:duration="700" android:interpolator="@android:anim/overshoot_interpolator"/>'
    '</set>')
(res/'animator/splash_power.xml').write_text(
    '<objectAnimator xmlns:android="http://schemas.android.com/apk/res/android" android:propertyName="trimPathEnd" '
    'android:valueFrom="0" android:valueTo="1" android:valueType="floatType" android:duration="600" '
    'android:interpolator="@android:interpolator/fast_out_slow_in"/>')
(res/'drawable/splash_animated.xml').write_text(
    '<animated-vector xmlns:android="http://schemas.android.com/apk/res/android" android:drawable="@drawable/splash_icon">'
    '<target android:name="snow" android:animation="@animator/splash_snow"/>'
    '<target android:name="power" android:animation="@animator/splash_power"/>'
    '</animated-vector>')
def launch_bg(color):
    return ('<layer-list xmlns:android="http://schemas.android.com/apk/res/android">'
            '<item><shape><solid android:color="%s"/></shape></item>'
            '<item android:gravity="center" android:width="144dp" android:height="144dp" android:drawable="@drawable/splash_icon"/>'
            '</layer-list>' % color)
# Светлая заставка днём, тёмная — если в телефоне включена тёмная тема.
for folder, color in [('drawable', '#F3F9FF'), ('drawable-v21', '#F3F9FF'),
                      ('drawable-night', '#061A38'), ('drawable-night-v21', '#061A38')]:
    (res/folder).mkdir(parents=True, exist_ok=True)
    (res/folder/'launch_background.xml').write_text(launch_bg(color))
    (res/folder/'normal_background.xml').write_text(
        '<shape xmlns:android="http://schemas.android.com/apk/res/android"><solid android:color="%s"/></shape>' % color)
def styles_v31(color):
    return ('<?xml version="1.0" encoding="utf-8"?><resources>'
    '<style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">'
    '<item name="android:forceDarkAllowed">false</item>'
    '<item name="android:windowFullscreen">false</item>'
    '<item name="android:windowDrawsSystemBarBackgrounds">false</item>'
    '<item name="android:windowSplashScreenBackground">%s</item>'
    '<item name="android:windowSplashScreenAnimatedIcon">@drawable/splash_animated</item>'
    '<item name="android:windowSplashScreenAnimationDuration">900</item>'
    '<item name="android:windowBackground">@drawable/launch_background</item>'
    '</style>'
    '<style name="NormalTheme" parent="@android:style/Theme.Light.NoTitleBar">'
    '<item name="android:windowBackground">@drawable/normal_background</item>'
    '</style></resources>') % color
for folder, color in [('values-v31', '#F3F9FF'), ('values-night-v31', '#061A38')]:
    (res/folder).mkdir(parents=True, exist_ok=True)
    (res/folder/'styles.xml').write_text(styles_v31(color))
print('Android SMS receiver, permission, launcher icon, splash and version configured')

(res/'drawable/notification_icon.xml').write_text('<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24"><path android:strokeColor="#FFFFFFFF" android:strokeWidth="2" android:strokeLineCap="round" android:fillColor="#00000000" android:pathData="M7,5 A9,9 0,1 0,17 5 M12,2 L12,12"/></vector>')
