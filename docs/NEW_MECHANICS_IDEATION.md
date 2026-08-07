# Gameplay Systems & Mechanics Audit + Expansion Proposals

## 1. Audit Summary
The codebase reveals a highly kinetic, systemic, and physical first-person framework with heavy emphasis on advanced movement and tactile puzzle-solving.

**Core Systems Identified:**
*   **Advanced Locomotion:** A robust state machine governing walking, sprinting, crouching, sliding, swimming, vaulting, ziplines, monkey bars, ladders, updrafts, and glider deployment. Includes momentum retention and coyote time.
*   **Physics Interaction:** Master/Scanner relationship for interacting with the world. Features short-range grabbing, throwing, heavy lifting (which limits movement), weapon handling, and operating terminals/machines.
*   **Environmental State:** Modular components reacting to rain, updrafts, waterfalls, and ice/sand friction changes.
*   **Puzzle & Systemic Elements:** A rich library of interactive physics objects, including physics cables, pulleys, lasers, mirrors, magnets, portals, conveyor belts, explosive barrels, heavy boxes, and combination locks.
*   **Health & Hazards:** Modular health system with damage, healing, max health upgrades, and environmental hazards (spikes, bear traps, tentacles, turrets).

---

## 2. Traversal & Movement Mechanics

Building on the existing robust state machine, these mechanics expand first-person parkour and momentum-based traversal.

*   **Mechanic: Momentum Wall-Run**
    *   **Description:** While sprinting in the air alongside a flat vertical surface, the player can stick to the wall for a brief duration, maintaining their forward momentum before leaping off.
    *   **Integration Synergy:** Expands the `PlayerStateMachine` (adding a `StateWallRun`). Utilizes `LocomotionComponent.sprint_active` and existing air momentum logic.
    *   **AAA Inspiration:** *Titanfall 2* / *Ghostrunner* (Fluid preservation of kinetic energy through environments).

*   **Mechanic: Slide-Tackle / Kinetic Breach**
    *   **Description:** Sliding into specific weakened environmental objects (like wooden barricades or `destructible_glass`) or lightweight enemies instantly shatters them, using the player's momentum as a weapon.
    *   **Integration Synergy:** Hooks into `StateSlide` and the `physics_pusher` node, applying a massive impulse or calling `take_damage()` on objects with a `HealthComponent` upon collision during a slide.
    *   **AAA Inspiration:** *Mirror's Edge* / *Dying Light* (Weaponizing traversal states).

*   **Mechanic: Tether-Swing (Grapple Hook)**
    *   **Description:** The player can fire a physical rope at specific anchor points (or metallic surfaces) to swing across chasms. The length of the rope can be dynamically adjusted while swinging.
    *   **Integration Synergy:** Builds directly upon the existing `physics_cable_3d` and `climable_rope` systems. The `InteractionScanner` would detect anchor points, and the `PlayerStateMachine` would enter a new `StateSwing`.
    *   **AAA Inspiration:** *Portal 2* (Systemic momentum physics) / *Dying Light* (Kinetic grappling).

---

## 3. Contextual Interactions

Enhancing the tactile, physical connection between the player and the environment.

*   **Mechanic: Physics-Based Barricading**
    *   **Description:** The player can pick up heavy objects (using the existing `heavy_pickable_box`) and wedge them against doors or in front of automated turrets to block line-of-sight or prevent enemies from entering.
    *   **Integration Synergy:** Utilizes the `InteractionComponent`'s heavy lifting state. Enemies (like `tentacle_enemy` or `turret`) would have their raycasts blocked by the physical collision of the held/dropped objects.
    *   **AAA Inspiration:** *Prey (2017)* / *Amnesia: The Bunker* (Emergent problem solving using physics props).

*   **Mechanic: Conductive Object Chaining**
    *   **Description:** Water puddles or metallic objects can be physically moved to bridge gaps in broken electrical circuits, powering unpowered doors or traps.
    *   **Integration Synergy:** Expands the `cable_builder` and `plug` systems. `pickable_object` items could receive a "conductive" tag, allowing them to act as dynamic nodes in puzzle circuits.
    *   **AAA Inspiration:** *Breath of the Wild* (Systemic elemental chemistry).

*   **Mechanic: Improvised Projectiles**
    *   **Description:** When holding specific small rigid bodies (like broken glass shards or rocks), the throw mechanic is altered. Instead of a standard physics toss, it acts as a high-velocity distraction or minor damage projectile against targets.
    *   **Integration Synergy:** Modifies `InteractionComponent.throw_held_item()`. The thrown item inherits a much higher impulse and triggers an AI sound-investigation event upon impact.
    *   **AAA Inspiration:** *Half-Life 2* (Gravity Gun logic) / *Dishonored* (Distraction mechanics).

---

## 4. Systemic & Environmental Mechanics

Leveraging the engine's physics and state-driven environment for emergent puzzle-solving.

*   **Mechanic: Thermal Updraft Generation**
    *   **Description:** The player can throw an `explosive_barrel` or ignite a `burnable_obstacle` underneath a grate to dynamically create a temporary updraft, allowing them to use their glider to reach new heights.
    *   **Integration Synergy:** Combines the `burnable_obstacle` logic with the `EnvironmentComponent.enter_updraft()` system. Fire sources dynamically spawn a temporary `updraft_volume`.
    *   **AAA Inspiration:** *Tears of the Kingdom* (Systemic environmental manipulation for traversal).

*   **Mechanic: Portal-Momentum Redirection**
    *   **Description:** When falling at high speeds into a floor portal, the player maintains their exact kinetic energy when exiting a wall portal, launching them horizontally across the map.
    *   **Integration Synergy:** Modifies the existing `portal.gd` logic to preserve the vector magnitude of `Player.velocity` and strictly rotate the vector relative to the exit portal's normal.
    *   **AAA Inspiration:** *Portal* (Speedy thing goes in, speedy thing comes out).

*   **Mechanic: Magnetic Repulsion Puzzles**
    *   **Description:** Reversing the polarity of a `physics_magnet` or `basalt_magnet` to repel the player or metallic objects. The player could stand on a metal plate and activate a magnet below to be launched upwards.
    *   **Integration Synergy:** Extends `physics_magnet`. Instead of only pulling rigidbodies or the player, a "repel" state applies inverse force vectors, integrating with the `PlayerLocomotionComponent`'s momentum.
    *   **AAA Inspiration:** *Half-Life 2: Episode One* (Core room puzzles) / *Portal 2* (Excursion Funnels/Faith Plates).
