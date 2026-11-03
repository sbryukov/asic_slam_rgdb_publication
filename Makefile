# Makefile для сборки статьи и подготовки пакета arXiv
SHELL   = /bin/bash
MAIN    = main
ARXIV   = arxiv_submission
BUILD   = build
LATEXMK = latexmk -pdf -outdir=$(BUILD) -interaction=nonstopmode -file-line-error

.PHONY: all pdf watch clean distclean arxiv arxiv-check wordcount

all: pdf

pdf:
	$(LATEXMK) $(MAIN).tex

watch:
	$(LATEXMK) -pvc $(MAIN).tex

clean:
	latexmk -outdir=$(BUILD) -c
	@# старые артефакты в корне (от сборок до переноса в build/)
	rm -f $(MAIN).{aux,bbl,blg,fdb_latexmk,fls,log,out,synctex.gz,run.xml,pdf}

distclean: clean
	rm -rf $(BUILD) $(ARXIV) $(ARXIV).tar.gz

# Пакет для arXiv: исходники + готовый main.bbl (arXiv не запускает biber,
# а версии BibTeX могут отличаться — поэтому .bbl прикладываем всегда).
arxiv: pdf
	rm -rf $(ARXIV) && mkdir -p $(ARXIV)
	cp $(MAIN).tex $(BUILD)/$(MAIN).bbl preamble.tex macros.tex $(ARXIV)/
	cp -r sections tables figures $(ARXIV)/
	@# убрать строки-комментарии (arXiv публикует исходники!)
	@if command -v arxiv_latex_cleaner >/dev/null 2>&1; then \
	  arxiv_latex_cleaner $(ARXIV) && rm -rf $(ARXIV) && mv $(ARXIV)_arXiv $(ARXIV); \
	else echo ">> arxiv_latex_cleaner не установлен (pip install arxiv-latex-cleaner) — комментарии не удалены"; fi
	cd $(ARXIV) && tar -czf ../$(ARXIV).tar.gz .
	@echo ">> Готово: $(ARXIV).tar.gz"
	$(MAKE) arxiv-check

# Пробная сборка пакета «как на arXiv» (без .bib, только .bbl)
arxiv-check:
	rm -rf $(BUILD)/arxiv_test && mkdir $(BUILD)/arxiv_test && tar -xzf $(ARXIV).tar.gz -C $(BUILD)/arxiv_test
	cd $(BUILD)/arxiv_test && pdflatex -interaction=nonstopmode $(MAIN).tex >/dev/null && \
	  pdflatex -interaction=nonstopmode $(MAIN).tex >/dev/null && \
	  echo ">> arXiv-проверка пройдена" || echo "!! Ошибка сборки, см. $(BUILD)/arxiv_test/$(MAIN).log"
	@echo ">> Оставшихся TODO в исходниках: $$(grep -rho '\\TODO{' sections tables $(MAIN).tex | wc -l)"

wordcount:
	@texcount -inc -total -sum $(MAIN).tex 2>/dev/null || echo "texcount не установлен"
