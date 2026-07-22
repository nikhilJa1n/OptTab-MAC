import sys
import os
import re
import json
import subprocess
from datetime import datetime

def get_git_commit_logs(version):
    current_tag = f"v{version.lstrip('v')}"
    last_tag = ""
    
    try:
        # Get list of all existing tags
        all_tags_raw = subprocess.check_output(
            ["git", "tag", "-l", "--sort=-v:refname"],
            stderr=subprocess.DEVNULL
        ).decode("utf-8").strip()
        all_tags = [t.strip() for t in all_tags_raw.split("\n") if t.strip()]
        
        # Filter out current_tag if it exists already, so we get the previous release tag
        previous_tags = [t for t in all_tags if t != current_tag]
        if previous_tags:
            last_tag = previous_tags[0]
    except Exception:
        last_tag = ""
        
    logs = ""
    if last_tag:
        try:
            cmd = ["git", "log", f"{last_tag}..HEAD", "--pretty=format:%s"]
            logs = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode("utf-8").strip()
        except Exception:
            logs = ""
            
    if not logs:
        try:
            cmd = ["git", "log", "-n", "10", "--pretty=format:%s"]
            logs = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode("utf-8").strip()
        except Exception:
            logs = ""
            
    # Filter out internal/trivial bump & script commits
    filtered = []
    seen = set()
    skip_keywords = ["bump update.json", "merge branch", "update readme", "initial commit", "automated release bump", "refactor publish_release"]
    for line in logs.split("\n"):
        line_clean = line.strip()
        if not line_clean:
            continue
        if any(skip in line_clean.lower() for skip in skip_keywords):
            continue
        if line_clean not in seen:
            seen.add(line_clean)
            filtered.append(line_clean)
            
    return "\n".join(filtered)

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 update_version_history.py <version> [notes]")
        sys.exit(1)
        
    version = sys.argv[1]
    
    # Auto-pick release notes from git commit log if not explicitly provided
    if len(sys.argv) > 2 and sys.argv[2].strip():
        raw_notes = sys.argv[2].strip()
        print(f"[Automation] Syncing provided release notes into VersionHistory.swift & update.json.")
    else:
        print(f"[Automation] Auto-picking release notes from git commit log...")
        raw_notes = get_git_commit_logs(version)
        if not raw_notes:
            raw_notes = "Performance enhancements, stability fixes, and UI improvements."
            
    date_str = datetime.now().strftime("%B %Y")
    
    # Filter out markdown section headers (e.g. ## What's New, ### Features, ### Bug Fixes)
    raw_lines = raw_notes.split("\n")
    clean_lines = []
    for l in raw_lines:
        l_str = l.strip()
        if not l_str or l_str.startswith("#"):
            continue
        l_clean = l_str.lstrip("-•* ").strip()
        if l_clean:
            clean_lines.append(l_clean)
            
    if not clean_lines:
        clean_lines = ["Performance enhancements, stability fixes, and UI improvements."]
        
    features = [l for l in clean_lines if not any(k in l.lower() for k in ["fix", "bug", "resolve", "correct"])]
    fixes = [l for l in clean_lines if any(k in l.lower() for k in ["fix", "bug", "resolve", "correct"])]
    
    if not features and not fixes:
        features = clean_lines
        
    summary = clean_lines[0] if clean_lines else f"Release version {version}."
    
    # 1. Update VersionHistory.swift
    history_swift_path = "Sources/VersionHistory.swift"
    if os.path.exists(history_swift_path):
        with open(history_swift_path, "r", encoding="utf-8") as f:
            content = f.read()
            
        # If this version block already exists, remove it first so we can replace it cleanly
        version_pattern = rf'VersionRelease\(\s*version:\s*"{re.escape(version)}".*?\),?\n'
        content = re.sub(version_pattern, '', content, flags=re.DOTALL)
        
        # Mark all remaining existing releases as isCurrent: false
        content = content.replace("isCurrent: true", "isCurrent: false")
        
        features_swift = ",\n                ".join(f'"{f}"' for f in features) if features else ""
        fixes_swift = ",\n                ".join(f'"{f}"' for f in fixes) if fixes else ""
        
        new_entry = f'''        VersionRelease(
            version: "{version}",
            releaseDate: "{date_str}",
            isCurrent: true,
            summary: "{summary}",
            features: [
                {features_swift}
            ],
            fixes: [
                {fixes_swift}
            ]
        ),'''
        
        target = "static let releases: [VersionRelease] = ["
        if target in content:
            content = content.replace(target, f"{target}\n{new_entry}")
            with open(history_swift_path, "w", encoding="utf-8") as f:
                f.write(content)
            print(f"[Automation] Updated {history_swift_path} for version {version}")

    # 2. Update update.json
    update_json_path = "update.json"
    changelog_str = "\n".join(f"• {l}" for l in clean_lines)
    update_data = {
        "version": version,
        "downloadUrl": f"https://github.com/nikhilJa1n/OptTab-MAC/releases/download/v{version}/OptTab.dmg",
        "changelog": changelog_str
    }
    with open(update_json_path, "w", encoding="utf-8") as f:
        json.dump(update_data, f, indent=2)
    print(f"[Automation] Updated {update_json_path} for version {version}")

    # 3. Update RELEASE_NOTES.md for GitHub Release Notes Body
    release_notes_md_path = "RELEASE_NOTES.md"
    md_content = f"## What's New in v{version}\n\n"
    if features:
        md_content += "### 🌟 Features & Improvements\n"
        for item in features:
            md_content += f"- {item}\n"
        md_content += "\n"
    if fixes:
        md_content += "### 🛠️ Bug Fixes\n"
        for item in fixes:
            md_content += f"- {item}\n"
        md_content += "\n"
        
    with open(release_notes_md_path, "w", encoding="utf-8") as f:
        f.write(md_content)
    print(f"[Automation] Updated {release_notes_md_path} for version {version}")

if __name__ == "__main__":
    main()
