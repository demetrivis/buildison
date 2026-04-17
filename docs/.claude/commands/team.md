# /team — Montar uma Equipe de Teammates

You have been invoked with the `/team` command. Your job is to evaluate the current task, decide if it benefits from an agent team, and if so, create a team of teammates — independent Claude Code sessions that coordinate through a shared task list and communicate directly with each other.

## Core Principle

This is NOT about subagents. Subagents run inside your session and report back to you. Teammates are fully independent Claude Code instances with their own context windows. They can message each other, claim tasks from a shared list, and work in parallel without going through you for every decision.

Use teammates when the work requires collaboration, debate, or coordination between workers. Use subagents when you just need quick results reported back.

## When to Create a Team

Create a team when:
- The task has 2+ independent workstreams that benefit from parallel execution
- Workers need to communicate findings to each other (not just to you)
- The task benefits from adversarial review — teammates challenging each other's work
- The work spans multiple layers (frontend, backend, infra, tests) that each need a dedicated owner
- Investigation requires competing hypotheses explored simultaneously

Do NOT create a team when:
- The task is sequential and each step depends on the previous
- Multiple workers would edit the same files (causes conflicts)
- The task is simple enough for a single session or subagents
- The overhead of coordination would exceed the benefit

## Instructions

1. **Analyze the task**: Understand what the user needs. Identify independent workstreams, potential for parallel work, and whether teammates need to talk to each other.

2. **Design the team**: For each teammate, define:
   - A clear role and name (e.g., "security-reviewer", "backend-architect", "test-writer")
   - Specific responsibilities and deliverables
   - Which files or areas they own (avoid overlap to prevent conflicts)
   - Whether they need plan approval before making changes

3. **Size the team right**: Start with 3-5 teammates for most tasks. Aim for 5-6 tasks per teammate. More teammates means more coordination overhead and token cost — only scale when the work genuinely benefits.

4. **Explain your plan**: Before creating the team, briefly describe:
   - How many teammates and their roles
   - Why a team is better than subagents or a single session for this task
   - How the work divides across teammates without file conflicts

5. **Create the team**: Use natural language to instruct the creation of the agent team. Each teammate should receive a clear spawn prompt with full context about their role, the project, and what they need to deliver.

6. **Coordinate**: Monitor teammate progress, redirect if needed, and synthesize results as they come in.

## Team Design Examples

**Feature implementation across layers**:
```
Create an agent team for the new notifications feature:
- "api-owner": owns src/api/notifications/, builds endpoints and schemas
- "service-owner": owns src/services/notifications/, implements business logic
- "db-owner": owns migrations and src/models/notification.py, designs schema and queries
- "test-writer": owns tests/notifications/, writes tests as the others build
Have them communicate progress so the test-writer can start writing tests as soon as interfaces are defined.
```

**Debugging with competing hypotheses**:
```
Users report the app exits after one message instead of staying connected.
Spawn 4 agent teammates to investigate different hypotheses.
Have them talk to each other to try to disprove each other's theories,
like a scientific debate. Update findings as consensus emerges.
```

**Parallel code review**:
```
Create an agent team to review PR #142:
- One focused on security implications
- One checking performance impact
- One validating test coverage
Have them each review and share findings with each other.
```

**Research and architecture**:
```
I'm designing a real-time sync engine. Create an agent team:
- "researcher": explores existing approaches (CRDTs, OT, etc.)
- "architect": designs the system based on our constraints
- "devils-advocate": challenges every design decision
Have them debate and converge on a recommendation.
```

## Key Differences from Subagents

| Aspect | Subagents | Teammates (Agent Teams) |
|--------|-----------|------------------------|
| Context | Share your context, report back to you | Own context window, fully independent |
| Communication | Only talk to you | Message each other directly |
| Coordination | You manage everything | Shared task list, self-coordinate |
| Best for | Quick focused tasks, results only | Complex work needing collaboration |
| Token cost | Lower | Higher (each is a separate Claude instance) |

## Rules

- Always check that `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is enabled before attempting to create a team
- Divide file ownership so no two teammates edit the same file
- Give each teammate enough context in their spawn prompt — they don't inherit your conversation history
- For risky changes, require plan approval before teammates make modifications
- If a teammate gets stuck, intervene directly or spawn a replacement
- When done, clean up the team properly through the leader session
- If the task doesn't justify a team, say so and handle it directly or use subagents instead
