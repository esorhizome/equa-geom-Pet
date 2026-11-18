# geom-Pet

*Part of the equa series · esorhizome*

A small wireframe solid that sits in a corner of your screen and turns slowly.

It leans a little toward your cursor, like a dog in the same room keeping an eye on you.

It asks for nothing. It only answers when you touch it.

---

## Start it

Double-click **geom-Pet.cmd**.

---

## Touch it

- **Drag** — move it anywhere.
- **Click** — like a tickle: two dot eyes appear, squeeze shut in a long happy squint ( n   n ) and open again just before they fade, a few small hearts open out from the middle, and one short line appears. Then it all gently fades.
- Only the shape itself answers a click. The empty space around it lets clicks pass through.
- **Hover** — shows your *anchor*, the one thing you're doing right now.
- **Right-click** — the menu:
  - ⚓ anchor · ◯ breathe · △ shape · ◫ size · ♪ sound · ◐ rest · ✕ close
- **Size** — a slider in the menu, from small up to about half the screen's height.

---

## What it does on its own

- It turns, on two slow axes in the golden ratio, so the tumble never quite repeats.
- It leans a little toward your cursor.
- If you've been away for four minutes or more, it gives one small spin when you come back.

That's all. No timers, no reminders, no counting.

---

## The shapes

Thirteen solids from equanim's polyhedra library:

tetrahedron · cube · octahedron · dodecahedron · icosahedron · stella octangula · cuboctahedron · rhombic dodecahedron · truncated tetrahedron · truncated octahedron · truncated cube · rhombicuboctahedron · icosidodecahedron

None of them has more than 60 edges, so the pet stays light.

---

## The lines

The short lines the pet shows live in `lines.txt`, one per row.

Add your own on a new row. Put `|` where the words should break onto a new row.

Close the pet and start it again to see new lines.

Where each fact comes from, and how it was checked: [SOURCES.md](SOURCES.md).

---

## Sound

One soft tone, made in code each time the pet starts: a root note with its fifth and octave, a gentle rise, then a short even fade.

It rings higher to open and lower to close.

**♪ sound** in the menu turns it off.

---

## Where it keeps things

`%APPDATA%\geom-Pet\` holds your settings (place, size, shape, anchor), the two bell sounds, and a small log if anything goes wrong.

---

## Check it

```
powershell -STA -ExecutionPolicy Bypass -File geom-Pet.ps1 -Check
```

This builds every shape and the window without showing anything, and prints what it found.

---

## Start with Windows (optional)

1. Press **Win + R**.
2. Type `shell:startup` and press Enter.
3. Put a shortcut to **geom-Pet.cmd** in that folder.

---

*Thanks to equanim's `FractalMesh` polyhedra library, which this shelf of shapes comes from.*

---

## Licence

CC BY 4.0 · Sarah Clemencia Gomes (esorhizome). Share and adapt it freely, with credit. The full text is in [LICENSE](LICENSE).
