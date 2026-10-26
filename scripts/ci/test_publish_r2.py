#!/usr/bin/env python3
"""Tests for publish_r2.py against an in-memory bucket (no network):
    python3 scripts/ci/test_publish_r2.py
Version order, channels, the manifest, rotation (3 releases + 1 dev build),
what gets deleted (only stale version folders under the prefix), dry runs.
"""
import io
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import publish_r2 as p  # noqa: E402


class FakeS3:
    """put_object / get_object / list_objects_v2 (paginated) / delete_objects."""

    def __init__(self, page=2):
        self.objects = {}  # key -> (bytes, meta)
        self.page = page
        self.puts = 0

    def put_object(self, Bucket, Key, Body, ContentType, CacheControl):
        data = Body if isinstance(Body, bytes) else Body.read()
        self.objects[Key] = (data, {"ContentType": ContentType, "CacheControl": CacheControl})
        self.puts += 1

    def get_object(self, Bucket, Key):
        if Key not in self.objects:
            raise KeyError(Key)
        return {"Body": io.BytesIO(self.objects[Key][0])}

    def list_objects_v2(self, Bucket, Prefix, ContinuationToken=None):
        keys = sorted(k for k in self.objects if k.startswith(Prefix))
        start = int(ContinuationToken or 0)
        chunk = keys[start:start + self.page]
        r = {"Contents": [{"Key": k} for k in chunk], "IsTruncated": start + self.page < len(keys)}
        if r["IsTruncated"]:
            r["NextContinuationToken"] = str(start + self.page)
        return r

    def delete_objects(self, Bucket, Delete):
        for o in Delete["Objects"]:
            self.objects.pop(o["Key"], None)


def make_release(tmp, version):
    d = os.path.join(tmp, version)
    os.makedirs(d, exist_ok=True)
    names = [f"rayzr-editor-{version}-macos.dmg", f"rayzr-editor-{version}-windows.zip",
             f"rayzr-editor-{version}-linux-x86_64.AppImage", f"rayzr-editor-{version}-linux-amd64.deb",
             f"rayzr-editor-{version}-linux.tar.gz", "SHA256SUMS.txt"]
    for n in names:
        with open(os.path.join(d, n), "wb") as f:
            f.write(f"{version}:{n}".encode())
    return d


class VersionTests(unittest.TestCase):
    def test_order(self):
        vs = ["0.1.0", "0.10.0", "0.2.0", "0.2.0-beta.1", "0.2.0-beta.10", "0.2.0-beta.2", "1.0.0", "0.2.0-alpha"]
        got = sorted(vs, key=p.parse_version)
        self.assertEqual(got, ["0.1.0", "0.2.0-alpha", "0.2.0-beta.1", "0.2.0-beta.2", "0.2.0-beta.10", "0.2.0", "0.10.0", "1.0.0"])

    def test_invalid(self):
        for bad in ["1.0", "latest", "1.0.0.0", ""]:
            with self.assertRaises(ValueError):
                p.parse_version(bad)

    def test_channels(self):
        self.assertEqual(p.channel_of("0.1.0-dev.254"), "dev")
        self.assertEqual(p.channel_of("0.1.0"), "stable")
        self.assertEqual(p.channel_of("0.2.0-beta.1"), "stable")
        self.assertEqual(p.folder_of("0.1.0-dev.3"), "dev/v0.1.0-dev.3/")
        self.assertEqual(p.folder_of("0.1.0"), "releases/v0.1.0/")

    def test_describe(self):
        self.assertEqual(p.describe("rayzr-editor-0.1.0-macos.dmg")["os"], "macos")
        self.assertEqual(p.describe("rayzr-editor-0.1.0-windows.zip")["os"], "windows")
        self.assertEqual(p.describe("rayzr-editor-0.1.0-linux-x86_64.AppImage")["kind"], "appimage")
        self.assertEqual(p.describe("rayzr-editor-0.1.0-linux-amd64.deb")["kind"], "deb")
        self.assertEqual(p.describe("rayzr-editor-0.1.0-linux.tar.gz")["kind"], "tar.gz")
        self.assertEqual(p.describe("SHA256SUMS.txt")["kind"], "checksums")


class PublishTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.s3 = FakeS3()
        self.bucket = p.Bucket(self.s3, "b")
        self.log = []

    def publish(self, v, **kw):
        return p.publish(self.bucket, v, make_release(self.tmp, v), date=f"2026-01-01T00:00:{len(self.log):02d}+00:00",
                         log=self.log.append, **kw)

    def folders(self, prefix=""):
        return sorted({"/".join(k[len(prefix):].split("/")[:2]) for k in self.s3.objects if k.startswith(prefix) and "/" in k[len(prefix):]})

    def manifest(self, prefix=""):
        return json.loads(self.s3.objects[prefix + "manifest.json"][0])

    def test_first_release(self):
        m = self.publish("0.1.0", commit="abc")
        self.assertEqual(m["latest"], "0.1.0")
        self.assertEqual(len(m["stable"]), 1)
        e = m["stable"][0]
        self.assertEqual(e["tag"], "v0.1.0")
        self.assertEqual(e["commit"], "abc")
        self.assertFalse(e["prerelease"])
        self.assertEqual(len(e["files"]), 6)
        dmg = next(f for f in e["files"] if f["kind"] == "dmg")
        self.assertEqual(dmg["url"], "https://downloads.rayzr.app/releases/v0.1.0/rayzr-editor-0.1.0-macos.dmg")
        self.assertEqual(len(dmg["sha256"]), 64)
        self.assertEqual(self.manifest(), m)
        meta = self.s3.objects["releases/v0.1.0/rayzr-editor-0.1.0-macos.dmg"][1]
        self.assertIn("immutable", meta["CacheControl"])
        self.assertEqual(self.s3.objects["manifest.json"][1]["CacheControl"], "public, max-age=60")

    def test_keeps_newest_three_releases(self):
        for v in ["0.1.0", "0.2.0", "0.3.0-beta.1", "0.3.0", "0.2.1"]:
            self.publish(v)
        m = self.manifest()
        self.assertEqual([e["version"] for e in m["stable"]], ["0.3.0", "0.3.0-beta.1", "0.2.1"])
        self.assertEqual(m["latest"], "0.3.0")
        self.assertEqual(self.folders(), ["releases/v0.2.1", "releases/v0.3.0", "releases/v0.3.0-beta.1"])

    def test_older_release_than_kept_is_dropped_immediately(self):
        for v in ["0.4.0", "0.5.0", "0.6.0"]:
            self.publish(v)
        self.publish("0.1.0")  # (an old hotfix: not among the newest three)
        self.assertEqual([e["version"] for e in self.manifest()["stable"]], ["0.6.0", "0.5.0", "0.4.0"])
        self.assertNotIn("releases/v0.1.0", self.folders())

    def test_dev_build_replaces_previous(self):
        self.publish("0.1.0")
        self.publish("0.2.0-dev.10")
        self.publish("0.2.0-dev.11")
        m = self.manifest()
        self.assertEqual(m["dev"]["version"], "0.2.0-dev.11")
        self.assertEqual(m["dev"]["channel"], "dev")
        self.assertEqual(m["latest"], "0.1.0")
        self.assertEqual(self.folders(), ["dev/v0.2.0-dev.11", "releases/v0.1.0"])

    def test_latest_prefers_full_release(self):
        self.publish("0.1.0")
        m = self.publish("0.2.0-beta.1")
        self.assertEqual([e["version"] for e in m["stable"]], ["0.2.0-beta.1", "0.1.0"])
        self.assertEqual(m["latest"], "0.1.0")
        self.setUp()
        self.assertEqual(self.publish("0.2.0-beta.1")["latest"], "0.2.0-beta.1")  # (nothing else)

    def test_dev_only(self):
        m = self.publish("0.1.0-dev.5")
        self.assertIsNone(m["latest"])
        self.assertEqual(m["stable"], [])

    def test_republish_same_version_replaces(self):
        self.publish("0.1.0")
        self.publish("0.1.0")
        self.assertEqual(len(self.manifest()["stable"]), 1)

    def test_only_stale_version_folders_are_deleted(self):
        self.s3.objects["other/keep.txt"] = (b"x", {})
        self.s3.objects["test/hello.txt"] = (b"x", {})
        self.s3.objects["releases/notes.txt"] = (b"x", {})  # (not a version folder)
        for v in ["0.1.0", "0.2.0", "0.3.0", "0.4.0"]:
            self.publish(v)
        for k in ["other/keep.txt", "test/hello.txt", "releases/notes.txt"]:
            self.assertIn(k, self.s3.objects)
        self.assertNotIn("releases/v0.1.0", self.folders())

    def test_prefix_isolates(self):
        self.publish("9.0.0")  # production
        for v in ["0.1.0", "0.2.0", "0.3.0", "0.4.0"]:
            self.publish(v, prefix="ci-test/")
        self.assertIn("releases/v9.0.0", self.folders())
        self.assertEqual(self.manifest()["latest"], "9.0.0")
        self.assertEqual(self.manifest("ci-test/")["latest"], "0.4.0")
        url = self.manifest("ci-test/")["stable"][0]["files"][0]["url"]
        self.assertTrue(url.startswith("https://downloads.rayzr.app/ci-test/releases/v0.4.0/"), url)

    def test_keep_one(self):
        self.publish("0.1.0", keep=1)
        self.publish("0.2.0", keep=1)
        self.assertEqual(self.folders(), ["releases/v0.2.0"])

    def test_dry_run_changes_nothing(self):
        self.publish("0.1.0")
        before = dict(self.s3.objects)
        self.publish("0.2.0", dry_run=True)
        self.assertEqual(self.s3.objects, before)
        self.assertTrue(any("upload releases/v0.2.0/" in l for l in self.log))

    def test_manifest_written_before_deleting(self):
        order = []
        real_put, real_del = self.s3.put_object, self.s3.delete_objects
        self.s3.put_object = lambda **kw: (order.append(("put", kw["Key"])), real_put(**kw))
        self.s3.delete_objects = lambda **kw: (order.append(("delete", len(kw["Delete"]["Objects"]))), real_del(**kw))
        for v in ["0.1.0", "0.2.0", "0.3.0", "0.4.0"]:
            self.publish(v)
        i_manifest = max(i for i, o in enumerate(order) if o == ("put", "manifest.json"))
        i_delete = max(i for i, o in enumerate(order) if o[0] == "delete")
        self.assertLess(i_manifest, i_delete)

    def test_purges_manifest_and_deleted_files(self):
        purged = []
        for v in ["0.1.0", "0.2.0", "0.3.0"]:
            self.publish(v, purge=purged.extend)
        self.assertEqual(purged, ["https://downloads.rayzr.app/manifest.json"] * 3)
        purged.clear()
        self.publish("0.4.0", purge=purged.extend)
        self.assertEqual(purged[0], "https://downloads.rayzr.app/manifest.json")
        self.assertEqual(sorted(purged[1:]), sorted(f"https://downloads.rayzr.app/releases/v0.1.0/{n}" for n in os.listdir(os.path.join(self.tmp, "0.1.0"))))
        purged.clear()
        self.publish("0.5.0", purge=purged.extend, dry_run=True)
        self.assertEqual(purged, [])

    def test_empty_dir_fails(self):
        d = os.path.join(self.tmp, "empty")
        os.makedirs(d, exist_ok=True)
        with self.assertRaises(SystemExit):
            p.publish(self.bucket, "0.1.0", d, log=self.log.append)


if __name__ == "__main__":
    unittest.main()
