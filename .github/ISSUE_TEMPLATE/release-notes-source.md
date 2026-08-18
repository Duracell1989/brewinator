---
name: Missing or wrong release-notes source
about: A package resolves to "no forge repo detected", is skipped when it shouldn't be, or points at the wrong notes
title: "[notes] <package name>"
labels: notes-source
---

**Package name** (as `brew outdated` prints it):

**Formula or cask?**

**Where the real release notes live** (URL):

**What brewinator does today**

- [ ] Says "No forge repo detected"
- [ ] Is skipped by the built-in skip list, but notes do exist
- [ ] Fetches the wrong notes / wrong version
- [ ] Something else (describe below)

**Anything else**

Notes only need to exist somewhere fetchable - a GitHub/GitLab/Gitea release, a Sparkle appcast, a changelog file, or a vendor page. A link is enough; a pull request adding the source is very welcome but not required.
