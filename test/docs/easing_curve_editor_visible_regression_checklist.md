# Easing Curve Inspector visible-editor regression checklist

Run these checks in a visible Godot 4.7 editor with an `EasingCurve` selected.
They intentionally remain manual because native `FoldableContainer` layout and
Inspector focus/scroll behavior are not deterministic under `--editor --headless`.

## Points foldable

- Collapse Points once: the outer Inspector scroll position does not jump.
- Repeat collapse/expand several times: scroll position and layout remain stable.
- Click the fold title: it remains mouse-clickable.
- Confirm the native foldable does not take focus or trigger Inspector `follow_focus`.

## Curve Editor foldable

- Repeat the same first-collapse, repeated-toggle, title-click, and focus/scroll checks.

## Responsive Inspector

- At a narrow Inspector width, check Points property/value alignment, reset controls,
  labels, foldables, and Curve Editor for clipping or overlap.
- Repeat at a wide Inspector width.

Keep the intentional workaround in production unchanged:

```gdscript
_native_section.focus_mode = Control.FOCUS_NONE
```
