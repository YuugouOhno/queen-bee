#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

const PKG_DIR = path.resolve(__dirname, "..");
const SKILLS_SRC = path.join(PKG_DIR, "skills");
const COMMAND_SRC_DIR = path.join(PKG_DIR, "command");
const CONTEXTS_SRC = path.join(PKG_DIR, "contexts");
const HOOKS_DIR = path.join(PKG_DIR, "hooks");
const HOOK_SRC = path.join(HOOKS_DIR, "bo-prompt-context.py");
const HOME_DIR = process.env.HOME || process.env.USERPROFILE;

const SKILL_NAMES = [
  "bee-dispatch", "bee-leader-dispatch", "bee-task-decomposer", "bee-issue-sync",
  "bee-review-backend", "bee-review-frontend", "bee-review-database",
  "bee-review-operations", "bee-review-process", "bee-review-security",
];

function resolveSkillSrc(skillName, locale) {
  const localePath = path.join(SKILLS_SRC, locale, skillName);
  if (fs.existsSync(localePath)) return localePath;
  const enPath = path.join(SKILLS_SRC, "en", skillName);
  if (fs.existsSync(enPath)) return enPath;
  return path.join(SKILLS_SRC, skillName); // root fallback (backward compat)
}

function resolveCommandSrc(locale) {
  const localePath = path.join(COMMAND_SRC_DIR, locale, "bee-dev.md");
  if (fs.existsSync(localePath)) return localePath;
  const enPath = path.join(COMMAND_SRC_DIR, "en", "bee-dev.md");
  if (fs.existsSync(enPath)) return enPath;
  return path.join(COMMAND_SRC_DIR, "bee-dev.md"); // root fallback
}

function resolveContentCommandSrc(locale) {
  const localePath = path.join(COMMAND_SRC_DIR, locale, "bee-content.md");
  if (fs.existsSync(localePath)) return localePath;
  const enPath = path.join(COMMAND_SRC_DIR, "en", "bee-content.md");
  if (fs.existsSync(enPath)) return enPath;
  return path.join(COMMAND_SRC_DIR, "bee-content.md"); // root fallback (backward compat)
}

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

// ── .gitignore management ──

// Always ignore: runtime artifacts generated during /bo execution
const GITIGNORE_ALWAYS = [
  "queue.yaml",
  ".beeops/tasks/",
  ".beeops/worktrees/",
];

// Ignore only for personal (local/global) installs.
// --shared installs track these files so the whole team gets them.
const GITIGNORE_LOCAL = [
  ".claude/commands/bee-dev.md",
  ".claude/skills/bo-*/",
  ".beeops/locale",
];

function updateGitignore(root, hookMode) {
  const gitignorePath = path.join(root, ".gitignore");
  let content = "";
  if (fs.existsSync(gitignorePath)) {
    content = fs.readFileSync(gitignorePath, "utf8");
  }

  const entries = hookMode === "shared"
    ? GITIGNORE_ALWAYS
    : [...GITIGNORE_ALWAYS, ...GITIGNORE_LOCAL];

  const lines = content.split("\n");
  const missing = entries.filter((entry) => !lines.some((line) => line.trim() === entry));

  if (missing.length === 0) return;

  const block = "\n# beeops\n" + missing.join("\n") + "\n";
  fs.writeFileSync(gitignorePath, content.trimEnd() + block);
  for (const entry of missing) {
    console.log(`  gitignore: added ${entry}`);
  }
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

  // Migrate old hook name (prompt-context.py → bo-prompt-context.py)
  if (settings.hooks.UserPromptSubmit) {
    const oldIdx = settings.hooks.UserPromptSubmit.findIndex((entry) => {
      if (entry.hooks) {
        return entry.hooks.some((h) => h.command && h.command.includes("prompt-context.py") && h.command.includes("beeops"));
      }
      return entry.command && entry.command.includes("prompt-context.py") && entry.command.includes("beeops");
    });
    if (oldIdx >= 0) {
      settings.hooks.UserPromptSubmit.splice(oldIdx, 1);
      console.log(`  migrated: removed old prompt-context.py hook`);
    }
  }

  // UserPromptSubmit: bo-prompt-context.py
  // Resolve path at runtime; silently skip if beeops is not installed in the project
  const hookCommand = `_BO=$(node -p "require('path').dirname(require.resolve('beeops/package.json'))" 2>/dev/null) && python3 "$_BO/hooks/bo-prompt-context.py" || true`;
  const r1 = upsertHook(settings.hooks, "UserPromptSubmit", "bo-prompt-context.py", hookCommand);
  console.log(`  ${r1}: ${label} (UserPromptSubmit hook)`);

  fs.writeFileSync(settingsFile, JSON.stringify(settings, null, 2) + "\n");
}

// ── Beeops settings helpers ──

function readBeeopsSettings(root) {
  const file = path.join(root, ".beeops", "settings.json");
  if (!fs.existsSync(file)) return {};
  try {
    return JSON.parse(fs.readFileSync(file, "utf8"));
  } catch {
    return {};
  }
}

function readLocale(root) {
  const localeFile = path.join(root, ".beeops", "locale");
  if (fs.existsSync(localeFile)) {
    return fs.readFileSync(localeFile, "utf8").trim();
  }
  return "en";
}

function detectGithubUsername() {
  try {
    return execSync("gh api user --jq .login", { encoding: "utf8", stdio: "pipe" }).trim();
  } catch {
    try {
      return execSync("git config github.user", { encoding: "utf8", stdio: "pipe" }).trim();
    } catch {
      return "";
    }
  }
}

function writeDefaultSettings(root) {
  const file = path.join(root, ".beeops", "settings.json");
  if (fs.existsSync(file)) {
    console.log(`  settings: .beeops/settings.json already exists, skipping`);
    return;
  }
  const github_username = detectGithubUsername();
  const defaults = {
    assignee: github_username || "all",
    github_username,
    priority: "low",
    skip_review: false,
    max_parallel_leaders: 2,
  };
  ensureDir(path.dirname(file));
  fs.writeFileSync(file, JSON.stringify(defaults, null, 2) + "\n");
  console.log(`  created: .beeops/settings.json (edit to customize /bo behavior)`);
  if (github_username) {
    console.log(`  github_username: detected as '${github_username}'`);
  } else {
    console.log(`  github_username: not detected — set it manually in .beeops/settings.json`);
  }
}

// ── init ──

function addToProtect(root, key) {
  const file = path.join(root, ".beeops", "settings.json");
  const settings = readBeeopsSettings(root);
  const protect = Array.isArray(settings.protect) ? settings.protect : [];
  if (!protect.includes(key)) {
    protect.push(key);
    settings.protect = protect;
    ensureDir(path.dirname(file));
    fs.writeFileSync(file, JSON.stringify(settings, null, 2) + "\n");
    console.log(`  added "${key}" to protect in .beeops/settings.json`);
  }
}

async function confirmOverwrite(rl, label, protectKey) {
  const answer = (await rl.question(`  Overwrite ${label}? [Y/n/protect]: `)).trim().toLowerCase();
  if (answer === "n" || answer === "no") {
    return { skip: true, addProtect: false };
  }
  if (answer === "protect" || answer === "p") {
    return { skip: true, addProtect: true };
  }
  return { skip: false, addProtect: false }; // Y / Enter = yes
}

async function initCore(root, opts) {
  const claudeDir = path.join(root, ".claude");
  const isFirstInit = !fs.existsSync(path.join(claudeDir, "commands", "bee-dev.md")) &&
    !fs.existsSync(path.join(claudeDir, "commands", "bo.md"));
  const settings = readBeeopsSettings(root);
  const protect = Array.isArray(settings.protect) ? settings.protect : [];

  function isProtected(key) {
    return protect.some((p) => p === key || key.startsWith(p + "/"));
  }

  // Set up interactive readline for update confirmations (TTY only)
  let rl = null;
  const interactive = !isFirstInit && process.stdin.isTTY;
  if (interactive) {
    const { createInterface } = await import("readline/promises");
    rl = createInterface({ input: process.stdin, output: process.stdout });
    console.log("  [update] Updating existing beeops installation.");
    if (protect.length > 0) {
      console.log(`  [protect] Protected (will be skipped): ${protect.join(", ")}`);
    }
    console.log(`\n  For each existing file you can answer:`);
    console.log(`    Y / Enter  = overwrite`);
    console.log(`    n          = skip this time`);
    console.log(`    protect    = skip and add to protect (never overwrite again)\n`);
  } else if (!isFirstInit) {
    console.log("  [update] Updating existing beeops installation.\n");
    if (protect.length > 0) {
      console.log(`  [protect] Protected (will be skipped): ${protect.join(", ")}\n`);
    }
  }

  // 1. Copy command (locale-aware)
  // Migrate: remove old bo.md if bee-dev.md doesn't exist yet
  const oldCmdPath = path.join(claudeDir, "commands", "bo.md");
  const newCmdPath = path.join(claudeDir, "commands", "bee-dev.md");
  if (fs.existsSync(oldCmdPath) && !fs.existsSync(newCmdPath)) {
    fs.unlinkSync(oldCmdPath);
    console.log(`  migrated: removed .claude/commands/bo.md`);
  }
  if (isProtected("command")) {
    console.log(`  protected: .claude/commands/bee-dev.md (skipped)`);
  } else if (!isFirstInit && fs.existsSync(newCmdPath)) {
    if (interactive) {
      const { skip, addProtect } = await confirmOverwrite(rl, ".claude/commands/bee-dev.md", "command");
      if (addProtect) addToProtect(root, "command");
      if (!skip) copyFile(resolveCommandSrc(opts.locale), newCmdPath);
      else console.log(`  skipped: .claude/commands/bee-dev.md`);
    } else {
      copyFile(resolveCommandSrc(opts.locale), newCmdPath);
    }
  } else {
    copyFile(resolveCommandSrc(opts.locale), newCmdPath);
  }

  // 1b. Copy bee-content command (locale-aware)
  if (isProtected("command")) {
    console.log(`  protected: .claude/commands/bee-content.md (skipped)`);
  } else if (!isFirstInit && fs.existsSync(path.join(claudeDir, "commands", "bee-content.md"))) {
    if (interactive) {
      const { skip, addProtect } = await confirmOverwrite(rl, ".claude/commands/bee-content.md", "command");
      if (!skip) copyFile(resolveContentCommandSrc(opts.locale), path.join(claudeDir, "commands", "bee-content.md"));
      else console.log(`  skipped: .claude/commands/bee-content.md`);
    } else {
      copyFile(resolveContentCommandSrc(opts.locale), path.join(claudeDir, "commands", "bee-content.md"));
    }
  } else {
    copyFile(resolveContentCommandSrc(opts.locale), path.join(claudeDir, "commands", "bee-content.md"));
  }

  // 2. Copy skills (locale-aware)
  // Group: ask once for "skills" category if any exist
  const existingSkills = SKILL_NAMES.filter(
    (s) => !isProtected("skills") && !isProtected(`skills/${s}`) &&
      !isFirstInit && fs.existsSync(path.join(claudeDir, "skills", s, "SKILL.md"))
  );
  let skipAllSkills = false;
  if (interactive && existingSkills.length > 0) {
    console.log(`  The following skills already exist:`);
    existingSkills.forEach((s) => console.log(`    .claude/skills/${s}/SKILL.md`));
    const answer = (await rl.question(`  Overwrite all skills? [Y/n/protect]: `)).trim().toLowerCase();
    if (answer === "n" || answer === "no") {
      skipAllSkills = true;
      console.log(`  skipped: all skills`);
    } else if (answer === "protect" || answer === "p") {
      skipAllSkills = true;
      addToProtect(root, "skills");
    }
  }

  // Migrate legacy bo-* skill directories to bee-*
  const LEGACY_SKILL_NAMES = [
    "bo-dispatch", "bo-leader-dispatch", "bo-task-decomposer", "bo-issue-sync",
    "bo-review-backend", "bo-review-frontend", "bo-review-database",
    "bo-review-operations", "bo-review-process", "bo-review-security",
  ];
  for (const legacySkill of LEGACY_SKILL_NAMES) {
    const legacyPath = path.join(claudeDir, "skills", legacySkill);
    if (fs.existsSync(legacyPath)) {
      const newSkill = legacySkill.replace(/^bo-/, "bee-");
      const newPath = path.join(claudeDir, "skills", newSkill);
      fs.rmSync(legacyPath, { recursive: true });
      console.log(`  migrated: .claude/skills/${legacySkill}/ → ${newSkill}/`);
    }
  }

  for (const skill of SKILL_NAMES) {
    const skillKey = `skills/${skill}`;
    if (isProtected("skills") || isProtected(skillKey)) {
      console.log(`  protected: .claude/skills/${skill}/ (skipped)`);
    } else if (skipAllSkills && existingSkills.includes(skill)) {
      // already handled above
    } else {
      copyDir(resolveSkillSrc(skill, opts.locale), path.join(claudeDir, "skills", skill));
    }
  }

  // 3. Clean up removed beeops skills if exists
  for (const old of ["bo-log-writer", "bo-self-improver"]) {
    const oldDir = path.join(claudeDir, "skills", old);
    if (fs.existsSync(oldDir)) {
      fs.rmSync(oldDir, { recursive: true });
      console.log(`  removed: .claude/skills/${old}/ (no longer included)`);
    }
  }

  // 4. Update .gitignore (runtime artifacts should not be tracked)
  updateGitignore(root, opts.hookMode);

  // 5. Register hooks (UserPromptSubmit)
  updateSettingsHook(root, opts.hookMode);

  // 6. Save locale preference
  const boDir = path.join(root, ".beeops");
  ensureDir(boDir);
  fs.writeFileSync(path.join(boDir, "locale"), opts.locale + "\n");
  console.log(`  locale: ${opts.locale} (saved to .beeops/locale)`);

  // 7. Write default settings.json (only on first init)
  writeDefaultSettings(root);

  // 8. Copy contexts if --with-contexts
  if (opts.withContexts) {
    const destContexts = path.join(root, ".beeops", "contexts");
    if (isProtected("contexts")) {
      console.log(`  protected: .beeops/contexts/ (skipped)`);
    } else if (!isFirstInit && fs.existsSync(destContexts)) {
      if (interactive) {
        const { skip, addProtect } = await confirmOverwrite(rl, ".beeops/contexts/", "contexts");
        if (addProtect) addToProtect(root, "contexts");
        if (!skip) {
          copyDir(CONTEXTS_SRC, destContexts);
          console.log("  Contexts copied. Edit files to customize agent behavior.");
        } else {
          console.log(`  skipped: .beeops/contexts/`);
        }
      } else {
        copyDir(CONTEXTS_SRC, destContexts);
        console.log("  Contexts copied. Edit files to customize agent behavior.");
      }
    } else {
      copyDir(CONTEXTS_SRC, destContexts);
      console.log("\n  Contexts copied to .beeops/contexts/ for customization.");
      console.log("  Edit these files to customize agent behavior.");
      console.log("  Delete a file to fall back to the package default.");
    }
  }

  if (rl) rl.close();
}

function printSettingsSummary(root) {
  const file = path.join(root, ".beeops", "settings.json");
  if (!fs.existsSync(file)) return;
  const settings = readBeeopsSettings(root);
  console.log("\nCurrent settings (.beeops/settings.json):");
  for (const [k, v] of Object.entries(settings)) {
    console.log(`  ${k}: ${JSON.stringify(v)}`);
  }
  console.log("\nTo change these, edit .beeops/settings.json directly.");
  console.log('To protect files from future updates, add "protect" to settings.json:');
  console.log('  "protect": ["skills", "command", "contexts"]');
}

async function init(opts) {
  checkPrerequisites();

  const root = getProjectRoot();
  console.log(`Initializing beeops in ${root}...\n`);

  // Interactive locale confirmation (TTY only, skip if --locale was explicitly passed)
  if (!opts._localeExplicit && process.stdin.isTTY) {
    const { createInterface } = await import("readline/promises");
    const rl = createInterface({ input: process.stdin, output: process.stdout });
    const detected = opts.locale;
    const answer = (await rl.question(
      `  Locale detected: ${detected}. Press Enter to use it, or type another (${SUPPORTED_LOCALES.join("/")}): `
    )).trim().toLowerCase();
    rl.close();
    if (answer && SUPPORTED_LOCALES.includes(answer)) {
      opts.locale = answer;
    }
    console.log(`  Using locale: ${opts.locale}`);
  }

  await initCore(root, opts);

  console.log("\nbeeops initialized successfully!");
  console.log("Run /bee-dev in Claude Code to start the Queen.");
  printSettingsSummary(root);
}

const SUPPORTED_LOCALES = ["en", "ja", "zh", "es"];

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
  const cmdPath = path.join(claudeDir, "commands", "bee-dev.md");
  if (fs.existsSync(cmdPath)) {
    console.log("  [ok] .claude/commands/bee-dev.md");
  } else {
    console.log("  [missing] .claude/commands/bee-dev.md");
    ok = false;
  }

  // Check skills
  const CORE_SKILLS = [
    "bee-dispatch", "bee-leader-dispatch", "bee-task-decomposer", "bee-issue-sync",
    "bee-review-backend", "bee-review-frontend", "bee-review-database",
    "bee-review-operations", "bee-review-process", "bee-review-security",
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
    { hookType: "UserPromptSubmit", matchStr: "bo-prompt-context.py", label: "UserPromptSubmit" },
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
  const localContexts = path.join(root, ".beeops", "contexts");
  if (fs.existsSync(localContexts)) {
    const files = fs.readdirSync(localContexts);
    console.log(`  [info] .beeops/contexts/ (${files.length} custom file(s))`);
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
  console.log("  --locale <lang>  Set locale (auto-detected from system, available: en, ja, zh, es)\n");
  console.log("To change settings after init, edit .beeops/settings.json directly.\n");
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

// ── Locale auto-detection ──

function detectSystemLocale() {
  // 1. Environment variables (LANG, LC_ALL, LC_MESSAGES)
  const envLocale = process.env.LC_ALL || process.env.LC_MESSAGES || process.env.LANG || "";
  const envLower = envLocale.toLowerCase();
  if (envLower.startsWith("ja")) return "ja";
  if (envLower.startsWith("zh")) return "zh";
  if (envLower.startsWith("es")) return "es";

  // 2. macOS: AppleLanguages preference
  try {
    const result = execSync("defaults read NSGlobalDomain AppleLanguages 2>/dev/null", {
      encoding: "utf8", stdio: "pipe",
    }).trim();
    // result looks like: ("ja", "en-JP", ...)
    const first = result.match(/"([^"]+)"/);
    if (first) {
      const lang = first[1].toLowerCase();
      if (lang.startsWith("ja")) return "ja";
      if (lang.startsWith("zh")) return "zh";
      if (lang.startsWith("es")) return "es";
    }
  } catch {
    // ignore
  }

  return "en";
}

// ── Argument parsing ──

function parseArgs(argv) {
  const args = argv.slice(2);
  const opts = {
    hookMode: "local",
    withContexts: false,
    locale: detectSystemLocale(),
    _localeExplicit: false,
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
          opts._localeExplicit = true;
        }
        break;
    }
  }

  return { command, opts };
}

// ── Main ──
const { command, opts } = parseArgs(process.argv);

(async () => {
  switch (command) {
    case "init":
    case "update":
      await init(opts);
      break;
    case "check":
      check();
      break;
    default:
      printHelp();
      process.exit(command ? 1 : 0);
  }
})();
