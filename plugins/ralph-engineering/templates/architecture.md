# Architecture & Technology Guidelines

This document defines recommended technology stack and design principles for applications built with ralph-prd and ralph-loop. These are **opinionated defaults** - use them unless the user explicitly specifies different choices.

## Technology Stack

### Web Applications

| Layer | Technology | Notes |
|-------|------------|-------|
| Runtime | **Node.js** or **Bun** | Bun preferred for new projects |
| Package Manager | **pnpm** or **bun** | |
| Language | **TypeScript** | Strict mode enabled |
| Framework | **Next.js** (latest) | App Router preferred |
| UI Library | **React 19** | |
| Styling | **Tailwind CSS** | |
| Components | **shadcn/ui** | Copy components, don't install as dependency |
| State Management | **Zustand** | Use when client-side state is needed |
| AI/LLM Integration | **Vercel AI SDK** | For apps requiring LLM or AI agent features |

### Project Initialization

When creating a new web application:

```bash
pnpm create next-app@latest --typescript --tailwind --eslint --app --src-dir
```

Then add shadcn/ui:

```bash
pnpm dlx shadcn@latest init
```

## Design Principles

### 1. Server Components by Default
- Use React Server Components for data fetching and static content
- Only use `"use client"` when interactivity is required (event handlers, hooks, browser APIs)

### 2. Colocation
- Keep related files together (component, styles, tests, types)
- Feature-based directory structure over type-based

### 3. Type Safety
- Enable strict TypeScript configuration
- Define explicit types for API responses and component props
- Avoid `any` - use `unknown` with type guards when type is uncertain

### 4. Component Patterns
- Prefer composition over inheritance
- Use compound components for complex UI patterns
- Keep components focused and single-purpose

### 5. State Management Hierarchy
1. **URL state** - for shareable, bookmarkable state (search params)
2. **Server state** - for data from APIs (React Server Components or React Query)
3. **Local component state** - for UI-only state (useState)
4. **Global client state** - only when truly needed (Zustand)

### 6. Styling
- Use Tailwind utility classes directly in components
- Create reusable components rather than custom CSS classes
- Use CSS variables for theme customization

## AI/LLM Applications

When building applications with AI features:

### Vercel AI SDK Setup

```bash
pnpm add ai @ai-sdk/openai
```

### Patterns
- Use `useChat` hook for conversational interfaces
- Use `useCompletion` for single-prompt completions
- Stream responses for better UX
- Implement proper error boundaries for AI failures

### AI SDK UI Components

For rich AI interfaces, use AI SDK UI:

```bash
pnpm add @ai-sdk/ui-utils
```

## Applying These Guidelines

### In ralph-prd
When generating PRD features, consider:
- Features should align with these architectural patterns
- UI features should reference shadcn/ui component patterns
- Performance features should consider Next.js optimizations (Image, Link, etc.)

### In ralph-loop
When implementing features:
- Follow the technology stack unless the project uses different technologies
- Use established patterns from this guide
- Reference shadcn/ui documentation for component implementations

## Overriding Defaults

Users can override any of these defaults by explicitly specifying alternatives:
- "Use Vue instead of React"
- "Use CSS Modules instead of Tailwind"
- "Use Redux for state management"

When overrides are specified, respect the user's choice completely.
