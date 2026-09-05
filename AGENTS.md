# Working in this repo

## Clarity comes first

The goal of this code is that the next person to change it can see what it
does without reconstructing it. That goal outranks every other one here.

**Clarity is not the same thing as being brief.** Being brief is worth
something, but far less. When the two conflict, take the longer name, the
longer sentence, the extra clause in the `case`. A reader who has to look up
what a word means in this codebase has already lost more time than the
shorter name saved.

To achieve clarity, **always prefer concrete and common terms over invented
vocabulary** - a word coined for this codebase that a reader has to learn,
holding a meaning that plain words already had. Prefer concrete terms, even
when they are longer.

## Naming

### Test a name before proposing it

Ask: **where does this word come from?** A good name has an answer:

* it is what the interface already says on screen
* it is the name of the thing that causes it
* it is the common word for this, used the ordinary way

If the answer is "I made it up so we would have a word for this", the name is
wrong, however apt it feels while writing it. That feeling is not evidence —
the person who coins a term always finds it clear.

Worked example, `archive/plans/page-state.md` §2.0: every state name is
either the words the page already puts on screen (`:not_started` from "You
haven't started this form yet.") or the name of its cause (`:not_visible`
from the `visible?/2` callback that returned false). That section also lists
the names that were **rejected** and why, so nobody re-proposes them. When a
change settles a vocabulary question, write down the rejects too.

Counter-example, from the same work: `:workable?`. Invented, and it sat
beside the real callbacks `visible?/2` and `editable?/2` looking like a third
member of a family it was not in — "workable" and "editable" are near
synonyms in English while meaning unrelated things in the code. Two mistakes at
once: coining a word, and coining one that collides with the real names
sitting next to it.

### Reach for common words first

When in doubt, use the vocabulary Elixir and Phoenix already use, in the
ordinary way:

* pages: **index, show, new, edit, delete**
* functions over data: **list, get, create, update, delete**

These will not always fit — much of this library is about things Phoenix has
no word for. The point is not to force them; it is to try common
words first, and to coin one only for something that genuinely has no name
yet.

### Vocabulary this repo has settled on

One term, one meaning. Do not widen these, and do not introduce a synonym.

* **"user"** — the person working through a flow instance. Never "filler".
* **"position"** — exactly one thing: a place in a flow instance where a form
  sits, addressed by its `path`. Do not use the word for anything else.
* **start / edit / show** — the verbs on the instance side. **start** creates
  the form instance and pins the version; **edit** is the working page;
  **show** is read only. **Reopen** is its own action. Links read Start,
  Continue, or View — never "Open".
* **"gate"** — prose only, for the host's `on_mount`. It never appears in a
  function or state name.
* Compound names put **the domain noun last**: `snapshot_data`, not
  `data_snapshot`; `initial_data`, not `data_initial`.
* Shared logic for sibling LiveComponents lives in a module named **`Shared`**,
  not a module named for a concept.
* **Alias collisions do not drive names.** Argue from concepts. If two good
  names collide, alias one at the call site.

## Prose follows the same rule

This codebase carries unusually long moduledocs, on purpose: they say *why*,
not just what. They are held to the same standard as the code. A moduledoc
that introduces a term the code does not use has made the code harder to
read, not easier.

Say what a thing is before saying what it is for. Name the trade-off you
took and the one you rejected — a reader who knows why a door is locked does
not try to open it.

## When you rename something

Hard cutover. No aliases kept "for now", no `# renamed from` comments, no
deprecation shims. Write the code as though the new name had always been
there, and record the break in `CHANGELOG.md` where a reader will look for
it. A transition comment is a note to a reader who no longer exists.
