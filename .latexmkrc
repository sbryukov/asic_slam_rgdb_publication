# Настройки latexmk
$pdf_mode = 1;                       # pdflatex (как на arXiv)
$bibtex_use = 2;                     # запускать bibtex, удалять .bbl при -C
$out_dir = 'build';                  # PDF и все временные файлы -> build/
$pdflatex = 'pdflatex -synctex=1 -interaction=nonstopmode -file-line-error %O %S';
@generated_exts = (@generated_exts, 'synctex.gz', 'run.xml', 'nav', 'snm', 'vrb');
