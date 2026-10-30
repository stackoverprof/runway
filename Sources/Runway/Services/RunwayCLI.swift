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
            flight = fetch_one(repo_of(args), args.number)
            if args.json:
                print(json.dumps(flight, indent=2))
                return
            print_flight(flight)
            if flight.get("parent"):
                print("      part of #%s %s" % (flight["parent"]["number"], flight["parent"]["title"]))


        def create_issue(repo, title, body):
            url = gh(["issue", "create", "--repo", repo, "--title", title, "--body", body or ""]).strip()
            number = url.rstrip("/").split("/")[-1]
            return int(number), url


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
            print("Crew #%d on flight #%s: %s" % (number, flight, url))
            nudge()


        def cmd_crew_adopt(args):
            repo = repo_of(args)
            flight = args.flight or FLIGHT
            if not flight:
                sys.exit("runway: which flight? Pass --flight <number>.")
            adopt(repo, flight, args.issue)
            print("Crew #%s joins flight #%s" % (args.issue, flight))
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


        def cmd_close(args):
            repo = repo_of(args)
            gh(["issue", "close", str(args.number), "--repo", repo])
            print("#%s closed" % args.number)
            nudge()


        def cmd_reopen(args):
            repo = repo_of(args)
            gh(["issue", "reopen", str(args.number), "--repo", repo])
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
            show.add_argument("number")
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
            crew_release = crew_verbs.add_parser("release", help="let a crew go, without closing it")
            crew_release.add_argument("issue")
            crew_release.add_argument("--flight", default="")
            crew_release.set_defaults(run=cmd_crew_release)

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
