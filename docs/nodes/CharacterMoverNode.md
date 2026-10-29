## Shapes

A character mover collides through Box2D's mover functions, which work with
capsules. Its shapes are used as capsules:

- A **capsule** or **circle** as it is.
- A **box**, **polygon** or **chain**: the capsule that fits its bounds (along its longer side).
  Corners are rounded.
- A **segment**: a capsule along it.

With several shapes, it collides with all of them; sensor shapes are skipped.
The debug view draws the shapes you set. With no shape, it uses its
**Radius** and **Height**.
