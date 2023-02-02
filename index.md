---
layout: default
---

Scaling Repo Scanner is a Github Actions framework to perform various code-analytics tasks on publicly available Github Repositories.

## Scan logs

{% assign scans_by_year = site.data.scans | group_by: "year" | sort_by: "name" %}
{% for scan_year in scans_by_year %}
{% assign scans = scan_year.items %}
- **{{ scan_year.name }}**
{% for scan in scans reversed %}
  - **[{{ scan.date }}](./scans/{{ scan.id }})**: {{ scan.bugs }} bugs
{% endfor %}
{% endfor %}
