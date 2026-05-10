---
title: Privacy Policy
---

# Privacy Policy

**Effective date:** 2026-05-11

Stats for Claude ("the App") is a macOS menu-bar utility that displays your Claude Code usage. This document explains what the App does with your data.

## Summary

**The App collects no data and sends no data to the author or any third party.**

It reads files and credentials on your own machine, makes a single network request to Anthropic's API using your own credentials, and displays the result. Nothing else happens.

## What the App accesses on your device

- **`~/.claude/projects/*.jsonl`** — Claude Code's local session logs. You explicitly grant access during onboarding via a standard macOS file-picker. The grant is stored as a security-scoped bookmark and used only to read those files.
- **Claude Code OAuth token** — read from the macOS Keychain entry created by the Claude Code CLI (service: `Claude Code-credentials`). The token never leaves your device except as described below.

## What leaves your device

- One HTTPS request per minute to `https://api.anthropic.com/api/oauth/usage`, authenticated with **your own** Claude Code OAuth token, to fetch your usage data. This request goes directly to Anthropic, not to the author. Anthropic's handling of this data is governed by [Anthropic's Privacy Policy](https://www.anthropic.com/legal/privacy).

That is the only outbound network traffic the App initiates.

## What the App does NOT do

- No analytics, telemetry, or usage tracking.
- No crash reporting to the author.
- No advertising identifiers.
- No third-party SDKs that collect data.
- No data is uploaded to the author or to any server the author controls.

## App Sandbox

The App runs inside the macOS App Sandbox with a minimal entitlement set: user-selected read-only file access, scoped bookmarks, network client, and an App Group for sharing cached state with future widget extensions. It cannot access any data you have not explicitly granted.

## Children

The App is rated 4+ on the App Store. It does not knowingly collect data from anyone, including children.

## Changes to this policy

If this policy changes, the new version will be published at the same URL with an updated effective date. The history is also available in the [GitHub repository](https://github.com/vovarevenko/stats-for-claude/commits/main/docs/privacy.md).

## Contact

Open an issue at [github.com/vovarevenko/stats-for-claude/issues](https://github.com/vovarevenko/stats-for-claude/issues).
