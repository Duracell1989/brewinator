# Changelog

## [1.29.3] - 2026-11-03

This new patch release has fixed some minor regressions over the previous one:

- Fixed "Illegal instruction" error on certain x86_64 CPUs without SSE4.1.
  [pr#5162]

- Fixed "`lock()` not supported" error on Solaris. [pr#5167]

[1.29.3]: https://github.com/rust-lang/rustup/releases/tag/1.29.3
[pr#5162]: https://github.com/rust-lang/rustup/pull/5162
[pr#5167]: https://github.com/rust-lang/rustup/pull/5167

## [1.29.2] - 2026-10-20

This is a small release which only updates the rustls-webpki and
webpki-root-certs dependencies to address the problematic eMudhra
intermediate certificates issue described in [CVE-2026-111943].

See also [RUSTSEC-2026-0382].

[1.29.2]: https://github.com/rust-lang/rustup/releases/tag/1.29.2
[CVE-2026-111943]: https://www.cve.org/CVERecord?id=CVE-2026-111943
[RUSTSEC-2026-0382]: https://rustsec.org/advisories/RUSTSEC-2026-0382.html

## [1.29.1] - 2026-08-13

This new patch release has brought some minor improvements and fixes over the previous one.
