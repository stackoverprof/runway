extension AgentControl {
    /// The one command every Runway agent acts through. Installed on PATH for
    /// each session the app starts, so an agent discovers it by running it.
    static let runwayCLI = """
        #!/usr/bin/env python3
        \"\"\"runway: what an agent of any rank acts through.

        A flight is an issue. Its crews are that issue's sub-issues. Everything here
        goes straight to GitHub through `gh`, so the board an agent reads is the board
        the team reads.
        \"\"\"
        import argparse
        import datetime
        import json
        import os
        import subprocess
        import sys

        SCHEME = os.environ.get("RUNWAY_URL_SCHEME", "runway")
        RANK = os.environ.get("RUNWAY_RANK", "")
        FLIGHT = os.environ.get("RUNWAY_FLIGHT", "")
        CREW = os.environ.get("RUNWAY_CREW", "")
        REPORTS_TO = os.environ.get("RUNWAY_REPORTS_TO", "")


        def gh(args):
            done = subprocess.run(["gh"] + args, capture_output=True, text=True)
            if done.returncode != 0:
                sys.stderr.write((done.stderr or "gh failed").strip() + "\\n")
                sys.exit(done.returncode)
            return done.stdout


        def graphql(query, **variables):
            args = ["api", "graphql", "-f", "query=" + query]
            for key, value in variables.items():
                flag = "-F" if isinstance(value, int) else "-f"
                args += [flag, "%s=%s" % (key, value)]
            answer = json.loads(gh(args))
            if "errors" in answer:
                sys.exit("runway: " + answer["errors"][0].get("message", "GitHub refused that"))
            return answer["data"]


        def repo_of(args):
            repo = getattr(args, "repo", "") or os.environ.get("RUNWAY_REPOSITORY", "")
            if not repo:
                sys.exit("runway: no repository. Pass --repo owner/name.")
            return repo


        def nudge():
            \"\"\"Tell the app to re-read the board, so the panes move with you.\"\"\"
            subprocess.run(["open", "-g", SCHEME + "://refresh?tab=runway"], capture_output=True)


        FLIGHT_FIELDS = \"\"\"
        number title state url
        subIssuesSummary { total completed }
        subIssues(first: 100) {
          nodes { number title state url repository { nameWithOwner } }
        }
        \"\"\"

        SEARCH_QUERY = \"\"\"
        query($q: String!) {
          search(query: $q, type: ISSUE, first: 60) {
            nodes { ... on Issue { %s parent { number title } } }
          }
        }
        \"\"\" % FLIGHT_FIELDS

        ONE_QUERY = \"\"\"
        query($owner: String!, $name: String!, $number: Int!) {
          repository(owner: $owner, name: $name) {
            issue(number: $number) { id %s parent { number title } }
          }
        }
        \"\"\" % FLIGHT_FIELDS


        def split(repo):
            owner, _, name = repo.partition("/")
            if not owner or not name:
                sys.exit("runway: a repository reads owner/name, not " + repo)
            return owner, name


        def fetch_one(repo, number):
            owner, name = split(repo)
            issue = graphql(ONE_QUERY, owner=owner, name=name, number=int(number))["repository"]["issue"]
            if issue is None:
                sys.exit("runway: %s has no issue #%s" % (repo, number))
            return issue


        def node_id(repo, number):
            return fetch_one(repo, number)["id"]


        def mark(state):
            return "x" if state == "CLOSED" else " "


        def print_flight(flight, legs=True):
            summary = flight.get("subIssuesSummary") or {}
            total, done = summary.get("total", 0), summary.get("completed", 0)
            crews = " · %d/%d crews landed" % (done, total) if total else ""
            print("[%s] #%-6s %s%s" % (mark(flight["state"]), flight["number"], flight["title"], crews))
            if not legs:
                return
            for leg in (flight.get("subIssues") or {}).get("nodes", []):
                where = (leg.get("repository") or {}).get("nameWithOwner", "")
                suffix = "  (%s)" % where if where and where not in flight.get("url", "") else ""
                print("      [%s] #%-6s %s%s" % (mark(leg["state"]), leg["number"], leg["title"], suffix))


        # MARK: the verbs


        def cmd_whoami(args):
            rank = RANK or "unranked"
            print("You are %s in Runway." % rank)
            if FLIGHT:
                print("Flight: #%s" % FLIGHT)
            if CREW:
                print("Crew: #%s" % CREW)
            if REPORTS_TO:
                print("You report to: %s" % REPORTS_TO)
            repo = os.environ.get("RUNWAY_REPOSITORY", "")
            if repo:
                print("Repository: %s" % repo)
            print("")
            print("A flight is an issue. Its crews are that issue's sub-issues.")
            print("Run `runway help` for what you can do from here.")


        def cmd_list(args):
            repo = repo_of(args)
            query = "repo:%s assignee:@me is:issue state:%s sort:updated-desc" % (repo, args.state)
            found = graphql(SEARCH_QUERY, q=query)["search"]["nodes"]
            flights = [issue for issue in found if issue and not issue.get("parent")]
            if args.json:
                print(json.dumps(flights, indent=2))
                return
            if not flights:
                print("No %s flights assigned to you in %s." % (args.state, repo))
                return
            for flight in flights:
                print_flight(flight)


        def cmd_show(args):
            if not args.number:
                sys.exit("runway: which flight? Pass a number.")
            flight = fetch_one(repo_of(args), args.number)
            if args.json:
                print(json.dumps(flight, indent=2))
                return
            print_flight(flight)
            if flight.get("parent"):
                print("      part of #%s %s" % (flight["parent"]["number"], flight["parent"]["title"]))


        def create_issue(repo, title, body):
            url = gh(["issue", "create", "--repo", repo, "--title", title,
                      "--body", body or "", "--assignee", "@me"]).strip()
            number = url.rstrip("/").split("/")[-1]
            return int(number), url


        def assign_me(repo, number):
            # Runway only lists issues assigned to you, so a flight nobody owns
            # is invisible in the left pane.
            gh(["issue", "edit", str(number), "--repo", repo, "--add-assignee", "@me"])


        def adopt(repo, parent_number, child_number):
            mutation = \"\"\"
            mutation($parent: ID!, $child: ID!) {
              addSubIssue(input: {issueId: $parent, subIssueId: $child}) {
                issue { number }
              }
            }
            \"\"\"
            graphql(mutation, parent=node_id(repo, parent_number), child=node_id(repo, child_number))


        def cmd_flight_create(args):
            repo = repo_of(args)
            number, url = create_issue(repo, args.title, args.body)
            note("flight_created", issue=number, title=args.title, repository=repo)
            print("Flight #%d: %s" % (number, url))
            for title in args.crew or []:
                crew_number, crew_url = create_issue(repo, title, "")
                adopt(repo, number, crew_number)
                print("  crew #%d %s" % (crew_number, title))
            for existing in args.adopt or []:
                adopt(repo, number, existing)
                print("  crew #%s adopted" % existing)
            nudge()


        def cmd_crew_add(args):
            repo = repo_of(args)
            flight = args.flight or FLIGHT
            if not flight:
                sys.exit("runway: which flight? Pass --flight <number>.")
            number, url = create_issue(repo, args.title, args.body)
            adopt(repo, flight, number)
            assign_me(repo, flight)
            print("Crew #%d on flight #%s: %s" % (number, flight, url))
            nudge()


        def cmd_crew_adopt(args):
            repo = repo_of(args)
            flight = args.flight or FLIGHT
            if not flight:
                sys.exit("runway: which flight? Pass --flight <number>.")
            adopt(repo, flight, args.issue)
            assign_me(repo, flight)
            note("crew_adopted", issue=int(str(args.issue).lstrip("#")), flight=int(flight), repository=repo)
            print("Crew #%s joins flight #%s" % (args.issue, flight))
            nudge()


        ACTIVITY = os.path.join(
            os.path.dirname(os.path.dirname(os.path.realpath(__file__))),
            "activity.jsonl",
        )


        def note(action, **fields):
            # The same line the app writes, from the other side. A report
            # reads one file, whoever moved the work.
            fields["action"] = action
            fields["at"] = (
                datetime.datetime.now(datetime.timezone.utc)
                .replace(microsecond=0)
                .isoformat()
                .replace("+00:00", "Z")
            )
            fields["schema"] = 2
            try:
                with open(ACTIVITY, "a") as handle:
                    handle.write(json.dumps(fields, sort_keys=True) + "\\n")
            except Exception:
                pass


        DECK = os.path.join(
            os.path.dirname(os.path.dirname(os.path.realpath(__file__))),
            "crew-deck.json",
        )


        def read_deck():
            try:
                with open(DECK) as handle:
                    return set(json.load(handle).get("up", []))
            except Exception:
                return set()


        def write_deck(seats):
            with open(DECK, "w") as handle:
                json.dump({"up": sorted(seats)}, handle, indent=2)


        def cmd_crew_up(args):
            # Standing a crew up is the same act whoever does it: the pane and
            # the agents share one deck file.
            repo = repo_of(args)
            seats = read_deck()
            seats.add("%s#%s" % (repo, args.issue))
            write_deck(seats)
            note("crew_up", issue=int(str(args.issue).lstrip("#")), repository=repo)
            print("Crew #%s is up" % args.issue)
            nudge()


        def cmd_crew_down(args):
            repo = repo_of(args)
            seats = read_deck()
            seats.discard("%s#%s" % (repo, args.issue))
            write_deck(seats)
            note("crew_down", issue=int(str(args.issue).lstrip("#")), repository=repo)
            print("Crew #%s stood down" % args.issue)
            nudge()


        BOARD = os.path.join(
            os.path.dirname(os.path.dirname(os.path.realpath(__file__))),
            "board.json",
        )


        def read_board():
            try:
                with open(BOARD) as handle:
                    return json.load(handle)
            except Exception:
                return {}


        def write_board(board):
            with open(BOARD, "w") as handle:
                json.dump(board, handle, indent=2)


        def flights_of(repo):
            query = "repo:%s assignee:@me is:issue state:open sort:updated-desc" % repo
            found = graphql(SEARCH_QUERY, q=query)["search"]["nodes"]
            return [issue for issue in found if issue and not issue.get("parent")]


        def cmd_order(args):
            # The board's order is Erbin's own, so an agent only ever rewrites
            # it wholesale: either the numbers given, or a sort it can explain.
            repo = repo_of(args)
            board = read_board()
            entry = board.get(repo, {})
            if args.numbers:
                order = [int(n.lstrip("#")) for n in args.numbers]
            else:
                flights = flights_of(repo)
                priority = entry.get("priority", {})
                if args.by == "priority":
                    flights.sort(
                        key=lambda f: (priority.get(str(f["number"]), 9), -f["number"])
                    )
                elif args.by == "title":
                    flights.sort(key=lambda f: f["title"].lower())
                elif args.by == "newest":
                    flights.sort(key=lambda f: -f["number"])
                elif args.by == "oldest":
                    flights.sort(key=lambda f: f["number"])
                else:
                    sys.exit("runway: sort by priority, title, newest or oldest")
                order = [f["number"] for f in flights]
            entry["order"] = order
            board[repo] = entry
            write_board(board)
            note("order_changed", repository=repo, order=order, by=args.by or "given")
            print("Board order set, %d flights" % len(order))
            for number in order:
                print("  #%s" % number)
            nudge()


        def cmd_priority(args):
            repo = repo_of(args)
            board = read_board()
            entry = board.get(repo, {})
            priority = entry.get("priority", {})
            said = str(args.level).lower()
            number = str(int(str(args.issue).lstrip("#")))
            if said in ("none", "clear", "-"):
                priority.pop(number, None)
                print("#%s has no priority" % number)
            else:
                level = int(said.lstrip("p"))
                if level < 1 or level > 5:
                    sys.exit("runway: priority is P1 to P5")
                priority[number] = level
                print("#%s is P%d" % (number, level))
            entry["priority"] = priority
            board[repo] = entry
            write_board(board)
            note("priority_set", issue=int(number), repository=repo, priority=priority.get(number))
            nudge()


        def cmd_crew_release(args):
            repo = repo_of(args)
            flight = args.flight or FLIGHT
            if not flight:
                sys.exit("runway: which flight? Pass --flight <number>.")
            mutation = \"\"\"
            mutation($parent: ID!, $child: ID!) {
              removeSubIssue(input: {issueId: $parent, subIssueId: $child}) {
                issue { number }
              }
            }
            \"\"\"
            graphql(mutation, parent=node_id(repo, flight), child=node_id(repo, args.issue))
            print("Crew #%s leaves flight #%s" % (args.issue, flight))
            nudge()


        PROGRESS_HEADING = "## Progress"


        def issue_body(repo, number):
            return gh(["issue", "view", str(number), "--repo", repo, "--json", "body", "--jq", ".body"])


        def write_body(repo, number, body):
            import tempfile
            with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as handle:
                handle.write(body)
                path = handle.name
            gh(["issue", "edit", str(number), "--repo", repo, "--body-file", path])
            os.unlink(path)


        def split_progress(body):
            \"\"\"The lines of the Progress section, and the body either side of it.\"\"\"
            lines = body.split("\\n")
            start = None
            for index, line in enumerate(lines):
                if line.strip().lower().startswith(PROGRESS_HEADING.lower()):
                    start = index
                    break
            if start is None:
                return lines, [], []
            end = len(lines)
            for index in range(start + 1, len(lines)):
                if lines[index].strip().startswith("#"):
                    end = index
                    break
            return lines[:start + 1], lines[start + 1:end], lines[end:]


        def steps_of(section):
            steps = []
            for line in section:
                text = line.strip()
                if text.startswith("- [x]") or text.startswith("- [X]"):
                    steps.append((True, text[5:].strip()))
                elif text.startswith("- [ ]"):
                    steps.append((False, text[5:].strip()))
            return steps


        def rendered(steps):
            return ["- [%s] %s" % ("x" if done else " ", text) for done, text in steps]


        def save_steps(repo, number, steps):
            body = issue_body(repo, number)
            head, section, tail = split_progress(body)
            if not head or not head[-1].strip().lower().startswith(PROGRESS_HEADING.lower()):
                # No Progress section yet: give the issue one at the end.
                head = body.rstrip("\\n").split("\\n") + ["", PROGRESS_HEADING]
                tail = []
            kept = [line for line in section if line.strip() and not line.strip().startswith("- [")]
            write_body(repo, number, "\\n".join(head + [""] + kept + rendered(steps) + [""] + tail).strip() + "\\n")
            nudge()


        def flight_of(args):
            number = getattr(args, "flight", "") or FLIGHT or CREW
            if not number:
                sys.exit("runway: which issue? Pass --flight <number>.")
            return number


        def cmd_progress(args):
            repo = repo_of(args)
            number = flight_of(args)
            steps = steps_of(split_progress(issue_body(repo, number))[1])
            if not steps:
                print("No checklist on #%s yet. Add one with: runway progress add \\"first step\\"" % number)
                return
            for index, (done, text) in enumerate(steps, start=1):
                print("%2d. [%s] %s" % (index, "x" if done else " ", text))


        def cmd_progress_add(args):
            repo = repo_of(args)
            number = flight_of(args)
            steps = steps_of(split_progress(issue_body(repo, number))[1])
            steps.append((False, args.step))
            save_steps(repo, number, steps)
            note("step_added", issue=int(number), repository=repo, step=args.step)
            print("#%s step %d: %s" % (number, len(steps), args.step))


        def cmd_progress_mark(args, done):
            repo = repo_of(args)
            number = flight_of(args)
            steps = steps_of(split_progress(issue_body(repo, number))[1])
            index = args.step - 1
            if index < 0 or index >= len(steps):
                sys.exit("runway: #%s has no step %d" % (number, args.step))
            steps[index] = (done, steps[index][1])
            save_steps(repo, number, steps)
            note(
                "step_ticked" if done else "step_unticked",
                issue=int(number),
                repository=repo,
                step=steps[index][1],
            )
            print("#%s step %d %s" % (number, args.step, "ticked" if done else "unticked"))


        def cmd_progress_needs(args):
            # A blocker rides in its own step, written as a trailing
            # "(needs: ...)", so the checklist is the only list to keep.
            repo = repo_of(args)
            number = flight_of(args)
            steps = steps_of(split_progress(issue_body(repo, number))[1])
            index = args.step - 1
            if index < 0 or index >= len(steps):
                sys.exit("runway: #%s has no step %d" % (number, args.step))
            done, text = steps[index]
            bare = text
            if bare.endswith(")") and "(needs:" in bare.lower():
                bare = bare[:bare.lower().rindex("(needs:")].strip()
            said = (args.said or "").strip()
            steps[index] = (done, bare if not said else "%s (needs: %s)" % (bare, said))
            save_steps(repo, number, steps)
            note(
                "needs_set" if said else "needs_cleared",
                issue=int(number),
                repository=repo,
                step=steps[index][1],
                needs=said,
            )
            print("#%s step %d: %s" % (number, args.step, steps[index][1]))


        def cmd_progress_set(args):
            repo = repo_of(args)
            number = flight_of(args)
            lines = [line.strip() for line in sys.stdin.read().split("\\n") if line.strip()]
            steps = []
            for line in lines:
                if line.startswith("- [x]") or line.startswith("- [X]"):
                    steps.append((True, line[5:].strip()))
                elif line.startswith("- [ ]"):
                    steps.append((False, line[5:].strip()))
                elif line.startswith("- "):
                    steps.append((False, line[2:].strip()))
                else:
                    steps.append((False, line))
            save_steps(repo, number, steps)
            print("#%s checklist rewritten, %d steps" % (number, len(steps)))


        def parse_since(said):
            # "24h", "90m", "3d", or an ISO timestamp. Anything else is the
            # start of today, which is what "today" means to a report.
            now = datetime.datetime.now(datetime.timezone.utc)
            said = (said or "").strip().lower()
            if not said or said == "today":
                local = datetime.datetime.now().astimezone()
                start = local.replace(hour=0, minute=0, second=0, microsecond=0)
                return start.astimezone(datetime.timezone.utc)
            if said.endswith("h") and said[:-1].isdigit():
                return now - datetime.timedelta(hours=int(said[:-1]))
            if said.endswith("m") and said[:-1].isdigit():
                return now - datetime.timedelta(minutes=int(said[:-1]))
            if said.endswith("d") and said[:-1].isdigit():
                return now - datetime.timedelta(days=int(said[:-1]))
            try:
                parsed = datetime.datetime.fromisoformat(said.replace("z", "+00:00"))
                if parsed.tzinfo is None:
                    parsed = parsed.astimezone()
                return parsed.astimezone(datetime.timezone.utc)
            except ValueError:
                sys.exit("runway: --since takes 24h, 90m, 3d, today, or a timestamp")


        def read_activity(since):
            rows = []
            try:
                with open(ACTIVITY) as handle:
                    for line in handle:
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            row = json.loads(line)
                        except Exception:
                            continue
                        when = row.get("at", "")
                        try:
                            at = datetime.datetime.fromisoformat(when.replace("Z", "+00:00"))
                        except Exception:
                            continue
                        if at >= since:
                            row["_at"] = at
                            rows.append(row)
            except FileNotFoundError:
                return []
            rows.sort(key=lambda r: r["_at"])
            return rows


        def spell(seconds):
            seconds = int(seconds or 0)
            if seconds < 60:
                return "%ds" % seconds
            if seconds < 3600:
                return "%dm" % (seconds // 60)
            return "%dh%02dm" % (seconds // 3600, (seconds % 3600) // 60)


        def cmd_log(args):
            # What Runway saw happen. A report reads this for the shape of the
            # day and goes to GitHub for the evidence.
            since = parse_since(args.since)
            rows = read_activity(since)
            if args.json:
                for row in rows:
                    row.pop("_at", None)
                print(json.dumps(rows, indent=2))
                return
            if not rows:
                print("Nothing in the log since %s." % since.isoformat())
                return
            if not args.summary:
                for row in rows:
                    local = row["_at"].astimezone()
                    bits = []
                    if row.get("issue"):
                        bits.append("#%s" % row["issue"])
                    if row.get("title"):
                        bits.append(row["title"])
                    if row.get("step"):
                        bits.append(row["step"])
                    if row.get("needs"):
                        bits.append("needs: %s" % row["needs"])
                    if row.get("name"):
                        bits.append(row["name"])
                    if row.get("seconds"):
                        bits.append(spell(row["seconds"]))
                    print("%s  %-16s %s" % (
                        local.strftime("%d %b %H:%M"), row["action"], "  ".join(str(b) for b in bits)
                    ))
                return

            attention = {}
            worked = {}
            titles = {}
            ticked = []
            blocked = []
            closed = []
            made = []
            for row in rows:
                issue = row.get("issue")
                if row.get("title"):
                    titles[issue] = row["title"]
                action = row["action"]
                if action == "flight_left":
                    attention[issue] = attention.get(issue, 0) + int(row.get("seconds", 0))
                elif action in ("crew_down", "seat_worked"):
                    worked[issue] = worked.get(issue, 0) + int(row.get("seconds", 0))
                elif action == "step_ticked":
                    ticked.append((issue, row.get("step", "")))
                elif action == "needs_set":
                    blocked.append((issue, row.get("step", ""), row.get("needs", "")))
                elif action == "issue_closed":
                    closed.append(issue)
                elif action == "flight_created":
                    made.append((issue, row.get("title", "")))

            def name(issue):
                return "#%s %s" % (issue, titles.get(issue, "")).strip()

            print("Since %s" % since.astimezone().strftime("%d %b %H:%M"))
            if attention:
                print("")
                print("Your attention")
                for issue, seconds in sorted(attention.items(), key=lambda kv: -kv[1]):
                    print("  %-8s %s" % (spell(seconds), name(issue)))
            if worked:
                print("")
                print("Agents working")
                for issue, seconds in sorted(worked.items(), key=lambda kv: -kv[1]):
                    print("  %-8s %s" % (spell(seconds), name(issue)))
            if ticked:
                print("")
                print("Steps ticked")
                for issue, step in ticked:
                    print("  #%s  %s" % (issue, step))
            if blocked:
                print("")
                print("Blockers set")
                for issue, step, needs in blocked:
                    print("  #%s  %s (needs: %s)" % (issue, step, needs))
            if made:
                print("")
                print("Flights made")
                for issue, title in made:
                    print("  #%s  %s" % (issue, title))
            if closed:
                print("")
                print("Closed")
                for issue in closed:
                    print("  %s" % name(issue))


        def cmd_close(args):
            repo = repo_of(args)
            gh(["issue", "close", str(args.number), "--repo", repo])
            # A closed crew leaves the pane, so it leaves the deck with it.
            seats = read_deck()
            seats.discard("%s#%s" % (repo, args.number))
            write_deck(seats)
            note("issue_closed", issue=int(str(args.number).lstrip("#")), repository=repo)
            print("#%s closed" % args.number)
            nudge()


        def cmd_reopen(args):
            repo = repo_of(args)
            gh(["issue", "reopen", str(args.number), "--repo", repo])
            note("issue_reopened", issue=int(str(args.number).lstrip("#")), repository=repo)
            print("#%s reopened" % args.number)
            nudge()


        def build_parser():
            parser = argparse.ArgumentParser(
                prog="runway",
                description="A flight is an issue; its crews are that issue's sub-issues.",
            )
            parser.add_argument("--repo", default="", help="owner/name; defaults to the repository on screen")
            verbs = parser.add_subparsers(dest="verb", required=True)

            whoami = verbs.add_parser("whoami", help="your rank, your flight, what you answer to")
            whoami.set_defaults(run=cmd_whoami)

            listing = verbs.add_parser("list", help="the flights assigned to you")
            listing.add_argument("--state", default="open", choices=["open", "closed", "all"])
            listing.add_argument("--json", action="store_true")
            listing.set_defaults(run=cmd_list)

            show = verbs.add_parser("show", help="one flight and its crews")
            show.add_argument("number", nargs="?", default=FLIGHT,
                              help="defaults to the flight this seat flies")
            show.add_argument("--json", action="store_true")
            show.set_defaults(run=cmd_show)

            flight = verbs.add_parser("flight", help="make a flight")
            flight_verbs = flight.add_subparsers(dest="action", required=True)
            create = flight_verbs.add_parser("create", help="a new issue, with crews under it")
            create.add_argument("--title", required=True)
            create.add_argument("--body", default="")
            create.add_argument("--crew", action="append", help="a crew to create; repeatable")
            create.add_argument("--adopt", action="append", help="an existing issue to take as a crew; repeatable")
            create.set_defaults(run=cmd_flight_create)

            crew = verbs.add_parser("crew", help="the crews of a flight")
            crew_verbs = crew.add_subparsers(dest="action", required=True)
            crew_add = crew_verbs.add_parser("add", help="create an issue as a crew of this flight")
            crew_add.add_argument("--title", required=True)
            crew_add.add_argument("--body", default="")
            crew_add.add_argument("--flight", default="")
            crew_add.set_defaults(run=cmd_crew_add)
            crew_adopt = crew_verbs.add_parser("adopt", help="take an existing issue as a crew")
            crew_adopt.add_argument("issue")
            crew_adopt.add_argument("--flight", default="")
            crew_adopt.set_defaults(run=cmd_crew_adopt)
            crew_up = crew_verbs.add_parser("up", help="bring a crew up: open its terminal")
            crew_up.add_argument("issue")
            crew_up.set_defaults(run=cmd_crew_up)
            crew_down = crew_verbs.add_parser("down", help="stand a crew down to its card")
            crew_down.add_argument("issue")
            crew_down.set_defaults(run=cmd_crew_down)

            crew_release = crew_verbs.add_parser("release", help="let a crew go, without closing it")
            crew_release.add_argument("issue")
            crew_release.add_argument("--flight", default="")
            crew_release.set_defaults(run=cmd_crew_release)

            progress = verbs.add_parser("progress", help="the checklist you keep on the issue")
            progress.add_argument("--flight", default="", help="defaults to your own flight or crew")
            progress_verbs = progress.add_subparsers(dest="action")
            progress.set_defaults(run=cmd_progress)
            progress_add = progress_verbs.add_parser("add", help="add a step")
            progress_add.add_argument("step")
            progress_add.add_argument("--flight", default="")
            progress_add.set_defaults(run=cmd_progress_add)
            progress_tick = progress_verbs.add_parser("tick", help="tick a step by its number")
            progress_tick.add_argument("step", type=int)
            progress_tick.add_argument("--flight", default="")
            progress_tick.set_defaults(run=lambda args: cmd_progress_mark(args, True))
            progress_untick = progress_verbs.add_parser("untick", help="untick a step")
            progress_untick.add_argument("step", type=int)
            progress_untick.add_argument("--flight", default="")
            progress_untick.set_defaults(run=lambda args: cmd_progress_mark(args, False))
            progress_needs = progress_verbs.add_parser(
                "needs", help="say what a step is waiting on, or clear it"
            )
            progress_needs.add_argument("step", type=int)
            progress_needs.add_argument(
                "said", nargs="?", default="", help="leave empty to clear the blocker"
            )
            progress_needs.add_argument("--flight", default="")
            progress_needs.set_defaults(run=cmd_progress_needs)

            progress_set = progress_verbs.add_parser("set", help="rewrite the whole checklist from stdin")
            progress_set.add_argument("--flight", default="")
            progress_set.set_defaults(run=cmd_progress_set)

            order = verbs.add_parser("order", help="the order flights sit in on the board")
            order.add_argument("numbers", nargs="*", help="issue numbers, top first")
            order.add_argument(
                "--by", default="", help="priority, title, newest or oldest"
            )
            order.set_defaults(run=cmd_order)

            priority = verbs.add_parser("priority", help="set a flight's priority, P1 to P5")
            priority.add_argument("issue")
            priority.add_argument("level", help="1 to 5, or none")
            priority.set_defaults(run=cmd_priority)

            log = verbs.add_parser("log", help="what Runway saw happen, for a report")
            log.add_argument("--since", default="today", help="24h, 90m, 3d, today, or a timestamp")
            log.add_argument("--summary", action="store_true", help="grouped, not line by line")
            log.add_argument("--json", action="store_true")
            log.set_defaults(run=cmd_log)

            close = verbs.add_parser("close", help="close a flight or a crew")
            close.add_argument("number")
            close.set_defaults(run=cmd_close)

            reopen = verbs.add_parser("reopen", help="put one back in the air")
            reopen.add_argument("number")
            reopen.set_defaults(run=cmd_reopen)

            return parser


        def main():
            if len(sys.argv) > 1 and sys.argv[1] == "help":
                build_parser().print_help()
                return
            args = build_parser().parse_args()
            args.run(args)


        if __name__ == "__main__":
            main()

        """
}
