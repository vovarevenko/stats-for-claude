#!/usr/bin/env python3
"""
Injects Localizable.xcstrings into the xcodegen-generated pbxproj.
Run after every `xcodegen generate`:  python3 scripts/add_xcstrings.py
"""
import re, uuid, sys, os

# When called from Xcode pre-action, CWD is /tmp — use SRCROOT or script location.
_root = os.environ.get("SRCROOT") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJ  = os.path.join(_root, "StatsForClaude.xcodeproj", "project.pbxproj")
FILE_PATH = "StatsForClaude/Resources/Localizable.xcstrings"
FILE_TYPE = "text.xml.xcstrings"
LABEL     = "Localizable.xcstrings"
TARGET    = "StatsForClaude"   # PBXNativeTarget name to patch


def gen_id() -> str:
    return uuid.uuid4().hex[:24].upper()


def patch(content: str) -> str:
    if LABEL in content:
        print("Already patched — skipping.")
        return content

    file_ref_id    = gen_id()
    build_file_id  = gen_id()
    resources_phase_id = gen_id()

    # ── 1. PBXFileReference ──────────────────────────────────────────────────
    content = content.replace(
        "/* End PBXFileReference section */",
        (f'\t\t{file_ref_id} /* {LABEL} */ = {{'
         f'isa = PBXFileReference; lastKnownFileType = {FILE_TYPE}; '
         f'name = {LABEL}; path = "{FILE_PATH}"; sourceTree = "<group>"; }};\n'
         f'\t\t/* End PBXFileReference section */')
    )

    # ── 2. PBXBuildFile ──────────────────────────────────────────────────────
    content = content.replace(
        "/* End PBXBuildFile section */",
        (f'\t\t{build_file_id} /* {LABEL} in Resources */ = {{'
         f'isa = PBXBuildFile; fileRef = {file_ref_id} /* {LABEL} */; }};\n'
         f'\t\t/* End PBXBuildFile section */')
    )

    # ── 3. Create PBXResourcesBuildPhase section ─────────────────────────────
    resources_phase_block = (
        f'\n/* Begin PBXResourcesBuildPhase section */\n'
        f'\t\t{resources_phase_id} /* Resources */ = {{\n'
        f'\t\t\tisa = PBXResourcesBuildPhase;\n'
        f'\t\t\tbuildActionMask = 2147483647;\n'
        f'\t\t\tfiles = (\n'
        f'\t\t\t\t{build_file_id} /* {LABEL} in Resources */,\n'
        f'\t\t\t);\n'
        f'\t\t\trunOnlyForDeploymentPostprocessing = 0;\n'
        f'\t\t}};\n'
        f'/* End PBXResourcesBuildPhase section */\n'
    )

    # Insert after Frameworks build phase section
    content = content.replace(
        "/* End PBXFrameworksBuildPhase section */",
        "/* End PBXFrameworksBuildPhase section */" + resources_phase_block
    )

    # ── 4. Inject phase UUID into the StatsForClaude target buildPhases ───────
    # Find the target block by name
    target_pattern = re.compile(
        r'(name = ' + re.escape(TARGET) + r';.*?buildPhases = \(\n)(.*?)(\t\t\t\);)',
        re.DOTALL
    )

    def add_phase(m: re.Match) -> str:
        current_phases = m.group(2)
        # Only add if not already present
        if resources_phase_id in current_phases:
            return m.group(0)
        insertion = f'\t\t\t\t{resources_phase_id} /* Resources */,\n'
        return m.group(1) + current_phases + insertion + m.group(3)

    # We need to find the target by searching for its name in the right context
    # The PBXNativeTarget block pattern
    native_target_pattern = re.compile(
        r'(F228BBF7\w+ /\* StatsForClaude \*/ = \{\s*isa = PBXNativeTarget;.*?buildPhases = \(\n)(.*?)(\t\t\t\);)',
        re.DOTALL
    )

    # More robust: find by "name = StatsForClaude;" within a PBXNativeTarget block
    # Strategy: find all PBXNativeTarget blocks, pick the one with "name = StatsForClaude;"
    all_targets = list(re.finditer(
        r'(/\* StatsForClaude \*/ = \{[^}]*?isa = PBXNativeTarget;.*?buildPhases = \(\n)(.*?)(\t\t\t\);)',
        content, re.DOTALL
    ))

    if not all_targets:
        # Fallback: any target with buildPhases that doesn't have Resources yet
        all_targets = list(re.finditer(
            r'(isa = PBXNativeTarget;.*?name = StatsForClaude;.*?buildPhases = \(\n)(.*?)(\t\t\t\);)',
            content, re.DOTALL
        ))

    if all_targets:
        m = all_targets[-1]   # last match = StatsForClaude (not Widget)
        insertion = f'\t\t\t\t{resources_phase_id} /* Resources */,\n'
        old = m.group(0)
        new = m.group(1) + m.group(2) + insertion + m.group(3)
        content = content[:m.start()] + new + content[m.end():]
    else:
        print("WARNING: Could not locate StatsForClaude buildPhases — add resources phase manually.", file=sys.stderr)

    return content


if __name__ == "__main__":
    with open(PROJ, "r", encoding="utf-8") as f:
        original = f.read()

    patched = patch(original)

    if patched != original:
        with open(PROJ, "w", encoding="utf-8") as f:
            f.write(patched)
        print(f"✓ Patched {PROJ} — added {LABEL} + PBXResourcesBuildPhase")
    else:
        print("No changes made.")
