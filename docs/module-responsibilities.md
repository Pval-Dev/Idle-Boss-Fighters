# Module Responsibilities

This page maps the major Idle Boss Fighters components to their primary responsibilities. It reflects the architecture shown by the portfolio samples; the full production place contains additional assets and scripts.

## Core Orchestration

| Component | Role | Main responsibility |
|---|---|---|
| `GameManager` | Session/runtime coordinator | Player lifecycle, profile load/save, plot assignment, runtime loop startup, selected remote handlers, shutdown persistence |
| `GameLoop` | Runtime gameplay loop | Recurring combat/economy coordination and shared runtime updates |
| `CombatDirector` | Combat orchestrator | Shield/core phases, turn order, combo resolution, timeout and terminal-state flow |
| `CombatSystem` | Combat logic | Damage-oriented calculations and interactions with runtime combat entities |

## Data and Configuration

| Component | Role | Main responsibility |
|---|---|---|
| `PlayerData` | Persistent profile model | Economy, combat stats, cosmetics, quests, titles, boosts, tutorial state, serialization/deserialization |
| `Config` | Balance/configuration layer | Upgrade costs, progression formulas, boss tuning, reward ratios, constants |
| `AnimationData` | Data module | Animation references |
| `EffectData` | Data module | Visual-effect references/configuration |
| `AuraData` | Data module | Aura metadata and modifiers |
| `SoundData` | Data module | Sound references |
| `QuestConfig` | Configuration module | Quest requirements and rewards |
| `TitleConfig` | Configuration module | Title unlock metadata |

## Gameplay Services

| Component | Role | Main responsibility |
|---|---|---|
| `ActionSystem` | Action coordinator | Coordinates movement, animation, effects, and sound for high-level actions |
| `AnimationSystem` | Presentation subsystem | Animation playback |
| `EffectSystem` | Presentation subsystem | Runtime visual effects |
| `SoundSystem` | Presentation subsystem | Audio feedback |
| `MovementSystem` | Runtime subsystem | Combat movement and positioning |
| `DealerSystem` | Cosmetic economy | Rotating cosmetic offers and purchase flow |
| `QuestService` | Progression service | Quest state, progress, completion, and rewards |
| `TitleService` | Progression/cosmetic service | Title unlocks and active title state |

## Economy and Progression

| Component | Role | Main responsibility |
|---|---|---|
| `GemSpawner` | Reward runtime | Materializes gem rewards in the player's plot |
| `ChestSystem` | Reward system | Chance-based chest rewards |
| `BigNum` | Numeric utility | Extended-range representation, arithmetic, serialization, and formatting |
| Processor flow | Economy loop | Converts collected gems into claimable currency |
| Upgrade flow | Progression loop | Converts currency into permanent stat upgrades |

## Runtime Ownership

| Component | Role | Main responsibility |
|---|---|---|
| `PlotManager` | Ownership manager | Assigns/releases plots and resolves plot ownership |
| `NPCHandler` | Runtime entity handler | Maintains NPC references/state |
| `NPC` | Domain/runtime object | NPC statistics and runtime construction |
| `Boss` | Domain/runtime object | Boss statistics, shield/core state, and runtime construction |
| `SafeZone` | Recovery guard | Repositions entities that leave configured plot bounds |

## Networking

| Component | Role | Main responsibility |
|---|---|---|
| `PlayerRemotes` | Communication boundary | RemoteEvents and RemoteFunctions shared with clients |
| Client `LocalScripts` | Presentation/controllers | UI interaction and client requests |
| Server remote handlers | Authority boundary | Resolve player state, validate requests, and call server-side systems |

## Analytics

| Component | Role | Main responsibility |
|---|---|---|
| `AnalyticsService` | Session telemetry | Tracks active sessions, duration, bounded session history, and aggregate session totals |

The analytics sample uses a separate DataStore from gameplay progression so telemetry concerns do not need to live inside `PlayerData`.

## Architectural Notes

`GameManager` is intentionally a broad coordinator in this version. That made lifecycle sequencing straightforward during development, but it also creates a natural refactoring boundary. In a larger service-oriented version, persistence, remote handling, player sessions, and runtime health checks could be split into smaller modules with narrower dependencies.
