import json

with open("report.json", "r") as f:
    report = json.load(f)

# Manually add Structural Consistency findings
report["Structural Consistency"] = [
    "The project mixes event-driven architecture (Signals) and Direct Node References for inter-node communication.",
    "**Example Files using Signals:** `shared/events.gd`, `player/player.gd`",
    "**Example Files using Direct References (without signals):** `interactables/pickable_object.gd`, `interactables/keycard_pickup.gd`",
    "**Recommendation:** Unify the architecture by adopting an Event Bus pattern (using an `Events` singleton) or strict Signal usage for all loosely coupled inter-node communications, avoiding `get_node()` across different scene boundaries."
]

markdown = "# Architecture and Codebase Standardization Report\n\n"
markdown += "Based on an exhaustive analysis of the codebase (excluding `addons/`, `Player_OLD.gd`, and `playerENUM_TEST.gd`), here are the findings regarding standardization targets:\n\n"

for category, items in report.items():
    markdown += f"## {category}\n\n"
    if not items:
        markdown += "No violations found.\n\n"
    else:
        # Deduplicate items
        unique_items = list(set(items))
        unique_items.sort()
        for item in unique_items:
            markdown += f"- {item}\n"
    markdown += "\n"

with open("final_report.md", "w") as f:
    f.write(markdown)
