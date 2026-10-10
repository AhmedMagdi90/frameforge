import importlib.util
import plistlib
from pathlib import Path
import shutil
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('install_platforms', Path(__file__).with_name('install_platforms.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PlatformInstallTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        shutil.copytree(Path(__file__).resolve().parents[1] / 'platform', self.root / 'platform')
        app = self.root / 'android/app'
        app.mkdir(parents=True)
        (app / 'build.gradle.kts').write_text('android { defaultConfig { minSdk = flutter.minSdkVersion } }\n')
        manifest = app / 'src/main/AndroidManifest.xml'
        manifest.parent.mkdir(parents=True)
        manifest.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application android:label="frameforge"><activity android:name=".MainActivity" android:launchMode="singleTask" android:taskAffinity="" /></application></manifest>')
        runner = self.root / 'ios/Runner'
        runner.mkdir(parents=True)
        with (runner / 'Info.plist').open('wb') as handle:
            plistlib.dump({'CFBundleName': 'frameforge', 'KeepMe': True,
                'UIApplicationSceneManifest': {'UIApplicationSupportsMultipleScenes': False}}, handle)
        pbx = self.root / 'ios/Runner.xcodeproj/project.pbxproj'
        pbx.parent.mkdir()
        pbx.write_text('IPHONEOS_DEPLOYMENT_TARGET = 13.0;')

    def tearDown(self):
        self.temporary.cleanup()

    def test_install_is_repeatable_and_registers_native_sources(self):
        module.install(self.root)
        first = (self.root / 'android/app/build.gradle.kts').read_text()
        module.install(self.root)
        self.assertEqual(first, (self.root / 'android/app/build.gradle.kts').read_text())
        self.assertEqual(first.count('FRAMEFORGE_MEDIA3_START'), 1)
        self.assertIn('minSdk = 26', first)
        manifest = (self.root / 'android/app/src/main/AndroidManifest.xml').read_text()
        self.assertEqual(manifest.count('com.linusu.flutter_web_auth_2.CallbackActivity'), 1)
        self.assertEqual(manifest.count('android.permission.INTERNET'), 1)
        self.assertIn('android:scheme="frameforge-ai"', manifest)
        self.assertIn('android:launchMode="singleTop"', manifest)
        self.assertNotIn('taskAffinity', manifest)
        self.assertTrue((self.root / 'android/app/src/main/kotlin/dev/frameforge/frameforge/VideoEngine.kt').is_file())
        delegate = (self.root / 'ios/Runner/AppDelegate.swift').read_text()
        self.assertIn('final class VideoEngine', delegate)
        self.assertEqual(delegate.count('@main'), 1)
        with (self.root / 'ios/Runner/Info.plist').open('rb') as handle:
            info = plistlib.load(handle)
        self.assertEqual(info['CFBundleDisplayName'], 'FrameForge')
        self.assertTrue(info['KeepMe'])
        self.assertNotIn('UIApplicationSceneManifest', info)
        self.assertEqual(sum('frameforge-ai' in value['CFBundleURLSchemes'] for value in info['CFBundleURLTypes']), 1)
        self.assertIn("platform :ios, '15.0'", (self.root / 'ios/Podfile').read_text())
        self.assertIn('15.0', (self.root / 'ios/Runner.xcodeproj/project.pbxproj').read_text())

    def test_existing_podfile_settings_are_preserved(self):
        podfile = self.root / 'ios/Podfile'
        podfile.write_text("# platform :ios, '13.0'\n# Custom setting\n")
        module.install(self.root)
        self.assertIn("platform :ios, '15.0'", podfile.read_text())
        self.assertIn('# Custom setting', podfile.read_text())


if __name__ == '__main__':
    unittest.main()
