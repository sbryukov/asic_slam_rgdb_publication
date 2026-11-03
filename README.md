# ASIC SLAM 

LaTeX sources for a paper on an ASIC accelerator for SLAM. The setup uses the `article` class, `natbib`/BibTeX and `pdflatex` — a combination that compiles reliably on the arXiv build server.

## Repository Layout

```
main.tex              root file (metadata, section order)
preamble.tex          package imports
macros.tex            custom commands: \TODO, \NUM, \sysname, SLAM notation
references.bib        bibliography
sections/             sections: 00_abstract … 09_appendix
tables/               tables (included via \input)
figures/              figures (PDF/PNG/JPG, TikZ diagrams *.tikz)
.vscode/              LaTeX Workshop settings, tasks, snippets
Makefile, .latexmkrc  build configuration
scripts/wiki/         LaTeX -> GitHub Wiki conversion (make wiki, CI deploy_wiki)
build/                PDF and build artifacts (created automatically)
```

## Setting Up Ubuntu

Tested on Ubuntu 22.04 / 24.04.

### 1. Basic tools

```bash
sudo apt update
sudo apt install -y git make wget gpg apt-transport-https
```

### 2. TeX Live

Minimal set of packages sufficient for this template (~1.5 GB):

```bash
sudo apt install -y \
  texlive-latex-base texlive-latex-recommended texlive-latex-extra \
  texlive-fonts-recommended lmodern \
  texlive-science texlive-pictures \
  texlive-extra-utils \
  latexmk
```

| Package | Provides |
|---|---|
| `texlive-latex-base` | `pdflatex`, `bibtex`, `natbib`, `plainnat`, `babel` |
| `texlive-latex-recommended` | `microtype`, `booktabs`, `listings`, `mathtools`, `xcolor`, `subfig` |
| `texlive-latex-extra` | `cleveref`, `todonotes`, `enumitem`, `multirow`, `makecell`, `threeparttable` |
| `texlive-fonts-recommended`, `lmodern` | Latin Modern fonts |
| `texlive-science` | `siunitx`, `algorithmicx` |
| `texlive-pictures` | TikZ/PGF |
| `texlive-extra-utils` | `texcount` (`make wordcount`) |
| `latexmk` | automated builds |

To install everything at once, use `sudo apt install texlive-full` (~6 GB).

Verify the installation:

```bash
pdflatex --version && bibtex --version && latexmk --version
```

### 3. Visual Studio Code

Via snap (simplest):

```bash
sudo snap install code --classic
```

or from the official Microsoft repository (updated through `apt`):

```bash
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/microsoft.gpg
sudo install -D -o root -g root -m 644 /tmp/microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
  | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
sudo apt update && sudo apt install -y code
```

### 4. VS Code extensions

When you first open the folder, VS Code offers the recommended extensions from `.vscode/extensions.json` — click **Install All**. Alternatively, from the terminal:

```bash
code --install-extension James-Yu.latex-workshop
code --install-extension ltex-plus.vscode-ltex-plus
code --install-extension streetsidesoftware.code-spell-checker
code --install-extension Gruntfuggly.todo-tree
```

| Extension | Purpose |
|---|---|
| LaTeX Workshop | build, PDF preview, SyncTeX, autocompletion |
| LTeX+ | grammar and style checking (LanguageTool, works offline; downloads Java and LanguageTool on first run) |
| Code Spell Checker | spelling in text and comments |
| Todo Tree | lists all `\TODO{}` / `\NOTE{}` markers in the sidebar |

### 5. arXiv tooling (optional)

`arxiv_latex_cleaner` strips comments from the sources before submission. Ubuntu 23.04+ blocks `pip install` into the system Python, so install it with `pipx`:

```bash
sudo apt install -y pipx
pipx ensurepath          # then restart the terminal
pipx install arxiv-latex-cleaner
```

### 6. Clone and build

```bash
git clone <repository-URL> asic_slam_publication
cd asic_slam_publication
make            # -> build/main.pdf
code .
```

If `make` finishes without errors and `build/main.pdf` appears, the environment is ready.

## Working in VS Code

- The PDF is rebuilt every time a `.tex` file is saved (recipe `latexmk (pdflatex)`).
- Open the PDF preview in a VS Code tab with `Ctrl+Alt+V`; jump from PDF to source with `Ctrl+Click` on the PDF, and from source to PDF with `Ctrl+Alt+J`.
- Tasks (`Ctrl+Shift+P` → *Tasks: Run Task*): *Build PDF*, *Build arXiv package*, *Clean*, *Word count*. `Ctrl+Shift+B` builds the PDF.
- Snippets: type `fig`, `tab` or `todo` and press `Tab`.

Building from the terminal: `make` (or `latexmk main.tex`); continuous build: `make watch`.

The PDF and all intermediate files (`.aux`, `.log`, `.bbl`, `.synctex.gz`, …) go to `build/`; the output is `build/main.pdf`. Cleanup: `make clean` (intermediate files) or `make distclean` (the whole `build/` folder and the arXiv package).

## Writing Markers

- `\TODO{...}` — red marker for text still to be written; `\NOTE{...}` — a note; `\NUM` — placeholder for a number; `\CITE` — citation needed.
- Todo Tree lists all markers in the sidebar.
- The system name is defined in one place: `\sysname` in `macros.tex` (currently the working name `SlamChip`).

## Submitting to arXiv

```bash
make arxiv
```

This builds the PDF, copies the sources together with the generated `build/main.bbl` into `arxiv_submission/`, strips comments if `arxiv_latex_cleaner` is installed, packs everything into `arxiv_submission.tar.gz`, and test-compiles the archive without the `.bib` file (in `build/arxiv_test/`).

Pre-submission checklist:

- [ ] no `\TODO`, `\NUM` or `\CITE` left (`make arxiv-check` reports how many remain);
- [ ] markers disabled in the final version: in `macros.tex` replace the `\TODO` definition with `\renewcommand{\TODO}[1]{}`;
- [ ] comments with internal notes removed — arXiv publishes the source files;
- [ ] figures in PDF/PNG/JPG (pdflatex does not accept EPS), file names without spaces or non-ASCII characters;
- [ ] abstract in the submission form ≤ 1920 characters, with no LaTeX macros such as `\sysname`;
- [ ] primary category (`cs.AR`, cross-list `cs.RO`, `cs.CV`) and license selected;
- [ ] entries in `references.bib` checked against their DOIs (`li2019cnn_slam_asic` is a placeholder and must be replaced).

## Wiki

The CI stage `deploy_wiki` (on pushes to the default branch and on `v*` tags) publishes the paper to the repository Wiki:

- **Home** page: title, authors, a **Download PDF** link, abstract, table of contents and the full article text (converted from LaTeX with pandoc: numbered sections, cross-references, numeric citations, tables, math);
- `assets/asic_slam.pdf` and `assets/figures/*.png` (TikZ figures, algorithms and placeholders rendered to PNG) are committed to the `<repo>.wiki.git` repository.

Only `Home.md` and `assets/` are overwritten; other wiki pages are kept.

One-time setup: enable the Wiki in the repository settings and create any first page (the wiki repository does not exist until then). The job pushes with `GITHUB_TOKEN`; if that is not allowed, add a fine-grained token with *Contents: read and write* as the secret `WIKI_TOKEN`. Runner needs `python3` and `pdftocairo` (`sudo apt install poppler-utils`); pandoc ≥ 3.1 is downloaded automatically if the system one is older.

Local preview: `make wiki` → `build/wiki/Home.md` (requires `pandoc` ≥ 3.1).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `! LaTeX Error: File 'xxx.sty' not found` | `apt-file search xxx.sty` (from the `apt-file` package) shows which `texlive-*` package to install |
| LaTeX Workshop: `spawn latexmk ENOENT` | `latexmk` is not installed, or snap-installed VS Code does not see the updated `PATH` — log out and back in after installing |
| PDF does not open in the VS Code tab | make sure `.vscode/settings.json` contains `"latex-workshop.latex.outDir": "%DIR%/build"` |
| `[?]` instead of citations in the PDF | rebuild: `make clean && make` |
