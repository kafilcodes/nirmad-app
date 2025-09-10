# UI/UX Guidelines for Nirmad

These principles are project-wide. Use them for all screens and roles.

- Law of Similarity & Proximity: group related items; keep visual consistency for similar controls.
- Spacing system: use multiples of 4. Base gutter: R.gutter(context).
- Typographic scale: prefer rem-based values (1rem = 16px). Small text uses higher line-height for readability.
- Design tokens: rely on ThemeData/ColorScheme for colors and surfaces; define accent and light-accent as primary/secondary.
- Hierarchy first: headings > body > meta; use weight, size, and color contrast to establish flow.
- Z-pattern for content bodies; grids/lists/cards/charts should align to the same grid.
- Use skeletons/shimmers during loading for significant content sections.

Notes
- Avoid fixed pixel paddings large than 24px; favor R.gutter(context) and ResponsiveValue when possible.
- Keep components modular and reusable; prefer composition over duplication.
- Respect platform constraints for touch targets and accessibility.
