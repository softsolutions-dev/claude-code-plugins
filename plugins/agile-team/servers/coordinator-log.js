#!/usr/bin/env node
// Minimal MCP server for coordinator log read/write.
// Uses newline-delimited JSON over stdio (not Content-Length framing).
// session_id is injected by PreToolUse hook (not in tool schemas).

const fs = require('fs');
const path = require('path');
const readline = require('readline');

const PLUGIN_ROOT = process.env.CLAUDE_PLUGIN_ROOT || path.resolve(__dirname, '..');
const SESSIONS_DIR = path.join(PLUGIN_ROOT, '.sessions');

function goalsPath(sessionId) {
  return path.join(SESSIONS_DIR, `${sessionId}.goals.json`);
}

function readGoals(sessionId) {
  const p = goalsPath(sessionId);
  if (!fs.existsSync(p)) return { goals: [] };
  return JSON.parse(fs.readFileSync(p, 'utf-8'));
}

function writeGoals(sessionId, data) {
  fs.mkdirSync(SESSIONS_DIR, { recursive: true });
  const target = goalsPath(sessionId);
  const tmp = target + '.tmp';
  fs.writeFileSync(tmp, JSON.stringify(data, null, 2));
  fs.renameSync(tmp, target);
}

// --- Send JSON-RPC message (newline-delimited) ---

function send(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n');
}

function respond(id, result) {
  send({ jsonrpc: '2.0', id, result });
}

function respondError(id, code, message) {
  send({ jsonrpc: '2.0', id, error: { code, message } });
}

// --- Tool definitions ---

const TOOLS = [
  {
    name: 'coordinator_log_write',
    description: 'Append a timestamped entry to the coordinator log. This is your persistent memory — it survives context compaction.',
    inputSchema: {
      type: 'object',
      properties: {
        entry: { type: 'string', description: 'The log entry to append' }
      },
      required: ['entry']
    }
  },
  {
    name: 'coordinator_log_read',
    description: 'Read the coordinator log. Returns the last N lines (default 50).',
    inputSchema: {
      type: 'object',
      properties: {
        lines: { type: 'number', description: 'Number of lines to return from the end (default 300)' }
      }
    }
  },
  {
    name: 'goal_add',
    description: 'Add a goal to the queue. Goals are worked sequentially — one at a time.',
    inputSchema: {
      type: 'object',
      properties: {
        description: { type: 'string', description: 'Short description of the goal' }
      },
      required: ['description']
    }
  },
  {
    name: 'goal_current',
    description: 'Get the current active goal. Returns goal description and position (e.g., "Goal 2 of 4").',
    inputSchema: { type: 'object', properties: {} }
  },
  {
    name: 'goal_complete',
    description: 'Mark the current goal as complete and advance to the next one.',
    inputSchema: { type: 'object', properties: {} }
  }
];

// --- Tool implementations ---

function handleToolCall(id, name, args) {
  const sessionId = args.session_id;
  if (!sessionId) {
    return respond(id, { content: [{ type: 'text', text: 'Error: No active agile session. Use /agile-team to start one.' }], isError: true });
  }

  const logPath = path.join(SESSIONS_DIR, `${sessionId}.log`);

  if (name === 'coordinator_log_write') {
    if (!args.entry) {
      return respond(id, { content: [{ type: 'text', text: 'Error: entry is required' }], isError: true });
    }
    try {
      fs.mkdirSync(SESSIONS_DIR, { recursive: true });
      const ts = new Date().toISOString().replace('T', ' ').replace(/\.\d+Z$/, 'Z');
      fs.appendFileSync(logPath, `[${ts}] ${args.entry}\n`);
      respond(id, { content: [{ type: 'text', text: `Logged: ${args.entry}` }] });
    } catch (e) {
      respond(id, { content: [{ type: 'text', text: `Error: ${e.message}` }], isError: true });
    }
  } else if (name === 'coordinator_log_read') {
    try {
      if (!fs.existsSync(logPath)) {
        return respond(id, { content: [{ type: 'text', text: '(log is empty — no entries yet)' }] });
      }
      const lines = fs.readFileSync(logPath, 'utf-8').split('\n').filter(l => l);
      const tail = lines.slice(-(args.lines || 50)).join('\n');
      respond(id, { content: [{ type: 'text', text: tail || '(log is empty — no entries yet)' }] });
    } catch (e) {
      respond(id, { content: [{ type: 'text', text: `Error: ${e.message}` }], isError: true });
    }
  } else if (name === 'goal_add') {
    if (!args.description) {
      return respond(id, { content: [{ type: 'text', text: 'Error: description is required' }], isError: true });
    }
    try {
      const data = readGoals(sessionId);
      const goalId = data.goals.length + 1;
      const hasActive = data.goals.some(g => g.status === 'active');
      data.goals.push({ id: goalId, description: args.description, status: hasActive ? 'pending' : 'active' });
      writeGoals(sessionId, data);
      respond(id, { content: [{ type: 'text', text: `Added goal ${goalId}: ${args.description}` }] });
    } catch (e) {
      respond(id, { content: [{ type: 'text', text: `Error: ${e.message}` }], isError: true });
    }

  } else if (name === 'goal_current') {
    try {
      const data = readGoals(sessionId);
      const total = data.goals.length;
      if (total === 0) {
        return respond(id, { content: [{ type: 'text', text: 'No goals yet. Use goal_add to create goals.' }] });
      }
      const active = data.goals.find(g => g.status === 'active');
      if (!active) {
        return respond(id, { content: [{ type: 'text', text: 'All goals complete.' }] });
      }
      respond(id, { content: [{ type: 'text', text: `Goal ${active.id} of ${total}: ${active.description}` }] });
    } catch (e) {
      respond(id, { content: [{ type: 'text', text: `Error: ${e.message}` }], isError: true });
    }

  } else if (name === 'goal_complete') {
    try {
      const data = readGoals(sessionId);
      const active = data.goals.find(g => g.status === 'active');
      if (!active) {
        return respond(id, { content: [{ type: 'text', text: 'No active goal to complete.' }] });
      }
      active.status = 'completed';
      const next = data.goals.find(g => g.status === 'pending');
      if (next) next.status = 'active';
      writeGoals(sessionId, data);
      const total = data.goals.length;
      const msg = next
        ? `Goal ${active.id} complete. Now active — Goal ${next.id} of ${total}: ${next.description}`
        : `All ${total} goals complete.`;
      respond(id, { content: [{ type: 'text', text: msg }] });
    } catch (e) {
      respond(id, { content: [{ type: 'text', text: `Error: ${e.message}` }], isError: true });
    }

  } else {
    respondError(id, -32601, `Unknown tool: ${name}`);
  }
}

// --- Request handler ---

function handleMessage(msg) {
  const { id, method, params } = msg;

  if (method === 'initialize') {
    respond(id, {
      protocolVersion: '2025-11-25',
      capabilities: { tools: {} },
      serverInfo: { name: 'coordinator-log', version: '1.0.0' }
    });
  } else if (method === 'notifications/initialized') {
    // no-op
  } else if (method === 'tools/list') {
    respond(id, { tools: TOOLS });
  } else if (method === 'tools/call') {
    handleToolCall(id, params.name, params.arguments || {});
  } else if (id !== undefined) {
    respondError(id, -32601, `Unknown method: ${method}`);
  }
}

// --- Read newline-delimited JSON from stdin ---

const rl = readline.createInterface({ input: process.stdin });
rl.on('line', (line) => {
  if (!line.trim()) return;
  try {
    handleMessage(JSON.parse(line));
  } catch (e) {
    process.stderr.write(`Parse error: ${e.message}\n`);
  }
});
