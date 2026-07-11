#!/usr/bin/env python3
"""sync-okf-skills.py — mirror knowledge/{skills,agent-rules}/*.md into .omp/skills/
for native omp discovery (program.md §9/§11). stdlib-only.

Two source classes, handled differently (program.md §11.2-11.3):

- EMBEDDED: the knowledge/ file already carries a native `name:`/`description:`
  frontmatter block right after the OKF wrapper (imported verbatim from a real
  SKILL.md). knowledge/ is the source of truth for these — regenerated
  deterministically on every run, overwriting .omp/skills/<name>/SKILL.md.
- BARE: the knowledge/ file has no embedded native frontmatter (AGENTS.md/
  CLAUDE.md-style imports, manual profile docs). These require synthesized
  frontmatter and sometimes light manual fixes an LLM made once — a script
  cannot safely reproduce that. .omp/skills/<name>/SKILL.md is the source of
  truth for these once it exists; this script NEVER writes or overwrites them,
  it only reports drift/gaps against BARE_MANIFEST.

Run from repo root or anywhere (path is self-relative). Exit 0 always (informational
tool); commit/push is sync-skills.sh's job.
"""
import os
import re
import sys

REPO = os.path.dirname(os.path.abspath(__file__))
KNOWLEDGE_DIRS = [
    ("skills", os.path.join(REPO, "knowledge", "skills")),
    ("agent-rules", os.path.join(REPO, "knowledge", "agent-rules")),
]
DEST = os.path.join(REPO, ".omp", "skills")

# Known BARE-class sources -> the .omp/skills/<name> they were synthesized into.
# New bare files not listed here are flagged as needing manual synthesis +
# registration (see skill://okf-to-native-skill-migration).
BARE_MANIFEST = {
    "skills/meridian.md": "meridian",
    "agent-rules/agent-skills-repo-agents.md": "agent-skills-repo-agent-rules",
    "agent-rules/agent-skills-repo-claude.md": "agent-skills-repo-conventions",
    "agent-rules/codex-agents.md": "codex-codegraph-rules",
    "agent-rules/hermes-agent-agents.md": "hermes-agent-framework-guide",
    "agent-rules/hermes-agents.md": "hermes-runtime-rules",
    "agent-rules/meridian-claude.md": "meridian-bot-engineering-manual",
    "agent-rules/miftahudin-profile.md": "miftahudin-admin-profile",
}


def detect(path):
    """Return ('embedded', name, body) | ('bare', None, None) | None (unparsable)."""
    text = open(path, encoding="utf-8").read()
    lines = text.split("\n")
    if not lines or lines[0].strip() != "---":
        return None
    try:
        okf_close = next(i for i in range(1, len(lines)) if lines[i].strip() == "---")
    except StopIteration:
        return None
    i = okf_close + 1
    blanks = 0
    while i < len(lines) and lines[i].strip() == "" and blanks < 2:
        i += 1
        blanks += 1
    if i < len(lines) and lines[i].strip() == "---":
        try:
            native_close = next(j for j in range(i + 1, len(lines)) if lines[j].strip() == "---")
        except StopIteration:
            return None
        name = None
        for l in lines[i + 1:native_close]:
            m = re.match(r"^name:\s*(.+)$", l.strip())
            if m:
                name = m.group(1).strip()
        if not name:
            return None
        body = "\n".join(lines[i:]).lstrip("\n")
        if not body.endswith("\n"):
            body += "\n"
        return ("embedded", name, body)
    return ("bare", None, None)


def main():
    regenerated = []
    unchanged = 0
    bare_missing = []
    bare_unregistered = []

    for prefix, d in KNOWLEDGE_DIRS:
        if not os.path.isdir(d):
            continue
        for fname in sorted(os.listdir(d)):
            if not fname.endswith(".md"):
                continue
            path = os.path.join(d, fname)
            rel = f"{prefix}/{fname}"
            result = detect(path)
            if result is None:
                continue
            kind, name, body = result

            if kind == "embedded":
                dest_dir = os.path.join(DEST, name)
                dest_path = os.path.join(dest_dir, "SKILL.md")
                existing = open(dest_path, encoding="utf-8").read() if os.path.exists(dest_path) else None
                if existing != body:
                    os.makedirs(dest_dir, exist_ok=True)
                    with open(dest_path, "w", encoding="utf-8") as f:
                        f.write(body)
                    regenerated.append(name)
                else:
                    unchanged += 1
            else:
                mapped = BARE_MANIFEST.get(rel)
                if mapped is None:
                    bare_unregistered.append(rel)
                elif not os.path.exists(os.path.join(DEST, mapped, "SKILL.md")):
                    bare_missing.append((rel, mapped))

    if regenerated:
        print(f"Regenerated {len(regenerated)} embedded-class skill(s): {', '.join(regenerated)}")
    else:
        print(f"No embedded-class changes ({unchanged} already up to date).")

    if bare_missing:
        print(f"WARN: {len(bare_missing)} bare-class skill(s) missing their .omp/skills/ entry "
              f"(needs manual synthesis, see skill://okf-to-native-skill-migration):")
        for rel, mapped in bare_missing:
            print(f"  - knowledge/{rel} -> .omp/skills/{mapped}/SKILL.md")

    if bare_unregistered:
        print(f"WARN: {len(bare_unregistered)} new bare-class knowledge file(s) not in BARE_MANIFEST "
              f"(needs manual synthesis + registration in sync-okf-skills.py):")
        for rel in bare_unregistered:
            print(f"  - knowledge/{rel}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
