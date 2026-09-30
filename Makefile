PORT ?= 8887
DOCS_DIR := $(shell pwd)
SITE_DIR := $(DOCS_DIR)/www

.PHONY: install build serve clean

install:
	cd $(DOCS_DIR)/.. && npm install

build: install
	rm -rf $(SITE_DIR)
	cd $(DOCS_DIR) && npx antora site.yml --stacktrace

serve: build
	@echo "Serving at http://localhost:$(PORT)"
	python3 -m http.server $(PORT) --directory $(SITE_DIR)

clean:
	rm -rf $(SITE_DIR)
