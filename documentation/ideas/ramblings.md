# Ramblings

A place for project lore, origin stories, and background that doesn't fit in
the formal docs but is worth remembering. Loose, narrative, first-person.
Nothing here is spec — it's the *why* behind the names and choices.

---

## The Robinson and Dogberry Origin Story (Mila)

The basic idea is that I miss the simplicity of CGI. Every file represented
a page in the URL path by its mere presence in that tree. I recognized that
it would need to do more than just execute files, but I still wanted that
old-school feeling of laying out a site in a directory tree. My old high
school is Robinson Secondary, so I named it Robinson. That Ruby library is
still running unotate.com.

The system worked well, but I recognized that it needed to be rebuilt from
scratch using what I'd learned. So I began a Ruby library called Dogberry.
It was to be a production-quality middleware realization of what I wanted
Robinson to be.

Then I stopped coding in Ruby and Dogberry was never quite finished. It was
pretty cool, though. So now we're back to calling it the Robinson handler —
the directory-tree-driven page handler living inside the KScript Dogberry
framework. Dogberry is the middleware layer; Robinson is the filesystem-tree
handler that originally inspired the whole thing.
