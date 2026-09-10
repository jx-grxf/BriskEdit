import pathlib, subprocess, tempfile, unittest, sys

ROOT = pathlib.Path(__file__).parents[1]

class ReleaseScriptTests(unittest.TestCase):
    def build(self, version):
        return tuple(map(int, subprocess.check_output([ROOT / "script/release_build_number.sh", version], text=True).strip().split(".")))

    def test_build_numbers_follow_release_order(self):
        self.assertLess(self.build("0.5.2-beta.1"), self.build("0.5.2"))
        self.assertLess(self.build("0.5.2"), self.build("0.5.3-beta.1"))

    def test_merge_keeps_items_from_both_feeds(self):
        template = '<?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>{}<sparkle:version>{}</sparkle:version></item></channel></rss>'
        with tempfile.TemporaryDirectory() as d:
            d = pathlib.Path(d); a=d/'a.xml'; b=d/'b.xml'; out=d/'out.xml'
            a.write_text(template.format('', 100)); b.write_text(template.format('<sparkle:channel>beta</sparkle:channel>', 200))
            subprocess.check_call([ROOT/'script/merge_appcasts.py', a, b, out])
            text=out.read_text(); self.assertIn('100', text); self.assertIn('200', text)

    def test_build_mapping_respects_bundle_component_limits(self):
        value = self.build("0.6.0")
        self.assertGreater(value, (19, 0, 0))
        self.assertEqual(value, (1006, 0, 99))
        self.assertLessEqual(value[0], 9999)
        self.assertLessEqual(value[1], 99)
        self.assertLessEqual(value[2], 99)

    def test_invalid_beta_ordinal_is_rejected(self):
        result = subprocess.run([ROOT / "script/release_build_number.sh", "0.6.0-beta.99"], capture_output=True)
        self.assertNotEqual(result.returncode, 0)

    def test_published_releases_are_immutable(self):
        from script.release_policy import validate
        existing = [{"tag_name": "v0.6.0", "draft": False, "prerelease": False}]
        with self.assertRaises(ValueError):
            validate("0.6.0", existing)

    def test_old_stable_does_not_replace_latest(self):
        from script.release_policy import validate
        latest = [{"tag_name": "v0.6.0", "draft": False, "prerelease": False}]
        with self.assertRaises(ValueError):
            validate("0.5.3", latest)
        validate("0.6.1-beta.1", latest)
        validate("0.6.1", latest)

    def test_newer_beta_does_not_block_stable_maintenance(self):
        from script.release_policy import validate
        releases = [{"tag_name": "v0.7.0-beta.1", "draft": False, "prerelease": True}]
        validate("0.6.1", releases)
        with self.assertRaises(ValueError):
            validate("0.7.0-beta.1", releases)

    def test_combined_feed_requires_new_build_and_versioned_enclosure(self):
        import base64
        import contextlib
        import io
        from script.verify_composite_appcast import validate
        signature = base64.b64encode(bytes(64)).decode()
        xml = f"""<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
        <sparkle:version>1006.0.99</sparkle:version><sparkle:shortVersionString>0.6.0</sparkle:shortVersionString>
        <enclosure url="https://github.com/jx-grxf/BriskEdit/releases/download/v0.6.0/BriskEdit-0.6.0.zip" length="1" sparkle:edSignature="{signature}"/>
        </item></channel></rss>"""
        with tempfile.TemporaryDirectory() as directory:
            directory = pathlib.Path(directory)
            feed = directory / "feed.xml"
            feed.write_text(xml)
            with contextlib.redirect_stdout(io.StringIO()):
                validate(feed, "1006.0.99", "jx-grxf/BriskEdit", directory / "items")
                with self.assertRaises(ValueError):
                    validate(feed, "1007.0.99", "jx-grxf/BriskEdit", directory / "items")
                with self.assertRaises(ValueError):
                    validate(feed, "1006.0.99", "wrong/repo", directory / "items")

    def artifact(self, field, **env):
        import os
        return subprocess.check_output([ROOT / "script/release_artifacts.sh", field], text=True, env={**os.environ, **env}).strip()

    def test_nightly_artifacts_never_collide_with_release_artifacts(self):
        stable = dict(BRISKEDIT_UPDATE_CHANNEL="stable", BRISKEDIT_VERSION="0.6.1", BRISKEDIT_BUILD="1006.1.99")
        nightly = dict(BRISKEDIT_UPDATE_CHANNEL="nightly", BRISKEDIT_VERSION="0.6.1-nightly.211", BRISKEDIT_BUILD="211")
        self.assertEqual(self.artifact("bundle-id", **stable), "com.johannesgrof.briskedit")
        self.assertEqual(self.artifact("bundle-id", **nightly), "com.johannesgrof.briskedit.nightly")
        self.assertEqual(self.artifact("app-bundle", **nightly), "BriskEdit Nightly.app")
        self.assertEqual(self.artifact("dmg", **stable), "BriskEdit-0.6.1.dmg")
        self.assertEqual(self.artifact("dmg", **nightly), "BriskEdit-Nightly.dmg")
        self.assertEqual(self.artifact("zip", **nightly), "BriskEdit-Nightly-211.zip")
        result = subprocess.run([ROOT / "script/release_artifacts.sh", "dmg"], capture_output=True, env={"BRISKEDIT_UPDATE_CHANNEL": "canary", "PATH": "/usr/bin:/bin"})
        self.assertNotEqual(result.returncode, 0)

    def test_nightly_feed_decision_only_moves_forward(self):
        from script.nightly_feed_decision import decide
        template = '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><sparkle:channel>{}</sparkle:channel><sparkle:version>{}</sparkle:version></item></channel></rss>'
        with tempfile.TemporaryDirectory() as directory:
            feed = pathlib.Path(directory) / "appcast.xml"
            self.assertEqual(decide(feed, "211"), "publish")
            feed.write_text(template.format("nightly", 211))
            self.assertEqual(decide(feed, "212"), "publish")
            self.assertTrue(decide(feed, "211").startswith("skip"))
            self.assertEqual(decide(feed, "211", force=True), "publish")
            self.assertTrue(decide(feed, "210", force=True).startswith("skip"))
            feed.write_text(template.format("beta", 211))
            with self.assertRaises(ValueError):
                decide(feed, "212")
            with self.assertRaises(ValueError):
                decide(feed, "1006.1.99")

    def metadata(self, **env):
        import os
        return subprocess.run([ROOT / "script/verify_release_metadata.sh"], capture_output=True, text=True, env={**os.environ, **env})

    def test_nightly_metadata_requires_project_version_and_integer_build(self):
        version = subprocess.check_output(["awk", "-F\"", "/MARKETING_VERSION:/ { print $2; exit }", ROOT / "project.yml"], text=True).strip()
        ok = self.metadata(BRISKEDIT_UPDATE_CHANNEL="nightly", BRISKEDIT_VERSION=f"{version}-nightly.211", BRISKEDIT_BUILD="211", BRISKEDIT_RELEASE_TAG="nightly")
        self.assertEqual(ok.returncode, 0, ok.stderr)
        for env in (
            dict(BRISKEDIT_VERSION=version, BRISKEDIT_BUILD="211"),
            dict(BRISKEDIT_VERSION=f"{version}-nightly.211", BRISKEDIT_BUILD="1006.1.99"),
            dict(BRISKEDIT_VERSION=f"{version}-nightly.211", BRISKEDIT_BUILD="211", BRISKEDIT_RELEASE_TAG=f"v{version}"),
        ):
            self.assertNotEqual(self.metadata(BRISKEDIT_UPDATE_CHANNEL="nightly", **env).returncode, 0, env)

    def test_nightly_identity_uses_commit_count_and_project_version(self):
        output = subprocess.check_output([ROOT / "script/nightly_identity.sh", "HEAD"], text=True, cwd=ROOT)
        values = dict(line.split("=", 1) for line in output.strip().splitlines())
        count = subprocess.check_output(["git", "rev-list", "--count", "HEAD"], text=True, cwd=ROOT).strip()
        self.assertEqual(values["build"], count)
        self.assertRegex(values["version"], rf"^\d+\.\d+\.\d+(-beta\.\d+)?-nightly\.{count}$")
        self.assertEqual(len(values["short_commit"]), 7)

    @unittest.skipUnless(sys.platform == "darwin", "Swift verifier requires Xcode on macOS")
    def test_verifier_does_not_mix_fields_between_items(self):
        xml = '''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        <item><sparkle:version>100</sparkle:version><sparkle:shortVersionString>1.0</sparkle:shortVersionString><enclosure url="https://example/one.zip" length="1" sparkle:edSignature="sig"/></item>
        <item><sparkle:version>200</sparkle:version><sparkle:shortVersionString>2.0</sparkle:shortVersionString><enclosure url="https://example/two.zip" length="1" sparkle:edSignature="sig"/></item>
        </channel></rss>'''
        with tempfile.TemporaryDirectory() as d:
            path = pathlib.Path(d) / 'appcast.xml'; path.write_text(xml)
            result = subprocess.run([ROOT/'script/verify_appcast.swift', path, 'https://example/one.zip', 'stable', '2.0', '200'], text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)

if __name__ == "__main__": unittest.main()
