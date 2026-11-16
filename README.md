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
- **Click** — like a tickle: two arched eyes ( n   n ), a few small hearts and one short line appear, then gently fade.
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

## Sound

Two recorded tones, made by esorhizome in FL Studio Mobile (MiniSynth "Fifth", filtered, with reverb).

The higher one opens. The lower one closes.

They live in `sounds/`. If that folder is missing, the pet makes a soft bell in code instead.

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
