#!/usr/bin/env python3
"""Publishes a release's packages to the website's downloads (Cloudflare R2,
served at https://downloads.rayzr.app) and keeps only the newest ones.

    python3 scripts/ci/publish_r2.py --version 0.1.0 --dir release \\
        [--commit <sha>] [--keep 3] [--prefix ""] [--dry-run]

Credentials come from the environment (repository secrets in CI):
R2_ENDPOINT, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY (and R2_BUCKET,
default rayzr-downloads). With CLOUDFLARE_API_TOKEN (and CLOUDFLARE_ZONE_ID,
default rayzr.app's zone) the CDN cache is purged for the new manifest and
every deleted file - otherwise downloads.rayzr.app keeps serving cached
copies of deleted versions (they are cached for a year: versioned paths).

Layout in the bucket (under --prefix, "" in production):

    releases/v<version>/<file>    a release (tags without -dev.: 0.1.0, 0.2.0-beta.1)
    dev/v<version>/<file>         the latest dev build (<VERSION>-dev.<n>)
    manifest.json                 what the site lists (schema below)

A release joins the newest --keep releases (semver order); a dev build
replaces the previous one. manifest.json is written first, then every
version folder it no longer lists is deleted - so the site never links to a
deleted file. The release workflow (.github/workflows/release.yml) runs this
after the GitHub Release; the website (rayzr_website) reads manifest.json.

manifest.json:
    {"schema": 1, "updated": ISO-8601, "base_url": "https://downloads.rayzr.app",
     "latest": "0.2.0" | null   the newest full release (a prerelease only if
                                there are no others),
     "stable": [entry, ...]   newest first, at most --keep,
     "dev": entry | null}
    entry: {"version", "tag", "channel": "stable" | "dev", "prerelease": bool,
            "date", "commit", "notes_url",
            "files": [{"name", "os", "arch", "kind", "label", "size", "sha256", "url"}]}
"""
import argparse
import datetime
import hashlib
import json
import mimetypes
import os
import re
import sys

REPO = "https://github.com/bcrowe306/rayzr"
DEFAULT_BUCKET = "rayzr-downloads"
DEFAULT_BASE_URL = "https://downloads.rayzr.app"
DEFAULT_ZONE_ID = "003ff4bb3641f16d5f54ebb7b441d7b8"  # rayzr.app


# --- versions ---------------------------------------------------------------------------

SEMVER = re.compile(r"^v?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$")


def parse_version(v):
    """'0.2.0-beta.1' -> a sort key (prereleases sort below their release)."""
    m = SEMVER.match(v)
    if not m:
        raise ValueError(f"not a version: {v!r}")
    major, minor, patch, pre = int(m.group(1)), int(m.group(2)), int(m.group(3)), m.group(4)
    if pre is None:
        return (major, minor, patch, 1, ())
    ids = tuple((0, int(p), "") if p.isdigit() else (1, 0, p) for p in pre.split("."))
    return (major, minor, patch, 0, ids)


def channel_of(version):
    return "dev" if re.search(r"-dev\.\d+$", version) else "stable"


def folder_of(version):
    return f"{'dev' if channel_of(version) == 'dev' else 'releases'}/v{version}/"


# --- files ------------------------------------------------------------------------------

def describe(name):
    """What a package is, from its name (scripts in release.yml name them)."""
    n = name.lower()
    if n == "sha256sums.txt":
        return {"os": "any", "arch": "any", "kind": "checksums", "label": "SHA-256 checksums"}
    if n.endswith(".dmg"):
        return {"os": "macos", "arch": "arm64", "kind": "dmg", "label": "macOS (Apple silicon)"}
    if "windows" in n and n.endswith(".zip"):
        return {"os": "windows", "arch": "x64", "kind": "zip", "label": "Windows (x64)"}
    if n.endswith(".appimage"):
        return {"os": "linux", "arch": "x64", "kind": "appimage", "label": "Linux AppImage (x64)"}
    if n.endswith(".deb"):
        return {"os": "linux", "arch": "x64", "kind": "deb", "label": "Debian / Ubuntu (x64)"}
    if "linux" in n and n.endswith(".tar.gz"):
        return {"os": "linux", "arch": "x64", "kind": "tar.gz", "label": "Linux tarball (x64)"}
    return {"os": "any", "arch": "any", "kind": "file", "label": name}


def content_type(name):
    if name.endswith(".dmg"):
        return "application/x-apple-diskimage"
    if name.lower().endswith(".appimage"):
        return "application/octet-stream"
    if name.endswith(".deb"):
        return "application/vnd.debian.binary-package"
    if name.endswith(".tar.gz"):
        return "application/gzip"
    return mimetypes.guess_type(name)[0] or "application/octet-stream"


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def collect_files(directory):
    names = sorted(n for n in os.listdir(directory) if os.path.isfile(os.path.join(directory, n)) and not n.startswith("."))
    if not names:
        raise SystemExit(f"publish_r2: no files in {directory}")
    return names


# --- the manifest -----------------------------------------------------------------------

def empty_manifest(base_url):
    return {"schema": 1, "updated": None, "base_url": base_url, "latest": None, "stable": [], "dev": None}


def updated_manifest(manifest, entry, keep):
    """The manifest with `entry` added: releases sorted newest first and cut to
    `keep`; a dev build replaces the previous one."""
    m = dict(manifest)
    m.setdefault("stable", [])
    if entry["channel"] == "dev":
        m["dev"] = entry
    else:
        stable = [e for e in m.get("stable", []) if e["version"] != entry["version"]] + [entry]
        stable.sort(key=lambda e: parse_version(e["version"]), reverse=True)
        m["stable"] = stable[:keep]
    # (The default download / docs: the newest full release; a beta only
    # when there is nothing else.)
    full = [e for e in m["stable"] if not e["prerelease"]]
    m["latest"] = (full or m["stable"])[0]["version"] if m["stable"] else None
    m["updated"] = entry["date"]
    return m


def kept_folders(manifest):
    out = {folder_of(e["version"]) for e in manifest.get("stable", [])}
    if manifest.get("dev"):
        out.add(folder_of(manifest["dev"]["version"]))
    return out


def stale_keys(keys, manifest, prefix):
    """Objects under releases/ or dev/ whose version folder the manifest no
    longer lists (nothing else is ever deleted)."""
    keep = kept_folders(manifest)
    out = []
    for k in keys:
        rel = k[len(prefix):] if k.startswith(prefix) else None
        if rel is None:
            continue
        m = re.match(r"^((?:releases|dev)/v[^/]+/)", rel)
        if m and m.group(1) not in keep:
            out.append(k)
    return out


# --- the bucket -------------------------------------------------------------------------

class Bucket:
    """The few S3 calls we need (boto3 client; tests pass a fake)."""

    def __init__(self, client, name):
        self.c = client
        self.name = name

    def get_json(self, key):
        try:
            obj = self.c.get_object(Bucket=self.name, Key=key)
        except Exception as e:  # (botocore's NoSuchKey, or a fake's KeyError)
            if "NoSuchKey" in type(e).__name__ or "NoSuchKey" in str(e) or isinstance(e, KeyError):
                return None
            raise
        return json.loads(obj["Body"].read())

    def put_file(self, key, path, ctype, cache):
        with open(path, "rb") as f:
            self.c.put_object(Bucket=self.name, Key=key, Body=f, ContentType=ctype, CacheControl=cache)

    def put_json(self, key, data, cache):
        body = (json.dumps(data, indent=2) + "\n").encode()
        self.c.put_object(Bucket=self.name, Key=key, Body=body, ContentType="application/json", CacheControl=cache)

    def keys(self, prefix):
        out, token = [], None
        while True:
            kw = {"Bucket": self.name, "Prefix": prefix}
            if token:
                kw["ContinuationToken"] = token
            r = self.c.list_objects_v2(**kw)
            out += [o["Key"] for o in r.get("Contents", [])]
            if not r.get("IsTruncated"):
                return out
            token = r["NextContinuationToken"]

    def delete(self, keys):
        for i in range(0, len(keys), 1000):
            batch = keys[i:i + 1000]
            self.c.delete_objects(Bucket=self.name, Delete={"Objects": [{"Key": k} for k in batch], "Quiet": True})


def make_purger(token, zone_id, log=print):
    """purge(urls): Cloudflare's cache purge by URL (30 per request); a
    failure is a warning (the files are already gone from the bucket)."""
    import urllib.request

    def purge(urls):
        for i in range(0, len(urls), 30):
            req = urllib.request.Request(
                f"https://api.cloudflare.com/client/v4/zones/{zone_id}/purge_cache",
                data=json.dumps({"files": urls[i:i + 30]}).encode(), method="POST",
                headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"})
            try:
                with urllib.request.urlopen(req, timeout=30) as r:
                    ok = json.load(r).get("success")
            except Exception as e:  # (HTTP errors, network)
                ok, e_msg = False, str(e)
            else:
                e_msg = ""
            if not ok:
                log(f"warning: cache purge failed {e_msg}".rstrip())
    return purge


def make_client():
    import boto3  # (pip install boto3; only needed for real runs)
    missing = [v for v in ("R2_ENDPOINT", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY") if not os.environ.get(v)]
    if missing:
        raise SystemExit("publish_r2: set " + ", ".join(missing))
    return boto3.client(
        "s3", endpoint_url=os.environ["R2_ENDPOINT"], region_name="auto",
        aws_access_key_id=os.environ["R2_ACCESS_KEY_ID"],
        aws_secret_access_key=os.environ["R2_SECRET_ACCESS_KEY"])


# --- publishing -------------------------------------------------------------------------

def publish(bucket, version, directory, *, commit="", keep=3, prefix="", base_url=DEFAULT_BASE_URL,
            date=None, dry_run=False, log=print, purge=None):
    """Uploads `directory`'s files as `version`, updates the manifest and
    deletes what it no longer lists. Returns the new manifest."""
    parse_version(version)  # (validates)
    if keep < 1:
        raise ValueError("keep must be at least 1")
    date = date or datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
    folder = prefix + folder_of(version)
    files = []
    for name in collect_files(directory):
        path = os.path.join(directory, name)
        key = folder + name
        info = describe(name)
        files.append({"name": name, **info, "size": os.path.getsize(path), "sha256": sha256_of(path),
                      "url": f"{base_url}/{key}"})
        log(f"upload {key} ({files[-1]['size']} bytes)")
        if not dry_run:
            bucket.put_file(key, path, content_type(name), "public, max-age=31536000, immutable")
    entry = {
        "version": version, "tag": f"v{version}", "channel": channel_of(version),
        "prerelease": "-" in version, "date": date, "commit": commit,
        "notes_url": f"{REPO}/releases/tag/v{version}", "files": files,
    }
    manifest = bucket.get_json(prefix + "manifest.json") or empty_manifest(base_url)
    manifest["base_url"] = base_url
    manifest = updated_manifest(manifest, entry, keep)
    log(f"manifest: latest={manifest['latest']} stable={[e['version'] for e in manifest['stable']]} "
        f"dev={manifest['dev']['version'] if manifest['dev'] else None}")
    if not dry_run:
        bucket.put_json(prefix + "manifest.json", manifest, "public, max-age=60")
    stale = stale_keys(bucket.keys(prefix + "releases/") + bucket.keys(prefix + "dev/"), manifest, prefix)
    for k in stale:
        log(f"delete {k}")
    if stale and not dry_run:
        bucket.delete(stale)
    # The CDN: the new manifest at once, and no cached copies of deleted files.
    if purge and not dry_run:
        purge([f"{base_url}/{prefix}manifest.json"] + [f"{base_url}/{k}" for k in stale])
    return manifest


def main(argv=None):
    ap = argparse.ArgumentParser(description="Publish a release to the R2 downloads bucket.")
    ap.add_argument("--version", required=True, help="e.g. 0.1.0, 0.2.0-beta.1, 0.1.0-dev.42")
    ap.add_argument("--dir", required=True, help="folder with the packages and SHA256SUMS.txt")
    ap.add_argument("--commit", default=os.environ.get("GITHUB_SHA", ""))
    ap.add_argument("--keep", type=int, default=3, help="releases to keep (default 3)")
    ap.add_argument("--prefix", default="", help="key prefix (tests use e.g. ci-test/)")
    ap.add_argument("--bucket", default=os.environ.get("R2_BUCKET", DEFAULT_BUCKET))
    ap.add_argument("--base-url", default=DEFAULT_BASE_URL)
    ap.add_argument("--dry-run", action="store_true", help="print what would happen")
    a = ap.parse_args(argv)
    if a.prefix and not a.prefix.endswith("/"):
        a.prefix += "/"
    bucket = Bucket(make_client(), a.bucket)
    token = os.environ.get("CLOUDFLARE_API_TOKEN")
    purge = make_purger(token, os.environ.get("CLOUDFLARE_ZONE_ID", DEFAULT_ZONE_ID)) if token else None
    if not purge:
        print("publish_r2: no CLOUDFLARE_API_TOKEN - the CDN cache isn't purged")
    publish(bucket, a.version, a.dir, commit=a.commit, keep=a.keep, prefix=a.prefix,
            base_url=a.base_url, dry_run=a.dry_run, purge=purge)
    return 0


if __name__ == "__main__":
    sys.exit(main())
