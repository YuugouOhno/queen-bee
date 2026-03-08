#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

const PKG_DIR = path.resolve(__dirname, "..");
const COMMAND_SRC = path.join(PKG_DIR, "command", "bo.md");
const SKILLS_SRC = path.join(PKG_DIR, "skills");
const CONTEXTS_SRC = path.join(PKG_DIR, "contexts");
const HOOKS_DIR = path.join(PKG_DIR, "hooks");
const HOOK_SRC = path.join(HOOKS_DIR, "prompt-context.py");
const HOME_DIR = process.env.HOME || process.env.USERPROFILE;

// ── Helpers ──

function getProjectRoot() {
  try {
    return execSync("git rev-parse --show-toplevel", { encoding: "utf8" }).trim();
  } catch {
    console.error("Error: Not inside a git repository.");
    process.exit(1);
  }
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function copyFile(src, dest) {
  ensureDir(path.dirname(dest));
  fs.copyFileSync(src, dest);
  console.log(`  copied: ${path.relative(process.cwd(), dest)}`);
}

function copyDir(src, dest) {
  ensureDir(dest);
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);
    if (entry.isDirectory()) {
      copyDir(srcPath, destPath);
    } else {
      copyFile(srcPath, destPath);
    }
  }
}

function commandExists(cmd) {
  try {
    execSync(`command -v ${cmd}`, { encoding: "utf8", stdio: "pipe" });
    return true;
  } catch {
    return false;
  }
}

function getCommandVersion(cmd, versionFlag) {
  try {
    return execSync(`${cmd} ${versionFlag || "--version"}`, {
      encoding: "utf8",
      stdio: "pipe",
    }).trim().split("\n")[0];
  } catch {
    return null;
  }
}

// ── Prerequisites check ──

function checkPrerequisites() {
  console.log("Checking prerequisites...\n");
  let allOk = true;
  const warnings = [];

  const checks = [
    { cmd: "node", required: true, label: "Node.js", versionFlag: "--version" },
    { cmd: "git", required: true, label: "git", versionFlag: "--version" },
    { cmd: "tmux", required: true, label: "tmux", versionFlag: "-V" },
    { cmd: "python3", required: true, label: "python3", versionFlag: "--version" },
    { cmd: "claude", required: false, label: "Claude CLI", versionFlag: "--version" },
    { cmd: "gh", required: false, label: "GitHub CLI (gh)", versionFlag: "--version" },
  ];

  for (const { cmd, required, label, versionFlag } of checks) {
    if (commandExists(cmd)) {
      const ver = getCommandVersion(cmd, versionFlag) || "";
      console.log(`  [ok] ${label} (${ver})`);
    } else if (required) {
      console.log(`  [MISSING] ${label} — required`);
      allOk = false;
    } else {
      console.log(`  [warn] ${label} — not found (optional)`);
      warnings.push(label);
    }
  }

  // Node.js version check
  const nodeVersion = parseInt(process.versions.node.split(".")[0], 10);
  if (nodeVersion < 18) {
    console.log(`  [MISSING] Node.js >= 18 required (current: ${process.versions.node})`);
    allOk = false;
  }

  console.log("");

  if (!allOk) {
    console.error("Some required prerequisites are missing. Install them and try again.");
    process.exit(1);
  }

  if (warnings.length > 0) {
    console.log(`  Note: ${warnings.join(", ")} not found. Some features may not work.\n`);
  }

  return allOk;
}

// ── Hook registration ──

function resolveSettingsFile(root, mode) {
  switch (mode) {
    case "global":
      return path.join(HOME_DIR, ".claude", "settings.json");
    case "shared":
      return path.join(root, ".claude", "settings.json");
    case "local":
    default:
      return path.join(root, ".claude", "settings.local.json");
  }
}

function settingsModeLabel(mode) {
  switch (mode) {
    case "global": return "~/.claude/settings.json";
    case "shared": return ".claude/settings.json";
    case "local":
    default: return ".claude/settings.local.json";
  }
}

function upsertHook(hooks, hookType, matchStr, command, matcher) {
  if (!hooks[hookType]) hooks[hookType] = [];

  const existingIdx = hooks[hookType].findIndex((entry) => {
    // Check new format
    if (entry.hooks) {
      return entry.hooks.some((h) => h.command && h.command.includes(matchStr));
    }
    // Check old format (for migration)
    return entry.type === "command" && entry.command && entry.command.includes(matchStr);
  });

  const hookEntry = { hooks: [{ type: "command", command }] };
  if (matcher) hookEntry.matcher = matcher;

  if (existingIdx >= 0) {
    hooks[hookType][existingIdx] = hookEntry;
    return "updated";
  } else {
    hooks[hookType].push(hookEntry);
    return "added";
  }
}

function updateSettingsHook(root, mode) {
  const settingsFile = resolveSettingsFile(root, mode);
  ensureDir(path.dirname(settingsFile));

  let settings = {};
  if (fs.existsSync(settingsFile)) {
    try {
      settings = JSON.parse(fs.readFileSync(settingsFile, "utf8"));
    } catch {
      console.warn(`  warn: Could not parse ${path.basename(settingsFile)}, creating new one`);
      settings = {};
    }
  }

  if (!settings.hooks) settings.hooks = {};

  const label = settingsModeLabel(mode);

  // UserPromptSubmit: prompt-context.py
  const r1 = upsertHook(settings.hooks, "UserPromptSubmit", "prompt-context.py", `python3 ${HOOK_SRC}`);
  console.log(`  ${r1}: ${label} (UserPromptSubmit hook)`);

  fs.writeFileSync(settingsFile, JSON.stringify(settings, null, 2) + "\n");
}

// ── init ──

function init(opts) {
  checkPrerequisites();

  const root = getProjectRoot();
  const claudeDir = path.join(root, ".claude");

  console.log(`Initializing beeops in ${root}...\n`);

  // 1. Copy command
  copyFile(COMMAND_SRC, path.join(claudeDir, "commands", "bo.md"));

  // 2. Copy skills
  copyDir(
    path.join(SKILLS_SRC, "bo-dispatch"),
    path.join(claudeDir, "skills", "bo-dispatch")
  );
  copyDir(
    path.join(SKILLS_SRC, "bo-leader-dispatch"),
    path.join(claudeDir, "skills", "bo-leader-dispatch")
  );
  copyDir(
    path.join(SKILLS_SRC, "bo-task-decomposer"),
    path.join(claudeDir, "skills", "bo-task-decomposer")
  );
  copyDir(
    path.join(SKILLS_SRC, "bo-issue-sync"),
    path.join(claudeDir, "skills", "bo-issue-sync")
  );
  copyDir(
    path.join(SKILLS_SRC, "bo-review-backend"),
    path.join(claudeDir, "skills", "bo-review-backend")
  );
  copyDir(
    path.join(SKILLS_SRC, "bo-review-frontend"),
    path.join(claudeDir, "skills", "bo-review-frontend")
  );
  copyDir(
    path.join(SKILLS_SRC, "bo-review-database"),
    path.join(claudeDir, "skills", "bo-review-database")
  );
  copyDir(
    path.join(SKILLS_SRC, "bo-review-operations"),
    path.join(claudeDir, "skills", "bo-review-operations")
  );
  copyDir(
    path.join(SKILLS_SRC, "bo-review-process"),
    path.join(claudeDir, "skills", "bo-review-process")
  );
  copyDir(
    path.join(SKILLS_SRC, "bo-review-security"),
    path.join(claudeDir, "skills", "bo-review-security")
  );

  // 3. Clean up old names if exists
  for (const old of [
    "leader-dispatch", "ants-leader-dispatch", "ants-dispatch",
    "meta-task-decomposer", "orch-issue-sync", "meta-log-writer", "meta-self-improver",
    "bo-log-writer", "bo-self-improver",
    "review-backend", "review-frontend", "review-database",
    "review-operations", "review-process", "review-security",
  ]) {
    const oldDir = path.join(claudeDir, "skills", old);
    if (fs.existsSync(oldDir)) {
      fs.rmSync(oldDir, { recursive: true });
      console.log(`  removed: .claude/skills/${old}/ (migrated to bo-*)`);
    }
  }
  // Old command file
  const oldCmd = path.join(claudeDir, "commands", "ants.md");
  if (fs.existsSync(oldCmd)) {
    fs.unlinkSync(oldCmd);
    console.log("  removed: .claude/commands/ants.md (migrated to bo.md)");
  }

  // 4. Register hooks (UserPromptSubmit)
  updateSettingsHook(root, opts.hookMode);

  // 5. Save locale preference
  const boDir = path.join(claudeDir, "beeops");
  ensureDir(boDir);
  fs.writeFileSync(path.join(boDir, "locale"), opts.locale + "\n");
  console.log(`  locale: ${opts.locale} (saved to .claude/beeops/locale)`);

  // 6. Copy contexts if --with-contexts
  if (opts.withContexts) {
    const destContexts = path.join(claudeDir, "beeops", "contexts");
    copyDir(CONTEXTS_SRC, destContexts);
    console.log("\n  Contexts copied to .claude/beeops/contexts/ for customization.");
    console.log("  Edit these files to customize agent behavior.");
    console.log("  Delete a file to fall back to the package default.");
  }

  console.log("\nbeeops initialized successfully!");
  console.log("Run /bo in Claude Code to start the Queen.");
}

// ── check ──

function findHookInSettings(settingsFile, hookType, matchStr) {
  if (!fs.existsSync(settingsFile)) return null;
  try {
    const settings = JSON.parse(fs.readFileSync(settingsFile, "utf8"));
    const entries = settings.hooks?.[hookType] || [];
    const found = entries.find((entry) => {
      // New format: { matcher, hooks: [{ type, command }] }
      if (entry.hooks) {
        return entry.hooks.some((h) => h.command && h.command.includes(matchStr));
      }
      // Old format: { type, command }
      return entry.command && entry.command.includes(matchStr);
    });
    return found || null;
  } catch {
    return null;
  }
}

function check() {
  const root = getProjectRoot();
  const claudeDir = path.join(root, ".claude");
  let ok = true;

  console.log("Checking beeops setup...\n");

  // Check command
  const cmdPath = path.join(claudeDir, "commands", "bo.md");
  if (fs.existsSync(cmdPath)) {
    console.log("  [ok] .claude/commands/bo.md");
  } else {
    console.log("  [missing] .claude/commands/bo.md");
    ok = false;
  }

  // Check skills
  const CORE_SKILLS = [
    "bo-dispatch", "bo-leader-dispatch", "bo-task-decomposer", "bo-issue-sync",
    "bo-review-backend", "bo-review-frontend", "bo-review-database",
    "bo-review-operations", "bo-review-process", "bo-review-security",
  ];
  for (const skill of CORE_SKILLS) {
    const skillPath = path.join(claudeDir, "skills", skill, "SKILL.md");
    if (fs.existsSync(skillPath)) {
      console.log(`  [ok] .claude/skills/${skill}/SKILL.md`);
    } else {
      console.log(`  [missing] .claude/skills/${skill}/SKILL.md`);
      ok = false;
    }
  }

  // Check hook across all 3 settings locations
  const settingsLocations = [
    { file: path.join(claudeDir, "settings.local.json"), label: ".claude/settings.local.json" },
    { file: path.join(claudeDir, "settings.json"), label: ".claude/settings.json" },
    { file: path.join(HOME_DIR, ".claude", "settings.json"), label: "~/.claude/settings.json" },
  ];

  const HOOK_CHECKS = [
    { hookType: "UserPromptSubmit", matchStr: "prompt-context.py", label: "UserPromptSubmit" },
  ];

  for (const { hookType, matchStr, label: hookLabel } of HOOK_CHECKS) {
    let hookFound = false;
    for (const { file, label } of settingsLocations) {
      const hook = findHookInSettings(file, hookType, matchStr);
      if (hook) {
        console.log(`  [ok] ${label} (${hookLabel} hook)`);
        hookFound = true;
        break;
      }
    }
    if (!hookFound) {
      console.log(`  [missing] ${hookLabel} hook not found`);
      ok = false;
    }
  }

  // Check local contexts (informational)
  const localContexts = path.join(claudeDir, "beeops", "contexts");
  if (fs.existsSync(localContexts)) {
    const files = fs.readdirSync(localContexts);
    console.log(`  [info] .claude/beeops/contexts/ (${files.length} custom file(s))`);
  }

  // Check package resolvable
  try {
    require.resolve("beeops/package.json");
    console.log("  [ok] beeops package resolvable");
  } catch {
    console.log("  [warn] beeops package not resolvable from cwd");
  }

  console.log(ok ? "\nAll checks passed!" : "\nSome checks failed. Run: npx beeops init");
  process.exit(ok ? 0 : 1);
}

// ── Help / Version ──

function printHelp() {
  console.log("beeops — 3-layer multi-agent orchestration for Claude Code\n");
  console.log("Usage: beeops <command> [options]\n");
  console.log("Commands:");
  console.log("  init    Install beeops into the current project");
  console.log("  update  Update beeops files (same as init)");
  console.log("  check   Verify beeops setup\n");
  console.log("Options for init/update:");
  console.log("  --local          Register hook in .claude/settings.local.json (default)");
  console.log("  --shared         Register hook in .claude/settings.json (team-shared)");
  console.log("  -g, --global     Register hook in ~/.claude/settings.json (all projects)");
  console.log("  --with-contexts  Copy default contexts for customization");
  console.log("  --locale <lang>  Set locale (default: en, available: en, ja)\n");
  console.log("Examples:");
  console.log("  npx beeops init");
  console.log("  npx beeops init --shared --locale ja");
  console.log("  npx beeops init --with-contexts");
  console.log("  npx beeops check");
}

function printVersion() {
  const pkg = JSON.parse(fs.readFileSync(path.join(PKG_DIR, "package.json"), "utf8"));
  console.log(`beeops v${pkg.version}`);
}

// ── Argument parsing ──

function parseArgs(argv) {
  const args = argv.slice(2);
  const opts = {
    hookMode: "local",
    withContexts: false,
    locale: "en",
  };

  // Check for help/version flags first (anywhere in args)
  if (args.includes("-h") || args.includes("--help") || args.includes("help")) {
    printHelp();
    process.exit(0);
  }
  if (args.includes("-v") || args.includes("--version") || args.includes("version")) {
    printVersion();
    process.exit(0);
  }

  const command = args[0];

  for (let i = 1; i < args.length; i++) {
    switch (args[i]) {
      case "--global":
      case "-g":
        opts.hookMode = "global";
        break;
      case "--shared":
        opts.hookMode = "shared";
        break;
      case "--local":
        opts.hookMode = "local";
        break;
      case "--with-contexts":
        opts.withContexts = true;
        break;
      case "--locale":
        if (args[i + 1]) {
          opts.locale = args[++i];
        }
        break;
    }
  }

  return { command, opts };
}

// ── Main ──
const { command, opts } = parseArgs(process.argv);

switch (command) {
  case "init":
  case "update":
    init(opts);
    break;
  case "check":
    check();
    break;
  default:
    printHelp();
    process.exit(command ? 1 : 0);
}
