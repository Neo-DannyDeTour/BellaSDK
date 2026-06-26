import json

with open("extended_report.json", "r") as f:
    extended_report = json.load(f)

# Combine with existing report content
with open("final_report.md", "r") as f:
    existing_markdown = f.read()

markdown = existing_markdown + "\n\n"

for category, items in extended_report.items():
    markdown += f"## {category}\n\n"
    if not items:
        markdown += "No violations found based on the scan heuristics.\n\n"
    else:
        unique_items = list(set(items))
        unique_items.sort()
        for item in unique_items:
            # truncate long items slightly if they are huge lines
            if len(item) > 400 and not item.startswith("**Current Autoloads Detected:**"):
                item = item[:397] + "..."
            markdown += f"- {item}\n"
    markdown += "\n"

with open("combined_final_report.md", "w") as f:
    f.write(markdown)
