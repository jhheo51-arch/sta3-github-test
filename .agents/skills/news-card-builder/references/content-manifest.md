# Content manifest

Use this structure when many sources or items must be combined. JSON is preferred when another script will consume the result; Markdown is acceptable for a human-only handoff.

## Collection fields

- `subject`: roundup topic
- `audience`: intended readers
- `cutoff_at`: latest allowed source time, including timezone
- `period_start`, `period_end`: coverage window
- `source_policy`: primary-source preference and allowed fallbacks
- `items`: normalized information records
- `cards`: planned and generated card records

## Item fields

- `id`: stable identifier derived from the canonical source URL
- `category`: user-requested or evidence-based grouping
- `title`: concise factual title
- `published_at`, `starts_at`, `ends_at`: keep publication and event dates separate
- `status`: current, upcoming, expired, or unknown
- `facts`: verified numbers, conditions, and short summary
- `price`: amount plus unit and variation note, or an explicit unknown state
- `source_url`: canonical source
- `source_kind`: official, primary, secondary, or user-provided
- `image_path` or `image_url`: directly relevant visual
- `verification_notes`: conflicts, missing fields, and check timestamp

## Card fields

- `role`: overview or detail
- `topic`: card subject
- `headline`, `period_label`, `body_copy`: exact display text
- `item_ids`: records represented on the card
- `reference_images`: each path with its role
- `output_path`: versioned image path
- `qa`: spelling, date, price, clipping, contrast, attribution, and logo checks

## Compression rules

- Prefer one claim per line.
- Keep publication date distinct from event period.
- Put the most time-sensitive verified item first.
- Do not convert an uncertain value into a precise number.
- If the overview becomes crowded, reduce item count or add detail cards instead of shrinking essential text beyond readability.
