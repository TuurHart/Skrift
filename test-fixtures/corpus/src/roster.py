"""The synthetic people roster — byte-compatible with the app's names.json.

Everyone here is invented. The narrator of the corpus is Fenna de Wit, who runs a small
bicycle-repair-and-ceramics workshop in Rotterdam with her partner Lotte. The roster is
built to exercise the name-linking tiers: distinctive names (auto-link), two people who
share a first name (ambiguous), first names that are also common words (suggested only),
and people mentioned in notes who are NOT on the roster (stay plain).
"""
import uuid

NAMESPACE = uuid.UUID("7b1c9d2e-4a3f-4c8b-9e1d-2f5a6b7c8d9e")   # corpus id namespace
STAMP = "2026-09-01T09:00:00Z"


def person(canonical, aliases, short=None):
    return {"canonical": f"[[{canonical}]]", "aliases": aliases, "short": short or aliases[0],
            "lastModifiedAt": STAMP}


ROSTER = [
    person("Lotte Vos", ["Lotte"]),                      # partner — distinctive → auto-link
    person("Hendrik Vos", ["Hendrik", "Henk"]),          # Lotte's father — two aliases
    person("Jack Morrow", ["Jack"]),                     # two Jacks → "Jack" is ambiguous
    person("Jack Ferreira", ["Jack"]),
    person("Rose Aldana", ["Rose"]),                     # common word → suggested tier
    person("Will Okafor", ["Will"]),                     # common word → "will" stays plain
    person("Mariam Haddad", ["Mariam"]),
    person("Sam Ruiz", ["Sam"]),                         # two Sams → ambiguous
    person("Sam Lindqvist", ["Sam"]),
    person("Bruno Castel", ["Bruno"]),
    person("Nadia Elharrak", ["Nadia"]),
    person("Pieter-Jan Claes", ["Pieter-Jan", "PJ"]),   # hyphen + initials alias
    person("Ines Månsson", ["Ines"]),                    # non-ASCII in canonical
]
# Mentioned in notes but NOT on the roster (must stay plain text): Marco, Yusuf, Tante Ria, Dr. Feldman, Kai.
