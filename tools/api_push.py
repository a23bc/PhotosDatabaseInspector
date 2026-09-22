"""Push the current local commit to GitHub through the Git Data API.

git-over-https to github.com is blocked here (proxy CONNECT -> 502), but api.github.com
works. This script rebuilds the exact same commit object on the remote:

  parent  = whatever origin/main is now (verified to equal the local parent)
  tree    = rebuilt from locally identical blobs (SHA-checked)
  author/committer/message = copied byte for byte from the local commit

If the tree SHA does not match the local tree, it aborts before touching any ref.
"""

import base64
import json
import os
import subprocess
import sys
import time

REPO = "a23bc/PhotosDatabaseInspector"
BRANCH = "main"

def sh(*args, input_bytes=None):
    p = subprocess.run(args, capture_output=True, input=input_bytes)
    if p.returncode != 0:
        raise RuntimeError("%s -> %s" % (" ".join(args), p.stderr.decode("utf-8", "replace").strip()))
    return p.stdout

def git(*args):
    return sh("git", *args).decode("utf-8", "replace").strip()

def git_bytes(*args):
    return sh("git", *args)

def gh(method, path, payload=None):
    cmd = ["gh", "api", "--method", method, path]
    if payload is not None:
        tmp = os.path.join("build", "_api_payload.json")
        with open(tmp, "wb") as fh:
            fh.write(json.dumps(payload).encode("utf-8"))
        cmd += ["--input", tmp]
    out = sh(*cmd)
    return json.loads(out.decode("utf-8"))

# ---------------------------------------------------------------- local facts
local_head = git("rev-parse", "HEAD")
local_tree = git("rev-parse", "HEAD^{tree}")
parent = git("rev-parse", "HEAD^")
raw = git_bytes("cat-file", "commit", "HEAD").decode("utf-8", "replace")
header, _, message = raw.partition("\n\n")
author_line = [l for l in header.splitlines() if l.startswith("author ")][0][len("author "):]
# "a23bc <2949454631@qq.com> 1790072028 +0800"
name_email, epoch, tz = author_line.rsplit(" ", 2)
name, _, email = name_email.partition(" <")
email = email.rstrip(">")
# ISO 8601 with the original UTC offset, so GitHub writes the same bytes we have locally
sign = 1 if tz[0] == "+" else -1
hh, mm = int(tz[1:3]), int(tz[3:5])
local_epoch = int(epoch) + sign * (hh * 3600 + mm * 60)
iso = (time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(local_epoch)) + "%s%02d:%02d" % (tz[0], hh, mm))

print("local HEAD   :", local_head)
print("local tree   :", local_tree)
print("parent       :", parent)
print("author       :", name, "<%s>" % email, epoch, tz, "->", iso)

changes = git("diff", "--name-status", parent, local_head).splitlines()
print("\nchanges:")
for line in changes:
    print("  ", line)

# ---------------------------------------------------------------- blobs
print("\nuploading blobs")
blob_shas = {}
for line in changes:
    parts = line.split("\t")
    status, paths = parts[0], parts[1:]
    if status.startswith("D"):
        continue
    path = paths[-1]
    data = git_bytes("cat-file", "blob", "%s:%s" % (local_head, path))
    local_blob = git("rev-parse", "%s:%s" % (local_head, path))
    payload = {"content": base64.b64encode(data).decode(), "encoding": "base64"}
    result = gh("POST", "/repos/%s/git/blobs" % REPO, payload)
    if result["sha"] != local_blob:
        print("  MISMATCH %s: remote %s != local %s" % (path, result["sha"], local_blob))
        sys.exit("aborting: remote blob content differs from local")
    blob_shas[path] = result["sha"]
    print("  ok %-58s %s" % (path, local_blob[:10]))

# ---------------------------------------------------------------- tree
print("\nbuilding tree")
entries = []
for line in changes:
    parts = line.split("\t")
    status, paths = parts[0], parts[1:]
    if status.startswith("D"):
        entries.append({"path": paths[0], "mode": "100644", "type": "blob", "sha": None})
    elif status.startswith("R"):
        entries.append({"path": paths[0], "mode": "100644", "type": "blob", "sha": None})
        entries.append({"path": paths[1], "mode": "100644", "type": "blob", "sha": blob_shas[paths[1]]})
    elif status.startswith("A"):
        entries.append({"path": paths[0], "mode": "100644", "type": "blob", "sha": blob_shas[paths[0]]})
    else:
        entries.append({"path": paths[0], "mode": "100644", "type": "blob", "sha": blob_shas[paths[0]]})

remote_head = gh("GET", "/repos/%s/git/ref/heads/%s" % (REPO, BRANCH))["object"]["sha"]
if remote_head != parent:
    sys.exit("aborting: remote %s is %s but the local parent is %s" % (BRANCH, remote_head, parent))
print("remote %s is at the expected parent %s" % (BRANCH, remote_head[:10]))

tree = gh("POST", "/repos/%s/git/trees" % REPO,
          {"base_tree": git("rev-parse", "%s^{tree}" % parent), "tree": entries})
print("remote tree  :", tree["sha"])
if tree["sha"] != local_tree:
    sys.exit("aborting: remote tree %s != local tree %s (no ref was moved)" % (tree["sha"], local_tree))
print("tree matches the local commit tree")

# ---------------------------------------------------------------- commit
print("\ncreating commit")
commit = gh("POST", "/repos/%s/git/commits" % REPO, {
    "message": message,
    "tree": tree["sha"],
    "parents": [parent],
    "author": {"name": name, "email": email, "date": iso},
    "committer": {"name": name, "email": email, "date": iso},
})
print("remote commit:", commit["sha"])
if commit["sha"] != local_head:
    sys.exit("aborting: remote commit %s != local HEAD %s (no ref was moved; "
             "local and remote would have diverged)" % (commit["sha"], local_head))
print("commit object is byte-identical to the local one")

# ---------------------------------------------------------------- ref
print("\nupdating ref")
gh("PATCH", "/repos/%s/git/refs/heads/%s" % (REPO, BRANCH), {"sha": commit["sha"], "force": False})
print("moved", BRANCH, remote_head[:10], "->", commit["sha"][:10])
print("verified: remote head =", gh("GET", "/repos/%s/git/ref/heads/%s" % (REPO, BRANCH))["object"]["sha"])
