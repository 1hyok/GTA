"""Parse checked-in Python sources without importing them or writing bytecode."""
import ast
import json
from pathlib import Path
import subprocess
import sys
import tokenize


def main() -> int:
    root = Path(sys.argv[1]).resolve()
    listing = subprocess.run(
        ["git", "-C", str(root), "ls-files", "-z", "--", "*.py", "*.pyw"],
        check=True,
        capture_output=True,
    )
    names = [name.decode("utf-8") for name in listing.stdout.split(b"\0") if name]
    # Vendored tools have their own dependencies and release lifecycle.
    paths = [root / name for name in names if not name.startswith(("third_party/", "Lester-Ver2.0/"))]
    # Include this new checker before its first commit, too.
    checker = Path(__file__).resolve()
    if checker not in paths:
        paths.append(checker)
    errors = []
    for path in paths:
        try:
            with tokenize.open(path) as source:
                ast.parse(source.read(), filename=str(path))
        except (SyntaxError, UnicodeError) as error:
            errors.append({"file": str(path.relative_to(root)), "message": str(error)})
    print(json.dumps({"files": len(paths), "errors": errors}, ensure_ascii=True))
    return bool(errors)


if __name__ == "__main__":
    sys.exit(main())
