# Ralph Engineering Plugin

This is a Claude Code plugin project providing engineering tools and workflows.

## Project Structure

- `.claude-plugin/marketplace.json` - Marketplace configuration for plugin distribution
- `plugins/ralph-engineering/` - Main plugin directory
  - `.claude-plugin/plugin.json` - Plugin metadata and configuration
  - `commands/` - Slash commands (`.md` files)
  - `skills/` - Reusable skills (directories with `SKILL.md`)
  - `agents/` - Agent definitions (`.md` files)

## Development Guidelines

### Commands
- Commands are markdown files in the `commands/` directory
- Named as `command-name.md`
- Invoked with `/ralph-engineering:command-name`

### Skills
- Skills are directories in the `skills/` directory
- Must contain a `SKILL.md` file
- Can include additional assets in subdirectories

### Agents
- Agents are markdown files in the `agents/` directory
- Define specialized behaviors for specific tasks

## Testing

Test your plugin locally by running Claude Code from this directory.
