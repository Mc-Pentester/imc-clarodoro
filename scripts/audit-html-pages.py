#!/usr/bin/env python3
"""Audit HTML structure, local static assets, duplicate IDs and JavaScript syntax."""
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path
import re
from urllib.parse import unquote, urlsplit
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PAGES = {
    "index.html": "private-pages/index.php",
    "eleves.html": "private-pages/index.php",
    "matieres.html": None,
    "resultats.html": "private-pages/resultats.php",
    "finances.html": "private-pages/finances.php",
    "personnel.html": "private-pages/personnel.php",
    "annees-scolaires.html": None,
    "Vacances.html": None,
    "badge.html": "private-pages/badge.php",
    "PDG.html": "private-pages/PDG.php",
    "payroll-recovery.html": "private-pages/payroll-recovery.php",
}
ASSET_EXTENSIONS = {
    ".css", ".js", ".mjs", ".png", ".jpg", ".jpeg", ".gif", ".svg",
    ".webp", ".ico", ".woff", ".woff2", ".ttf", ".map"
}
JS_TYPES = {"", "text/javascript", "application/javascript", "module"}


class PageParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids = []
        self.script_open = 0
        self.script_close = 0
        self.body_close = 0
        self.html_close = 0
        self.after_html_text = []
        self.visible_script_like_text = []
        self.html_closed = False
        self.in_script = False
        self.current_script = None
        self.inline_scripts = []
        self.assets = []
        self.script_sources = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        tag = tag.lower()
        if self.html_closed:
            pass
        if "id" in attrs and attrs["id"]:
            self.ids.append(attrs["id"])
        if tag == "script":
            self.script_open += 1
            self.in_script = True
            self.current_script = {"src": attrs.get("src"), "type": (attrs.get("type") or "").lower(), "chunks": []}
            if attrs.get("src"):
                self.script_sources.append(attrs["src"])
                self.assets.append(attrs["src"])
        for attr in ("src", "href"):
            value = attrs.get(attr)
            if value and (tag, attr) != ("script", "src"):
                self.assets.append(value)

    def handle_data(self, data):
        if self.in_script and self.current_script is not None:
            self.current_script["chunks"].append(data)
        elif data.strip():
            if self.html_closed:
                self.after_html_text.append(data.strip()[:100])
            if re.search(r"\bconst\s+blob\s*=\s*new\s+Blob\b|\bfunction\s+echapper\s*\(", data):
                self.visible_script_like_text.append(data.strip()[:160])

    def handle_endtag(self, tag):
        tag = tag.lower()
        if tag == "script":
            self.script_close += 1
            if self.current_script is not None:
                self.inline_scripts.append(self.current_script)
            self.current_script = None
            self.in_script = False
        elif tag == "body":
            self.body_close += 1
        elif tag == "html":
            self.html_close += 1
            self.html_closed = True


def local_asset_path(value):
    value = value.strip()
    if not value or value.startswith(("#", "//")):
        return None
    parsed = urlsplit(value)
    if parsed.scheme or not parsed.path:
        return None
    path = Path(unquote(parsed.path.lstrip("/")))
    if path.suffix.lower() not in ASSET_EXTENSIONS:
        return None
    return (ROOT / path).resolve()


def main():
    errors = []
    checked_js = set()
    for public, private in PAGES.items():
        source = private or public
        path = ROOT / source
        if not path.is_file():
            errors.append(f"{public}: source file missing: {source}")
            continue
        parser = PageParser()
        try:
            parser.feed(path.read_text(encoding="utf-8"))
            parser.close()
        except Exception as exc:
            errors.append(f"{source}: HTML parsing failed: {exc}")
            continue

        if parser.script_open != parser.script_close:
            errors.append(f"{source}: script tags unbalanced ({parser.script_open} open, {parser.script_close} close)")
        if parser.body_close != 1:
            errors.append(f"{source}: expected one </body>, found {parser.body_close}")
        if parser.html_close != 1:
            errors.append(f"{source}: expected one </html>, found {parser.html_close}")
        duplicates = sorted(k for k, count in Counter(parser.ids).items() if count > 1)
        if duplicates:
            errors.append(f"{source}: duplicate HTML id(s): {', '.join(duplicates)}")
        duplicate_scripts = sorted(k for k, count in Counter(parser.script_sources).items() if count > 1)
        if duplicate_scripts:
            errors.append(f"{source}: duplicate script src(s): {', '.join(duplicate_scripts)}")
        if parser.after_html_text:
            errors.append(f"{source}: visible text after </html>: {' | '.join(parser.after_html_text)}")
        if parser.visible_script_like_text:
            errors.append(f"{source}: JavaScript appears outside a script element as visible text: {' | '.join(parser.visible_script_like_text)}")

        for raw in parser.assets:
            asset = local_asset_path(raw)
            if asset is not None and not asset.is_file():
                errors.append(f"{source}: missing local asset {raw}")

        for item in parser.inline_scripts:
            script_type = item["type"]
            src = item["src"]
            code = "".join(item["chunks"])
            if script_type not in JS_TYPES:
                continue
            if src:
                asset = local_asset_path(src)
                if asset is None or not asset.is_file() or asset.suffix.lower() not in {".js", ".mjs"}:
                    continue
                js_path = asset
                if js_path in checked_js:
                    continue
                checked_js.add(js_path)
                result = subprocess.run(["node", "--check", str(js_path)], text=True, capture_output=True)
                if result.returncode:
                    errors.append(f"{source}: JavaScript syntax error in {src}: {(result.stderr or result.stdout).strip()}")
            elif code.strip():
                suffix = ".mjs" if script_type == "module" else ".js"
                with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=suffix, delete=False) as tmp:
                    tmp.write(code)
                    temp_name = tmp.name
                result = subprocess.run(["node", "--check", temp_name], text=True, capture_output=True)
                Path(temp_name).unlink(missing_ok=True)
                if result.returncode:
                    errors.append(f"{source}: inline JavaScript syntax error: {(result.stderr or result.stdout).strip()}")

        print(f"HTML AUDIT: {public} -> {source}: PASS")

    if errors:
        print("\nHTML AUDIT ERRORS:")
        for error in errors:
            print(f"- {error}")
        raise SystemExit(1)
    print(f"HTML/JS STRUCTURE AUDIT: PASS ({len(PAGES)} pages, {len(checked_js)} local JS files syntax-checked)")


if __name__ == "__main__":
    main()
