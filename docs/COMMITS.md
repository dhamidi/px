Agents: after completing a unit of work, git add your files, commit with a descriptive message (Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>), and git push.

HARD RULES learned from incidents:
- ALWAYS commit with explicit pathspecs: `git commit -m "..." -- <your files>` —
  a bare `git commit` commits the shared index, sweeping up whatever a
  concurrent agent has staged (this happened; attribution was lost).
- After any service restart, verify the SERVED hashed asset for any shared
  file you touched has non-trivial size and contains your section — a restart
  during another agent's transient working-tree state can bake a truncated
  file into the compiled assets (this happened: a 13-byte ui.css shipped).
