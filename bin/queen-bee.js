#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

const PKG_DIR = path.resolve(__dirname, "..");
const COMMAND_SRC = path.join(PKG_DIR, "command", "qb.md");
const SKILLS_SRC = path.join(PKG_DIR, "skills");
const CONTEXTS_SRC = path.join(PKG_DIR, "contexts");
const HOOK_SRC = path.join(PKG_DIR, "hooks", "prompt-context.py");
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
  if (!settings.hooks.UserPromptSubmit) settings.hooks.UserPromptSubmit = [];

  const hookCommand = `python3 ${HOOK_SRC}`;
  const existingIdx = settings.hooks.UserPromptSubmit.findIndex(
    (h) => h.type === "command" && h.command && h.command.includes("prompt-context.py")
  );

  const hookEntry = {
    type: "command",
    command: hookCommand,
  };

  const label = settingsModeLabel(mode);
  if (existingIdx >= 0) {
    settings.hooks.UserPromptSubmit[existingIdx] = hookEntry;
    console.log(`  updated: ${label} (hook updated)`);
  } else {
    settings.hooks.UserPromptSubmit.push(hookEntry);
    console.log(`  added: ${label} (hook registered)`);
  }

  fs.writeFileSync(settingsFile, JSON.stringify(settings, null, 2) + "\n");
}

// ── init ──

function init(opts) {
  checkPrerequisites();

  const root = getProjectRoot();
  const claudeDir = path.join(root, ".claude");

  console.log(`Initializing queen-bee in ${root}...\n`);

  // 1. Copy command
  copyFile(COMMAND_SRC, path.join(claudeDir, "commands", "qb.md"));

  // 2. Copy skills
  copyDir(
    path.join(SKILLS_SRC, "qb-dispatch"),
    path.join(claudeDir, "skills", "qb-dispatch")
  );
  copyDir(
    path.join(SKILLS_SRC, "qb-leader-dispatch"),
    path.join(claudeDir, "skills", "qb-leader-dispatch")
  );
  copyDir(
    path.join(SKILLS_SRC, "meta-task-decomposer"),
    path.join(claudeDir, "skills", "meta-task-decomposer")
  );
  copyDir(
    path.join(SKILLS_SRC, "orch-issue-sync"),
    path.join(claudeDir, "skills", "orch-issue-sync")
  );

  // 3. Clean up old names if exists
  for (const old of ["leader-dispatch", "ants-leader-dispatch", "ants-dispatch"]) {
    const oldDir = path.join(claudeDir, "skills", old);
    if (fs.existsSync(oldDir)) {
      fs.rmSync(oldDir, { recursive: true });
      console.log(`  removed: .claude/skills/${old}/ (migrated to qb-*)`);
    }
  }
  // Old command file
  const oldCmd = path.join(claudeDir, "commands", "ants.md");
  if (fs.existsSync(oldCmd)) {
    fs.unlinkSync(oldCmd);
    console.log("  removed: .claude/commands/ants.md (migrated to qb.md)");
  }

  // 4. Register hook
  updateSettingsHook(root, opts.hookMode);

  // 5. Save locale preference
  const qbDir = path.join(claudeDir, "queen-bee");
  ensureDir(qbDir);
  fs.writeFileSync(path.join(qbDir, "locale"), opts.locale + "\n");
  console.log(`  locale: ${opts.locale} (saved to .claude/queen-bee/locale)`);

  // 6. Copy contexts if --with-contexts
  if (opts.withContexts) {
    const destContexts = path.join(claudeDir, "queen-bee", "contexts");
    copyDir(CONTEXTS_SRC, destContexts);
    console.log("\n  Contexts copied to .claude/queen-bee/contexts/ for customization.");
    console.log("  Edit these files to customize agent behavior.");
    console.log("  Delete a file to fall back to the package default.");
  }

  console.log("\nqueen-bee initialized successfully!");
  console.log("Run /qb in Claude Code to start the Queen.");
}

// ── check ──

function findHookInSettings(settingsFile) {
  if (!fs.existsSync(settingsFile)) return null;
  try {
    const settings = JSON.parse(fs.readFileSync(settingsFile, "utf8"));
    const hooks = settings.hooks?.UserPromptSubmit || [];
    const found = hooks.find(
      (h) => h.command && h.command.includes("prompt-context.py")
    );
    return found || null;
  } catch {
    return null;
  }
}

function check() {
  const root = getProjectRoot();
  const claudeDir = path.join(root, ".claude");
  let ok = true;

  console.log("Checking queen-bee setup...\n");

  // Check command
  const cmdPath = path.join(claudeDir, "commands", "qb.md");
  if (fs.existsSync(cmdPath)) {
    console.log("  [ok] .claude/commands/qb.md");
  } else {
    console.log("  [missing] .claude/commands/qb.md");
    ok = false;
  }

  // Check skills
  for (const skill of ["qb-dispatch", "qb-leader-dispatch", "meta-task-decomposer", "orch-issue-sync"]) {
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

  let hookFound = false;
  for (const { file, label } of settingsLocations) {
    const hook = findHookInSettings(file);
    if (hook) {
      console.log(`  [ok] ${label} (hook registered)`);
      hookFound = true;
      break;
    }
  }
  if (!hookFound) {
    console.log("  [missing] hook not found in any settings file");
    ok = false;
  }

  // Check local contexts (informational)
  const localContexts = path.join(claudeDir, "queen-bee", "contexts");
  if (fs.existsSync(localContexts)) {
    const files = fs.readdirSync(localContexts);
    console.log(`  [info] .claude/queen-bee/contexts/ (${files.length} custom file(s))`);
  }

  // Check package resolvable
  try {
    require.resolve("queen-bee/package.json");
    console.log("  [ok] queen-bee package resolvable");
  } catch {
    console.log("  [warn] queen-bee package not resolvable from cwd");
  }

  console.log(ok ? "\nAll checks passed!" : "\nSome checks failed. Run: npx queen-bee init");
  process.exit(ok ? 0 : 1);
}

// ── Argument parsing ──

function parseArgs(argv) {
  const args = argv.slice(2);
  const command = args[0];
  const opts = {
    hookMode: "local",
    withContexts: false,
    locale: "en",
  };

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
    console.log("Usage: queen-bee <command> [options]\n");
    console.log("Commands:");
    console.log("  init    Install queen-bee into the current project");
    console.log("  update  Update queen-bee files (same as init)");
    console.log("  check   Verify queen-bee setup\n");
    console.log("Options for init/update:");
    console.log("  --local          Register hook in .claude/settings.local.json (default)");
    console.log("  --shared         Register hook in .claude/settings.json (team-shared)");
    console.log("  -g, --global     Register hook in ~/.claude/settings.json (all projects)");
    console.log("  --with-contexts  Copy default contexts to .claude/queen-bee/contexts/ for customization");
    console.log("  --locale <lang>  Set locale for agent prompts (default: en, available: en, ja)");
    process.exit(command ? 1 : 0);
}
