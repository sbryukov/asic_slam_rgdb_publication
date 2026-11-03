#!/usr/bin/env python3
"""Prepare the LaTeX sources for conversion to a GitHub Wiki page.

  * flattens \\input / \\include into one file and strips comments;
  * unwraps the \\twocolumn[...] title block so pandoc sees title + abstract;
  * renders every figure/algorithm whose body is not a plain \\includegraphics
    (TikZ, algorithmic, placeholder boxes, ...) to PNG with pdflatex;
  * converts \\includegraphics images (PDF -> PNG, PNG/JPG copied);
  * turns table* / figure* into table / figure (pandoc keeps the caption).

Usage: prepare.py <main.tex> <out_dir>
Writes <out_dir>/flat.tex and <out_dir>/figures/*.png.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

GRAPHICS_DIRS = ["", "figures"]
IMG_EXT = [".pdf", ".png", ".jpg", ".jpeg"]
DPI = "200"


def strip_comments(text):
    out = []
    for line in text.splitlines():
        m = re.search(r"(?<!\\)%", line)
        if m:
            line = line[: m.start()]
            if not line.strip():
                continue
        out.append(line)
    return "\n".join(out) + "\n"


def flatten(path, root):
    for cand in (path, path + ".tex"):
        full = os.path.join(root, cand)
        if os.path.isfile(full):
            break
    else:
        print(f"prepare: warning: {path} not found", file=sys.stderr)
        return ""
    with open(full, encoding="utf-8") as f:
        text = strip_comments(f.read())
    return re.sub(
        r"\\(?:input|include)\{([^}]+)\}",
        lambda m: flatten(m.group(1).strip(), root),
        text,
    )


def braced(text, start):
    """Return (content, end) of the {...} group starting at text[start] == '{'."""
    depth, i = 0, start
    while i < len(text):
        c = text[i]
        if c == "\\":
            i += 2
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1 : i], i + 1
        i += 1
    raise ValueError("unbalanced braces")


def take_command(body, name):
    """Remove the first \\name[...]{...} from body; return (arg, body)."""
    m = re.search(r"\\" + name + r"\*?\s*(\[[^\]]*\])?\s*\{", body)
    if not m:
        return None, body
    arg, end = braced(body, m.end() - 1)
    return arg, body[: m.start()] + body[end:]


def unwrap_twocolumn(text):
    m = re.search(r"\\twocolumn\s*\[", text)
    if not m:
        return text
    depth, i = 1, m.end()
    while depth and i < len(text):
        if text[i] == "[":
            depth += 1
        elif text[i] == "]":
            depth -= 1
        i += 1
    inner = text[m.end() : i - 1]
    inner = re.sub(r"\\(begin|end)\{@twocolumnfalse\}", "", inner)
    return text[: m.start()] + inner + text[i:]


class Renderer:
    def __init__(self, preamble, out_dir, src_root):
        self.preamble = preamble
        self.fig_dir = os.path.join(out_dir, "figures")
        self.src_root = src_root
        self.count = 0
        os.makedirs(self.fig_dir, exist_ok=True)

    def render_latex(self, body, name):
        doc = (
            "\\documentclass[varwidth=12cm,border=6pt]{standalone}\n"
            + self.preamble
            + "\n\\setlength{\\columnwidth}{12cm}\\setlength{\\linewidth}{12cm}\n"
            "\\begin{document}\n" + body + "\n\\end{document}\n"
        )
        with tempfile.TemporaryDirectory() as tmp:
            tex = os.path.join(tmp, "fig.tex")
            with open(tex, "w", encoding="utf-8") as f:
                f.write(doc)
            env = dict(os.environ, TEXINPUTS=self.src_root + "//:")
            r = subprocess.run(
                ["pdflatex", "-interaction=nonstopmode", "-halt-on-error", "fig.tex"],
                cwd=tmp, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            )
            pdf = os.path.join(tmp, "fig.pdf")
            if r.returncode != 0 or not os.path.isfile(pdf):
                log = r.stdout.decode(errors="replace")
                errs = [l for l in log.splitlines() if l.startswith("!")]
                print(f"prepare: warning: could not render {name}: {errs[:3]}",
                      file=sys.stderr)
                return None
            return self.pdf_to_png(pdf, name)

    def pdf_to_png(self, pdf, name):
        target = os.path.join(self.fig_dir, name)
        subprocess.run(["pdftocairo", "-png", "-r", DPI, "-singlefile",
                        pdf, target], check=True)
        return f"figures/{name}.png"

    def find_image(self, ref):
        for d in GRAPHICS_DIRS:
            base = os.path.join(self.src_root, d, ref)
            for ext in [""] + IMG_EXT:
                p = base + ext
                if os.path.isfile(p) and os.path.splitext(p)[1].lower() in IMG_EXT:
                    return p
        return None

    def convert_image(self, m):
        ref = m.group(2).strip()
        src = self.find_image(ref)
        if not src:
            print(f"prepare: warning: image {ref} not found", file=sys.stderr)
            return m.group(0)
        self.count += 1
        stem = re.sub(r"[^A-Za-z0-9_-]", "_", os.path.splitext(os.path.basename(src))[0])
        ext = os.path.splitext(src)[1].lower()
        if ext == ".pdf":
            out = self.pdf_to_png(src, stem)
        else:
            shutil.copy(src, os.path.join(self.fig_dir, stem + ext))
            out = f"figures/{stem}{ext}"
        return "\\includegraphics{" + out + "}"


def process_floats(text, r):
    env_re = re.compile(
        r"\\begin\{(figure\*?|algorithm\*?)\}(\[[^\]]*\])?(.*?)\\end\{\1\}", re.S)
    counters = {"figure": 0, "algorithm": 0}

    def repl(m):
        kind = m.group(1).rstrip("*")
        counters[kind] += 1
        body = m.group(3)
        caption, body = take_command(body, "caption")
        label, body = take_command(body, "label")
        body = body.replace("\\centering", "").strip()
        if kind == "algorithm" and not label:
            label = f"alg:auto{counters[kind]}"
        name = re.sub(r"[^A-Za-z0-9_-]", "_", label or f"{kind}{counters[kind]}")

        only_graphics = re.fullmatch(
            r"(\s*\\includegraphics\s*(\[[^\]]*\])?\s*\{[^}]+\}\s*(\\hfill|\\\\|\\quad)?)+",
            body)
        if only_graphics:
            img = re.sub(r"\\includegraphics\s*(\[[^\]]*\])?\s*\{([^}]+)\}",
                         r.convert_image, body)
        else:
            png = r.render_latex(body, name)
            img = f"\\includegraphics{{{png}}}" if png else body

        out = "\\begin{figure}\n" + img + "\n"
        if caption is not None:
            out += "\\caption{" + caption + "}\n"
        if label:
            out += "\\label{" + label + "}\n"
        return out + "\\end{figure}"

    return env_re.sub(repl, text)


def main():
    main_tex, out_dir = sys.argv[1], sys.argv[2]
    root = os.path.dirname(os.path.abspath(main_tex))
    os.makedirs(out_dir, exist_ok=True)

    text = flatten(os.path.basename(main_tex), root)
    # Preamble for standalone rendering = everything between \documentclass and
    # \begin{document} (packages, macros, \hypersetup ...).
    head, _, _ = text.partition("\\begin{document}")
    preamble = re.sub(r"\\documentclass(\[[^\]]*\])?\{[^}]*\}", "", head)
    preamble = re.sub(r"\\usepackage(\[[^\]]*\])?\{geometry\}", "", preamble)

    text = unwrap_twocolumn(text)
    # \appendix is dropped by pandoc - keep a marker for the Lua filter
    text = re.sub(r"\\appendix\b", r"\\begin{wikiappendix}\\end{wikiappendix}", text)
    text = re.sub(r"\\begin\{(table|figure)\*\}", r"\\begin{\1}", text)
    text = re.sub(r"\\end\{(table|figure)\*\}", r"\\end{\1}", text)
    # threeparttable wraps the table in an extra block and hides its label
    text = re.sub(r"\\(begin|end)\{threeparttable\}", "", text)
    text = process_floats(text, Renderer(preamble, out_dir, root))

    with open(os.path.join(out_dir, "flat.tex"), "w", encoding="utf-8") as f:
        f.write(text)


if __name__ == "__main__":
    main()
