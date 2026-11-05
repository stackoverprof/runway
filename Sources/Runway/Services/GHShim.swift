import Foundation

extension AgentControl {
    /// `gh`, as a Runway seat sees it: the real `gh`, and then the board is
    /// told what changed, so it shows at once.
    ///
    /// Agents change GitHub with plain `gh` as often as with `runway`: a PR
    /// retitled, made ready, merged, an issue edited or closed. GitHub's list
    /// and search answers lag such a write by up to a minute and Runway caches
    /// on top, so the board went on showing the old title. Every seat's PATH
    /// starts with Runway's bin folder, so this stands in front of the real
    /// `gh`, runs it untouched, and after a write that succeeded it reads the
    /// one PR or issue back directly (that read is never stale) and drops it
    /// where the app picks it up within a second. The read happens in the
    /// background, so the agent never waits on it.
    static let ghShim = #"""
    #!/usr/bin/env python3
    """gh in a Runway seat: the real gh, then the board told what changed."""
    import json
    import os
    import subprocess
    import sys

    HERE = os.path.dirname(os.path.realpath(__file__))
    SUPPORT = os.path.dirname(HERE)
    SCHEME = os.environ.get("RUNWAY_URL_SCHEME", "runway")


    def real_gh():
        for folder in os.environ.get("PATH", "").split(os.pathsep):
            if not folder or os.path.realpath(folder) == HERE:
                continue
            path = os.path.join(folder, "gh")
            if os.path.isfile(path) and os.access(path, os.X_OK):
                return path
        for path in ("/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"):
            if os.path.exists(path):
                return path
        sys.exit("gh: not installed")


    GH = real_gh()
    WRITES = {
        "pr": {"create", "edit", "close", "reopen", "merge", "ready", "comment", "review"},
        "issue": {"create", "edit", "close", "reopen", "comment", "delete", "transfer"},
    }
    PR_FIELDS = ("number,title,state,isDraft,author,createdAt,updatedAt,mergedAt,"
                 "closedAt,url,headRefName,baseRefName")


    def repo_flags(args):
        flags = []
        for index, arg in enumerate(args):
            if arg in ("-R", "--repo") and index + 1 < len(args):
                flags = ["--repo", args[index + 1]]
            elif arg.startswith("--repo="):
                flags = ["--repo", arg.split("=", 1)[1]]
        return flags


    def selector(args):
        rest = args[2:]
        if rest and not rest[0].startswith("-"):
            return rest[0]
        for arg in rest:
            if arg.lstrip("#").isdigit() or arg.startswith("https://"):
                return arg
        return None


    def key(repo, number):
        return "%s__%s" % (repo.lower().replace("/", "__"), number)


    def repo_of(url):
        parts = url.split("/")
        return "%s/%s" % (parts[3], parts[4])


    def place(folder, name, text):
        folder = os.path.join(SUPPORT, folder)
        os.makedirs(folder, exist_ok=True)
        target = os.path.join(folder, name)
        with open(target + ".tmp", "w") as handle:
            handle.write(text)
        os.replace(target + ".tmp", target)


    def view(noun, sel, flags, fields):
        argv = [GH, noun, "view"] + ([sel] if sel else []) + flags + ["--json", fields]
        done = subprocess.run(argv, capture_output=True, text=True)
        return json.loads(done.stdout) if done.returncode == 0 else None


    def record(noun, verb, sel, flags):
        if noun == "pr":
            pull = view("pr", sel, flags, PR_FIELDS)
            if pull:
                place("pending-pulls", key(repo_of(pull["url"]), pull["number"]) + ".json", json.dumps(pull))
        elif noun == "issue" and sel and verb != "delete":
            issue = view("issue", sel, flags, "number,title,state,body,url")
            if not issue:
                return
            name = key(repo_of(issue["url"]), issue["number"])
            place("pending-bodies", name + ".md", issue.get("body") or "")
            states = os.path.join(SUPPORT, "pending-states", name + ".json")
            current = {}
            try:
                with open(states) as handle:
                    current = json.load(handle)
            except Exception:
                pass
            current["state"] = issue["state"]
            current["title"] = issue["title"]
            if verb == "create":
                current["create"] = {"title": issue["title"], "url": issue["url"], "body": issue.get("body") or ""}
            place("pending-states", name + ".json", json.dumps(current))


    def nudge(noun):
        tab = "pulls" if noun == "pr" else "runway"
        subprocess.run(["open", "-g", "%s://refresh?tab=%s" % (SCHEME, tab)], capture_output=True)


    def main():
        args = sys.argv[1:]
        if args[:1] == ["--runway-record"]:
            noun, verb, sel = args[1], args[2], args[3] or None
            try:
                record(noun, verb, sel, args[4:])
            finally:
                nudge(noun)
            return

        noun, verb = (args + ["", ""])[:2]
        api_write = noun == "api" and (
            any("mutation" in arg for arg in args)
            or any(args[i] in ("-X", "--method") and i + 1 < len(args)
                   and args[i + 1].upper() != "GET" for i in range(len(args)))
        )
        if os.environ.get("RUNWAY_GH_DIRECT") or not (verb in WRITES.get(noun, ()) or api_write):
            os.execv(GH, [GH] + args)

        creating = verb == "create"
        if creating:
            done = subprocess.run([GH] + args, stdout=subprocess.PIPE)
            sys.stdout.buffer.write(done.stdout)
            sys.stdout.flush()
        else:
            done = subprocess.run([GH] + args)
        if done.returncode == 0:
            if api_write:
                nudge("issue")
                nudge("pr")
            else:
                sel = selector(args)
                if creating:
                    lines = done.stdout.decode(errors="replace").split()
                    sel = next((l for l in reversed(lines) if l.startswith("https://")), None)
                subprocess.Popen(
                    [sys.executable, os.path.realpath(__file__), "--runway-record", noun, verb, sel or ""]
                    + repo_flags(args),
                    stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    start_new_session=True,
                )
        sys.exit(done.returncode)


    main()
    """#
}
