#!/usr/bin/env node

import * as fs from "fs";
import * as path from "path";
import * as os from "os";

// --- Types ---

interface Goal {
  id: number;
  description: string;
  status: "active" | "pending" | "completed";
}

interface GoalsFile {
  goals: Goal[];
}

interface LogEntry {
  ts: string;
  goal: number | null;
  title: string;
  description?: string;
}

interface SessionInfo {
  sessionId: string;
  logPath: string;
  goalsPath: string;
  startedAt: Date;
  mtime: Date;
  stableId: number;
}

// --- Sessions discovery ---

function findSessionsDir(): string {
  const override = process.env.AGILE_SESSIONS_DIR;
  if (override) {
    if (!fs.existsSync(override)) {
      fatal(`AGILE_SESSIONS_DIR does not exist: ${override}`);
    }
    return override;
  }

  const cacheBase = path.join(os.homedir(), ".claude", "plugins", "cache");
  if (!fs.existsSync(cacheBase)) {
    fatal("No plugin cache found at ~/.claude/plugins/cache/");
  }

  // Scan cache/*/agile-team/*/.sessions/
  let best: { dir: string; mtime: number } | null = null;

  for (const marketplace of readdirSafe(cacheBase)) {
    const pluginDir = path.join(cacheBase, marketplace, "agile-team");
    if (!fs.existsSync(pluginDir)) continue;

    for (const version of readdirSafe(pluginDir)) {
      const sessionsDir = path.join(pluginDir, version, ".sessions");
      if (!fs.existsSync(sessionsDir)) continue;

      const stat = fs.statSync(sessionsDir);
      if (!best || stat.mtimeMs > best.mtime) {
        best = { dir: sessionsDir, mtime: stat.mtimeMs };
      }
    }
  }

  if (!best) {
    fatal("No .sessions/ directory found. Has /agile-team been used?");
  }
  return best.dir;
}

function readdirSafe(dir: string): string[] {
  try {
    return fs
      .readdirSync(dir, { withFileTypes: true })
      .filter((d) => d.isDirectory())
      .map((d) => d.name);
  } catch {
    return [];
  }
}

function parseStartTime(logPath: string): Date | null {
  try {
    const fd = fs.openSync(logPath, "r");
    const buf = Buffer.alloc(512);
    fs.readSync(fd, buf, 0, 512, 0);
    fs.closeSync(fd);
    const firstLine = buf.toString("utf-8").split("\n")[0];
    try {
      const entry: LogEntry = JSON.parse(firstLine);
      if (entry.ts) return new Date(entry.ts);
    } catch {
      // Legacy plain text format fallback
      const match = firstLine.match(/Session started (\S+)/);
      if (match) return new Date(match[1]);
    }
  } catch {
    // fall through
  }
  return null;
}

function parseLogEntries(logPath: string): LogEntry[] {
  if (!fs.existsSync(logPath)) return [];
  const lines = fs.readFileSync(logPath, "utf-8").split("\n").filter((l) => l.trim());
  const entries: LogEntry[] = [];
  for (const line of lines) {
    try {
      entries.push(JSON.parse(line));
    } catch {
      // skip non-JSON lines
    }
  }
  return entries;
}

function discoverSessions(sessionsDir: string): SessionInfo[] {
  const files = fs.readdirSync(sessionsDir).filter((f) => f.endsWith(".log"));
  const sessions: SessionInfo[] = files.map((f) => {
    const sessionId = f.replace(".log", "");
    const logPath = path.join(sessionsDir, f);
    const goalsPath = path.join(sessionsDir, `${sessionId}.goals.json`);
    const stat = fs.statSync(logPath);
    const startedAt = parseStartTime(logPath) || stat.birthtime;
    return { sessionId, logPath, goalsPath, startedAt, mtime: stat.mtime, stableId: 0 };
  });

  // Assign stable IDs by creation order (oldest = 1)
  sessions.sort((a, b) => a.startedAt.getTime() - b.startedAt.getTime());
  for (let i = 0; i < sessions.length; i++) {
    sessions[i].stableId = i + 1;
  }
  return sessions;
}

// --- Session resolver ---

function resolveSession(
  sessions: SessionInfo[],
  ref: string
): SessionInfo {
  // Numeric stable ID
  const num = parseInt(ref, 10);
  if (!isNaN(num)) {
    const match = sessions.find((s) => s.stableId === num);
    if (match) return match;
    fatal(`No session with ID ${num}. Run "agile sessions" to see list.`);
  }

  // Partial UUID prefix match
  const matches = sessions.filter((s) => s.sessionId.startsWith(ref));
  if (matches.length === 1) return matches[0];
  if (matches.length > 1) {
    fatal(
      `Ambiguous session "${ref}" — matches ${matches.length} sessions. Use a longer prefix.`
    );
  }

  fatal(
    `No session matching "${ref}". Run "agile sessions" to see available sessions.`
  );
}

// --- Goal helpers ---

function readGoals(goalsPath: string): GoalsFile {
  if (!fs.existsSync(goalsPath)) return { goals: [] };
  return JSON.parse(fs.readFileSync(goalsPath, "utf-8"));
}

function writeGoals(goalsPath: string, data: GoalsFile): void {
  const dir = path.dirname(goalsPath);
  fs.mkdirSync(dir, { recursive: true });
  const tmp = goalsPath + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2));
  fs.renameSync(tmp, goalsPath);
}

// --- Output helpers ---

function fatal(msg: string): never {
  console.error(`Error: ${msg}`);
  process.exit(1);
}

function pad(s: string, len: number): string {
  return s.padEnd(len);
}

function formatDate(d: Date): string {
  const y = d.getFullYear();
  const mo = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  const h = String(d.getHours()).padStart(2, "0");
  const mi = String(d.getMinutes()).padStart(2, "0");
  const s = String(d.getSeconds()).padStart(2, "0");
  return `${y}-${mo}-${day} ${h}:${mi}:${s}`;
}

function goalStatusSummary(goalsPath: string): {
  total: number;
  completed: number;
  label: string;
} {
  const data = readGoals(goalsPath);
  const total = data.goals.length;
  if (total === 0) return { total: 0, completed: 0, label: "No goals" };

  const completed = data.goals.filter((g) => g.status === "completed").length;
  const active = data.goals.find((g) => g.status === "active");

  let label: string;
  if (completed === total) {
    label = "All complete";
  } else if (active) {
    label = `Goal ${active.id}: ${active.description.slice(0, 40)}`;
  } else {
    label = `${completed}/${total}`;
  }
  return { total, completed, label };
}

// --- Commands ---

function cmdSessions(sessions: SessionInfo[]): void {
  if (sessions.length === 0) {
    console.log("No sessions found.");
    return;
  }

  // Display sorted by last activity descending
  const sorted = [...sessions].sort((a, b) => b.mtime.getTime() - a.mtime.getTime());
  const latestId = sorted[0].stableId;

  console.log(
    ` ${"#".padStart(2)}  ${pad("ID", 10)}${pad("Started", 22)}${pad("Last Activity", 22)}${pad("Goals", 7)}Status`
  );

  for (const s of sorted) {
    const marker = s.stableId === latestId ? "*" : " ";
    const idx = String(s.stableId).padStart(2);
    const id = s.sessionId.slice(0, 8);
    const started = formatDate(s.startedAt);
    const lastActivity = formatDate(s.mtime);
    const { total, completed, label } = goalStatusSummary(s.goalsPath);
    const goalsCol = total > 0 ? `${completed}/${total}` : "-";

    console.log(
      `${marker}${idx}  ${pad(id, 10)}${pad(started, 22)}${pad(lastActivity, 22)}${pad(goalsCol, 7)}${label}`
    );
  }
}

function cmdLog(session: SessionInfo, lines?: number, goalFilter?: number): void {
  const entries = parseLogEntries(session.logPath);

  if (entries.length === 0) {
    console.log("(log is empty)");
    return;
  }

  let filtered = entries;
  if (goalFilter !== undefined) {
    filtered = entries.filter((e) => e.goal === goalFilter);
  }

  const display = lines && lines > 0 ? filtered.slice(-lines) : filtered;

  for (const e of display) {
    const ts = formatDate(new Date(e.ts));
    const goalTag = e.goal !== null ? ` [G${e.goal}]` : "";
    const desc = e.description ? `\n    ${e.description}` : "";
    console.log(`[${ts}]${goalTag} ${e.title}${desc}`);
  }
}

function cmdGoalsList(session: SessionInfo): void {
  const data = readGoals(session.goalsPath);

  if (data.goals.length === 0) {
    console.log("No goals.");
    return;
  }

  console.log(` ${"#".padStart(2)}  ${pad("Status", 11)}Description`);
  for (const g of data.goals) {
    const idx = String(g.id).padStart(2);
    console.log(` ${idx}  ${pad(g.status, 11)}${g.description}`);
  }
}

function cmdGoalsAdd(session: SessionInfo, description: string): void {
  const data = readGoals(session.goalsPath);
  const goalId = data.goals.length + 1;
  const hasActive = data.goals.some((g) => g.status === "active");
  const status: Goal["status"] = hasActive ? "pending" : "active";
  data.goals.push({ id: goalId, description, status });
  writeGoals(session.goalsPath, data);
  console.log(`Added goal ${goalId}: ${description} (${status})`);
}

function cmdGoalsEdit(
  session: SessionInfo,
  goalId: number,
  newDesc: string
): void {
  const data = readGoals(session.goalsPath);
  const goal = data.goals.find((g) => g.id === goalId);
  if (!goal) fatal(`Goal ${goalId} not found.`);
  goal.description = newDesc;
  writeGoals(session.goalsPath, data);
  console.log(`Updated goal ${goalId}: ${newDesc}`);
}

function cmdGoalsStatus(
  session: SessionInfo,
  goalId: number,
  newStatus: Goal["status"]
): void {
  const validStatuses: Goal["status"][] = ["active", "pending", "completed"];
  if (!validStatuses.includes(newStatus)) {
    fatal(`Invalid status "${newStatus}". Use: ${validStatuses.join(", ")}`);
  }

  const data = readGoals(session.goalsPath);
  const goal = data.goals.find((g) => g.id === goalId);
  if (!goal) fatal(`Goal ${goalId} not found.`);

  const old = goal.status;
  goal.status = newStatus;
  writeGoals(session.goalsPath, data);
  console.log(`Goal ${goalId}: ${old} -> ${newStatus}`);
}

function cmdGoalsComplete(session: SessionInfo, goalId: number): void {
  const data = readGoals(session.goalsPath);
  const goal = data.goals.find((g) => g.id === goalId);
  if (!goal) fatal(`Goal ${goalId} not found.`);
  if (goal.status === "completed") {
    console.log(`Goal ${goalId} is already completed.`);
    return;
  }

  goal.status = "completed";

  // Promote next pending goal
  const next = data.goals.find((g) => g.status === "pending");
  if (next) next.status = "active";

  writeGoals(session.goalsPath, data);

  if (next) {
    console.log(
      `Completed goal ${goalId}. Goal ${next.id} now active: ${next.description}`
    );
  } else {
    console.log(`Completed goal ${goalId}. All ${data.goals.length} goals complete.`);
  }
}

// --- Usage ---

function printUsage(): void {
  console.log(`Usage:
  agile-team sessions                              List all sessions
  agile-team log <session> [--lines N] [--goal N]  View session log
  agile-team goals <session>                       List goals
  agile-team goals add <session> "description"     Add a goal
  agile-team goals edit <session> <id> "new desc"  Edit goal description
  agile-team goals status <session> <id> <status>  Change goal status
  agile-team goals complete <session> <id>         Complete goal + promote next

Session: use # from "agile-team sessions" or partial UUID.`);
}

// --- Main ---

function main(): void {
  const args = process.argv.slice(2);

  if (args.length === 0 || args[0] === "--help" || args[0] === "-h") {
    printUsage();
    process.exit(0);
  }

  const command = args[0];
  const sessionsDir = findSessionsDir();
  const sessions = discoverSessions(sessionsDir);

  if (command === "sessions") {
    cmdSessions(sessions);
    return;
  }

  if (command === "log") {
    if (!args[1]) fatal('Session required. Run "agile sessions" to see list.');
    const session = resolveSession(sessions, args[1]);
    const linesIdx = args.indexOf("--lines");
    const lines = linesIdx >= 0 ? parseInt(args[linesIdx + 1], 10) : undefined;
    const goalIdx = args.indexOf("--goal");
    const goalFilter = goalIdx >= 0 ? parseInt(args[goalIdx + 1], 10) : undefined;
    cmdLog(session, lines, goalFilter);
    return;
  }

  if (command === "goals") {
    const sub = args[1];

    if (sub === "add") {
      if (!args[2]) fatal("Session required.");
      const session = resolveSession(sessions, args[2]);
      const desc = args[3];
      if (!desc) fatal("Description required.");
      cmdGoalsAdd(session, desc);
      return;
    }

    if (sub === "edit") {
      if (!args[2]) fatal("Session required.");
      const session = resolveSession(sessions, args[2]);
      const goalId = parseInt(args[3], 10);
      if (isNaN(goalId)) fatal("Goal ID required.");
      const desc = args[4];
      if (!desc) fatal("New description required.");
      cmdGoalsEdit(session, goalId, desc);
      return;
    }

    if (sub === "status") {
      if (!args[2]) fatal("Session required.");
      const session = resolveSession(sessions, args[2]);
      const goalId = parseInt(args[3], 10);
      if (isNaN(goalId)) fatal("Goal ID required.");
      const status = args[4] as Goal["status"];
      if (!status) fatal("Status required (active, pending, completed).");
      cmdGoalsStatus(session, goalId, status);
      return;
    }

    if (sub === "complete") {
      if (!args[2]) fatal("Session required.");
      const session = resolveSession(sessions, args[2]);
      const goalId = parseInt(args[3], 10);
      if (isNaN(goalId)) fatal("Goal ID required.");
      cmdGoalsComplete(session, goalId);
      return;
    }

    // Default: list goals
    if (!sub) fatal('Session required. Run "agile sessions" to see list.');
    const session = resolveSession(sessions, sub);
    cmdGoalsList(session);
    return;
  }

  console.error(`Unknown command: ${command}`);
  printUsage();
  process.exit(1);
}

main();
