# agile-team CLI

View session logs and manage goals from the agile-team plugin outside of Claude.

## Install

```
npm install && npm run build && npm link
```

## Usage

```
agile-team sessions                              # List all sessions
agile-team log <session> [--lines N] [--goal N]  # View session log
agile-team goals <session>                       # List goals
agile-team goals add <session> "description"     # Add a goal
agile-team goals edit <session> <id> "new desc"  # Edit goal description
agile-team goals status <session> <id> <status>  # Change goal status
agile-team goals complete <session> <id>         # Complete + promote next
```

`<session>` is the `#` from `agile-team sessions` or a partial UUID.
