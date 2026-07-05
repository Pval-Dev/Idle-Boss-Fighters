
# Module Responsibilities

This document describes the main systems used in Idle Boss Fighters and their technical responsibility inside the project architecture.

## Core Orchestration

| Component | Type | Responsibility | Technical Value |
|---|---|---|---|
| GameManager | Main orchestrator | Coordinates player lifecycle, data loading/saving, plot assignment, purchase validation, system initialization and global event handling. | Centralized orchestration layer |
| GameLoop | Runtime loop | Coordinates recurring gameplay processes such as economy progression, combat updates and timed systems. | Continuous runtime coordination |
| CombatDirector | Combat orchestrator | Controls combat phases, turn order, boss shield/core transitions, combos, victory and defeat flow. | Stateful gameplay simulation |
| CombatSystem | Combat module | Executes combat calculations and connects combat logic with runtime entities. | Encapsulated combat logic |

## Data & Configuration

| Component | Type | Responsibility | Technical Value |
|---|---|---|---|
| PlayerData | Data model | Defines persistent player statistics, economy, inventory, unlocks and progression state. | Persistent player profile model |
| Config | Configuration layer | Centralizes balance values, economy parameters, combat tuning and system constants. | Single source of configuration |
| AnimationData | Data module | Stores animation references used by gameplay systems. | Data-driven animation setup |
| EffectData | Data module | Stores visual effect references and configuration. | Data-driven effect management |
| AuraData | Data module | Defines aura cosmetics and related metadata. | Cosmetic configuration layer |
| SoundData | Data module | Stores sound references used by sound systems. | Data-driven audio configuration |
| QuestConfig | Configuration module | Defines quest requirements, rewards and progression rules. | Retention system configuration |
| TitleConfig | Configuration module | Defines unlockable player titles and related metadata. | Cosmetic progression configuration |

## Gameplay Systems

| Component | Type | Responsibility | Technical Value |
|---|---|---|---|
| ActionSystem | Gameplay system | Coordinates high-level actions between combat, animation, movement, sound and effects. | Separates action execution from individual subsystems |
| AnimationSystem | Gameplay system | Handles animation playback for NPCs, bosses and combat actions. | Isolated animation responsibility |
| EffectSystem | Gameplay system | Spawns and manages visual effects during combat and progression events. | Isolated visual feedback layer |
| SoundSystem | Gameplay system | Plays sound feedback for attacks, UI and world events. | Isolated audio feedback layer |
| MovementSystem | Gameplay system | Handles movement logic used during combat actions and positioning. | Controlled runtime movement |
| DealerSystem | Gameplay system | Manages rotating cosmetic dealers, skin/aura availability and purchase flow. | Cosmetic and monetization-oriented system |
| QuestService | Gameplay service | Tracks quest progress, completion and rewards. | Player retention and progression layer |
| TitleService | Gameplay service | Manages title unlocks, active title state and player display titles. | Cosmetic achievement system |

## Economy & Progression

| Component | Type | Responsibility | Technical Value |
|---|---|---|---|
| GemSpawner | Economy module | Spawns gems as rewards during the progression loop. | Reward generation system |
| ChestSystem | Economy module | Handles chest reward opportunities and random reward spawning. | Chance-based reward layer |
| BigNum | Utility / numeric system | Represents, formats and serializes very large progression values. | Scalable incremental economy support |
| Processor Flow | Internal gameplay loop | Converts collected gems into claimable money over time. | Controlled economy pacing |
| Upgrade Flow | Internal progression system | Converts player money into permanent stat progression. | Long-term progression loop |

## World Runtime

| Component | Type | Responsibility | Technical Value |
|---|---|---|---|
| PlotManager | World management system | Assigns and manages isolated player plots. | Per-player runtime world isolation |
| NPCHandler | Runtime world handler | Maintains server-side NPC state and world references. | Runtime entity management |
| NPC | Domain class / builder | Builds NPC data, statistics and behavior references. | Encapsulated NPC construction |
| Boss | Domain class / builder | Builds boss data, statistics, shield/core state and boss-specific behavior. | Encapsulated boss construction |
| StatsLeaderboard | World system | Updates and displays global player progression statistics. | Competitive progression visibility |

## Networking & Observers

| Component | Type | Responsibility | Technical Value |
|---|---|---|---|
| PlayerRemotes | Remote communication layer | Provides RemoteEvents and RemoteFunctions for client-server communication. | Network boundary between UI and server logic |
| Client LocalScripts | Client-side controllers | Handles UI interaction, visual feedback and client requests to the server. | Client presentation layer |
| Server Listeners | Internal subsystem | Listens to client requests, validates actions and forwards them to server systems. | Server-authoritative request handling |

## Utilities & Fault Tolerance

| Component | Type | Responsibility | Technical Value |
|---|---|---|---|
| SafeZone | Fault tolerance helper | Recovers NPCs when physics or runtime errors move them outside valid areas. | Runtime error tolerance |
| DamageNumbersService | Visual helper | Displays floating damage numbers during combat. | Non-critical visual feedback layer |
| AnalyticsService | Analytics helper | Tracks gameplay flow, player behavior and session-related data. | Product validation and telemetry support |
